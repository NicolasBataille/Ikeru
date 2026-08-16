import Testing
import Foundation
import SwiftData
@testable import IkeruCore

// MARK: - Live-network gate

/// `IKERU_LIVE_SYNC_TEST=1` is the opt-in switch for `LiveSyncVolumeTests`
/// below — see that suite's doc comment for why it must default to
/// SKIPPED, including in CI.
///
/// A free function (not a `static var` on the suite itself) deliberately:
/// referencing the suite type from inside its own `@Suite(...)` attribute
/// argument is legal Swift, but keeping the condition external avoids any
/// doubt about evaluation order at macro-expansion time.
private func liveSyncTestIsEnabled() -> Bool {
    ProcessInfo.processInfo.environment["IKERU_LIVE_SYNC_TEST"] == "1"
}

// MARK: - LiveSyncVolumeTests

/// GAP-02 (`docs/known-gaps.md`, "Le pull a tourné contre le vrai Supabase,
/// mais sur le cas le plus simple possible") closer.
///
/// Every other live-Supabase check on record for the pull path exercised
/// exactly ONE row, ONE page, ONE request — the simplest case this code can
/// ever see. Never tested against the real project: multi-page pagination,
/// real volume/latency, and — the sharpest gap — the composite
/// `(server_updated_at, id)` cursor (`SyncCursorPosition`) actually walking
/// a real server-side tie cluster wider than one page. `FakeSyncServer`
/// (`SyncPullDivergenceTests.swift`) proved the LOGIC; nothing had proven
/// the wire.
///
/// This suite pushes ~2000 rows to the live project in a SINGLE upsert —
/// deliberately, not accidentally: `touch_server_updated_at()` stamps
/// `server_updated_at` with `now()`, the TRANSACTION timestamp, so one bulk
/// upsert gives every row it touches the IDENTICAL value (verified live,
/// see `SyncCursorPosition`'s doc comment). ~2000 rows in one upsert is
/// therefore not an inflated volume — it is the exact "one wide tie
/// cluster, paginated" shape `docs/known-gaps.md` names as the missing
/// case, and forcing a small page size on the way back is what makes the
/// composite cursor's tie-breaking actually run instead of just being
/// exercised in theory.
///
/// ## What this proves, and what it still doesn't
///
/// Proves (against the live project, not `FakeSyncServer`): a real
/// multi-page pull recovers every row of a real tie cluster, exactly once,
/// with the real `PostgRESTPullTransport` request shape and the real
/// `SyncPullActor`/`SyncCursorStore`/`SyncMergeRules` apply path — plus
/// real latency and page-count numbers.
///
/// Still does NOT prove (see `docs/known-gaps.md` GAP-02's remaining list):
/// poisoned rows against a real server (GAP-03/GAP-04 — still read from
/// code only), or merge/divergence between two devices sharing one account
/// (GAP-01 — this suite uses exactly one identity, one device).
///
/// ## Running this suite
///
/// Skipped by default, deliberately including in CI — `.github/workflows/ci.yml`'s
/// `swift test` step runs the FULL suite (only the 3 store-migration
/// suites are excluded, by `--skip`, and none of those names match this
/// file), so a runtime `.enabled(if:)` gate is the only thing standing
/// between an ordinary CI run and 2000 rows landing in production. Run it
/// by hand, with output captured to a file (not `| tail`, which would
/// truncate exactly the numbers this suite exists to report):
///
/// ```
/// cd IkeruCore
/// IKERU_LIVE_SYNC_TEST=1 swift test --filter LiveSyncVolumeTests \
///   > /tmp/live-sync-volume.log 2>&1
/// ```
///
/// ## Safety — production writes, scoped and cleaned up
///
/// - Creates its OWN anonymous Supabase user for this run only — the exact
///   `POST /auth/v1/signup` call `AnonymousIdentityManager.signInAnonymously()`
///   makes in production, via the same `URLSessionSupabaseAuthTransport`.
///   Every write this suite makes is scoped to that `user_id` by Row Level
///   Security (`supabase/migrations/20260810000000_baseline_schema.sql` —
///   every policy is `auth.uid() = user_id`); there is no query in this
///   file that could touch another learner's row even if it tried to.
/// - Deletes that user at the end via the deployed `delete-account` Edge
///   Function (`URLSessionCloudDeletionTransport`, same call
///   `CloudDataDeletionService` makes) — `ON DELETE CASCADE` from
///   `auth.users` takes every row in all 8 tables with it, not just the one
///   table this suite writes to. Cleanup runs on BOTH the success path and
///   the failure path (see `runCleanedUp` below) — a failed `#expect` still
///   leaves production exactly as clean as a passing run.
/// - Never reads or sends the `service_role` key. Every request — auth,
///   push, pull, deletion — uses the publishable key
///   (`SupabaseConfig.publishableKey`, already public in this repo) plus
///   this run's own session token, identical to what the shipping app
///   sends.
@Suite("LiveSyncVolume", .enabled(if: liveSyncTestIsEnabled()))
struct LiveSyncVolumeTests {

