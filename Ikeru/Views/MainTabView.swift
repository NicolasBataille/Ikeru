import SwiftUI
import SwiftData
import Combine
import IkeruCore

// MARK: - Tab Definition

enum AppTab: Int, CaseIterable, Identifiable {
    // -startTab=N maps to: 0=explore, 1=practice (default), 2=settings
    case explore     // left
    case practice    // center (default)
    case settings    // right

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .practice: return "Practice"
        case .explore: return "Explore"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .practice: return "house"
        case .explore: return "book.closed"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - MainTabView

struct MainTabView: View {

    /// Retained for call-site compatibility with IkeruApp; the in-app feature
    /// tour was removed in the beginner-first rework, so this is currently unused.
    var isNewUserOnboarding: Bool = false

    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: AppTab = {
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("-startTab=") }),
           let raw = Int(arg.dropFirst("-startTab=".count)),
           let tab = AppTab(rawValue: raw) {
            return tab
        }
        return .practice
    }()
    @State private var presentAISettings = CommandLine.arguments.contains("-presentAISettings")
    @State private var appLocale = AppLocale()
    @State private var displayMode: DisplayMode = .beginner
    @State private var displayModeRepo: (any DisplayModePreferenceRepository)?
    @State private var displayModeCancellable: AnyCancellable?

    /// In-app coach-mark tour over the three tabs. Per-profile "seen" flag, so
    /// it runs once after onboarding (and on demand via Settings → replay).
    @State private var tourController = FeatureTourController()

    var body: some View {
        ZStack(alignment: .bottom) {
            IkeruScreenBackground()

            tabContent
                .ignoresSafeArea(.keyboard)

            // The bar OWNS the bottom safe area rather than sitting on top of
            // it. Respecting it (the default) pins the content above the home
            // indicator while the material still tints that ~34pt strip, so
            // the labels float with a band of dead space underneath that no
            // amount of padding elsewhere can reclaim — trimming above the
            // icons only moved them further from it.
            //
            // Owning it lets the content sit lower, and the bar manages its
            // own bottom clearance instead (see `IkeruTabBar`'s padding).
            IkeruTabBar(selection: $selectedTab, tabs: AppTab.allCases)
                .ignoresSafeArea(.keyboard)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if tourController.isActive {
                    FeatureTourOverlay(
                        controller: tourController,
                        anchors: anchors,
                        proxy: proxy
                    )
                }
            }
            .ignoresSafeArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            initializeDisplayModeRepo()
            // Existing users (no sign-up cover) see the tour on first launch
            // after this ships, once, if they've never completed it.
            if !isNewUserOnboarding, let id = ActiveProfileResolver.activeProfileID() {
                tourController.startIfNeeded(profileID: id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startQuizFromShortcut)) { _ in
            selectedTab = .practice
        }
        .onReceive(NotificationCenter.default.publisher(for: .startReviewFromShortcut)) { _ in
            selectedTab = .practice
        }
        .onReceive(NotificationCenter.default.publisher(for: .displayModeDidChange)) { _ in
            // Onboarding placement (or any out-of-band writer) changed the mode;
            // re-read so beginner aids vs. tatami density apply without relaunch.
            if let repo = displayModeRepo {
                displayMode = repo.current()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestFeatureTour)) { _ in
            if let id = ActiveProfileResolver.activeProfileID() {
                tourController.startIfNeeded(profileID: id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .replayFeatureTour)) { _ in
            if let id = ActiveProfileResolver.activeProfileID() {
                tourController.restart(profileID: id)
            }
        }
        .onChange(of: tourController.index) { _, _ in syncTabToTourStep() }
        .onChange(of: tourController.isActive) { _, active in
            if active { syncTabToTourStep() }
        }
        .environment(\.locale, appLocale.currentLocale)
        .environment(appLocale)
        .environment(\.displayMode, displayMode)
        .environment(\.displayModeRepository, displayModeRepo)
        .fullScreenCover(isPresented: $presentAISettings) {
            NavigationStack {
                AISettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { presentAISettings = false }
                        }
                    }
            }
        }
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        ZStack {
            switch selectedTab {
            case .practice:
                TabContentView(tab: .practice).transition(.opacity)
            case .explore:
                TabContentView(tab: .explore).transition(.opacity)
            case .settings:
                TabContentView(tab: .settings).transition(.opacity)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: selectedTab)
    }

    // MARK: - Display Mode Initialization

    private func initializeDisplayModeRepo() {
        guard displayModeRepo == nil else { return }
        let container = modelContext.container
        let repo = UserDefaultsDisplayModePreferenceRepository(
            defaults: .standard,
            activeProfileID: { ActiveProfileResolver.activeProfileID() },
            profileCreatedAt: { id in
                let context = container.mainContext
                let descriptor = FetchDescriptor<UserProfile>(
                    predicate: #Predicate { $0.id == id }
                )
                return (try? context.fetch(descriptor))?.first?.createdAt
            }
        )
        self.displayModeRepo = repo
        self.displayMode = repo.current()
        self.displayModeCancellable = repo.publisher
            .receive(on: DispatchQueue.main)
            .sink { mode in self.displayMode = mode }
    }

    // MARK: - Feature Tour

    /// Switches to the tab a tour step wants in view behind the spotlight.
    private func syncTabToTourStep() {
        guard let step = tourController.currentStep, let tab = step.tab else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            selectedTab = tab
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when sign-up onboarding finishes so the in-app feature tour can begin.
    static let requestFeatureTour = Notification.Name("ikeru.requestFeatureTour")
    /// Posted from Settings to replay the feature tour on demand.
    static let replayFeatureTour = Notification.Name("ikeru.replayFeatureTour")
}

// MARK: - Tab Content View (with NavigationStack per tab)

private struct TabContentView: View {

    let tab: AppTab

    var body: some View {
        NavigationStack {
            tabRootView
        }
    }

    @ViewBuilder
    private var tabRootView: some View {
        switch tab {
        case .practice:
            HomeView()
        case .explore:
            ExploreView()
        case .settings:
            SettingsView()
        }
    }
}

// MARK: - Preview

#Preview("MainTabView") {
    MainTabView()
        .preferredColorScheme(.dark)
}
