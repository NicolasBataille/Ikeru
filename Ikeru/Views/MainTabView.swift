import SwiftUI
import SwiftData
import Combine
import IkeruCore

// MARK: - Tab Definition

enum AppTab: Int, CaseIterable, Identifiable {
    // -startTab=N maps to: 0=companion, 1=study, 2=home (default), 3=rpg, 4=settings
    case companion   // tap-only, position 0
    case study       // swipe pager left
    case home        // swipe pager center (default)
    case rpg         // swipe pager right
    case settings    // tap-only, position 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .study: return "Study"
        case .companion: return "Companion"
        case .rpg: return "RPG"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .study: return "book.closed"
        case .companion: return "bubble.left"
        case .rpg: return "mountain.2"            // path / summit metaphor
        case .settings: return "gearshape"
        }
    }
}

// MARK: - MainTabView

struct MainTabView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: AppTab = {
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("-startTab=") }),
           let raw = Int(arg.dropFirst("-startTab=".count)),
           let tab = AppTab(rawValue: raw) {
            return tab
        }
        return .home
    }()
    @State private var showCompanionChat = false
    @State private var companionViewModel: CompanionChatViewModel?
    @State private var presentAISettings = CommandLine.arguments.contains("-presentAISettings")
    @State private var appLocale = AppLocale()
    @State private var displayMode: DisplayMode = .beginner
    @State private var displayModeRepo: (any DisplayModePreferenceRepository)?
    @State private var displayModeCancellable: AnyCancellable?

    var body: some View {
        ZStack(alignment: .bottom) {
            IkeruScreenBackground()

            // Tab content
            tabContent
                .ignoresSafeArea(.keyboard)

            // Custom floating Liquid Glass tab bar
            IkeruTabBar(selection: $selectedTab, tabs: AppTab.allCases)
                .ignoresSafeArea(.keyboard)

            // Persistent companion avatar — Sakura is part of the surface,
            // not just a tab. Hidden when the Companion tab is active so
            // the floating glyph doesn't sit over the chat itself.
            companionAvatarOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            initializeCompanionViewModel()
            initializeDisplayModeRepo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .startQuizFromShortcut)) { _ in
            selectedTab = .home
        }
        .onReceive(NotificationCenter.default.publisher(for: .startReviewFromShortcut)) { _ in
            selectedTab = .home
        }
        .sheet(isPresented: $showCompanionChat) {
            if let vm = companionViewModel {
                CompanionChatSheet(viewModel: vm)
                    .presentationDetents([.large, .medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
            }
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

    @State private var liveOffsetFraction: CGFloat = 1 // home is index 1 within the pager

    private var learningPagerIndex: Binding<Int> {
        Binding(
            get: {
                switch selectedTab {
                case .study: return 0
                case .home:  return 1
                case .rpg:   return 2
                default:     return 1
                }
            },
            set: { new in
                switch new {
                case 0: selectedTab = .study
                case 2: selectedTab = .rpg
                default: selectedTab = .home
                }
            }
        )
    }

    @ViewBuilder
    private var tabContent: some View {
        ZStack {
            switch selectedTab {
            case .study, .home, .rpg:
                PagedLearningStack(
                    pageCount: 3,
                    activeIndex: learningPagerIndex,
                    liveOffsetFraction: $liveOffsetFraction,
                    content: { index in
                        switch index {
                        case 0: TabContentView(tab: .study)
                        case 1: TabContentView(tab: .home)
                        case 2: TabContentView(tab: .rpg)
                        default: Color.clear
                        }
                    }
                )
                .transition(.opacity)
            case .companion:
                TabContentView(tab: .companion)
                    .transition(.opacity)
            case .settings:
                TabContentView(tab: .settings)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: selectedTab)
    }

    // MARK: - Companion Overlay
    //
    // Floats above the tab bar in the bottom-right gutter. Tap opens the
    // companion chat sheet without changing tabs — quick access from any
    // surface, in keeping with the original spec ("persistent companion
    // overlay").

    @ViewBuilder
    private var companionAvatarOverlay: some View {
        if selectedTab != .companion {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    CompanionAvatarView(
                        hasAttention: false,
                        showBadge: false,
                        onTap: { showCompanionChat = true }
                    )
                    .padding(.trailing, 20)
                    .padding(.bottom, 100) // clears the floating tab bar
                }
            }
            .ignoresSafeArea(.keyboard)
            .transition(.opacity)
        }
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

    // MARK: - Companion Initialization

    private func initializeCompanionViewModel() {
        guard companionViewModel == nil else { return }
        let container = modelContext.container

        let context = container.mainContext
        let descriptor = FetchDescriptor<UserProfile>()
        let profiles = (try? context.fetch(descriptor)) ?? []
        let profileId = profiles.first?.id ?? UUID()

        companionViewModel = CompanionChatViewModel(
            modelContainer: container,
            profileId: profileId
        )
    }
}

// MARK: - Tab Content View (with NavigationStack per tab)

private struct TabContentView: View {

    let tab: AppTab
    @State private var coordinator = NavigationCoordinator()

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            tabRootView
                .navigationDestination(for: NavigationDestination.self) { destination in
                    Text("Detail: \(String(describing: destination))")
                        .foregroundStyle(.white)
                }
        }
        .environment(\.navigationCoordinator, coordinator)
    }

    @ViewBuilder
    private var tabRootView: some View {
        switch tab {
        case .home:
            HomeView()
        case .study:
            EtudeView()
        case .companion:
            CompanionTabView()
        case .rpg:
            RPGProfileView()
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
