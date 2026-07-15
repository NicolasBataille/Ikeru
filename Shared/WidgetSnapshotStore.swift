import Foundation

/// Key surface for the app-group `UserDefaults` snapshot the home-screen
/// widgets render. Both `Ikeru` (writer) and `IkeruWidget` (reader) target-
/// include this file (see the root-level `Shared` group in the pbxproj, next
/// to `IkeruPlatformTheme.swift`) so the two sides can never drift on key
/// names or the suite id.
enum WidgetSnapshotKeys {
    /// Must match `com.apple.security.application-groups` in both
    /// `Ikeru/Ikeru.entitlements` and `IkeruWidget/IkeruWidget.entitlements`.
    static let suiteName = "group.com.ikeru.shared"
    static let dueCount = "widget.dueCount"
    static let level = "widget.level"
    static let lastStudyDate = "widget.lastStudyDate"
}

/// Snapshot of the data the home-screen widgets render.
struct WidgetSnapshot: Sendable, Equatable {
    let dueCount: Int
    let level: Int
    let lastStudyDate: Date?
}

/// Reads/writes `WidgetSnapshot` in the shared app-group `UserDefaults`.
///
/// Graceful everywhere: if the app-group container isn't available (missing
/// entitlement, un-provisioned simulator run, …) `UserDefaults(suiteName:)`
/// returns nil and every operation below becomes a silent no-op / nil-read
/// instead of a crash. Callers on the read side (widget timeline providers)
/// are expected to fall back to placeholder content when `read()` is nil.
enum WidgetSnapshotStore {
    /// Persists the current snapshot. `lastStudyDate` is optional because a
    /// profile that has never completed a session has no study date yet —
    /// passing `nil` leaves whatever was previously stored untouched rather
    /// than clobbering it.
    static func write(dueCount: Int, level: Int, lastStudyDate: Date?) {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshotKeys.suiteName) else { return }
        defaults.set(dueCount, forKey: WidgetSnapshotKeys.dueCount)
        defaults.set(level, forKey: WidgetSnapshotKeys.level)
        if let lastStudyDate {
            defaults.set(lastStudyDate, forKey: WidgetSnapshotKeys.lastStudyDate)
        }
    }

    /// Reads the last-written snapshot. Returns nil when nothing has been
    /// written yet (fresh install, before the first session/foreground
    /// refresh) or when the shared suite can't be opened.
    static func read() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshotKeys.suiteName) else { return nil }
        guard defaults.object(forKey: WidgetSnapshotKeys.dueCount) != nil else { return nil }
        return WidgetSnapshot(
            dueCount: defaults.integer(forKey: WidgetSnapshotKeys.dueCount),
            level: defaults.integer(forKey: WidgetSnapshotKeys.level),
            lastStudyDate: defaults.object(forKey: WidgetSnapshotKeys.lastStudyDate) as? Date
        )
    }
}
