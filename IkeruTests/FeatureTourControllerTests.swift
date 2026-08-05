import Testing
import Foundation
@testable import Ikeru

@MainActor
@Suite("FeatureTourController")
struct FeatureTourControllerTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "FeatureTourTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("startIfNeeded begins the tour for a fresh profile")
    func startsWhenUnseen() {
        let controller = FeatureTourController(defaults: makeDefaults())
        let id = UUID()
        controller.startIfNeeded(profileID: id)
        #expect(controller.isActive)
        #expect(controller.index == 0)
        #expect(controller.currentStep != nil)
    }

    @Test("startIfNeeded is a no-op once the tour has been seen")
    func skipsWhenAlreadySeen() {
        let defaults = makeDefaults()
        let id = UUID()
        defaults.set(true, forKey: FeatureTourController.storageKey(for: id))
        let controller = FeatureTourController(defaults: defaults)
        controller.startIfNeeded(profileID: id)
        #expect(controller.isActive == false)
    }

    @Test("next advances through steps")
    func nextAdvances() {
        let controller = FeatureTourController(defaults: makeDefaults())
        controller.startIfNeeded(profileID: UUID())
        controller.next()
        #expect(controller.index == 1)
    }

    @Test("completing the last step ends the tour and marks it seen")
    func completionMarksSeen() {
        let defaults = makeDefaults()
        let id = UUID()
        let controller = FeatureTourController(defaults: defaults)
        controller.startIfNeeded(profileID: id)
        // Walk to the end.
        for _ in 0..<controller.totalSteps {
            controller.next()
        }
        #expect(controller.isActive == false)
        #expect(controller.hasSeenTour(profileID: id))
    }

    @Test("skip ends the tour immediately and marks it seen")
    func skipMarksSeen() {
        let defaults = makeDefaults()
        let id = UUID()
        let controller = FeatureTourController(defaults: defaults)
        controller.startIfNeeded(profileID: id)
        controller.skip()
        #expect(controller.isActive == false)
        #expect(controller.hasSeenTour(profileID: id))
    }

    @Test("back never goes below the first step")
    func backClampsAtZero() {
        let controller = FeatureTourController(defaults: makeDefaults())
        controller.startIfNeeded(profileID: UUID())
        controller.back()
        #expect(controller.index == 0)
    }

    @Test("restart replays the tour even after it was seen")
    func restartIgnoresSeenFlag() {
        let defaults = makeDefaults()
        let id = UUID()
        defaults.set(true, forKey: FeatureTourController.storageKey(for: id))
        let controller = FeatureTourController(defaults: defaults)
        controller.restart(profileID: id)
        #expect(controller.isActive)
        #expect(controller.index == 0)
    }
}
