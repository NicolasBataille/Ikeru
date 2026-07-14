import Testing
import Foundation
@testable import IkeruCore

@Suite("TatamiSuggestionCooldown")
struct TatamiSuggestionCooldownTests {

    private let calendar = Calendar(identifier: .gregorian)

    @Test("Never dismissed → should offer")
    func neverDismissed() {
        #expect(TatamiSuggestionCooldown.shouldOffer(lastDismissedAt: nil, now: Date()))
    }

    @Test("Dismissed today → should not offer")
    func dismissedToday() {
        let now = Date()
        #expect(!TatamiSuggestionCooldown.shouldOffer(lastDismissedAt: now, now: now, calendar: calendar))
    }

    @Test("Dismissed 13 days ago → should not offer (cooldown not elapsed)")
    func thirteenDaysAgo() {
        let now = Date()
        let dismissed = calendar.date(byAdding: .day, value: -13, to: now)!
        #expect(!TatamiSuggestionCooldown.shouldOffer(lastDismissedAt: dismissed, now: now, calendar: calendar))
    }

    @Test("Dismissed exactly 14 days ago → should offer (inclusive boundary)")
    func fourteenDaysAgo() {
        let now = Date()
        let dismissed = calendar.date(byAdding: .day, value: -14, to: now)!
        #expect(TatamiSuggestionCooldown.shouldOffer(lastDismissedAt: dismissed, now: now, calendar: calendar))
    }

    @Test("Dismissed 30 days ago → should offer")
    func thirtyDaysAgo() {
        let now = Date()
        let dismissed = calendar.date(byAdding: .day, value: -30, to: now)!
        #expect(TatamiSuggestionCooldown.shouldOffer(lastDismissedAt: dismissed, now: now, calendar: calendar))
    }
}

@Suite("UserDefaultsTatamiSuggestionDismissalRepository")
struct TatamiSuggestionDismissalRepositoryTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "TatamiSuggestionDismissalTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("No dismissal recorded → nil")
    func noDismissal() {
        let defaults = makeDefaults()
        let profileID = UUID()
        let repo = UserDefaultsTatamiSuggestionDismissalRepository(
            defaults: defaults,
            activeProfileID: { profileID }
        )
        #expect(repo.lastDismissedAt() == nil)
    }

    @Test("Recording a dismissal persists and is read back")
    func recordAndRead() {
        let defaults = makeDefaults()
        let profileID = UUID()
        let repo = UserDefaultsTatamiSuggestionDismissalRepository(
            defaults: defaults,
            activeProfileID: { profileID }
        )
        let date = Date()
        repo.recordDismissal(at: date)
        #expect(repo.lastDismissedAt()?.timeIntervalSince1970 == date.timeIntervalSince1970)
    }

    @Test("Profile scoping: two profiles maintain independent dismissal dates")
    func profileScoping() {
        let defaults = makeDefaults()
        let p1 = UUID()
        let p2 = UUID()
        final class Holder: @unchecked Sendable {
            var id: UUID
            init(_ id: UUID) { self.id = id }
        }
        let holder = Holder(p1)
        let repo = UserDefaultsTatamiSuggestionDismissalRepository(
            defaults: defaults,
            activeProfileID: { holder.id }
        )

        let p1Date = Date()
        repo.recordDismissal(at: p1Date)
        holder.id = p2
        #expect(repo.lastDismissedAt() == nil)
        holder.id = p1
        #expect(repo.lastDismissedAt() != nil)
    }

    @Test("Missing profile: recordDismissal and lastDismissedAt are safe no-ops")
    func missingProfile() {
        let defaults = makeDefaults()
        let repo = UserDefaultsTatamiSuggestionDismissalRepository(
            defaults: defaults,
            activeProfileID: { nil }
        )
        repo.recordDismissal(at: Date())
        #expect(repo.lastDismissedAt() == nil)
        #expect(defaults.dictionaryRepresentation().keys.contains {
            $0.hasPrefix("ikeru.display.mode.suggestionDismissedAt.")
        } == false)
    }
}
