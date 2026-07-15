import Foundation

// MARK: - StoreRecoveryNotice

/// `UserDefaults`-backed flag recording that a `StoreRecovery.moveStoreAside`
/// recovery happened, so the UI can surface a one-time, honest notice the
/// next time the user sees a screen — the container-creation retry happens
/// synchronously inside `IkeruApp.init`, before any SwiftUI view exists to
/// present an alert immediately.
///
/// Persisted (not just in-memory) so the notice survives a cold relaunch
/// between the recovery happening and the user next opening the app.
enum StoreRecoveryNotice {

    private static let pendingKey = "ikeru.storeRecovery.pending"
    private static let recoveryPathKey = "ikeru.storeRecovery.path"

    /// Records that recovery happened and a notice is owed to the user.
    static func markPending(recoveryDirectory: URL, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: pendingKey)
        defaults.set(recoveryDirectory.path, forKey: recoveryPathKey)
    }

    /// Whether a recovery notice is still owed to the user.
    static func isPending(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: pendingKey)
    }

    /// The recovery directory's path, for reference in the notice/logs.
    /// `nil` if no recovery is pending or none was ever recorded.
    static func recoveryPath(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: recoveryPathKey)
    }

    /// Clears the pending flag once the user has seen the notice.
    static func acknowledge(defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: pendingKey)
    }
}
