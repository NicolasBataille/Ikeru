import Testing
import Foundation
@testable import IkeruCore

@Suite("UserDefaultsSyncConsentStore")
struct SyncPreferencesTests {

    /// A throwaway `UserDefaults` suite per test — never touches
    /// `UserDefaults.standard`, so this test file leaves no residue on the
    /// machine running it (and doesn't collide with the app's real
    /// cloud-sync consent state if run against a real app process).
    private func makeStore() -> (store: UserDefaultsSyncConsentStore, defaults: UserDefaults) {
        let suiteName = "com.ikeru.tests.sync.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (UserDefaultsSyncConsentStore(defaults: defaults), defaults)
    }

    @Test("Consent defaults to false")
    func consentDefaultsFalse() {
        let (store, _) = makeStore()
        #expect(store.isConsentGiven() == false)
    }

    @Test("setConsentGiven persists across store instances sharing the same defaults suite")
    func consentPersists() {
        let (store, defaults) = makeStore()
        store.setConsentGiven(true)

        let reloaded = UserDefaultsSyncConsentStore(defaults: defaults)
        #expect(reloaded.isConsentGiven() == true)
    }

    @Test("lastAttemptDate / lastSuccessDate are nil until recorded")
    func datesNilUntilRecorded() {
        let (store, _) = makeStore()
        #expect(store.lastAttemptDate() == nil)
        #expect(store.lastSuccessDate() == nil)
    }

    @Test("recordAttempt / recordSuccess round-trip through epoch-seconds storage")
    func datesRoundTrip() {
        let (store, _) = makeStore()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        store.recordAttempt(at: date)
        store.recordSuccess(at: date)

        // UserDefaults stores Double — allow for floating-point round-trip
        // slop rather than requiring bit-exact equality.
        #expect(abs((store.lastAttemptDate() ?? .distantPast).timeIntervalSince(date)) < 0.001)
        #expect(abs((store.lastSuccessDate() ?? .distantPast).timeIntervalSince(date)) < 0.001)
    }

    @Test("recordError stores and clears a message")
    func errorMessageRoundTrips() {
        let (store, _) = makeStore()
        #expect(store.lastErrorMessage() == nil)
        store.recordError("boom")
        #expect(store.lastErrorMessage() == "boom")
        store.recordError(nil)
        #expect(store.lastErrorMessage() == nil)
    }
}
