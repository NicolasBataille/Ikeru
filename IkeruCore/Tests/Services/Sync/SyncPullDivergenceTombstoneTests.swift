import Testing
import Foundation
import SwiftData
@testable import IkeruCore

/// The regression suite for GAP-15: **a deletion that never left the device**.
///
/// The defect, reproduced on a real device on 2026-08-15: the learner deleted
/// 風物詩 from their dictionary, it disappeared from the list, and the row on
/// Supabase was still there afterwards with `deleted_at = null`. Turning cloud
/// backup off and back on (`SyncCursorStore.resetAll()`) rewound the pull
/// cursor, the pull re-inserted every server row it had no local match for,
/// and 風物詩 came back. Same shape, worse blast radius, after a reinstall or
/// an identity change: every deletion the learner ever made returns at once.
///
/// The cause was **not** in the merge rules, the payload builder or the pull
/// actor — all three already handled `deleted_at` and were covered by
/// `SyncPullDivergenceTests`. It was that nothing in production ever *set*
/// `deletedAt`: every deletion was a hard `modelContext.delete(_:)`, which
/// leaves the push nothing to send. The existing divergence tests missed it
/// precisely because their `deleteCard` fixture stamps `card.deletedAt` by
/// hand — the test supplied the very input production never produced.
///
/// So every test here **deletes through the real repository entry point**
/// (`VocabularyRepository.deleteEntry`, `CardRepository.deleteCard`) and never
/// touches `deletedAt` directly. If the first link is ever unplugged again,
/// these fail.
///
/// Named to match the CI test filter's existing `SyncPullDivergence` motif so
/// the workflow picks it up without editing `ci.yml`.
@Suite("SyncPullDivergenceTombstones")
struct SyncPullDivergenceTombstoneTests {

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
            // `TextImport` is not optional in these containers: `SyncPullActor`
            // pulls `text_imports` and counts it in `localRowCount()`, so a
            // container without it makes every `pullAll` throw.
            TextImport.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Pushes every table `CloudSyncCoordinator.syncNow()` pushes, in the same
    /// order.
    private func pushEverything(
        container: ModelContainer,
        server: FakeSyncServer,
        token: String = "token"
    ) async throws {
        let push = SyncModelActor(modelContainer: container)
        _ = try await push.pushAllProfiles(using: server, accessToken: token)
        _ = try await push.pushAllRPGStates(using: server, accessToken: token)
        _ = try await push.pushDirtyCards(using: server, accessToken: token)
        _ = try await push.pushDirtyReviewLogs(using: server, accessToken: token)
        _ = try await push.pushDirtyVocabularyEntries(using: server, accessToken: token)
        _ = try await push.pushDirtyVocabularyEncounters(using: server, accessToken: token)
        _ = try await push.pushDirtyExerciseOutcomeLogs(using: server, accessToken: token)
        _ = try await push.pushDirtyTextImports(using: server, accessToken: token)
    }

    /// Every row the fake server holds for a table, read back through its real
    /// `SyncPullTransport` surface (a `nil` cursor means "from the start").
    private func serverRows(
        _ server: FakeSyncServer,
        table: String
    ) async throws -> [SyncRow] {
        try await server.fetchRows(table: table, since: nil, limit: 500, accessToken: "token")
    }

    /// The `deleted_at` cell of a specific server row, distinguishing "column
    /// absent or null" (`nil`) from an actual timestamp.
    private func serverDeletedAt(
        _ rows: [SyncRow],
        id: UUID
    ) -> String? {
        for row in rows {
            guard case .string(let rowID)? = row["id"], rowID == id.uuidString else { continue }
            if case .string(let stamp)? = row["deleted_at"] { return stamp }
            return nil
        }
        return nil
    }

    /// Inserts a profile so `CardModelActor`'s active-profile scoping resolves
    /// (its fallback picks the oldest live profile).
    @discardableResult
    private func seedProfile(into container: ModelContainer) throws -> UUID {
        let context = ModelContext(container)
        let profile = UserProfile(displayName: "Learner")
        context.insert(profile)
        try context.save()
        return profile.id
    }