    /// ~2000 — see the type doc comment for why this is the volume the
    /// registry actually asked for, not an arbitrary large number.
    static let rowCount = 2000

    /// Forced small on purpose so the pull genuinely spans several pages
    /// instead of swallowing all 2000 rows in one request — `SyncPullActor
    /// .defaultPageSize` (1000) would only need 2 pages; 300 exercises the
    /// loop harder for the same row count while staying well above
    /// `SyncModelActor`'s 500-row push batch size documented on
    /// `SyncPullTransport` (this suite pushes all 2000 in ONE request
    /// regardless, so that particular boundary doesn't apply here, but
    /// staying clear of round numbers like 500/1000 keeps this test honest
    /// about not having tuned the page size to make the arithmetic
    /// suspiciously clean).
    static let pageSize = 300

    /// `exercise_outcome_logs` — the one table among the 7 pulled tables
    /// with NO server-enforced foreign key on its parent id
    /// (`profile_id` is a plain `uuid` column, not `references … on delete
    /// cascade` — verified against `baseline_schema.sql`) and no
    /// SwiftData-relationship FK on the local apply side either (see
    /// `SyncPullActor.applyExerciseOutcomeLogRows`'s doc comment: "a
    /// SCALAR field ... not a local-entity lookup"). Pushing 2000 rows here
    /// needs no `profiles`/`cards` seed data first — the volume/pagination
    /// question this suite asks is orthogonal to the FK-ordering question
    /// `SyncPullActor.pullOrder` already answers elsewhere.
    static let table = "exercise_outcome_logs"

    @Test("~2000-row single-upsert tie cluster pulls back complete, deduplicated, and paginated")
    func fullTieClusterPullsBackComplete() async throws {
        let authTransport = URLSessionSupabaseAuthTransport()
        let deletionTransport = URLSessionCloudDeletionTransport()

        // The one production call this suite makes that ISN'T under direct
        // test here — `signInAnonymously()` itself is covered elsewhere
        // (`AnonymousIdentityManagerTests`, and the curl verification in
        // `SupabaseAuthTransport.swift`'s doc comment). This is just this
        // suite's own throwaway identity.
        let session = try await authTransport.signInAnonymously()
        print("[LiveSyncVolume] created live anonymous user \(session.userID)")

        // Cleanup MUST run whether the scenario below throws, a `#expect`
        // records a failure but doesn't throw, or everything passes — see
        // the type doc comment's Safety section. Swift's `defer` cannot
        // straddle the `await` this needs cleanly across every toolchain
        // this repo targets, so the do/catch below calls cleanup
        // explicitly on both paths instead of relying on scope exit.
        do {
            try await runScenario(accessToken: session.accessToken)
        } catch {
            print("[LiveSyncVolume] scenario threw (\(error)) — deleting the live user before rethrowing")
            await deleteAccountBestEffort(deletionTransport, accessToken: session.accessToken, userID: session.userID)
            throw error
        }

        await deleteAccountBestEffort(deletionTransport, accessToken: session.accessToken, userID: session.userID)
    }

    /// Calls the `delete-account` Edge Function and reports success/failure
    /// loudly — but never THROWS itself, so it's safe to call from the
    /// catch block above without masking the original error. A failure
    /// here after a genuine scenario failure is the one case this suite
    /// cannot self-heal: it prints the orphaned `userID` so it can be
    /// found and removed by hand from the Supabase dashboard (never via
    /// `service_role` from this suite — see the type doc comment).
    private func deleteAccountBestEffort(
        _ transport: URLSessionCloudDeletionTransport,
        accessToken: String,
        userID: UUID
    ) async {
        do {
            try await transport.deleteAccount(accessToken: accessToken)
            print("[LiveSyncVolume] deleted live user \(userID) — delete-account returned 2xx")
        } catch {
            Issue.record("delete-account failed for live user \(userID): \(error) — this user and its rows are ORPHANED on aiayzlarixlogcoyswna and need manual cleanup via the dashboard")
        }
    }

