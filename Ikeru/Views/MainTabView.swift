import SwiftUI
import SwiftData
import IkeruCore

// MARK: - Tab Definition

enum AppTab: Int, CaseIterable, Identifiable {
    case home
    case study
    case companion
    case rpg
    case settings

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
        case .home: return "house.fill"
        case .study: return "book.fill"
        case .companion: return "bubble.left.fill"
        case .rpg: return "shield.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - MainTabView

struct MainTabView: View {

    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                TabContentView(tab: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .tag(tab)
            }
        }
        .tint(Color(hex: IkeruTheme.Colors.primaryAccent))
        .onAppear {
            configureTabBarAppearance()
        }
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor(
            red: CGFloat((IkeruTheme.Colors.surface >> 16) & 0xFF) / 255.0,
            green: CGFloat((IkeruTheme.Colors.surface >> 8) & 0xFF) / 255.0,
            blue: CGFloat(IkeruTheme.Colors.surface & 0xFF) / 255.0,
            alpha: 1.0
        )

        // Active tab color (amber)
        let activeColor = UIColor(
            red: CGFloat((IkeruTheme.Colors.primaryAccent >> 16) & 0xFF) / 255.0,
            green: CGFloat((IkeruTheme.Colors.primaryAccent >> 8) & 0xFF) / 255.0,
            blue: CGFloat(IkeruTheme.Colors.primaryAccent & 0xFF) / 255.0,
            alpha: 1.0
        )

        // Inactive tab color (white 40%)
        let inactiveColor = UIColor.white.withAlphaComponent(0.4)

        appearance.stackedLayoutAppearance.selected.iconColor = activeColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: activeColor]
        appearance.stackedLayoutAppearance.normal.iconColor = inactiveColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: inactiveColor]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
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
            HomeTabView()
        case .settings:
            SettingsView()
        default:
            PlaceholderTabView(tab: tab)
        }
    }
}

// MARK: - Home Tab View

private struct HomeTabView: View {

    @Environment(\.profileViewModel) private var profileViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var sessionViewModel: SessionViewModel?
    @State private var showSession = false

    var body: some View {
        ZStack {
            Color.ikeruBackground
                .ignoresSafeArea()

            VStack(spacing: IkeruTheme.Spacing.lg) {
                if let name = profileViewModel?.displayName, !name.isEmpty {
                    Text("Welcome, \(name)!")
                        .font(.ikeruHeading1)
                        .foregroundStyle(.white)
                } else {
                    Text("Welcome!")
                        .font(.ikeruHeading1)
                        .foregroundStyle(.white)
                }

                Text("Ready to study?")
                    .font(.ikeruBody)
                    .foregroundStyle(.ikeruTextSecondary)

                // XP Bar (full variant) on home screen
                if let vm = sessionViewModel {
                    XPBarView(
                        totalXP: vm.totalXP,
                        level: vm.currentLevel,
                        variant: .full
                    )
                    .padding(.horizontal, IkeruTheme.Spacing.lg)
                    .ikeruCard(.standard)
                    .padding(.horizontal, IkeruTheme.Spacing.md)
                }

                Spacer()

                VStack(spacing: IkeruTheme.Spacing.md) {
                    Button {
                        startSession()
                    } label: {
                        HStack(spacing: IkeruTheme.Spacing.sm) {
                            Image(systemName: "play.fill")
                            Text("Start Session")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .ikeruButtonStyle(.primary)
                    .padding(.horizontal, IkeruTheme.Spacing.lg)

                    // Session preview
                    if let vm = sessionViewModel, vm.estimatedCardCount > 0 {
                        Text("~\(estimatedMinutes(vm.estimatedCardCount)) min \u{00B7} \(vm.estimatedCardCount) reviews")
                            .font(.ikeruCaption)
                            .foregroundStyle(.ikeruTextSecondary)
                    } else {
                        Text("Start a session to begin learning")
                            .font(.ikeruCaption)
                            .foregroundStyle(.ikeruTextSecondary)
                    }
                }

                Spacer()
            }
            .padding(.top, IkeruTheme.Spacing.xl)
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .fullScreenCover(isPresented: $showSession) {
            if let vm = sessionViewModel {
                ActiveSessionView(viewModel: vm)
                    .onChange(of: vm.isActive) { _, isActive in
                        if !isActive {
                            showSession = false
                            // Refresh estimate and RPG state after session ends
                            Task {
                                await vm.loadSessionEstimate()
                                await vm.loadRPGStateForDisplay()
                            }
                        }
                    }
            }
        }
        .task {
            initializeSessionViewModel()
            await sessionViewModel?.loadSessionEstimate()
            await sessionViewModel?.loadRPGStateForDisplay()
        }
    }

    // MARK: - Helpers

    private func initializeSessionViewModel() {
        guard sessionViewModel == nil else { return }
        let container = modelContext.container
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)
        sessionViewModel = SessionViewModel(
            plannerService: planner,
            cardRepository: repo,
            modelContainer: container
        )
    }

    private func startSession() {
        guard let vm = sessionViewModel else { return }
        Task {
            // Seed content if needed
            let container = modelContext.container
            let repo = CardRepository(modelContainer: container)
            let allCards = await repo.allCards()
            await ContentSeedService.seedBeginnerKanaIfNeeded(
                repository: repo,
                existingCardCount: allCards.count
            )
            await vm.startSession()
            showSession = true
        }
    }

    private func estimatedMinutes(_ cardCount: Int) -> Int {
        max(1, cardCount) // Roughly 1 minute per card
    }
}

// MARK: - Placeholder View

private struct PlaceholderTabView: View {

    let tab: AppTab

    var body: some View {
        ZStack {
            Color(hex: IkeruTheme.Colors.background)
                .ignoresSafeArea()

            VStack(spacing: IkeruTheme.Spacing.md) {
                Image(systemName: tab.icon)
                    .font(.system(size: 48))
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.primaryAccent))

                Text(tab.title)
                    .font(.ikeruHeading1)
                    .foregroundStyle(.white)

                Text("Coming soon...")
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruTextSecondary)
            }
        }
        .navigationTitle(tab.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: - Preview

#Preview("MainTabView") {
    MainTabView()
        .preferredColorScheme(.dark)
}
