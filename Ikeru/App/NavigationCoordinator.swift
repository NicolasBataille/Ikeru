import SwiftUI
import IkeruCore
import os

// MARK: - Navigation Destination

public enum NavigationDestination: Hashable {
    // Home
    case home

    // Study
    case studySession
    case reviewQueue

    // Companion
    case companionChat

    // RPG
    case rpgProfile
    case rpgQuest

    // Settings
    case settings
    case settingsAppearance
}

// MARK: - NavigationCoordinator

@MainActor
@Observable
public final class NavigationCoordinator {

    public var path = NavigationPath()

    public var pathCount: Int {
        path.count
    }

    public init() {}

    // MARK: - Navigation Actions

    public func push(_ destination: NavigationDestination) {
        Logger.ui.debug("Navigation push: \(String(describing: destination))")
        path.append(destination)
    }

    public func pop() {
        guard path.count > 0 else {
            Logger.ui.warning("Navigation pop called on empty path")
            return
        }
        Logger.ui.debug("Navigation pop")
        path.removeLast()
    }

    public func popToRoot() {
        guard path.count > 0 else { return }
        Logger.ui.debug("Navigation pop to root from depth \(self.path.count)")
        path = NavigationPath()
    }
}

// MARK: - Environment Key

private struct NavigationCoordinatorKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue = NavigationCoordinator()
}

extension EnvironmentValues {
    public var navigationCoordinator: NavigationCoordinator {
        get { self[NavigationCoordinatorKey.self] }
        set { self[NavigationCoordinatorKey.self] = newValue }
    }
}