    // MARK: - Scenario

    private func runScenario(accessToken: String) async throws {
        // MARK: 1. Build ~2000 rows — same field set
        // `SyncPayloadBuilder.row(for: ExerciseOutcomeLog)` sends, built by
        // hand here (not by round-tripping through a local `ModelContainer`
        // + that function) because the push side of this scenario has
        // nothing to prove about local persistence — only the WIRE shape,
        // which is what actually reaches PostgREST.
        let profileID = UUID()
        let occurredAt = Date()
        var rows: [SyncRow] = []
        rows.reserveCapacity(Self.rowCount)
        for _ in 0..<Self.rowCount {
            rows.append(try Self.makeExerciseOutcomeLogRow(profileID: profileID, occurredAt: occurredAt))
        }
        let rowIDs = Set(rows.compactMap { row -> String? in
            guard case .string(let id)? = row["id"] else { return nil }
            return id
        })
        #expect(rowIDs.count == Self.rowCount, "row ids must be unique before they even leave the device")

        // MARK: 2. Push all ~2000 in ONE upsert — the real
        // `SyncDataTransport`/`PostgRESTSyncTransport`, no reimplementation.
        // One PostgREST bulk POST is one server-side transaction, so this
        // is what actually produces the tie cluster (see the type doc
        // comment).
        let pushTransport = PostgRESTSyncTransport()
        let pushStart = Date()
        try await pushTransport.upsert(table: Self.table, rows: rows, accessToken: accessToken)
        let pushSeconds = Date().timeIntervalSince(pushStart)
        print("[LiveSyncVolume] pushed \(rows.count) rows to \(Self.table) in \(String(format: "%.2f", pushSeconds))s")

        // MARK: 3. Pull them back through the REAL pull pipeline:
        // `PostgRESTPullTransport` (wrapped ONLY to count pages — no
        // pagination logic reimplemented, that stays entirely inside
        // `SyncPullActor.pullAndApply`'s loop), a fresh empty in-memory
        // SwiftData store, the real `SyncPullActor`, and `MockSyncCursorStore`
        // / `MockSyncSkipTracker` — genuine `Sources/` conformances of
        // `SyncCursorStore`/`SyncSkipTracker` (the composite-cursor
        // `advanceCursor(forTable:afterApplying:)` logic under test here
        // lives once, as a protocol extension in `SyncCursorStore.swift`,
        // shared by every conformance including this one — using the
        // in-memory one instead of `UserDefaultsSyncCursorStore` avoids
        // leaking test state into this machine's real `UserDefaults`
        // without exercising any different cursor-advance code path).
        let container = try Self.makeContainer()
        let countingTransport = PageCountingPullTransport(wrapping: PostgRESTPullTransport())
        let cursorStore = MockSyncCursorStore()
        let skipTracker = MockSyncSkipTracker()
        let pullActor = SyncPullActor(modelContainer: container)

        let pullStart = Date()
        let summary = try await pullActor.pullAll(
            transport: countingTransport,
            cursorStore: cursorStore,
            skipTracker: skipTracker,
            accessToken: accessToken,
            pageSize: Self.pageSize
        )
        let pullSeconds = Date().timeIntervalSince(pullStart)
        let pageCount = countingTransport.pageCount(forTable: Self.table)
        let expectedPages = Int((Double(Self.rowCount) / Double(Self.pageSize)).rounded(.up))
        print("[LiveSyncVolume] pulled back in \(String(format: "%.2f", pullSeconds))s across \(pageCount) page(s) of \(Self.table) (pageSize=\(Self.pageSize), expected \(expectedPages) page(s))")
        print("[LiveSyncVolume] summary: applied=\(summary.appliedRowCounts[Self.table] ?? -1) alreadyPresent=\(summary.alreadyPresentRowCounts[Self.table] ?? -1) skipped=\(summary.skippedRowCounts[Self.table] ?? -1) permanentlyDropped=\(summary.permanentlyDroppedRowCounts[Self.table] ?? -1)")

        // MARK: 4. Completeness — the tie cluster came back whole, exactly
        // once each, and pagination genuinely ran more than once. This is
        // the exact claim `docs/known-gaps.md` GAP-02 says was never
        // checked against a real server.
        #expect(summary.appliedRowCounts[Self.table] == Self.rowCount)
        #expect(summary.alreadyPresentRowCounts[Self.table] == 0)
        #expect(summary.skippedRowCounts[Self.table] == 0)
        #expect(summary.permanentlyDroppedRowCounts[Self.table] == 0)
        #expect(pageCount > 1, "expected multi-page pagination at pageSize=\(Self.pageSize) for \(Self.rowCount) rows, got \(pageCount) page(s)")
        #expect(pageCount == expectedPages, "expected exactly \(expectedPages) page(s) (no wasted or missing round trips), got \(pageCount)")

        // MARK: 5. Prove it locally too — not just that the summary claims
        // completeness, but that the in-memory store actually holds
        // exactly `rowCount` distinct rows.
        let context = ModelContext(container)
        let localCount = try context.fetchCount(FetchDescriptor<ExerciseOutcomeLog>())
        #expect(localCount == Self.rowCount)
        let localIDs = try context.fetch(FetchDescriptor<ExerciseOutcomeLog>()).map(\.id)
        #expect(Set(localIDs).count == Self.rowCount, "expected zero duplicate rows applied locally")
    }

