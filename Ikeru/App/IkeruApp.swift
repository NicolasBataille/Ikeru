import SwiftUI
import SwiftData
import IkeruCore
import BackgroundTasks
import os

/// Holds the app-wide `AssetCache` outside of SwiftUI `@State`, so background
/// task closures can read it without capturing a stale struct-value `self`.
/// `@State` values are re-resolved per-body-evaluation and are unreliable when
/// read from a `BGTaskScheduler` handler closure hours later.
@MainActor
final class AssetCacheHolder {
    static let shared = AssetCacheHolder()
    var cache: AssetCache?
    private init() {}
}

@main
struct IkeruApp: App {

    // MARK: - Pre-warm constants

    /// BGTaskScheduler identifier — must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    static let preWarmTaskIdentifier = "com.ikeru.rig.prewarm"
    /// UserDefaults key controlling whether the BG pre-warm runs.
    static let preWarmEnabledKey = "ikeru.prewarm.enabled"
    /// UserDefaults key controlling the optional batch-done notification.
    static let preWarmNotifyKey = "ikeru.prewarm.notify"
    /// Re-schedule cadence for the background refresh task.
    static let preWarmRescheduleInterval: TimeInterval = 4 * 60 * 60

    /// Cold-start guard — ensures the launch animation plays exactly once
    /// per process lifetime, not on scene-phase changes or re-inits.
    @MainActor
    private static var hasPlayedLaunchAnimation = false

