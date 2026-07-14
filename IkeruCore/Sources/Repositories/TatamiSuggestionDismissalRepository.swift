import Foundation

/// Pure day-boundary logic deciding whether the "you're ready for Tatami"
/// suggestion may be shown again after the learner picked "Later".
///
/// Kept separate from the repository so the re-offer rule is a plain,
/// dependency-free function that's trivial to unit test.
public enum TatamiSuggestionCooldown {

    /// Number of full calendar days that must elapse after a "Later"
    /// dismissal before the suggestion may be shown again.
    public static let cooldownDays = 14

    /// Returns `true` when the suggestion should be (re-)offered: either it
    /// was never dismissed, or at least `cooldownDays` full calendar days
    /// have passed since the last dismissal.
    public static func shouldOffer(
        lastDismissedAt: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let lastDismissedAt else { return true }
        let daysSince = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: lastDismissedAt),
            to: calendar.startOfDay(for: now)
        ).day ?? cooldownDays
        return daysSince >= cooldownDays
    }
}

/// Profile-scoped store for the last time the learner dismissed the Tatami
/// suggestion via "Later". Mirrors `DisplayModePreferenceRepository`'s
/// profile-scoping pattern: implementations resolve the active profile id
/// internally on every call so a profile switch is reflected immediately.
public protocol TatamiSuggestionDismissalRepository: Sendable {
    /// The last dismissal date for the active profile, if any.
    func lastDismissedAt() -> Date?

    /// Records a "Later" dismissal for the active profile at the given date.
    func recordDismissal(at date: Date)
}

public final class UserDefaultsTatamiSuggestionDismissalRepository:
    TatamiSuggestionDismissalRepository, @unchecked Sendable
{
    private static let keyPrefix = "ikeru.display.mode.suggestionDismissedAt."

    private let defaults: UserDefaults
    private let activeProfileID: @Sendable () -> UUID?

    public init(
        defaults: UserDefaults = .standard,
        activeProfileID: @escaping @Sendable () -> UUID?
    ) {
        self.defaults = defaults
        self.activeProfileID = activeProfileID
    }

    public func lastDismissedAt() -> Date? {
        guard let id = activeProfileID() else { return nil }
        return defaults.object(forKey: Self.keyPrefix + id.uuidString) as? Date
    }

    public func recordDismissal(at date: Date) {
        guard let id = activeProfileID() else { return }
        defaults.set(date, forKey: Self.keyPrefix + id.uuidString)
    }
}
