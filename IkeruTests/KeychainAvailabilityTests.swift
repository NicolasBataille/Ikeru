import Testing
import Foundation
@testable import IkeruCore

/// Does the Keychain work at all in this environment?
///
/// Written 2026-08-15 to settle a question that cost an evening. While setting
/// up the two-client merge test (GAP-01) on a simulator, cloud sync stalled on
/// "backup pending" with `ikeru.cloudSync.lastError = saveFailed(-34018)` —
/// `errSecMissingEntitlement`. Three builds were spent on the theory that the
/// app was missing entitlements, before `xcodebuild -showBuildSettings` showed
/// `ENTITLEMENTS_REQUIRED = NO`: Xcode never applies entitlements to Simulator
/// destinations, by design. So the theory was wrong, and the real cause was
/// never established.
///
/// This suite makes the question answerable in seconds instead of by
/// inference. It exercises `KeychainHelper` directly — the same code path
/// `AnonymousIdentityManager` uses to persist the sync session.
///
/// If it fails with -34018, the environment cannot store a session and no
/// cloud-sync test can run there; erase the simulator and retry. If it passes
/// while sync still reports -34018, the fault is in how sync calls the
/// Keychain, not in the Keychain being unavailable — and that is a product
/// bug worth chasing.
@Suite("Keychain availability")
struct KeychainAvailabilityTests {

    private let key = "com.ikeru.test.keychain-probe"

    @Test("Keychain round-trips a value in this environment")
    func roundTrip() throws {
        let keychain = KeychainHelper()
        defer { try? keychain.delete(key: key) }

        try keychain.save(key: key, value: "probe-value")
        #expect(try keychain.load(key: key) == "probe-value")
    }

    @Test("Overwriting an existing key keeps the newest value")
    func overwrite() throws {
        let keychain = KeychainHelper()
        defer { try? keychain.delete(key: key) }

        try keychain.save(key: key, value: "first")
        try keychain.save(key: key, value: "second")
        #expect(try keychain.load(key: key) == "second")
    }

    @Test("A key that was never written reads back as nil, not an error")
    func missingKeyIsNil() throws {
        #expect(try KeychainHelper().load(key: "com.ikeru.test.never-written") == nil)
    }
}
