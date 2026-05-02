import Foundation
import Combine

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
