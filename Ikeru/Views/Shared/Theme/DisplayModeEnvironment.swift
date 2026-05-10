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
