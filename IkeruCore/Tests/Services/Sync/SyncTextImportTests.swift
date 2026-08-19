import Testing
import Foundation
import SwiftData
@testable import IkeruCore

/// `text_imports` — the table that carries the learner's own prose.
///
/// Nico's ruling (2026-08-19): an imported text IS backed up, so a reinstall
/// restores the cards **with** the sentence they came from. That widens what
/// leaves the device, so the bar here is higher than "a row round-trips":
///
/// - the text must come back **byte for byte** (règle 2 : le texte de
///   l'utilisateur n'est jamais réécrit ni tronqué) — pinned as a test, in the
///   same spirit as `SyncPayloadBuilderTests`' snippet-omission test which
///   pins the opposite promise for `vocabulary_encounters`;
/// - `user_id` must never be sent (the server's `auth.uid()` default owns it);
/// - a deletion must travel, and it must be produced by the **real**
///   `TextImportRepository.delete(_:)`, never by stamping `deletedAt` by hand.
///   That last point is the whole lesson of `SyncPullDivergenceTombstoneTests`
///   (GAP-15): the old tests missed a shipped defect precisely because their
///   fixture supplied the input production never produced.
///
/// The TYPE name starts with `Sync` on purpose — `--filter` matches the type,
/// not the `@Suite` display name, and `swift test --filter Sync` is the
/// verification command this chantier is checked with. A suite that filter
/// cannot see is a suite nobody runs by hand.
@Suite("SyncTextImports")
struct SyncTextImportTests {

    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self,
            Card.self,
            ReviewLog.self,
            RPGState.self,
            VocabularyEntry.self,
            VocabularyEncounter.self,
            ExerciseOutcomeLog.self,
            CompanionChatMessage.self,
            TextImport.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// A real text with the shapes that break naive round-trips: multiple
    /// lines, an ideographic full stop, a wave dash, an emoji, trailing
    /// whitespace and a blank line. If any layer trims, normalises or
    /// re-encodes, one of these is what gives it away.
    private static let sampleText = """
    昨日、友だちと渋谷へ行きました。
    人がとても多かったです〜

    また行きたい 🍜
    """

    private func pushImports(
        container: ModelContainer,
        server: FakeSyncServer,
        token: String = "token"
    ) async throws -> Int {
        try await SyncModelActor(modelContainer: container)
            .pushDirtyTextImports(using: server, accessToken: token)
    }

    private func pullEverything(
        container: ModelContainer,
        server: FakeSyncServer,
        token: String = "token"
    ) async throws -> SyncPullActor.PullSummary {
        try await SyncPullActor(modelContainer: container).pullAll(
            transport: server,
            cursorStore: MockSyncCursorStore(),
            skipTracker: MockSyncSkipTracker(),
            accessToken: token
        )
    }

