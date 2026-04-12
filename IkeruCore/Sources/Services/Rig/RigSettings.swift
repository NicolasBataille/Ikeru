import Foundation

// MARK: - RigSettings
//
// User-configurable settings for the local ikeru-rig bridge.
//
// The base URL is stored in `UserDefaults` because it's not sensitive (just a
// LAN IP). The shared token IS sensitive and lives in the Keychain via the
// `KeychainStore` protocol — same pattern as every other API key in the app.

public struct RigSettings: Sendable, Equatable {

    /// Base URL of the rig server, e.g. `http://192.168.1.42:8787`.
    public let baseURL: URL

    /// Shared secret enforced by the rig's `X-Ikeru-Token` middleware.
    public let sharedToken: String

    /// Per-request timeout in seconds.
    public let requestTimeout: TimeInterval

    public init(
        baseURL: URL,
        sharedToken: String,
        requestTimeout: TimeInterval = 15
    ) {
        self.baseURL = baseURL
        self.sharedToken = sharedToken
        self.requestTimeout = requestTimeout
    }

    /// True when both pieces are present and the URL is non-empty.
    public var isConfigured: Bool {
        !baseURL.absoluteString.isEmpty && !sharedToken.isEmpty
    }
}

// MARK: - Persistence

/// Keys used by `RigSettingsStore` to read/write settings.
public enum RigSettingsStoreKeys {
    public static let baseURL = "com.ikeru.rig.base-url"
    public static let token = "com.ikeru.rig.shared-token"
}

/// Loads and saves `RigSettings` from a `KeychainStore` (token) plus
/// `UserDefaults` (URL). Tests can substitute both.
public struct RigSettingsStore: @unchecked Sendable {

    private let keychain: any KeychainStore
    private let defaults: UserDefaults

    public init(
        keychain: any KeychainStore = KeychainHelper(),
        defaults: UserDefaults = .standard
    ) {
        self.keychain = keychain
        self.defaults = defaults
    }

    public func load() -> RigSettings? {
        guard let urlString = defaults.string(forKey: RigSettingsStoreKeys.baseURL),
              let url = URL(string: urlString) else {
            return nil
        }
        let token = (try? keychain.load(key: RigSettingsStoreKeys.token)) ?? ""
        return RigSettings(baseURL: url, sharedToken: token)
    }

    public func save(_ settings: RigSettings) throws {
        defaults.set(settings.baseURL.absoluteString, forKey: RigSettingsStoreKeys.baseURL)
        try keychain.save(key: RigSettingsStoreKeys.token, value: settings.sharedToken)
    }

    public func clear() throws {
        defaults.removeObject(forKey: RigSettingsStoreKeys.baseURL)
        try? keychain.delete(key: RigSettingsStoreKeys.token)
    }
}
