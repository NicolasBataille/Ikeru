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

// GAP-10 (2026-08-16): `@main` moved to `IkeruMain.swift`, which picks
// between this real app and an empty test-host `App` based on
// `isRunningUnderXCTest` below — see that file's doc comment for why.
struct IkeruApp: App {

    // MARK: - Test-host detection

    /// True when this process is the app-hosted test target's TEST HOST
    /// (`xcodebuild test -scheme Ikeru`) rather than a real launch.
    /// `XCTestConfigurationFilePath` is the standard, widely-used signal for
    /// this (set by the XCTest launcher regardless of whether the actual
    /// tests are written with XCTest or Swift Testing — Swift Testing is
    /// hosted through the same XCTest bridge under `xcodebuild test`).
    ///
    /// Why this exists (GAP-10, 2026-08-16): `IkeruTests` builds and tears
    /// down its OWN in-memory `ModelContainer` per test, but `xcodebuild
    /// test` still launches this REAL `App` as the test host, so its full
    /// SwiftUI scene — including the `.task { }` below — genuinely mounts
    /// and runs unless gated.
    ///
    /// CORRECTION (2026-08-16, same day): an earlier version of this comment
    /// claimed this gate FIXED the `SwiftData/BackingData.swift:940: Fatal
    /// error: Never access a full future backing data` crash by removing
    /// `IkeruApp`'s own second `ModelContainer` from the process. That claim
    /// was measured and falsified, not just doubted: `@main` was moved to
    /// `IkeruMain.swift`, which swaps in an empty `TestHostApp` (no
    /// `ModelContainer`, no `.task`, no `IkeruApp` instance at all) whenever
    /// `isRunningUnderXCTest` is true. `HomeViewModelTests
    /// .loadDataLoadsRPGState()`, run alone, still crashed with the
    /// IDENTICAL fatal error afterwards — proof this app's own container was
    /// never the (or at least not the only) cause. The real mechanism is
    /// still not identified; see GAP-10's final report for the measured
    /// evidence (two distinct crash signatures, `ModelContainer(` reachable
    /// only from this file per a repo-wide grep, contradicting evidence
    /// against a background-actor/mainContext race).
    ///
    /// This gate is kept anyway as ordinary test hygiene — the app-hosted
    /// test target should not run this app's real startup side effects
    /// (background task registration, launch animation, profile
    /// initialization) as an accidental by-product of hosting tests — not as
    /// a fix for the SwiftData crash.
    static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

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
    /// Set by `NameEntryView` right before it dismisses itself on the
    /// "I already have an account" restore path — read (and reset) by the
    /// `onChange(of: showOnboarding)` below so a RETURNING learner does not
    /// get the brand-new-user feature tour, which that handler otherwise
    /// fires unconditionally on every onboarding dismissal.
    @State private var onboardingFinishedViaRestore = false
    @State private var hasCheckedProfile = false
    @State private var hasFinishedLaunch: Bool = IkeruApp.hasPlayedLaunchAnimation
    /// Set by `LaunchAnimationView.onReadyForContent` so the real UI is built
    /// and settled underneath before the launch layer's exit fade runs.
    @State private var isMainContentMounted: Bool = IkeruApp.hasPlayedLaunchAnimation
    @State private var aiRouterService = AIRouterService()
    @State private var assetCache: AssetCache?
    @State private var showStoreRecoveryNotice = false
    @Environment(\.scenePhase) private var scenePhase

    let modelContainer: ModelContainer