    private func fetchImport(id: UUID, in container: ModelContainer) throws -> TextImport? {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<TextImport>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: - Payload shape

    @Test("The pushed row carries every business column and never user_id")
    func rowShape() async throws {
        let container = try makeContainer()
        let repo = TextImportRepository(modelContainer: container)
        let entryA = UUID()
        let entryB = UUID()
        let dto = await repo.create(content: Self.sampleText, source: .photo,
                                    coverage: 0.75, entryIDs: [entryA, entryB])

        let record = try #require(try fetchImport(id: dto.id, in: container))
        let row = SyncPayloadBuilder.row(for: record)

        #expect(row["id"] == .uuid(dto.id))
        #expect(row["title"] == .string(dto.title))
        #expect(row["content"] == .string(Self.sampleText))
        #expect(row["source"] == .string("photo"))
        #expect(row["created_at"] == .date(record.createdAt))
        #expect(row["coverage"] == .number(0.75))
        // Order is meaningful — it is the learner's selection order.
        #expect(row["entry_ids"] == .array([.uuid(entryA), .uuid(entryB)]))
        #expect(row["deleted_at"] == .null)

        // The server's `auth.uid()` default owns this column; a client-supplied
        // value that disagreed with the bearer token would be a hazard worth
        // removing entirely, so it is never sent at all.
        #expect(row["user_id"] == nil)
        // And no leftover blob: this table promotes every field to a real
        // column (see the migration header).
        #expect(row["payload"] == nil)
    }

    @Test("A coverage of nil is pushed as null, never as zero")
    func nilCoverageIsNull() throws {
        // `nil` means "there was nothing measurable to count", `0` would claim
        // the learner knew none of it. The reading journal reads this back
        // months later — the two must not collapse.
        let record = TextImport(content: "あ", coverage: nil)
        #expect(SyncPayloadBuilder.row(for: record)["coverage"] == .null)

        let measured = TextImport(content: "あ", coverage: 0)
        #expect(SyncPayloadBuilder.row(for: measured)["coverage"] == .number(0))
    }

    @Test("An import that produced no card still pushes an empty array, not null")
    func emptyEntryIDsStayAnArray() throws {
        // "I kept nothing from this text" is a real outcome the journal shows.
        // A `null` here would be indistinguishable from a shape error on the
        // way back in (`SyncRowDecoding.uuidArray` skips the row for that).
        let record = TextImport(content: "あ", entryIDs: [])
        #expect(SyncPayloadBuilder.row(for: record)["entry_ids"] == .array([]))
    }

    // MARK: - Round trip

    @Test("A text imported on one device is restored on another, byte for byte")
    func roundTripPreservesTextExactly() async throws {
        let server = FakeSyncServer()
        let deviceA = try makeContainer()
        let deviceB = try makeContainer()

        let entryIDs = [UUID(), UUID(), UUID()]
        let dto = await TextImportRepository(modelContainer: deviceA)
            .create(content: Self.sampleText, source: .photo,
                    coverage: 0.42, entryIDs: entryIDs)

        #expect(try await pushImports(container: deviceA, server: server) == 1)
        // Device B is a fresh install: nothing local, so rule 1 does not fire
        // and the pull is a normal apply.
        _ = try await pullEverything(container: deviceB, server: server)

        let restored = try #require(try fetchImport(id: dto.id, in: deviceB))

        // The point of the whole chantier: the sentence the card came from is
        // still there, unaltered. Compared against the literal source, not
        // against device A's copy — a bug that mangled the text symmetrically
        // on both sides would pass the latter.
        #expect(restored.content == Self.sampleText)
        #expect(restored.title == dto.title)
        #expect(restored.source == .photo)
        #expect(restored.coverage == 0.42)
        #expect(restored.entryIDs == entryIDs, "selection order must survive the round trip")
        // Millisecond tolerance, not equality: `SyncJSON.dateFormatter` writes
        // ISO-8601 with fractional seconds at MILLISECOND resolution, so a
        // `Date`'s sub-millisecond tail is lost on the wire for every table —
        // measured, documented and pinned in
        // `SyncPullDivergenceTests+MillisecondTruncation.swift`, not specific to
        // this one. The text itself is asserted byte-exact above; a timestamp
        // is not text.
        #expect(abs(restored.createdAt.timeIntervalSince(dto.createdAt)) < 0.001)
        #expect(restored.deletedAt == nil)
    }

    @Test("Pulling the same import twice changes nothing")
    func pullIsIdempotent() async throws {
        let server = FakeSyncServer()
        let deviceA = try makeContainer()
        let deviceB = try makeContainer()

        let dto = await TextImportRepository(modelContainer: deviceA)
            .create(content: Self.sampleText, source: .paste, coverage: nil, entryIDs: [])
        _ = try await pushImports(container: deviceA, server: server)

        // Two cold pulls, each with its own cursor store, so the second one
        // re-delivers every row the first already applied — the redelivery
        // shape a cursor rewind (backup off/on) produces in production.
        _ = try await pullEverything(container: deviceB, server: server)
        _ = try await pullEverything(container: deviceB, server: server)

        let context = ModelContext(deviceB)
        let all = try context.fetch(FetchDescriptor<TextImport>())
        #expect(all.count == 1, "a redelivered row must merge, not duplicate")
        #expect(all.first?.id == dto.id)
        #expect(all.first?.content == Self.sampleText)
    }

    @Test("A row whose content is missing is skipped, and the rest of the page still applies")
    func poisonRowDoesNotTakeThePageDown() async throws {
        let server = FakeSyncServer()
        let container = try makeContainer()

        let good = TextImport(content: "元気ですか")
        let goodRow = SyncPayloadBuilder.row(for: good)
        var broken = SyncPayloadBuilder.row(for: TextImport(content: "壊れた"))
        broken["content"] = nil

        try await server.upsert(table: "text_imports", rows: [goodRow, broken], accessToken: "token")

        // A local row so rule 1 (empty remote + populated local) cannot fire
        // and swallow the pull before it reaches this table.
        let seed = ModelContext(container)
        seed.insert(UserProfile(displayName: "Learner"))
        try seed.save()

        let summary = try await pullEverything(container: container, server: server)

        #expect(summary.appliedRowCounts["text_imports"] == 1)
        #expect(summary.skippedRowCounts["text_imports"] == 1)
        #expect(try fetchImport(id: good.id, in: container)?.content == "元気ですか")
    }

    // MARK: - Deletion

    @Test("Deleting an import through the repository puts a non-null deleted_at in the pushed row")
    func deletionReachesThePushPayload() async throws {
        // Deliberately NOT stamping `deletedAt` by hand: the GAP-15 defect was
        // that nothing in production ever set it, and the tests missed it
        // because their fixture did the setting themselves.
        let server = FakeSyncServer()
        let container = try makeContainer()
        let repo = TextImportRepository(modelContainer: container)

        let dto = await repo.create(content: Self.sampleText, source: .paste,
                                    coverage: nil, entryIDs: [])
        _ = try await pushImports(container: container, server: server)

        await repo.delete(id: dto.id)
        #expect(try await pushImports(container: container, server: server) == 1,
                "the tombstone must be pushed even though the row was already synced")

        let rows = try await server.fetchRows(table: "text_imports", since: nil,
                                              limit: 100, accessToken: "token")
        let row = try #require(rows.first { $0["id"] == .uuid(dto.id) })
        guard case .string = row["deleted_at"] else {
            Issue.record("deleted_at is still null on the server — the deletion never left the device")
            return
        }
    }

