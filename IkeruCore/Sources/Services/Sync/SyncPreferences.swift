import Foundation

/// `UserDefaults` keys for cloud-sync consent + status. New keys, declared
/// here rather than reusing an existing preferences file — this lot's file
/// perimeter is limited to `Services/Sync/`.
public enum CloudSyncPreferences {
    /// `Bool`. Default `false` — sync is opt-in, off until the learner says
    /// yes (task item 5). Read this key with `@AppStorage` from the
    /// Settings toggle so the UI and `CloudSyncCoordinator` always agree.
    public static let consentDefaultsKey = "ikeru.cloudSync.consentEnabled"

    /// `Double` (epoch seconds). `0` means "never attempted".
    public static let lastAttemptDefaultsKey = "ikeru.cloudSync.lastAttemptAt"

    /// `Double` (epoch seconds). `0` means "never succeeded" — this is what
    /// the honest "never synced" settings state (task item 5) checks.
    public static let lastSuccessDefaultsKey = "ikeru.cloudSync.lastSuccessAt"

    /// `String?`. Diagnostic message from the most recent failed attempt,
    /// or unset after a success. Not localized UI copy — a display layer
    /// must map this to something a learner can read, not show verbatim.
    public static let lastErrorDefaultsKey = "ikeru.cloudSync.lastError"
}

/// Where `CloudSyncCoordinator` reads/writes consent + status. Protocol
/// boundary so tests never touch real `UserDefaults` (`MockSyncConsentStore`
/// below) or the throttle/attempt bookkeeping.
public protocol SyncConsentStore: Sendable {
    func isConsentGiven() -> Bool
    func setConsentGiven(_ value: Bool)

    func recordAttempt(at date: Date)
    func recordSuccess(at date: Date)
    func recordError(_ message: String?)

    func lastAttemptDate() -> Date?
    func lastSuccessDate() -> Date?
    func lastErrorMessage() -> String?
}

/// Production implementation over `UserDefaults.standard` (or an injected
/// suite, for App Group scenarios later).
public final class UserDefaultsSyncConsentStore: SyncConsentStore, @unchecked Sendable {

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isConsentGiven() -> Bool {
        defaults.bool(forKey: CloudSyncPreferences.consentDefaultsKey)
    }

    public func setConsentGiven(_ value: Bool) {
        defaults.set(value, forKey: CloudSyncPreferences.consentDefaultsKey)
    }

    public func recordAttempt(at date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: CloudSyncPreferences.lastAttemptDefaultsKey)
    }

    public func recordSuccess(at date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: CloudSyncPreferences.lastSuccessDefaultsKey)
    }

    public func recordError(_ message: String?) {
        defaults.set(message, forKey: CloudSyncPreferences.lastErrorDefaultsKey)
    }

    public func lastAttemptDate() -> Date? {
        dateValue(forKey: CloudSyncPreferences.lastAttemptDefaultsKey)
    }

    public func lastSuccessDate() -> Date? {
        dateValue(forKey: CloudSyncPreferences.lastSuccessDefaultsKey)
    }

    public func lastErrorMessage() -> String? {
        defaults.string(forKey: CloudSyncPreferences.lastErrorDefaultsKey)
    }

    private func dateValue(forKey key: String) -> Date? {
        let stored = defaults.double(forKey: key)
        return stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }
}

/// In-memory fake for tests.
public final class MockSyncConsentStore: SyncConsentStore, @unchecked Sendable {

    private var consentGiven: Bool
    private var attemptAt: Date?
    private var successAt: Date?
    private var errorMessage: String?
    private let lock = NSLock()

    public init(consentGiven: Bool = false) {
        self.consentGiven = consentGiven
    }

    public func isConsentGiven() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return consentGiven
    }

    public func setConsentGiven(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        consentGiven = value
    }

    public func recordAttempt(at date: Date) {
        lock.lock(); defer { lock.unlock() }
        attemptAt = date
    }

    public func recordSuccess(at date: Date) {
        lock.lock(); defer { lock.unlock() }
        successAt = date
    }

    public func recordError(_ message: String?) {
        lock.lock(); defer { lock.unlock() }
        errorMessage = message
    }

    public func lastAttemptDate() -> Date? {
        lock.lock(); defer { lock.unlock() }
        return attemptAt
    }

    public func lastSuccessDate() -> Date? {
        lock.lock(); defer { lock.unlock() }
        return successAt
    }

    public func lastErrorMessage() -> String? {
        lock.lock(); defer { lock.unlock() }
        return errorMessage
    }
}