    // MARK: - Test 1: a deleted entry is gone from EVERY repository read path

    /// The trap this whole change had to avoid: missing one read path means
    /// the deleted word still shows up in one screen. This walks every public
    /// read on `VocabularyRepository` rather than asserting on the one the
    /// implementation happens to filter.
    @Test("A deleted vocabulary entry disappears from every VocabularyRepository read path")
    func deletedEntryIsInvisibleEverywhere() async throws {
        let container = try makeContainer()
        let repo = VocabularyRepository(modelContainer: container)

        let kept = await repo.addEntry(word: "犬", reading: "いぬ", meaning: "dog")
        let doomed = await repo.addEntry(word: "風物詩", reading: "ふうぶつし", meaning: "seasonal tradition")
        await repo.logEncounter(entryId: doomed.id, source: .readingPassage, contextSnippet: "…")

        await repo.deleteEntry(by: doomed.id)

        let all = await repo.allEntries()
        #expect(all.map(\.id) == [kept.id], "allEntries still lists the deleted word")

        #expect(await repo.entry(by: doomed.id) == nil)
        #expect(await repo.entry(byWord: "風物詩") == nil)
        #expect(await repo.hasEntry(forWord: "風物詩") == false)
        #expect(await repo.encounters(for: doomed.id).isEmpty)

        let due = await repo.dueEntries(before: Date().addingTimeInterval(86_400 * 3650))
        #expect(due.contains { $0.id == doomed.id } == false, "the deleted word is still drilled")

        // The kept entry must be untouched — a soft delete that over-reaches
        // is just as broken as one that under-reaches.
        #expect(await repo.entry(by: kept.id) != nil)
    }

    // MARK: - Test 2: the deletion actually reaches the push payload

