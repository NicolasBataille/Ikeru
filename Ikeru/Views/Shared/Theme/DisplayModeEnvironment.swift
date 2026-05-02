import SwiftUI
import IkeruCore

private struct DisplayModeKey: EnvironmentKey {
    static let defaultValue: DisplayMode = .beginner
}

extension EnvironmentValues {
    var displayMode: DisplayMode {
        get { self[DisplayModeKey.self] }
        set { self[DisplayModeKey.self] = newValue }
    }
}
