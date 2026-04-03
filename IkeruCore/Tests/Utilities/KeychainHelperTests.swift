import Testing
import Foundation
@testable import IkeruCore

@Suite("KeychainHelper")
struct KeychainHelperTests {

    // MARK: - Protocol Conformance

    @Test("KeychainHelper conforms to KeychainStore protocol")
    func conformsToProtocol() {
        let helper: any KeychainStore = KeychainHelper()
        #expect(helper is KeychainHelper)
    }

    // MARK: - MockKeychainStore

    @Test("MockKeychainStore saves and loads values")
    func mockSaveAndLoad() throws {
        let store = MockKeychainStore()
        try store.save(key: "test-key", value: "test-value")
        let loaded = try store.load(key: "test-key")
        #expect(loaded == "test-value")
    }

    @Test("MockKeychainStore returns nil for missing key")
    func mockLoadMissing() throws {
        let store = MockKeychainStore()
        let loaded = try store.load(key: "nonexistent")
        #expect(loaded == nil)
    }

    @Test("MockKeychainStore deletes values")
    func mockDelete() throws {
        let store = MockKeychainStore()
        try store.save(key: "test-key", value: "test-value")
        try store.delete(key: "test-key")
        let loaded = try store.load(key: "test-key")
        #expect(loaded == nil)
    }

    @Test("MockKeychainStore overwrites existing values")
    func mockOverwrite() throws {
        let store = MockKeychainStore()
        try store.save(key: "key", value: "original")
        try store.save(key: "key", value: "updated")
        let loaded = try store.load(key: "key")
        #expect(loaded == "updated")
    }

    @Test("MockKeychainStore delete on missing key does not throw")
    func mockDeleteMissing() throws {
        let store = MockKeychainStore()
        try store.delete(key: "nonexistent")
    }

    // MARK: - Keychain Key Constants

    @Test("Keychain keys have correct identifiers")
    func keychainKeyConstants() {
        #expect(KeychainKeys.geminiAPIKey == "com.ikeru.gemini-api-key")
        #expect(KeychainKeys.claudeSessionToken == "com.ikeru.claude-session-token")
    }
}
