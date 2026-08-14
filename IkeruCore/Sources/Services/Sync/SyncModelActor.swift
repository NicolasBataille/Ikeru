import Foundation
import SwiftData

/// Background `ModelActor` that reads locally-dirty rows and pushes them —
/// mirrors the `CardModelActor` pattern in `Repositories/CardRepository.swift`
/// (background-thread SwiftData access via `@ModelActor`, not a new
/// isolation strategy invented for this lot).
///
/// Every `pushDirty*` method fetches, builds rows, calls the transport, and
/// marks `syncedAt` — all inside this actor's isolation. Only `Sendable`
/// values (`SyncRow`, `String`) ever cross out to `SyncDataTransport`; the
/// `@Model` instances themselves (not `Sendable`) never leave this actor.
@ModelActor
actor SyncModelActor {

    /// Rows per PostgREST request. Review logs in particular can number in
    /// the thousands on a first push (design spec §8: ~50/day × months) —
    /// unbounded single-request bodies risk timeouts/memory spikes on both
    /// ends.
    private static let batchSize = 500

    // MARK: - Delta selection
    //
    // A single shared rule, applied per-row rather than as a SwiftData
    // `#Predicate` (predicates with optional-comparison / force-unwrap
    // patterns like `syncedAt != nil && updatedAt > syncedAt!` are known to
    // be fragile to express correctly, and this lot's rules forbid running
    // a build to verify one compiles and behaves as intended — see this
    // task's final notes). Fetching the (per-learner-scale, per design spec
    // §8: single-digit MB/year) full table and filtering in memory is the
    // safe tradeoff.
    private func isDirty(updatedAt: Date, deletedAt: Date?, syncedAt: Date?) -> Bool {
        guard let syncedAt else { return true } // never pushed
        if let deletedAt, deletedAt > syncedAt { return true } // tombstone not yet propagated
        return updatedAt > syncedAt
    }

    // MARK: - profiles / rpg_states — always pushed, not delta-filtered
    //
    // Neither `UserProfile` nor `RPGState` has any repository code that
    // bumps `updatedAt` on mutation today (see each model's "Cloud sync
    // (schema-only, lot 0)" doc comment) — that wiring lives in
    // `Repositories/`, outside this lot's file perimeter. Under the delta
    // rule alone, a profile's/RPG state's row would push exactly once
    // (first sync) and then freeze forever, silently defeating the lot's
    // whole point for XP/streaks — data that, unlike `Card`, is NOT
    // reconstructible from `ReviewLog` (design spec §3 rule 2 only covers
    // `Card`). Both tables hold at most a handful of rows per device, so
    // pushing all of them every sync is cheap and correct regardless of
    // whether `updatedAt` is ever wired up. Declared as a deliberate
    // per-entity delta-rule override, not an oversight — see this task's
    // final notes.

    func pushAllProfiles(using transport: any SyncDataTransport, accessToken: String) async throws -> Int {
        let profiles = try modelContext.fetch(FetchDescriptor<UserProfile>())
        guard !profiles.isEmpty else { return 0 }
        for batch in profiles.chunked(into: Self.batchSize) {
            let rows = try batch.map { try SyncPayloadBuilder.row(for: $0) }
            try await transport.upsert(table: "profiles", rows: rows, accessToken: accessToken)
            for profile in batch { profile.syncedAt = profile.updatedAt }
            try modelContext.save()
        }
        return profiles.count
    }

    func pushAllRPGStates(using transport: any SyncDataTransport, accessToken: String) async throws -> Int {
        let states = try modelContext.fetch(FetchDescriptor<RPGState>())
        guard !states.isEmpty else { return 0 }
        for batch in states.chunked(into: Self.batchSize) {
            let rows = try batch.map { try SyncPayloadBuilder.row(for: $0) }
            try await transport.upsert(table: "rpg_states", rows: rows, accessToken: accessToken)
            for state in batch { state.syncedAt = state.updatedAt }
            try modelContext.save()
        }
        return states.count
    }

    // MARK: - cards / vocabulary_entries — delta, with a declared staleness gap
    //
    // `syncedAt == nil` (a brand-new row) is caught exactly. A mutation to
    // an already-synced row (e.g. FSRS state after a review) is caught only
    // if something bumps `updatedAt` — nothing does yet, for the same
    // repository-wiring reason as above. Practical effect: a card's/entry's
    // FIRST push is correct; subsequent field-level edits are NOT re-pushed
    // by this lot. Mitigation already designed for: spec §5.3 rule 2 makes
    // `ReviewLog` (which IS fully append-only-correct, see below) the
    // source of truth for `Card`'s derived state — lot 2's replay can
    // reconstruct current FSRS state without relying on `cards.updated_at`
    // ever having moved. `VocabularyEntry` has no equivalent append-only
    // log to fall back on; its staleness gap is real and undeclared-away.

    func pushDirtyCards(using transport: any SyncDataTransport, accessToken: String) async throws -> Int {
        let all = try modelContext.fetch(FetchDescriptor<Card>())
        let dirty = all.filter { isDirty(updatedAt: $0.updatedAt, deletedAt: $0.deletedAt, syncedAt: $0.syncedAt) }
        guard !dirty.isEmpty else { return 0 }
        for batch in dirty.chunked(into: Self.batchSize) {
            let rows = try batch.map { try SyncPayloadBuilder.row(for: $0) }
            try await transport.upsert(table: "cards", rows: rows, accessToken: accessToken)
            for card in batch { card.syncedAt = card.updatedAt }
            try modelContext.save()
        }
        return dirty.count
    }

    func pushDirtyVocabularyEntries(using transport: any SyncDataTransport, accessToken: String) async throws -> Int {
        let all = try modelContext.fetch(FetchDescriptor<VocabularyEntry>())
        let dirty = all.filter { isDirty(updatedAt: $0.updatedAt, deletedAt: $0.deletedAt, syncedAt: $0.syncedAt) }
        guard !dirty.isEmpty else { return 0 }
        for batch in dirty.chunked(into: Self.batchSize) {
            let rows = try batch.map { try SyncPayloadBuilder.row(for: $0) }
            try await transport.upsert(table: "vocabulary_entries", rows: rows, accessToken: accessToken)
            for entry in batch { entry.syncedAt = entry.updatedAt }
            try modelContext.save()
        }
        return dirty.count
    }

    // MARK: - Append-only tables — delta selection is EXACT here
    //
    // `review_logs` / `vocabulary_encounters` / `exercise_outcome_logs` rows
    // are created once and never mutated afterward (design spec §3) — every
    // instance's `init` sets `updatedAt = Date()` and `syncedAt = nil` at
    // creation and nothing ever touches either field again except this
    // actor. `syncedAt == nil` therefore identifies exactly the rows never
    // yet pushed, with no staleness gap.

    func pushDirtyReviewLogs(using transport: any SyncDataTransport, accessToken: String) async throws -> Int {
        let all = try modelContext.fetch(FetchDescriptor<ReviewLog>())
        let dirty = all.filter { $0.syncedAt == nil }
        guard !dirty.isEmpty else { return 0 }
        for batch in dirty.chunked(into: Self.batchSize) {
            let rows = try batch.map { try SyncPayloadBuilder.row(for: $0) }
            try await transport.upsert(table: "review_logs", rows: rows, accessToken: accessToken)
            for log in batch { log.syncedAt = log.updatedAt }
            try modelContext.save()
        }
        return dirty.count
    }

    func pushDirtyVocabularyEncounters(using transport: any SyncDataTransport, accessToken: String) async throws -> Int {
        let all = try modelContext.fetch(FetchDescriptor<VocabularyEncounter>())
        let dirty = all.filter { $0.syncedAt == nil }
        guard !dirty.isEmpty else { return 0 }
        for batch in dirty.chunked(into: Self.batchSize) {
            let rows = try batch.map { try SyncPayloadBuilder.row(for: $0) }
            try await transport.upsert(table: "vocabulary_encounters", rows: rows, accessToken: accessToken)
            for encounter in batch { encounter.syncedAt = encounter.updatedAt }
            try modelContext.save()
        }
        return dirty.count
    }

    func pushDirtyExerciseOutcomeLogs(using transport: any SyncDataTransport, accessToken: String) async throws -> Int {
        let all = try modelContext.fetch(FetchDescriptor<ExerciseOutcomeLog>())
        let dirty = all.filter { $0.syncedAt == nil }
        guard !dirty.isEmpty else { return 0 }
        for batch in dirty.chunked(into: Self.batchSize) {
            let rows = try batch.map { try SyncPayloadBuilder.row(for: $0) }
            try await transport.upsert(table: "exercise_outcome_logs", rows: rows, accessToken: accessToken)
            for log in batch { log.syncedAt = log.updatedAt }
            try modelContext.save()
        }
        return dirty.count
    }

    // companion_chat_messages: no pushDirty* method exists for this entity
    // — see `SyncPayloadBuilder`'s trailing comment. Not an omission to fix
    // later in THIS lot.

    // MARK: - markEverythingUnsynced (CRITIQUE B)

    /// Sets `syncedAt = nil` on every row across all 7 synced types and
    /// saves — the fix for the most serious defect this lot's second
    /// adversarial review round found (Critical B): "cloud account wiped,
    /// then re-seeded from local" silently pushed almost nothing.
    ///
    /// The bug this closes: `pushDirtyCards`/`pushDirtyVocabularyEntries`
    /// filter on `isDirty` (`syncedAt == nil || updatedAt > syncedAt`), and
    /// the 3 append-only `pushDirty*` methods filter on `syncedAt == nil`
    /// STRICTLY. After a server-side account is erased
    /// (`CloudDataDeletionService.deleteAllCloudData()`) — or after a
    /// rejected refresh token silently mints a brand-new anonymous identity
    /// (`AnonymousIdentityManager`, same failure mode without going through
    /// deletion at all) — every local row still carries the `syncedAt`
    /// stamp from pushes made to the OLD, now-gone account. Every one of
    /// those rows reads as "already synced" to the delta filters above, so
    /// a subsequent push sends ZERO cards, ZERO review logs, ZERO
    /// vocabulary — only `profiles`/`rpg_states` (pushed unconditionally
    /// every cycle regardless of `syncedAt`) actually reach the new
    /// account. Months of review history silently never make it to the
    /// server, while `SettingsView`'s status row reports "up to date"
    /// (the push itself DID succeed — it just had almost nothing dirty to
    /// send).
    ///
    /// Called from exactly two places, both documented at their own call
    /// sites:
    /// - `CloudDataDeletionService.deleteAllCloudData()`, right after that
    ///   service resets the pull cursors — so a LATER opt-back-in re-seeds
    ///   for real.
    /// - `CloudSyncCoordinator.syncNow()`, BEFORE the push half of a cycle
    ///   whose pull half just reported `PullOutcome.seededFromLocal` —
    ///   this is the one that actually matters for the rejected-refresh-
    ///   token case above, since that path never goes through
    ///   `CloudDataDeletionService` at all: the ONLY signal it produces is
    ///   rule 1 firing on the next pull against the fresh identity.
    ///
    /// Deliberately NOT called from `setConsent(false)`: turning backup off
    /// leaves the data on the server exactly as it was, so every local
    /// `syncedAt` stays factually correct. Marking everything unsynced
    /// there would just re-push identical rows for no reason the moment
    /// consent is turned back on.
    func markEverythingUnsynced() throws {
        for profile in try modelContext.fetch(FetchDescriptor<UserProfile>()) { profile.syncedAt = nil }
        for state in try modelContext.fetch(FetchDescriptor<RPGState>()) { state.syncedAt = nil }
        for card in try modelContext.fetch(FetchDescriptor<Card>()) { card.syncedAt = nil }
        for log in try modelContext.fetch(FetchDescriptor<ReviewLog>()) { log.syncedAt = nil }
        for entry in try modelContext.fetch(FetchDescriptor<VocabularyEntry>()) { entry.syncedAt = nil }
        for encounter in try modelContext.fetch(FetchDescriptor<VocabularyEncounter>()) { encounter.syncedAt = nil }
        for log in try modelContext.fetch(FetchDescriptor<ExerciseOutcomeLog>()) { log.syncedAt = nil }
        try modelContext.save()
    }
}

// MARK: - Chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
