import Testing
import SwiftUI
@testable import Ikeru
@testable import IkeruCore

@Suite("DisplayMode environment")
@MainActor
struct DisplayModeEnvironmentTests {

    @Test("Default value is .beginner")
    func defaultValue() {
        let value = EnvironmentValues().displayMode
        #expect(value == .beginner)
    }

    @Test("Reads injected value")
    func injectedValue() {
        var env = EnvironmentValues()
        env.displayMode = .tatami
        #expect(env.displayMode == .tatami)
    }
}
