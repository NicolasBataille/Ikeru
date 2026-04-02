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
            HomeView()
        case .settings:
            SettingsView()
        default:
            PlaceholderTabView(tab: tab)
        }
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