    @Test("A deletion on one device tombstones the import on another, and does not resurrect")
    func deletionPropagatesAndStays() async throws {
        let server = FakeSyncServer()
        let deviceA = try makeContainer()
        let deviceB = try makeContainer()
        let repoA = TextImportRepository(modelContainer: deviceA)

        let dto = await repoA.create(content: Self.sampleText, source: .paste,
                                     coverage: nil, entryIDs: [])
        _ = try await pushImports(container: deviceA, server: server)
        _ = try await pullEverything(container: deviceB, server: server)
        #expect(try fetchImport(id: dto.id, in: deviceB) != nil)

        await repoA.delete(id: dto.id)
        _ = try await pushImports(container: deviceA, server: server)

        _ = try await pullEverything(container: deviceB, server: server)
        #expect(try fetchImport(id: dto.id, in: deviceB)?.deletedAt != nil)

        // B pushes its own state back and re-pulls: the tombstone must survive
        // its own echo rather than being un-deleted by a stale local copy.
        _ = try await pushImports(container: deviceB, server: server)
        _ = try await pullEverything(container: deviceB, server: server)
        #expect(try fetchImport(id: dto.id, in: deviceB)?.deletedAt != nil)

        let restoredList = await TextImportRepository(modelContainer: deviceB).all()
        #expect(restoredList.isEmpty, "a tombstoned import must not show in the reading journal")
    }

    // MARK: - Forward compatibility

    @Test("An unknown source value written by a newer app version survives verbatim")
    func unknownSourceIsNotRewritten() async throws {
        // `ImportSource` has two cases today; a third door (a share extension,
        // a file) would be written by a newer build against the same account.
        // An older build must hand it back unchanged rather than quietly
        // rewriting it to `paste` — otherwise the newer device loses the value
        // the moment the older one syncs.
        let server = FakeSyncServer()
        let container = try makeContainer()

        let record = TextImport(content: "未来のテキスト")
        var row = SyncPayloadBuilder.row(for: record)
        row["source"] = .string("share-extension")
        try await server.upsert(table: "text_imports", rows: [row], accessToken: "token")

        let seed = ModelContext(container)
        seed.insert(UserProfile(displayName: "Learner"))
        try seed.save()
        _ = try await pullEverything(container: container, server: server)

        let restored = try #require(try fetchImport(id: record.id, in: container))
        #expect(restored.sourceRawValue == "share-extension")
        // The typed accessor still degrades gracefully for the UI.
        #expect(restored.source == .paste)
    }
}
