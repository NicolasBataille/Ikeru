import Foundation
import Security
import os

// MARK: - Keychain Key Constants

/// Well-known Keychain key identifiers for AI provider secrets.
public enum KeychainKeys {
    public static let geminiAPIKey = "com.ikeru.gemini-api-key"
    public static let claudeAPIKey = "com.ikeru.claude-api-key"
    public static let openRouterAPIKey = "com.ikeru.openrouter-api-key"
    public static let groqAPIKey = "com.ikeru.groq-api-key"
    public static let cerebrasAPIKey = "com.ikeru.cerebras-api-key"
    public static let githubModelsAPIKey = "com.ikeru.github-models-api-key"

    /// Legacy key kept for backwards-compatible read-only migration.
    @available(*, deprecated, message: "Anthropic closed third-party subscription auth. Use claudeAPIKey for paid API access.")
    public static let claudeSessionToken = "com.ikeru.claude-session-token"
}

// MARK: - KeychainStore Protocol

/// Abstraction over Keychain access for testability.
public protocol KeychainStore: Sendable {
    /// Save a value to the Keychain under the given key.
    func save(key: String, value: String) throws
    /// Load a value from the Keychain for the given key. Returns nil if not found.
    func load(key: String) throws -> String?
    /// Delete a value from the Keychain for the given key.
    func delete(key: String) throws
}

// MARK: - KeychainError

public enum KeychainError: Error, Sendable {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case encodingFailed
}

// MARK: - KeychainHelper

/// Production Keychain implementation using Security framework.
/// Uses kSecClassGenericPassword with kSecAttrAccessibleWhenUnlockedThisDeviceOnly.
public struct KeychainHelper: KeychainStore, Sendable {

    public init() {}

    public func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing item first to avoid duplicates
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            Logger.ai.error("Keychain save failed for key (status: \(status))")
            throw KeychainError.saveFailed(status)
        }
    }

    public func load(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            Logger.ai.error("Keychain load failed for key (status: \(status))")
            throw KeychainError.loadFailed(status)
        }

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    public func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            Logger.ai.error("Keychain delete failed for key (status: \(status))")
            throw KeychainError.deleteFailed(status)
        }
    }
}

// MARK: - MockKeychainStore

/// In-memory mock for testing. Thread-safe via actor isolation not needed
/// since tests run serially within a Suite.
public final class MockKeychainStore: KeychainStore, @unchecked Sendable {

    private var storage: [String: String] = [:]
    private let lock = NSLock()

    public init(initialValues: [String: String] = [:]) {
        self.storage = initialValues
    }

    public func save(key: String, value: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = value
    }

    public func load(key: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func delete(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}
