import Foundation
import Observation

// MARK: - Feature Tour Controller
//
// Owns the tour's run state and the per-profile "seen" flag. Mirrors the
// persistence pattern of DisplayModeSuggestionCardController: a UserDefaults
// key namespaced by profile id, so each profile is onboarded once.

@Observable
final class FeatureTourController {

    /// UserDefaults key marking that a given profile finished (or skipped) the tour.
    static func storageKey(for profileID: UUID) -> String {
        "ikeru.hasSeenFeatureTour.\(profileID.uuidString)"
    }

    private let defaults: UserDefaults
    let steps: [TourStep]

    private(set) var isActive = false
    private(set) var index = 0
    private var activeProfileID: UUID?

    init(defaults: UserDefaults = .standard, steps: [TourStep] = TourStep.defaultTour) {
        self.defaults = defaults
        self.steps = steps
    }

    // MARK: Derived state

    var currentStep: TourStep? {
        guard isActive, steps.indices.contains(index) else { return nil }
        return steps[index]
    }

    var isFirstStep: Bool { index == 0 }
    var isLastStep: Bool { index >= steps.count - 1 }
    var totalSteps: Int { steps.count }

    // MARK: Persistence

    func hasSeenTour(profileID: UUID) -> Bool {
        defaults.bool(forKey: Self.storageKey(for: profileID))
    }

    /// Marks a profile's tour as already seen without running it — used by
    /// `NameEntryView.performRestoreSync()` for a returning learner whose
    /// progress (and the fact that they've already seen the tour, on
    /// whichever device backed it up) was just restored. Writes directly to
    /// the same UserDefaults key `hasSeenTour(profileID:)` reads, static
    /// and independent of any live `FeatureTourController` instance — the
    /// restore path runs inside `NameEntryView`, a different view hierarchy
    /// than `MainTabView`'s own `tourController`, so there is no shared
    /// instance to call `complete()` on.
    static func markSeen(profileID: UUID, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: storageKey(for: profileID))
    }

    // MARK: Lifecycle

    /// Starts the tour only if this profile has never completed it. Safe to call
    /// repeatedly — a no-op while a tour is already running or already seen.
    func startIfNeeded(profileID: UUID) {
        guard !isActive, !hasSeenTour(profileID: profileID) else { return }
        begin(profileID: profileID)
    }

    /// Plays the tour again on demand (Settings → replay), ignoring the seen flag.
    func restart(profileID: UUID) {
        begin(profileID: profileID)
    }

    private func begin(profileID: UUID) {
        activeProfileID = profileID
        index = 0
        isActive = true
    }

    func next() {
        guard isActive else { return }
        if isLastStep {
            complete()
        } else {
            index += 1
        }
    }

    func back() {
        guard isActive, index > 0 else { return }
        index -= 1
    }

    func skip() {
        complete()
    }

    private func complete() {
        if let id = activeProfileID {
            defaults.set(true, forKey: Self.storageKey(for: id))
        }
        isActive = false
        index = 0
        activeProfileID = nil
    }
}
