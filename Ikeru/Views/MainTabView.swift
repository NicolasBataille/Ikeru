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

    var body: some View {
        ZStack(alignment: .bottom) {
            IkeruScreenBackground()

            // Tab content
            tabContent
                .ignoresSafeArea(.keyboard)

            // Custom floating Liquid Glass tab bar
            IkeruTabBar(selection: $selectedTab, tabs: AppTab.allCases)
                .ignoresSafeArea(.keyboard)
        }
        .onAppear {
            initializeCompanionViewModel()
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
            ForEach(AppTab.allCases) { tab in
                if selectedTab == tab {
                    TabContentView(tab: tab)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.98)),
                                removal: .opacity
                            )
                        )
                }
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: selectedTab)
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
            ProgressDashboardView()
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
