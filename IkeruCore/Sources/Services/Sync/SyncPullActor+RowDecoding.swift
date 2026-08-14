import Foundation
import SwiftData

// MARK: - SyncIdentifiable
//
// Split out of `SyncPullActor.swift` itself (along with `SyncRowDecoding`
// and `SyncPullDateParsing` below) purely to stay under SwiftLint's
// `file_length` (1200 lines) budget — there is no behavioral reason these
// couldn't live in the main file. Same rationale as
// `SyncPullActor+StandaloneTables.swift`'s own doc comment.

/// Narrow conformance so `SyncPullActor.fetchOne` can write `$0.id == id`
/// inside a `#Predicate` generically — `#Predicate`'s macro expansion needs
/// the `id` property to be visible on the generic type at the call site,
/// which a bare `PersistentModel` constraint doesn't provide. Not `private`:
/// `fetchOne` itself is `internal` (see its doc comment in
/// `SyncPullActor.swift`) so `SyncPullActor+StandaloneTables.swift`'s
/// extension can call it, and a `private` generic constraint on an
/// `internal` function is not allowed — module-internal is still no wider
/// exposure than before, since neither this protocol nor `SyncPullActor` is
/// ever `public`.
protocol SyncIdentifiable {
    var id: UUID { get }
}

extension UserProfile: SyncIdentifiable {}
extension RPGState: SyncIdentifiable {}
extension Card: SyncIdentifiable {}
extension ReviewLog: SyncIdentifiable {}
extension VocabularyEntry: SyncIdentifiable {}
extension VocabularyEncounter: SyncIdentifiable {}
extension ExerciseOutcomeLog: SyncIdentifiable {}

// MARK: - RowApplyOutcome

/// Per-row outcome from an `apply*Rows` function — supersedes a bare `Bool`
/// (2026-08 lot-2 pull review, round 4): the old scheme could only say
/// "applied" or "skipped," so a skip caused by an undecodable payload
/// (PERMANENT — no future cycle can ever fix that) and a skip caused by an
/// unresolved foreign key (TRANSIENT — the referenced row hasn't been
/// pulled/applied YET, but will be once its own table's page arrives) were
/// indistinguishable to `SyncPullActor.pullAndApply`, which counted both
/// identically toward `SyncSkipTracker`'s tight 3-cycle drop threshold.
///
/// That silently abandoned real review history: a `review_logs` row whose
/// `cards` parent was itself delayed behind an unrelated poison row for 3+
/// cycles got permanently dropped at cycle 3 for "not resolving fast
/// enough," even though it was never actually unrecoverable — only
/// waiting. `pullAndApply` now routes `.skippedPermanent` through
/// `SyncSkipTracker.recordSkip` (unchanged 3-strike threshold) and
/// `.skippedTransient` through the separate `recordTransientSkip` (a much
/// wider bound — see `SyncPullActor.transientPoisonDropThreshold`'s doc
/// comment for why a bound is still needed there too).
///
/// Every `apply*Rows` function (4 in `SyncPullActor.swift`, 3 in
/// `SyncPullActor+StandaloneTables.swift`) must append exactly one case per
/// row it iterates, in the same order as its input `[SyncRow]` — the same
/// "one flag per row, in order" contract the old `[Bool]` scheme had (see
/// the `apply(table:rows:...)` dispatcher's doc comment), just with a third
/// state instead of two.
enum RowApplyOutcome: Sendable, Equatable {
    /// Applied this cycle — either newly created/updated, or (on one of the
    /// 3 append-only tables: `review_logs`, `vocabulary_encounters`,
    /// `exercise_outcome_logs`) a safe no-op redelivery of a row already
    /// durably present. `pullAndApply`'s cursor-advance prefix treats both
    /// the same way: safe to advance the cursor past.
    case applied
    /// Skipped because the payload itself could not be decoded — a
    /// malformed or missing required field, or a value this app version
    /// doesn't recognize (see every `apply*Rows` function's `try?` decode
    /// guards). Retrying later cannot help on its own; only
    /// `SyncSkipTracker`'s tight `SyncPullActor.poisonDropThreshold` should
    /// ever abandon a row for this reason.
    case skippedPermanent
    /// Skipped because a foreign key this row depends on — a `cards` row
    /// for `review_logs`, a `vocabulary_entries` row for
    /// `vocabulary_encounters` — is not yet present locally. Expected to
    /// self-heal once the parent table's own pull catches up (`cards` and
    /// `vocabulary_entries` are always pulled before their dependents, per
    /// `SyncPullActor`'s `pullOrder`) — must never consume a
    /// `poisonDropThreshold` strike, only the much wider
    /// `SyncPullActor.transientPoisonDropThreshold` one.
    case skippedTransient
}