    // MARK: - Fixtures

    /// Same 8-model schema `SyncPullDivergenceTests.makeContainer()` uses —
    /// `SyncPullActor` pulls all 7 synced tables every cycle regardless of
    /// which one this suite actually populates, so every model needs a
    /// place to land.
    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self,
            Card.self,
            ReviewLog.self,
            RPGState.self,
            VocabularyEntry.self,
            VocabularyEncounter.self,
            ExerciseOutcomeLog.self,
            CompanionChatMessage.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Field-for-field the same shape `SyncPayloadBuilder.row(for:)` builds
    /// for `exercise_outcome_logs` — `id`, `profile_id`, `occurred_at`,
    /// `payload` (`skill`/`accuracy`), `updated_at`, `deleted_at`. No
    /// `user_id` (server-defaulted from the bearer token) and no
    /// `server_updated_at` (server-stamped by the trigger this whole
    /// scenario is about) are ever sent by a real client either.
    private static func makeExerciseOutcomeLogRow(profileID: UUID, occurredAt: Date) throws -> SyncRow {
        struct Payload: Encodable {
            let skill: String
            let accuracy: Double
        }
        let payload = Payload(skill: SkillType.listening.rawValue, accuracy: 1.0)
        return [
            "id": .uuid(UUID()),
            "profile_id": .uuid(profileID),
            "occurred_at": .date(occurredAt),
            "payload": try SyncJSON.jsonValue(encoding: payload),
            "updated_at": .date(occurredAt),
            "deleted_at": .null,
        ]
    }
}

// MARK: - PageCountingPullTransport

/// Thin instrumentation wrapper around a REAL `SyncPullTransport` — every
/// call is forwarded verbatim to `wrapped` (`PostgRESTPullTransport` in this
/// suite); this type adds nothing to the request/response path, it only
/// counts how many times each table was actually asked for. Deliberately
/// NOT a reimplementation of pagination or of `SyncPullTransport` itself —
/// that would defeat the entire point of testing the production transport.
private final class PageCountingPullTransport: SyncPullTransport, @unchecked Sendable {

    private let wrapped: any SyncPullTransport
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    init(wrapping transport: any SyncPullTransport) {
        self.wrapped = transport
    }

    func fetchRows(table: String, since: SyncCursorPosition?, limit: Int, accessToken: String) async throws -> [SyncRow] {
        let rows = try await wrapped.fetchRows(table: table, since: since, limit: limit, accessToken: accessToken)
        // `withLock` runs the whole critical section synchronously, so it's
        // safe to call after the `await` above from this `async` function —
        // same pattern (and same reason) as `MockSyncDataTransport.upsert`.
        lock.withLock {
            counts[table, default: 0] += 1
        }
        return rows
    }

    func pageCount(forTable table: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[table] ?? 0
    }
}
