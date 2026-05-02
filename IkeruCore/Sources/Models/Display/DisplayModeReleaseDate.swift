import Foundation

public enum DisplayModeReleaseDate {
    /// Profiles created strictly before this date are considered "existing"
    /// for the purpose of the beginner-first migration: they keep `.tatami`
    /// chrome on first launch after the update. Profiles created on or after
    /// this date get `.beginner` as their initial value.
    ///
    /// Update this once at release time; never bump it later.
    public static let value: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 2
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .iso8601).date(from: components)!
    }()
}
