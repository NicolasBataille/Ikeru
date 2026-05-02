import Foundation
@preconcurrency import Combine

/// Profile-scoped preference store for `DisplayMode`. Implementations must
/// resolve the active profile id internally on every call so a profile
/// switch is reflected without restarting.
public protocol DisplayModePreferenceRepository: Sendable {
    /// Current mode for the active profile. Triggers lazy migration on first
    /// read for a profile that has no stored value yet.
    func current() -> DisplayMode

    /// Persist a new mode for the active profile. Publishes on `publisher`.
    func set(_ mode: DisplayMode)

    /// Stream of mode values for the active profile. Replays the current
    /// value on subscribe.
    var publisher: AnyPublisher<DisplayMode, Never> { get }
}

public final class UserDefaultsDisplayModePreferenceRepository:
    DisplayModePreferenceRepository, @unchecked Sendable
{
    private static let keyPrefix = "ikeru.display.mode."

    private let defaults: UserDefaults
    private let activeProfileID: @Sendable () -> UUID?
    private let profileCreatedAt: @Sendable (UUID) -> Date?
    private let subject: CurrentValueSubject<DisplayMode, Never>

    public init(
        defaults: UserDefaults = .standard,
        activeProfileID: @escaping @Sendable () -> UUID?,
        profileCreatedAt: @escaping @Sendable (UUID) -> Date?
    ) {
        self.defaults = defaults
        self.activeProfileID = activeProfileID
        self.profileCreatedAt = profileCreatedAt
        // Seed subject with whatever current() returns now (which performs
        // lazy migration if needed).
        self.subject = CurrentValueSubject(.beginner)
        self.subject.send(self.resolveCurrent())
    }

    public func current() -> DisplayMode {
        resolveCurrent()
    }

    public func set(_ mode: DisplayMode) {
        guard let id = activeProfileID() else { return }
        defaults.set(mode.rawValue, forKey: Self.keyPrefix + id.uuidString)
        subject.send(mode)
    }

    public var publisher: AnyPublisher<DisplayMode, Never> {
        subject.eraseToAnyPublisher()
    }

    // MARK: - Private

    private func resolveCurrent() -> DisplayMode {
        guard let id = activeProfileID() else { return .beginner }
        let key = Self.keyPrefix + id.uuidString
        if let raw = defaults.string(forKey: key), let mode = DisplayMode(rawValue: raw) {
            return mode
        }
        // Lazy migration: branch on profile age.
        let createdAt = profileCreatedAt(id) ?? Date()
        let migrated: DisplayMode = createdAt < DisplayModeReleaseDate.value
            ? .tatami
            : .beginner
        defaults.set(migrated.rawValue, forKey: key)
        return migrated
    }
}
