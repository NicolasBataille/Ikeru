import Foundation
import os

// MARK: - PitchAccentTracking Protocol

/// Tracks pitch accent accuracy over time, persisting results per pattern type.
public protocol PitchAccentTracking: Sendable {
    /// Records whether a pitch accent attempt was correct.
    func recordResult(pattern: PitchAccentType, wasCorrect: Bool) async

    /// Returns the accuracy (0.0 to 1.0) for a specific pattern type.
    func accuracy(for pattern: PitchAccentType) async -> Double

    /// Returns the total number of attempts for a specific pattern type.
    func totalAttempts(for pattern: PitchAccentType) async -> Int

    /// Returns the overall accuracy across all pattern types.
    func overallAccuracy() async -> Double
}

// MARK: - PitchAccentTracker

/// Persists pitch accent accuracy stats per pattern type using UserDefaults.
/// Thread-safe via actor isolation.
public actor PitchAccentTracker: PitchAccentTracking {

    // MARK: - Storage Keys

    private static let storageKeyPrefix = "com.ikeru.pitchAccent."

    // MARK: - State

    private var stats: [PitchAccentType: PatternStats]
    private let defaults: UserDefaults

    // MARK: - PatternStats

    private struct PatternStats: Codable, Sendable {
        var correct: Int
        var total: Int

        var accuracy: Double {
            guard total > 0 else { return 0.0 }
            return Double(correct) / Double(total)
        }
    }

    // MARK: - Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.stats = [:]

        // Load persisted stats
        for type in PitchAccentType.allCases {
            let key = Self.storageKeyPrefix + type.rawValue
            if let data = defaults.data(forKey: key),
               let decoded = try? JSONDecoder().decode(PatternStats.self, from: data) {
                self.stats[type] = decoded
            } else {
                self.stats[type] = PatternStats(correct: 0, total: 0)
            }
        }
    }

    // MARK: - PitchAccentTracking

    public func recordResult(pattern: PitchAccentType, wasCorrect: Bool) {
        var current = stats[pattern] ?? PatternStats(correct: 0, total: 0)
        current.total += 1
        if wasCorrect {
            current.correct += 1
        }
        stats[pattern] = current

        // Persist
        let key = Self.storageKeyPrefix + pattern.rawValue
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: key)
        }

        Logger.audio.debug(
            "Pitch accent tracked: pattern=\(pattern.rawValue), correct=\(wasCorrect), accuracy=\(String(format: "%.0f%%", current.accuracy * 100))"
        )
    }

    public func accuracy(for pattern: PitchAccentType) -> Double {
        stats[pattern]?.accuracy ?? 0.0
    }

    public func totalAttempts(for pattern: PitchAccentType) -> Int {
        stats[pattern]?.total ?? 0
    }

    public func overallAccuracy() -> Double {
        let allStats = stats.values
        let totalCorrect = allStats.reduce(0) { $0 + $1.correct }
        let totalAttempts = allStats.reduce(0) { $0 + $1.total }
        guard totalAttempts > 0 else { return 0.0 }
        return Double(totalCorrect) / Double(totalAttempts)
    }

    /// Resets all tracking data. Useful for testing.
    public func reset() {
        for type in PitchAccentType.allCases {
            stats[type] = PatternStats(correct: 0, total: 0)
            let key = Self.storageKeyPrefix + type.rawValue
            defaults.removeObject(forKey: key)
        }
    }
}
