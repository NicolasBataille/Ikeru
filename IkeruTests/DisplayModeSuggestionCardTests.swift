import Testing
import Foundation
@testable import Ikeru
@testable import IkeruCore

@Suite("DisplayModeSuggestionCardController")
struct DisplayModeSuggestionCardTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "SuggestionCardTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Eligible + not yet shown → shouldShow = true")
    func showsWhenEligible() {
        let defaults = makeDefaults()
        let id = UUID()
        let controller = DisplayModeSuggestionCardController(
            defaults: defaults,
            profileID: id,
            currentMode: .beginner
        )
        controller.onSignalsChanged(streak: 25, reviews: 600, mastery: 60)
        #expect(controller.shouldShow == true)
    }

    @Test("Already dismissed → shouldShow = false even when eligible")
    func dismissedSticks() {
        let defaults = makeDefaults()
        let id = UUID()
        defaults.set(true, forKey: "ikeru.display.mode.suggestionShown.\(id.uuidString)")
        let controller = DisplayModeSuggestionCardController(
            defaults: defaults,
            profileID: id,
            currentMode: .beginner
        )
        controller.onSignalsChanged(streak: 25, reviews: 600, mastery: 60)
        #expect(controller.shouldShow == false)
    }

    @Test("Mode is .tatami → shouldShow = false (already advanced)")
    func tatamiHidesCard() {
        let defaults = makeDefaults()
        let id = UUID()
        let controller = DisplayModeSuggestionCardController(
            defaults: defaults,
            profileID: id,
            currentMode: .tatami
        )
        controller.onSignalsChanged(streak: 25, reviews: 600, mastery: 60)
        #expect(controller.shouldShow == false)
    }

    @Test("dismiss() persists and hides")
    func dismissPersists() {
        let defaults = makeDefaults()
        let id = UUID()
        let controller = DisplayModeSuggestionCardController(
            defaults: defaults,
            profileID: id,
            currentMode: .beginner
        )
        controller.onSignalsChanged(streak: 25, reviews: 600, mastery: 60)
        controller.dismiss()
        #expect(controller.shouldShow == false)
        #expect(defaults.bool(forKey: "ikeru.display.mode.suggestionShown.\(id.uuidString)") == true)
    }
}
