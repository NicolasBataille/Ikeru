import Testing
@testable import Ikeru
@testable import IkeruCore

// MARK: - OnboardingRestoreDecisionTests
//
// `OnboardingRestoreDecision.decide` is the pure decision behind onboarding's
// "I already have an account" restore path (`NameEntryView.performRestoreSync()`)
// — no SwiftUI, no `ModelContainer`, no real Apple identity, so every branch
// is exercised directly here against plain `CloudSyncCoordinator.SyncOutcome`
// values.

@Suite("OnboardingRestoreDecision")
struct OnboardingRestoreDecisionTests {

    // MARK: - hasProfile wins, regardless of outcome

    @Test("A profile found after sync always restores, even on a failed sync")
    func profileFoundWinsOverFailure() {
        let decision = OnboardingRestoreDecision.decide(
            outcome: .failure("network unreachable"),
            hasProfile: true
        )
        #expect(decision == .profileRestored)
    }

    @Test("A profile found after sync always restores, even when this call reports already-syncing")
    func profileFoundWinsOverAlreadySyncing() {
        // Simulates a concurrent foreground/network-regain trigger delivering
        // the profile while THIS call's own syncNow() reports the reentrance
        // guard instead of a clean success.
        let decision = OnboardingRestoreDecision.decide(
            outcome: .skippedAlreadySyncing,
            hasProfile: true
        )
        #expect(decision == .profileRestored)
    }

    @Test("A profile found after a clean success restores")
    func profileFoundWinsOverSuccess() {
        let decision = OnboardingRestoreDecision.decide(
            outcome: .success(pushedRowCount: 0, pull: .applied(rowCount: 3, skippedRowCount: 0, permanentlyDroppedRowCount: 0)),
            hasProfile: true
        )
        #expect(decision == .profileRestored)
    }

    // MARK: - No profile, pull genuinely completed → no backup exists

    @Test("No profile, pull applied cleanly — genuinely no backup")
    func noProfileAppliedPull() {
        let decision = OnboardingRestoreDecision.decide(
            outcome: .success(pushedRowCount: 0, pull: .applied(rowCount: 0, skippedRowCount: 0, permanentlyDroppedRowCount: 0)),
            hasProfile: false
        )
        #expect(decision == .noBackupFound)
    }

    @Test("No profile, pull seeded from local (cold-start rule 1) — genuinely no backup")
    func noProfileSeededFromLocal() {
        let decision = OnboardingRestoreDecision.decide(
            outcome: .success(pushedRowCount: 5, pull: .seededFromLocal),
            hasProfile: false
        )
        #expect(decision == .noBackupFound)
    }

    // MARK: - No profile, pull itself failed → can't tell, not "no backup"

    @Test("No profile, pull failed — cannot conclude no backup exists")
    func noProfilePullFailed() {
        let decision = OnboardingRestoreDecision.decide(
            outcome: .success(pushedRowCount: 0, pull: .failed("timeout")),
            hasProfile: false
        )
        #expect(decision == .syncFailed(message: "timeout"))
    }

    // MARK: - No profile, push itself failed

    @Test("No profile, push failed outright — genuine sync failure")
    func noProfilePushFailed() {
        let decision = OnboardingRestoreDecision.decide(
            outcome: .failure("401 Unauthorized"),
            hasProfile: false
        )
        #expect(decision == .syncFailed(message: "401 Unauthorized"))
    }

    // MARK: - No profile, sync didn't actually run this attempt

    @Test("No profile, throttled — ambiguous, not a hard failure")
    func noProfileThrottled() {
        let decision = OnboardingRestoreDecision.decide(outcome: .skippedThrottled, hasProfile: false)
        #expect(decision == .retryShortly)
    }

    @Test("No profile, another sync already in flight — ambiguous, not a hard failure")
    func noProfileAlreadySyncing() {
        let decision = OnboardingRestoreDecision.decide(outcome: .skippedAlreadySyncing, hasProfile: false)
        #expect(decision == .retryShortly)
    }

    // MARK: - No profile, consent unexpectedly off (should be unreachable in practice)

    @Test("No profile, consent unexpectedly off — treated as a failure, never as 'no backup'")
    func noProfileConsentOff() {
        let decision = OnboardingRestoreDecision.decide(outcome: .skippedConsentOff, hasProfile: false)
        guard case .syncFailed = decision else {
            Issue.record("Expected .syncFailed, got \(decision)")
            return
        }
    }
}