    @State private var toastManager = ToastManager()
    @State private var profileViewModel: ProfileViewModel?
    @State private var showOnboarding = false
    @State private var hasCheckedProfile = false
    @State private var hasFinishedLaunch: Bool = IkeruApp.hasPlayedLaunchAnimation
    @State private var aiRouterService = AIRouterService()
    @State private var assetCache: AssetCache?
    @Environment(\.scenePhase) private var scenePhase

    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                UserProfile.self,
                Card.self,
                ReviewLog.self,
                RPGState.self,
                MnemonicCache.self,
                CompanionChatMessage.self,
                AssetManifest.self,
                VocabularyEntry.self,
                VocabularyEncounter.self,
            ])
            let config = ModelConfiguration(
                "Ikeru",
                schema: schema
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [config]
            )
        } catch {
            Logger.srs.critical("Failed to create ModelContainer: \(error)")
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Initialise the AssetCache synchronously so the first body evaluation
        // already sees a non-nil environment value. AssetCache init is pure
        // Foundation + SwiftData — no async required.
        let cache = AssetCache(
            configuration: .default(),
            modelContainer: modelContainer
        )
        MainActor.assumeIsolated {
            AssetCacheHolder.shared.cache = cache
        }
        _assetCache = State(initialValue: cache)

        registerPreWarmBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if hasFinishedLaunch {
                    mainContent
                        .transition(.opacity)
                } else {
                    LaunchAnimationView {
                        IkeruApp.hasPlayedLaunchAnimation = true
                        withAnimation(.easeInOut(duration: 0.4)) {
                            hasFinishedLaunch = true
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: hasFinishedLaunch)
                .preferredColorScheme(.dark)
                .environment(\.toastManager, toastManager)
                .environment(\.profileViewModel, profileViewModel)
                .environment(\.aiRouterService, aiRouterService)
                .environment(\.assetCache, assetCache)
                .toastOverlay()
                .task {
                    initializeProfileViewModel()
                    WatchConnectivityManager.shared.activate(modelContainer: modelContainer)
                    await scheduleNotificationsFromSettings()
                    schedulePreWarmTask()
                }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                schedulePreWarmTask()
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if hasCheckedProfile {
            MainTabView()
                .fullScreenCover(isPresented: $showOnboarding) {
                    NameEntryView()
                        .environment(\.profileViewModel, profileViewModel)
                        .onDisappear {
                            // Reload profile after onboarding dismisses
                            profileViewModel?.loadProfile()
                        }
                }
        } else {
            // Brief loading state while checking profile
            ZStack {
                Color.ikeruBackground
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Profile Initialization

    @MainActor
    private func initializeProfileViewModel() {
        let viewModel = ProfileViewModel(modelContext: modelContainer.mainContext)
        profileViewModel = viewModel

        // Dev helper: launch with -skipOnboarding to auto-create a default profile
        if !viewModel.hasProfile && CommandLine.arguments.contains("-skipOnboarding") {
            Logger.ui.info("Skip onboarding flag set — creating default profile")
            viewModel.createProfile(name: "Nico")
            viewModel.loadProfile()
        }

        #if DEBUG
        // Dev helper: launch with -mockProfile (and friends) to seed a rich fixture profile.
        // No-op when a profile already exists.
        TestFixtures.seedIfRequested(context: modelContainer.mainContext, profileVM: viewModel)
        #endif

        if viewModel.hasProfile {
            Logger.ui.info("Existing profile found — skipping onboarding")
            showOnboarding = false
        } else {
            Logger.ui.info("No profile found — showing onboarding")
            showOnboarding = true
        }

        hasCheckedProfile = true
    }

    // MARK: - Notification Scheduling

    @MainActor
    private func scheduleNotificationsFromSettings() async {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<UserProfile>()
        guard let profile = try? context.fetch(descriptor).first else { return }

        let settings = profile.settings
        let manager = NotificationManager.shared

        if settings.reviewReminderEnabled {
            let authorized = await manager.requestAuthorization()
            if authorized {
                await manager.scheduleReviewReminder(hour: settings.reviewReminderHour)
            }
        }

        if settings.weeklyCheckInEnabled {
            let authorized = await manager.requestAuthorization()
            if authorized {
                await manager.scheduleWeeklyCheckIn(
                    weekday: settings.weeklyCheckInDay,
                    hour: settings.weeklyCheckInHour
                )
            }
        }
    }

    // MARK: - Pre-warm BackgroundTasks (Story 7.5)

    /// Registers the BGAppRefreshTask handler. Must be called before the app
    /// finishes launching (i.e. inside `init`). The handler dispatches to
    /// `runPreWarmTask(_:)` on the main actor.
    private func registerPreWarmBackgroundTask() {
        // Default the toggle to ON the first time we ever see this device.
        if UserDefaults.standard.object(forKey: Self.preWarmEnabledKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.preWarmEnabledKey)
        }

        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.preWarmTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await self.runPreWarmTask(refreshTask)
            }
        }

        if registered {
            Logger.cache.info("BG prewarm handler registered (\(Self.preWarmTaskIdentifier, privacy: .public))")
        } else {
            Logger.cache.warning("BG prewarm handler registration failed — identifier missing from Info.plist?")
        }
    }

    /// Submits the next BG refresh request. Safe to call repeatedly.
    private func schedulePreWarmTask() {
        let enabled = UserDefaults.standard.bool(forKey: Self.preWarmEnabledKey)
        guard enabled else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.preWarmTaskIdentifier)
            Logger.cache.info("BG prewarm disabled by user — pending requests cancelled")
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: Self.preWarmTaskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(Self.preWarmRescheduleInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
            Logger.cache.info("BG prewarm scheduled (earliest in \(Int(Self.preWarmRescheduleInterval))s)")
        } catch {
            Logger.cache.error("BG prewarm scheduling failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Body of the background refresh task. Honours the user toggle, runs the
    /// pre-warm batch with a hard expiration handler, then re-schedules itself.
    @MainActor
    private func runPreWarmTask(_ task: BGAppRefreshTask) async {
        Logger.cache.info("BG prewarm executing")

        let container = modelContainer
        let work = Task { @MainActor in
            let enabled = UserDefaults.standard.bool(forKey: Self.preWarmEnabledKey)
            guard enabled else {
                Logger.cache.info("BG prewarm skipped — disabled in settings")
                return
            }

            // Read the AssetCache from the non-@State holder — @State values
            // are unreliable when captured from a BG closure.
            let cache = AssetCacheHolder.shared.cache
            guard let service = PreWarmFactory.make(
                modelContainer: container,
                assetCache: cache
            ) else {
                Logger.cache.warning("BG prewarm skipped — factory could not build PreWarmService")
                return
            }

            do {
                try await service.enqueueUpcomingDueAudio(window: 86_400)
                Logger.cache.info("BG prewarm done")
            } catch is CancellationError {
                Logger.cache.warning("BG prewarm cancelled mid-flight")
                throw CancellationError()
            } catch {
                Logger.cache.error("BG prewarm failed: \(error.localizedDescription, privacy: .public)")
                throw error
            }

            if UserDefaults.standard.bool(forKey: Self.preWarmNotifyKey) {
                await PreWarmNotifier.notifyBatchFinished()
            }
        }

        task.expirationHandler = {
            work.cancel()
            Logger.cache.warning("BG prewarm expired before completion")
            task.setTaskCompleted(success: false)
        }

        do {
            try await work.value
            schedulePreWarmTask()
            Logger.cache.info("BG prewarm rescheduled")
            task.setTaskCompleted(success: true)
        } catch {
            // Either cancellation (expirationHandler may already have
            // completed the task — setTaskCompleted is idempotent-safe in
            // practice) or an enqueue failure. Reschedule either way so we
            // try again on the next cadence window.
            schedulePreWarmTask()
            Logger.cache.info("BG prewarm rescheduled after failure")
            task.setTaskCompleted(success: false)
        }
    }
}
