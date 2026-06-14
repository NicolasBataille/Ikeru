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

    var body: some View {
        ZStack(alignment: .bottom) {
            IkeruScreenBackground()

            tabContent
                .ignoresSafeArea(.keyboard)

            IkeruTabBar(selection: $selectedTab, tabs: AppTab.allCases)
                .ignoresSafeArea(.keyboard)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            initializeDisplayModeRepo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .startQuizFromShortcut)) { _ in
            selectedTab = .practice
        }
        .onReceive(NotificationCenter.default.publisher(for: .startReviewFromShortcut)) { _ in
            selectedTab = .practice
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
            EtudeView()   // temporary — replaced by ExploreView in Phase 2
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