    init() {
        // Current versioned schema (IkeruSchemaV4) + migration plan so
        // @Model changes migrate explicitly instead of relying on implicit
        // lightweight migration. The plan carries the V1→V2 stage that adds
        // ExerciseOutcomeLog, V2→V3 which adds the answer provenance fields
        // on ReviewLog, then V3→V4 which adds the cloud-sync columns
        // (updatedAt/deletedAt/syncedAt) to the 8 synchronized entities —
        // see docs/design-specs/2026-08-10-cloud-sync-design.md §5.1. See
        // IkeruSchema.swift in IkeruCore.
        //
        // This MUST name the latest version. Declaring an older one opens the
        // container without error and then traps on the first insert
        // ("Failed to cast model IkeruCore.UserProfile"), which the store
        // recovery below cannot catch — it only wraps makeModelContainer.
        let schema = Schema(versionedSchema: IkeruSchemaV4.self)

        do {
            modelContainer = try Self.makeModelContainer(schema: schema)
        } catch {
            Logger.srs.critical("Failed to create ModelContainer: \(error)")

            #if DEBUG
            // Developers should see a broken store immediately, not have it
            // silently swept aside — a real V1→V2 migration bug should fail
            // loudly in development.
            fatalError("Failed to create ModelContainer: \(error)")
            #else
            // TestFlight/production: this is now a real risk surface (the
            // V1→V2 migration ships to users with existing stores). Move the
            // store directory aside — NEVER deleting anything — and retry
            // once with a fresh, empty store rather than crash-looping the
            // app on every launch.
            Logger.srs.critical("Attempting conservative store recovery (move-aside + retry)…")
            do {
                // The store's REAL on-disk location, from the same
                // ModelConfiguration the container opens — never a guessed
                // path (a named configuration's files live directly in
                // Application Support, not a per-bundle subdirectory).
                let storeURL = Self.storeConfiguration(schema: schema).url
                if let recoveryDestination = try StoreRecovery.moveStoreAside(storeURL: storeURL) {
                    Logger.srs.critical(
                        "Store moved aside to \(recoveryDestination.path, privacy: .public) — retrying with a fresh store"
                    )
                    StoreRecoveryNotice.markPending(recoveryDirectory: recoveryDestination)
                }
                modelContainer = try Self.makeModelContainer(schema: schema)
                Logger.srs.critical("Store recovery succeeded — app launching with a fresh store")
            } catch {
                Logger.srs.critical("Store recovery ALSO failed: \(error) — nothing left to try")
                fatalError("Failed to create ModelContainer even after store recovery: \(error)")
            }
            #endif
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
                // `mainContent` is mounted UNDER the launch layer as soon as
                // the animation signals `onReadyForContent` (breathe phase,
                // ~0.45s before its exit fade), so that fade — the master
                // clock's final 0.30s phase — cross-fades onto the real UI.
                // That is the single fade for the launch → main transition,
                // per launch-animation-rebuild-spec.md bug #5.
                //
                // It used to mount only at `onFinished`, so the exit fade
                // revealed an empty (black) window and the first screen then
                // ran a second fade-in of its own: a ~0.6s hard black hold
                // between the bloom and the first screen (measured on device
                // 2026-08-05) — exactly the double fade bug #5 targeted.
                // Mounting it at t=0 instead is NOT the fix: building the
                // view hierarchy blocks the first frames and, since the
                // launch clock is honest wall-clock time, that silently ate
                // the animation's whole intro.
                if hasFinishedLaunch || isMainContentMounted {
                    mainContent
                }

                if !hasFinishedLaunch {
                    LaunchAnimationView(
                        onFinished: {
                            IkeruApp.hasPlayedLaunchAnimation = true
                            hasFinishedLaunch = true
                        },
                        onReadyForContent: { isMainContentMounted = true }
                    )
                }
            }
            .preferredColorScheme(.dark)
            .environment(\.toastManager, toastManager)
            .environment(\.profileViewModel, profileViewModel)
            .environment(\.aiRouterService, aiRouterService)
            .environment(\.assetCache, assetCache)
            .toastOverlay()
            .task {
                    // GAP-10: skip the app's own startup machinery when this
                    // process is IkeruTests' test host, not a real launch —
                    // see `isRunningUnderXCTest`'s doc comment.
                    guard !Self.isRunningUnderXCTest else { return }
                    initializeProfileViewModel()
                    NotificationManager.shared.registerAsDelegate()
                    WatchConnectivityManager.shared.activate(modelContainer: modelContainer)
                    await scheduleNotificationsFromSettings()
                    schedulePreWarmTask()
                    await WidgetSnapshotRefresher.refresh(modelContainer: modelContainer)
                    // Cloud-sync push triggers (design spec §5.2): starts the
                    // network-regain monitor now, and readies the coordinator
                    // for the foreground trigger wired below in
                    // onChange(of: scenePhase). syncNow() itself no-ops
                    // without consent, so this is safe to start unconditionally.
                    CloudSyncTriggers.shared.start(modelContainer: modelContainer)
                    if StoreRecoveryNotice.isPending() {
                        showStoreRecoveryNotice = true
                    }
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .alert(
                    "Your data was recovered",
                    isPresented: $showStoreRecoveryNotice
                ) {
                    Button("Dismiss") {
                        StoreRecoveryNotice.acknowledge()
                    }
                } message: {
                    Text(
                        "A migration issue was detected at launch. Your data was preserved on this device, not lost. Export it from Settings or contact support if you need help."
                    )
                }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                schedulePreWarmTask()
            } else if newPhase == .active {
                Task { @MainActor in
                    await WidgetSnapshotRefresher.refresh(modelContainer: modelContainer)
                }
                // Cloud-sync foreground trigger (design spec §5.2). Detached
                // internally — never awaited here, never delays this UI path.
                CloudSyncTriggers.shared.triggerForegroundSync()
            }
        }
    }

    // MARK: - ModelContainer

    /// Builds the app's `ModelContainer` against the current versioned schema
    /// + migration plan. Factored out of `init` so the container-creation
    /// call can be retried identically after a store-recovery move-aside.
    /// The single source of truth for the store's configuration — and hence
    /// its on-disk `url`, which the store-recovery path relies on. Keep any
    /// future configuration change here so recovery can never target a stale
    /// location.
    private static func storeConfiguration(schema: Schema) -> ModelConfiguration {
        ModelConfiguration(
            "Ikeru",
            schema: schema,
            cloudKitDatabase: .none  // Manual backup via CloudBackupManager, not auto-sync
        )
    }

    private static func makeModelContainer(schema: Schema) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: IkeruMigrationPlan.self,
            configurations: [storeConfiguration(schema: schema)]
        )
    }

    // MARK: - Deep Links

    /// Handles `ikeru://…` URLs — currently only the home-screen widget's
    /// `.widgetURL`, which routes into a review session via the same
    /// notification the "Review Japanese" Siri Shortcut already posts
    /// (see `ShortcutsManager.swift`).
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "ikeru" else { return }
        switch url.host {
        case "review":
            NotificationCenter.default.post(name: .startReviewFromShortcut, object: nil)
        default:
            Logger.ui.info("Unhandled deep link host: \(url.host ?? "nil", privacy: .public)")
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if hasCheckedProfile {
            MainTabView(isNewUserOnboarding: showOnboarding)
                .fullScreenCover(isPresented: $showOnboarding) {
                    NameEntryView(finishedViaRestore: $onboardingFinishedViaRestore)
                        .environment(\.profileViewModel, profileViewModel)
                        .onDisappear {
                            // Reload profile after onboarding dismisses
                            profileViewModel?.loadProfile()
                        }
                }
                .onChange(of: showOnboarding) { wasShowing, isShowing in
                    guard wasShowing && !isShowing else { return }
                    if onboardingFinishedViaRestore {
                        // Restored an existing profile. This handler only
                        // stops itself from ALSO posting `.requestFeatureTour`
                        // — it does NOT, by itself, stop the tour from
                        // running: `MainTabView.onAppear` calls its own
                        // `tourController.startIfNeeded(profileID:)`
                        // independently of this flag, and would still fire
                        // for a returning learner if that `onAppear` re-runs
                        // on this cover's dismissal. What actually prevents
                        // that is `NameEntryView.performRestoreSync()`
                        // explicitly calling
                        // `FeatureTourController.markSeen(profileID:)`
                        // before setting this flag — `startIfNeeded` then
                        // finds `hasSeenTour` already true and no-ops on its
                        // own. Consume the flag here regardless, purely to
                        // avoid the redundant `.requestFeatureTour` post.
                        onboardingFinishedViaRestore = false
                    } else {
                        // Sign-up onboarding just finished — kick off the
                        // in-app feature tour for this brand-new profile.
                        NotificationCenter.default.post(name: .requestFeatureTour, object: nil)
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

        #if IKERU_DEV_TOOLS
        // Dev helper: launch with -wipeData to reset to a clean slate BEFORE
        // -skipOnboarding / -mockProfile run below. Without this, a second UI
        // test launch on the same simulator sees `hasProfile == true` from the
        // previous run and both of those flags silently no-op (`seedIfRequested`
        // and this file's own `-skipOnboarding` guard both check `hasProfile`
        // first) — the exact "seed doesn't re-run on the 2nd launch" trap named
        // in the GAP-09 UI-test-harness brief. Runs in its own IKERU_DEV_TOOLS
        // block (stripped before App Store submit, see CLAUDE.md) since
        // `TestFixtures.wipeAll` lives behind the same flag.
        if AppEnvironment.hasFlag("wipeData") {
            Logger.ui.info("wipeData flag set — clearing all persisted state before seeding")
            TestFixtures.wipeAll(context: modelContainer.mainContext, profileVM: viewModel)
        }
        #endif

        // Dev helper: launch with -skipOnboarding to auto-create a default profile
        if !viewModel.hasProfile && AppEnvironment.hasFlag("skipOnboarding") {
            Logger.ui.info("Skip onboarding flag set — creating default profile")
            viewModel.createProfile(name: "Nico")
            viewModel.loadProfile()
        }

        #if IKERU_DEV_TOOLS
        // Dev helper: launch with -mockProfile (and friends) to seed a rich fixture profile.
        // No-op when a profile already exists. Same behaviour ships in TestFlight
        // (so QA can launch a seed via the Outils dev menu) and is stripped before
        // App Store submit — see CLAUDE.md "Removing IKERU_DEV_TOOLS".
        TestFixtures.seedIfRequested(context: modelContainer.mainContext, profileVM: viewModel)
        #endif

        // Dev helper: launch with -skipTour to land on a profile that has already
        // "seen" the feature tour.
        //
        // Without this, `-skipOnboarding` and `-startTab=` do not compose, which
        // is not obvious and cost a UI test its diagnosis: creating a profile
        // starts the tour, and the tour drives navigation itself
        // (`MainTabView.syncTabToTourStep()`), overwriting whatever tab
        // `-startTab=` selected. The test asked for Settings and was quietly
        // taken to the tour's own step instead.
        //
        // Reuses `markSeen` rather than adding a second notion of "seen": it is
        // the same static writer the restore path uses, on the same UserDefaults
        // key `hasSeenTour(profileID:)` reads. A test that suppressed the tour
        // some other way would be testing a code path no learner ever takes.
        if let profileID = viewModel.currentProfile?.id,
           AppEnvironment.hasFlag("skipTour") {
            Logger.ui.info("Skip tour flag set — marking the feature tour as seen")
            FeatureTourController.markSeen(profileID: profileID)
        }

        // Dev helper: launch with -skipHints to land on a profile that has
        // already dismissed every in-context coach-mark (swipe tutorial,
        // caught-up explainer, kana drill modes, first-session daily term).
        //
        // Distinct from `-skipTour` above, which owns the *tab tour* and its
        // own controller. These are the lighter overlays that fire the first
        // time a learner reaches a surface — and they are opaque scrims: the
        // swipe tutorial covers the session card and its grade buttons
        // entirely (measured 2026-08-16, see `OnboardingFlags.markAllSeen`).
        // Any UI test that isn't about the coach-mark itself needs both flags.
        if let profileID = viewModel.currentProfile?.id,
           AppEnvironment.hasFlag("skipHints") {
            Logger.ui.info("Skip hints flag set — marking every coach-mark as seen")
            OnboardingFlags.markAllSeen(profileID: profileID)
        }

        // La grammaire entre dans le SRS : une carte `.grammar` par point du
        // bundle, semee une fois et idempotente sur le recto (le titre du
        // point). Sans ca, `CardType.grammar` restait un cas d'enum qu'aucune
        // carte n'habitait — mesure le 2026-08-19 — et la formule de
        // preparation JLPT recevait `grammarPointsFamiliarPlus: 0` en dur.
        //
        // Apres le profil, pas avant : les cartes appartiennent a un profil.
        Task { @MainActor in
            guard let repository = BundledContent.makeRepository() else { return }
            let points = await repository.grammarPointsByLevel(.n5)
            guard !points.isEmpty else { return }
            let seeded = await GrammarCardSeeder.seedIfNeeded(
                points: points,
                repository: CardRepository(modelContainer: modelContainer)
            )
            if !seeded.isEmpty {
                Logger.ui.info("Seeded \(seeded.count, privacy: .public) grammar cards")
            }
        }

        #if IKERU_DEV_TOOLS
        // GAP-01 two-client merge test only: launch with -switchToOldestProfile
        // to make the OTHER client's pulled-down profile (always the older
        // one by `createdAt` in this test's phase ordering — see
        // `LaunchArguments.switchToOldestProfile` in IkeruUITests) the
        // active one on THIS device. `viewModel.allProfiles` is already
        // sorted by `createdAt` ascending (`ProfileViewModel.loadProfile()`),
        // so `.first` is exactly that profile. Without this, every card/
        // review-log query stays scoped to this device's OWN throwaway
        // profile forever — a pull never changes which profile is active.
        // No-op when only one profile exists locally (nothing to switch to).
        if AppEnvironment.hasFlag("switchToOldestProfile"),
           let oldest = viewModel.allProfiles.first,
           oldest.id != viewModel.currentProfile?.id {
            Logger.ui.info("switchToOldestProfile flag set — switching active profile to \(oldest.id)")
            viewModel.switchProfile(to: oldest)
        }
        #endif

        if viewModel.hasProfile {
            Logger.ui.info("Existing profile found — skipping onboarding")
            showOnboarding = false
        } else {
            Logger.ui.info("No profile found — showing onboarding")
            showOnboarding = true
        }

        hasCheckedProfile = true

        // One-shot: attach pre-existing (profile-less) cards to the active profile.
        Task { @MainActor in
            let repo = CardRepository(modelContainer: modelContainer)
            await repo.attachOrphanCards()
        }

        // One-shot migration: existing profiles predate the unlock-tracking
        // model and have an empty `acknowledgedUnlocks`. Without backfill,
        // every threshold they already cross would fire as "new practice
        // unlocked" the first time the unlock service re-evaluates them.
        // Run once, when `acknowledgedUnlocks` is empty.
        Task { @MainActor in
            let context = modelContainer.mainContext
            guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context),
                  state.acknowledgedUnlocks.isEmpty else { return }
            // Tombstoned cards excluded: a deleted card must not push a
            // threshold over the line and silently pre-acknowledge an unlock
            // the learner would then never see fire.
            let fetchedCards: [Card] = (try? context.fetch(
                FetchDescriptor<Card>(predicate: #Predicate { $0.deletedAt == nil })
            )) ?? []
            let cards: [CardDTO] = fetchedCards.map { card in
                CardDTO(
                    id: card.id,
                    front: card.front,
                    back: card.back,
                    type: card.type,
                    fsrsState: card.fsrsState,
                    easeFactor: card.easeFactor,
                    interval: card.interval,
                    dueDate: card.dueDate,
                    lapseCount: card.lapseCount,
                    leechFlag: card.leechFlag
                )
            }
            // Grammar familiar+ is now derived from `cards` by the builder, so
            // the grammar unlock gate backfills correctly. `skillBalances` is
            // left empty here on purpose: the unlock service keys off mastery /
            // listening thresholds, never skill balances, so loading dashboard
            // data at launch just to fill this would be wasted I/O.
            let snapshot = LearnerSnapshotBuilder.build(
                cards: cards,
                jlptLevel: .n5,
                listeningAccuracyLast30: 0,
                listeningRecallLast30Days: 0,
                skillBalances: [:],
                hasNewContentQueued: false,
                lastSessionAt: state.lastSessionDate,
                now: Date()
            )
            state.acknowledgedUnlocks = UnlockBackfillService.backfill(
                previous: state.acknowledgedUnlocks,
                profile: snapshot,
                unlockService: DefaultExerciseUnlockService()
            )
            try? context.save()
            Logger.rpg.info(
                "unlock.backfill applied — acknowledged=\(state.acknowledgedUnlocks.count, privacy: .public)"
            )
        }

        // One-shot JLPT backfill: tags pre-existing N5 seed cards with their
        // JLPT level so the readiness formula can produce a non-zero N5 score
        // for migrating users. Gated by `RPGState.jlptBackfillVersion`, which
        // defaults to 0 for existing rows. Mirrors the UnlockBackfill pattern
        // above. Idempotent — JLPTBackfillService preserves already-tagged
        // cards.
        Task { @MainActor in
            let context = modelContainer.mainContext
            guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context),
                  state.jlptBackfillVersion == 0 else { return }

            // Tombstoned cards excluded: no point tagging a JLPT level onto a
            // card the learner deleted, and the readiness score this feeds
            // must not count it.
            let fetchedCards: [Card] = (try? context.fetch(
                FetchDescriptor<Card>(predicate: #Predicate { $0.deletedAt == nil })
            )) ?? []
            let dtos: [CardDTO] = fetchedCards.map { card in
                CardDTO(
                    id: card.id,
                    front: card.front,
                    back: card.back,
                    type: card.type,
                    fsrsState: card.fsrsState,
                    easeFactor: card.easeFactor,
                    interval: card.interval,
                    dueDate: card.dueDate,
                    lapseCount: card.lapseCount,
                    leechFlag: card.leechFlag,
                    jlptLevel: card.jlptLevel
                )
            }

            let tagged = JLPTBackfillService.tag(cards: dtos)
            // Index cards by id for O(1) lookup when applying tags.
            let cardsByID = Dictionary(uniqueKeysWithValues: fetchedCards.map { ($0.id, $0) })

            var taggedCount = 0
            for dto in tagged {
                guard let level = dto.jlptLevel,
                      let card = cardsByID[dto.id],
                      card.jlptLevel == nil
                else { continue }
                card.jlptLevel = level
                taggedCount += 1
                Logger.rpg.info(
                    "card.tagged.backfill cardId=\(card.id, privacy: .public) level=\(level.rawValue, privacy: .public)"
                )
            }

            state.jlptBackfillVersion = 1
            do {
                try context.save()
                Logger.rpg.info("jlpt.backfill complete count=\(taggedCount, privacy: .public)")
            } catch {
                // Roll back the in-memory version flag so the next launch
                // retries the backfill instead of silently skipping it.
                state.jlptBackfillVersion = 0
                Logger.rpg.error("jlpt.backfill save.failed error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Notification Scheduling

    @MainActor
    private func scheduleNotificationsFromSettings() async {
        let context = modelContainer.mainContext
        // A tombstoned profile must not keep scheduling reminders.
        let descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.deletedAt == nil })
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

        // Daily term reminder is configured via UserDefaults (the Settings
        // view writes there directly via @AppStorage).
        if UserDefaults.standard.bool(forKey: DailyTermSettings.enabledKey) {
            let authorized = await manager.requestAuthorization()
            if authorized {
                let hour = UserDefaults.standard.object(forKey: DailyTermSettings.hourKey) as? Int
                    ?? DailyTermSettings.defaultHour
                let minute = UserDefaults.standard.object(forKey: DailyTermSettings.minuteKey) as? Int
                    ?? DailyTermSettings.defaultMinute
                await manager.scheduleDailyTermReminder(hour: hour, minute: minute)
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
