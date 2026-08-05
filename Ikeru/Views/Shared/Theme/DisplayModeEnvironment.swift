import SwiftUI
import IkeruCore

private struct DisplayModeKey: EnvironmentKey {
    static let defaultValue: DisplayMode = .beginner
}

private struct DisplayModeRepositoryKey: EnvironmentKey {
    static let defaultValue: (any DisplayModePreferenceRepository)? = nil
}

extension EnvironmentValues {
    var displayMode: DisplayMode {
        get { self[DisplayModeKey.self] }
        set { self[DisplayModeKey.self] = newValue }
    }

    var displayModeRepository: (any DisplayModePreferenceRepository)? {
        get { self[DisplayModeRepositoryKey.self] }
        set { self[DisplayModeRepositoryKey.self] = newValue }
    }
}

extension Notification.Name {
    /// Posted when the active profile's `DisplayMode` is changed from outside
    /// the shared repository instance (e.g. the onboarding placement step,
    /// which writes through a freshly-built repository). `MainTabView` observes
    /// this to re-read its live `displayMode` without waiting for a relaunch.
    static let displayModeDidChange = Notification.Name("ikeru.displayMode.didChange")
}