    /// The first link itself. Before this change the push had nothing to send
    /// for a deletion, because the row was simply gone from the store.
    @Test("Deleting a vocabulary entry puts a non-null deleted_at in the pushed row")
    func deletionReachesThePushPayload() async throws {
        let container = try makeContainer()
        let server = FakeSyncServer()
        let repo = VocabularyRepository(modelContainer: container)

        let entry = await repo.addEntry(word: "風物詩", reading: "ふうぶつし", meaning: "seasonal tradition")
        try await pushEverything(container: container, server: server)

        // Precondition: the server holds it, alive.
        let before = try await serverRows(server, table: "vocabulary_entries")
        #expect(before.count == 1)
        #expect(serverDeletedAt(before, id: entry.id) == nil)

        await repo.deleteEntry(by: entry.id)
        try await pushEverything(container: container, server: server)

        let after = try await serverRows(server, table: "vocabulary_entries")
        #expect(
            serverDeletedAt(after, id: entry.id) != nil,
            "the deletion never reached the server — this is GAP-15 itself"
        )
    }

    // MARK: - Test 3: THE reproduction — cursor reset must not resurrect

    /// The device scenario, step by step, with the deletion pushed and the
    /// pull cursor rewound the way turning cloud backup off and on again
    /// rewinds it.
    @Test("Deleted word stays deleted across a full pull-cursor reset")
    func deletedWordSurvivesCursorReset() async throws {
        let container = try makeContainer()
        let server = FakeSyncServer()
        let repo = VocabularyRepository(modelContainer: container)
        let cursors = MockSyncCursorStore()
        let skips = MockSyncSkipTracker()

        let entry = await repo.addEntry(word: "風物詩", reading: "ふうぶつし", meaning: "seasonal tradition")
        try await pushEverything(container: container, server: server)

        await repo.deleteEntry(by: entry.id)
        try await pushEverything(container: container, server: server)

        // Cloud backup off, then on: every cursor goes back to nil and the
        // next pull replays the entire server history.
        try cursors.resetAll()

        let pull = SyncPullActor(modelContainer: container)
        _ = try await pull.pullAll(
            transport: server,
            cursorStore: cursors,
            skipTracker: skips,
            accessToken: "token"
        )

        #expect(await repo.entry(byWord: "風物詩") == nil, "風物詩 came back")
        #expect(await repo.allEntries().isEmpty)
    }

    /// The harsher variant, and the one that actually distinguishes a
    /// tombstone from a hard delete: the deletion has **not** been pushed yet,
    /// so the server row is still fully alive (`deleted_at = null`) — exactly
    /// the state the device was observed in. Under a hard delete the local row
    /// is gone, `SyncPullActor` finds no local match, and
    /// `applyVocabularyEntryRows` re-inserts it unconditionally. Under a
    /// tombstone the local row is still there and merge rule 4 keeps it dead.
    @Test("A deletion not yet pushed still wins over a live server row after a cursor reset")
    func unpushedDeletionBeatsLiveServerRow() async throws {
        let container = try makeContainer()
        let server = FakeSyncServer()
        let repo = VocabularyRepository(modelContainer: container)
        let cursors = MockSyncCursorStore()
        let skips = MockSyncSkipTracker()

        let entry = await repo.addEntry(word: "風物詩", reading: "ふうぶつし", meaning: "seasonal tradition")
        try await pushEverything(container: container, server: server)

        // Deleted locally, never pushed — the server still says it's alive.
        await repo.deleteEntry(by: entry.id)
        let serverSide = try await serverRows(server, table: "vocabulary_entries")
        #expect(serverDeletedAt(serverSide, id: entry.id) == nil, "fixture broken: server row should still be live")

        try cursors.resetAll()
        let pull = SyncPullActor(modelContainer: container)
        _ = try await pull.pullAll(
            transport: server,
            cursorStore: cursors,
            skipTracker: skips,
            accessToken: "token"
        )

        #expect(await repo.entry(byWord: "風物詩") == nil, "a live server row resurrected a local deletion")
        #expect(await repo.allEntries().isEmpty)
    }

    // MARK: - Test 4: the cascade must reach the push, not just the store

    /// `pushDirtyReviewLogs` used to select rows with `syncedAt == nil` on the
    /// premise that a review log, being append-only, can only ever be dirty
    /// because it has never been pushed. Cascade tombstones break that premise:
    /// deleting a card mutates logs that were pushed long ago. Under the old
    /// filter the card's tombstone travelled and its review history did not —
    /// the deleted card's reviews stayed alive on the server and replayed onto
    /// any other device.
    @Test("Deleting a card pushes tombstones for its already-synced review logs")
    func cardDeletionPushesReviewLogTombstones() async throws {
        let container = try makeContainer()
        let server = FakeSyncServer()
        try seedProfile(into: container)
        let repo = CardRepository(modelContainer: container)

        let card = await repo.createCard(front: "犬", back: "dog", type: .vocabulary)
        await repo.gradeCard(cardId: card.id, grade: .good, responseTimeMs: 500)

        // First sync: card and its review log both land on the server, alive,
        // and are stamped `syncedAt` locally.
        try await pushEverything(container: container, server: server)
        let logsBefore = try await serverRows(server, table: "review_logs")
        #expect(logsBefore.count == 1)
        let logID = try #require({ () -> UUID? in
            guard case .string(let raw)? = logsBefore.first?["id"] else { return nil }
            return UUID(uuidString: raw)
        }())
        #expect(serverDeletedAt(logsBefore, id: logID) == nil)

        await repo.deleteCard(by: card.id)
        try await pushEverything(container: container, server: server)

        let cardsAfter = try await serverRows(server, table: "cards")
        #expect(serverDeletedAt(cardsAfter, id: card.id) != nil, "the card tombstone never reached the server")

        let logsAfter = try await serverRows(server, table: "review_logs")
        #expect(
            serverDeletedAt(logsAfter, id: logID) != nil,
            "the review log of a deleted card is still alive on the server"
        )
    }

    // MARK: - Test 5: a deleted card is invisible to the card read paths

    @Test("A deleted card disappears from every CardRepository read path, with its review logs")
    func deletedCardIsInvisibleEverywhere() async throws {
        let container = try makeContainer()
        try seedProfile(into: container)
        let repo = CardRepository(modelContainer: container)

        let kept = await repo.createCard(front: "残る", back: "to remain", type: .vocabulary)
        let doomed = await repo.createCard(front: "捨てる", back: "to discard", type: .vocabulary)
        await repo.gradeCard(cardId: doomed.id, grade: .again, responseTimeMs: 300)

        await repo.deleteCard(by: doomed.id)

        #expect(await repo.card(by: doomed.id) == nil)
        #expect(await repo.allCards().map(\.id) == [kept.id])
        #expect(await repo.reviewLogs(for: doomed.id).isEmpty)
        #expect(await repo.activeProfileReviewLogs().isEmpty, "a deleted card's history still feeds the export")

        let window = Date().addingTimeInterval(-86_400)...Date().addingTimeInterval(86_400)
        let ranged = await repo.allReviewLogs(from: window.lowerBound, to: window.upperBound)
        #expect(ranged.isEmpty, "allReviewLogs fetches ReviewLog directly — it needs its own filter")

        let due = await repo.dueCards(before: Date().addingTimeInterval(86_400 * 3650))
        #expect(due.contains { $0.id == doomed.id } == false)

        let sorted = await repo.dueCardsSortedByDueDate(before: Date().addingTimeInterval(86_400 * 3650))
        #expect(sorted.contains { $0.id == doomed.id } == false)

        let byType = await repo.cards(byType: .vocabulary)
        #expect(byType.map(\.id) == [kept.id])
    }

    // MARK: - Test 6: never un-tombstone

    /// Merge rule 4 gives a tombstone victory regardless of timestamp, so a
    /// revived row is re-killed by the next pull that carries the old
    /// `deleted_at`. Re-adding a deleted word therefore has to mint a NEW
    /// entry. This asserts the new id — the property that keeps the word alive
    /// through a later sync — not merely that the word reappears.
    @Test("Re-adding a deleted word creates a new entry instead of reviving the tombstone")
    func reAddingADeletedWordMintsANewEntry() async throws {
        let container = try makeContainer()
        let server = FakeSyncServer()
        let repo = VocabularyRepository(modelContainer: container)
        let cursors = MockSyncCursorStore()
        let skips = MockSyncSkipTracker()

        let original = await repo.addEntry(word: "風物詩", reading: "ふうぶつし", meaning: "seasonal tradition")
        try await pushEverything(container: container, server: server)
        await repo.deleteEntry(by: original.id)
        try await pushEverything(container: container, server: server)

        let readded = await repo.addEntry(word: "風物詩", reading: "ふうぶつし", meaning: "seasonal tradition")
        #expect(readded.id != original.id, "the tombstoned entry was revived — rule 4 will re-kill it")

        // And it survives the sync round-trip that would have killed a revived
        // row: push the new entry, rewind the cursor, pull everything back.
        try await pushEverything(container: container, server: server)
        try cursors.resetAll()
        let pull = SyncPullActor(modelContainer: container)
        _ = try await pull.pullAll(
            transport: server,
            cursorStore: cursors,
            skipTracker: skips,
            accessToken: "token"
        )

        let live = await repo.entry(byWord: "風物詩")
        #expect(live?.id == readded.id, "the re-added word did not survive a pull")
    }

    // MARK: - Test 7: the profile cascade reaches every owned row

    /// `UserProfile` used to be hard-deleted, and SwiftData's `.cascade` rules
    /// took `cards`, their `reviewLogs` and `rpgState` with it. A tombstone
    /// fires no delete rule at all, so the cascade is hand-written now — and
    /// a hand-written cascade that stops one level short is exactly how a
    /// deleted profile's cards stay alive on the server and come back.
    ///
    /// Asserts on each level separately rather than on a total count, so a
    /// cascade that reaches cards but not their review logs still fails.
    @Test("Deleting a profile tombstones its cards, their review logs, its RPG state and its outcomes")
    func profileDeletionCascadesToTheWholeGraph() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let profile = UserProfile(displayName: "Learner")
        context.insert(profile)
        let card = Card(front: "犬", back: "dog", type: .vocabulary)
        card.profile = profile
        context.insert(card)
        let log = ReviewLog(card: card, grade: .good, responseTimeMs: 400)
        context.insert(log)
        let outcome = ExerciseOutcomeLog(skill: .listening, accuracy: 0.9, profileID: profile.id)
        context.insert(outcome)

        // A second profile whose data must be left completely alone.
        let bystander = UserProfile(displayName: "Other")
        context.insert(bystander)
        let bystanderCard = Card(front: "猫", back: "cat", type: .vocabulary)
        bystanderCard.profile = bystander
        context.insert(bystanderCard)
        let bystanderOutcome = ExerciseOutcomeLog(skill: .speaking, accuracy: 0.5, profileID: bystander.id)
        context.insert(bystanderOutcome)
        try context.save()

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        ProfileDeletion.tombstoneGraph(of: profile, in: context, at: now)
        try context.save()

        #expect(profile.deletedAt == now)
        #expect(card.deletedAt == now, "the profile's cards were not cascade-tombstoned")
        #expect(log.deletedAt == now, "the cascade stopped at cards and never reached their review logs")
        #expect(profile.rpgState?.deletedAt == now, "the profile's RPG state was not cascade-tombstoned")
        #expect(outcome.deletedAt == now, "ExerciseOutcomeLog is scalar-scoped and was missed")

        // Nothing belonging to the other profile was touched.
        #expect(bystander.deletedAt == nil)
        #expect(bystanderCard.deletedAt == nil)
        #expect(bystanderOutcome.deletedAt == nil)
        #expect(bystander.rpgState?.deletedAt == nil)
    }

    /// A row deleted earlier must keep its original deletion instant when a
    /// later cascade sweeps over it — otherwise re-deleting a parent silently
    /// rewrites history and re-pushes rows the server already has.
    @Test("The cascade does not rewrite the deletion time of an already-tombstoned row")
    func cascadeIsIdempotentOnAlreadyDeletedRows() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let profile = UserProfile(displayName: "Learner")
        context.insert(profile)
        let card = Card(front: "犬", back: "dog", type: .vocabulary)
        card.profile = profile
        context.insert(card)
        try context.save()

        let firstDeletion = Date(timeIntervalSince1970: 1_700_000_000)
        card.tombstone(at: firstDeletion)

        let laterDeletion = firstDeletion.addingTimeInterval(3600)
        ProfileDeletion.tombstoneGraph(of: profile, in: context, at: laterDeletion)
        try context.save()

        #expect(card.deletedAt == firstDeletion, "an earlier deletion instant was overwritten")
        #expect(profile.deletedAt == laterDeletion)
    }

    // MARK: - Test 8: a tombstoned profile stops driving the app

    /// `ProfileViewModel.deleteProfile` (the writer) lives in the app target
    /// and is covered by `IkeruTests/ProfileViewModelTests`. What is testable
    /// here is the half that lives in Core: once a profile carries a
    /// tombstone, the active-profile *resolution* must not fall back onto it.
    /// Without the filter on the "oldest profile" fallback, deleting the
    /// active profile resolves straight back to the deleted one.
    @Test("A tombstoned profile is never resolved as the active profile")
    func tombstonedProfileIsNotResolvedAsActive() async throws {
        let container = try makeContainer()
        let profileID = try seedProfile(into: container)
        let repo = CardRepository(modelContainer: container)

        let card = await repo.createCard(front: "犬", back: "dog", type: .vocabulary)
        #expect(await repo.allCards().map(\.id) == [card.id])

        // Tombstone the profile through the same function
        // `ProfileViewModel.deleteProfile` calls.
        let context = ModelContext(container)
        let fetched = try #require(
            try context.fetch(
                FetchDescriptor<UserProfile>(predicate: #Predicate { $0.id == profileID })
            ).first
        )
        ProfileDeletion.tombstoneGraph(of: fetched, in: context)
        try context.save()

        // No live profile left to resolve, so nothing is scoped to it.
        #expect(await repo.allCards().isEmpty)
        #expect(await repo.dueCards(before: Date().addingTimeInterval(86_400 * 3650)).isEmpty)
        #expect(await repo.card(by: card.id) == nil)
    }

    // MARK: - Test 10: a tombstone reaches a SECOND device

    /// Every other test in this suite runs one device against the server. That
    /// is the blind spot this one closes, and it found a real defect: the
    /// append-only tables (`review_logs`, `vocabulary_encounters`,
    /// `exercise_outcome_logs`) short-circuited on "this id already exists
    /// locally" *before* looking at `deleted_at`, so a tombstone pushed by one
    /// device was received by the other and thrown away.
    ///
    /// The visible damage was not the row itself but what reads it:
    /// `CardModelActor.allReviewLogs(from:to:)` fetches `ReviewLog` directly
    /// rather than walking the card, and feeds progress stats and the weekly
    /// check-in. On device B the card died and its review log lived on —
    /// forever crediting work toward a card the learner had deleted. Measured
    /// before the fix: `cards=0 logs=1`.
    ///
    /// Two containers, one `FakeSyncServer`, and an ORDINARY incremental pull
    /// on B — no cursor reset. The reset is what the other tests lean on; this
    /// path has to work without one.
    @Test("A card deletion tombstones its review log on a second device")
    func tombstoneReachesSecondDevice() async throws {
        let server = FakeSyncServer()

        // ── Device A: a graded card, pushed.
        let deviceA = try makeContainer()
        try seedProfile(into: deviceA)
        let repoA = CardRepository(modelContainer: deviceA)
        let card = await repoA.createCard(front: "犬", back: "dog", type: .vocabulary)
        await repoA.gradeCard(cardId: card.id, grade: .good, responseTimeMs: 500)
        try await pushEverything(container: deviceA, server: server)

        // ── Device B: pulls that state.
        let deviceB = try makeContainer()
        let cursorsB = MockSyncCursorStore()
        let skipsB = MockSyncSkipTracker()
        let pullB = SyncPullActor(modelContainer: deviceB)
        _ = try await pullB.pullAll(
            transport: server,
            cursorStore: cursorsB,
            skipTracker: skipsB,
            accessToken: "token"
        )

        let repoB = CardRepository(modelContainer: deviceB)
        #expect(await repoB.card(by: card.id) != nil, "B never received the card")
        let logsOnB = await repoB.allReviewLogs(
            from: Date.distantPast,
            to: Date.distantFuture
        )
        #expect(logsOnB.count == 1, "B never received the review log")

        // ── A deletes the card; both tombstones go up.
        await repoA.deleteCard(by: card.id)
        try await pushEverything(container: deviceA, server: server)

        // ── B pulls again. Incremental: the cursor is wherever the first pull
        //    left it. This is the ordinary, everyday case.
        _ = try await pullB.pullAll(
            transport: server,
            cursorStore: cursorsB,
            skipTracker: skipsB,
            accessToken: "token"
        )

        #expect(await repoB.card(by: card.id) == nil, "the card outlived its deletion on B")
        let logsAfter = await repoB.allReviewLogs(
            from: Date.distantPast,
            to: Date.distantFuture
        )
        #expect(
            logsAfter.isEmpty,
            "B kept the review log of a deleted card — it keeps feeding progress stats forever"
        )
    }
}