// MARK: - SyncRowDecoding

/// Decodes the fields `SyncPullTransport` returns from a real PostgREST
/// `SELECT *` response — the reverse direction of `SyncPayloadBuilder`
/// (which only ever WRITES a `SyncRow`). Module-internal rather than
/// `private` to this file: `SyncPullActor.swift` and
/// `SyncPullActor+StandaloneTables.swift` both need it too, for the same
/// reason `SyncCursorTimestampParsing` stays scoped in `SyncCursorStore.swift`
/// — it is never `public`, so this costs nothing outside `IkeruCore`.
enum SyncRowDecoding {

    struct CommonFields {
        let id: UUID
        let updatedAt: Date
        let deletedAt: Date?
    }

    enum DecodingError: Error, Sendable {
        case missingField(String)
    }

    /// Every synced row carries `id` and `updated_at` unconditionally, and
    /// `deleted_at` as a nullable column. Throws rather than returning
    /// `nil` so a malformed row (missing/unparseable `id` or `updated_at`)
    /// is distinguishable, at the call site, from "this row is fine but has
    /// no `deleted_at`" — callers that don't care about telling those apart
    /// use `try?`.
    static func common(_ row: SyncRow) throws -> CommonFields {
        guard let id = uuid(row, "id") else { throw DecodingError.missingField("id") }
        guard let updatedAt = date(row, "updated_at") else { throw DecodingError.missingField("updated_at") }
        return CommonFields(id: id, updatedAt: updatedAt, deletedAt: date(row, "deleted_at"))
    }

    static func string(_ row: SyncRow, _ key: String) -> String? {
        guard case .string(let value)? = row[key] else { return nil }
        return value
    }

    static func number(_ row: SyncRow, _ key: String) -> Double? {
        guard case .number(let value)? = row[key] else { return nil }
        return value
    }

    static func uuid(_ row: SyncRow, _ key: String) -> UUID? {
        string(row, key).flatMap(UUID.init(uuidString:))
    }

    static func date(_ row: SyncRow, _ key: String) -> Date? {
        string(row, key).flatMap(SyncPullDateParsing.parse)
    }

    /// Decodes a nested `payload` `JSONValue` object into a typed DTO,
    /// through a LOCAL decoder (`payloadDecoder` below) rather than the
    /// shared `SyncJSON.decoder` — see `SyncPullDateParsing`'s doc comment
    /// for why: `SyncJSON.decoder`'s date strategy only accepts the
    /// always-fractional form this codebase's own encoder writes, and a
    /// real Postgres row can legitimately omit the fraction. Encoding
    /// `value` back through `SyncJSON.encoder` first is safe regardless of
    /// that encoder's date strategy — a `JSONValue` never contains a raw
    /// `Date`, only the already-stringified form, so no date-encoding logic
    /// runs on this leg at all.
    static func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        let data = try SyncJSON.encoder.encode(value)
        return try payloadDecoder.decode(T.self, from: data)
    }

    private static let payloadDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = SyncPullDateParsing.parse(raw) else {
                throw Swift.DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 date: \(raw)"
                )
            }
            return date
        }
        return decoder
    }()
}

// MARK: - SyncPullDateParsing

/// Tolerant ISO-8601 parsing for every date this actor reads off the wire —
/// row-level columns (`updated_at`, `deleted_at`, `occurred_at`) AND, via
/// `SyncRowDecoding.payloadDecoder` above, dates nested inside a `payload`
/// object (`dueDate`, `lastReview`, `createdAt`, `lastSessionDate`).
///
/// Duplicated from (not shared with — despite both living under
/// `Services/Sync/` and `SyncCursorTimestampParsing` having no `private`
/// modifier, so a direct call was possible) `SyncCursorStore.swift`'s
/// `SyncCursorTimestampParsing`, for the exact same empirically-verified
/// reason: real Postgres `to_json` output DROPS the fractional-seconds part
/// entirely for an exact-second timestamp (`"2026-08-14T10:00:00+00:00"`,
/// no decimal point) while `SyncJSON.dateFormatter` is configured
/// `.withFractionalSeconds`-only and returns `nil` on that shape. Every Date
/// field this actor decodes off a real row is exposed to the same hazard
/// `server_updated_at` is — not just the cursor column — so the same
/// two-formatter fallback is needed here too, not only in the cursor store.
/// Left duplicated rather than refactored to a shared call: harmless (two
/// tiny private formatters, not a correctness risk) and out of scope for
/// this verification pass — flagged here instead of silently left
/// mis-justified.
private enum SyncPullDateParsing {

    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let wholeSecond: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ raw: String) -> Date? {
        fractional.date(from: raw) ?? wholeSecond.date(from: raw)
    }
}
