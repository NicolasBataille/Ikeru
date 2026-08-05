import Testing
import Foundation
@testable import Ikeru

/// Coverage for remediation ITEM C — `WidgetSnapshotStore` is pure Foundation
/// (no SwiftData, no simulator entitlement needed) but had zero tests. Every
/// test uses a throwaway app-group suite name so it never touches the real
/// `group.com.ikeru.shared` container, and removes the persistent domain
/// afterwards so no state leaks between test runs.
@Suite("WidgetSnapshotStore")
struct WidgetSnapshotStoreTests {

    /// A distinct throwaway suite name per test avoids cross-test
    /// interference even though these tests aren't marked `.serialized`.
    private func throwawaySuiteName(_ label: String) -> String {
        "com.ikeru.tests.widgetsnapshot.\(label).\(UUID().uuidString)"
    }

    private func cleanUp(suiteName: String) {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    @Test("write then read round-trips the full snapshot")
    func writeReadRoundTrip() {
        let suite = throwawaySuiteName("roundtrip")
        defer { cleanUp(suiteName: suite) }

        let studyDate = Date(timeIntervalSince1970: 1_700_000_000)
        WidgetSnapshotStore.write(dueCount: 12, level: 7, lastStudyDate: studyDate, suiteName: suite)

        let snapshot = WidgetSnapshotStore.read(suiteName: suite)
        #expect(snapshot?.dueCount == 12)
        #expect(snapshot?.level == 7)
        #expect(snapshot?.lastStudyDate == studyDate)
    }

    @Test("write with a nil lastStudyDate leaves the field unset")
    func writeNilStudyDateLeavesUnset() {
        let suite = throwawaySuiteName("nildate")
        defer { cleanUp(suiteName: suite) }

        WidgetSnapshotStore.write(dueCount: 3, level: 1, lastStudyDate: nil, suiteName: suite)

        let snapshot = WidgetSnapshotStore.read(suiteName: suite)
        #expect(snapshot?.dueCount == 3)
        #expect(snapshot?.level == 1)
        #expect(snapshot?.lastStudyDate == nil)
    }

    @Test("read returns nil when nothing has ever been written")
    func readNilOnEmpty() {
        let suite = throwawaySuiteName("empty")
        defer { cleanUp(suiteName: suite) }

        #expect(WidgetSnapshotStore.read(suiteName: suite) == nil)
    }

    @Test("read returns nil for a suite name UserDefaults refuses to open")
    func readNilOnBadSuiteName() {
        // `UserDefaults(suiteName:)` is documented to fail (return nil) when
        // the suite name equals the current process's own bundle identifier
        // — the one "bad" suite name guaranteed to be rejected regardless of
        // environment. Falls back to a definitely-invalid placeholder if the
        // test bundle somehow has no identifier, which would also fail to
        // resolve to a usable suite.
        let badSuiteName = Bundle.main.bundleIdentifier ?? ""
        #expect(WidgetSnapshotStore.read(suiteName: badSuiteName) == nil)
    }
}
