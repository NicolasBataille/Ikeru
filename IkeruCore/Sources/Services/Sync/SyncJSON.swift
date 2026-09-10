import Foundation

// MARK: - SupabaseConfig

/// Connection details for the Ikeru Supabase project — cloud-sync lot 1
/// (`docs/design-specs/2026-08-10-cloud-sync-design.md`).
///
/// The publishable key is designed to be public (it ships in this
/// open-source repo on purpose): its safety comes entirely from Row Level
/// Security, which is enabled and enforced on every synced table — verified
/// from outside this task (anonymous `SELECT` returns `[]`, anonymous
/// `INSERT` is rejected with `42501`). The `service_role` key never appears
/// here or anywhere in this codebase.
public enum SupabaseConfig {

    /// Base URL of the Ikeru Supabase project (region: `eu-west-1`).
    public static let projectURL = URL(string: "https://aiayzlarixlogcoyswna.supabase.co")!

    /// Publishable (anon) API key. Safe to ship in a public repo — see the
    /// type doc comment.
    public static let publishableKey = "sb_publishable_THLdQoO5IdEZcCovxEQFAg_I14rjqU8"
}

// MARK: - SyncJSON

/// Shared JSON encoding/decoding configuration for everything in the Sync
/// module — one date format used consistently for wire payloads
/// (`JSONValue`-encoded rows) AND for the `SyncSession` persisted to
/// Keychain, so a session round-trips through the same codec that builds
/// request bodies.
///
/// `JSONEncoder`'s default date strategy (`.deferredToDate`, seconds since
/// 2001) is unusable against a Postgres `timestamptz` column — this type
/// exists specifically to avoid that trap everywhere a `Date` crosses the
/// wire.
public enum SyncJSON {

    /// ISO-8601 with fractional seconds — accepted by Postgres `timestamptz`
    /// and round-trips through `ISO8601DateFormatter` without precision loss
    /// at the resolution that matters here (sub-second sync ordering).
    ///
    /// `nonisolated(unsafe)`: `ISO8601DateFormatter` is a mutable reference
    /// type so the compiler can't verify `Sendable` on its own, but this
    /// instance's configuration (`formatOptions`) is set once at init below
    /// and never mutated again — only the non-mutating `string(from:)` /
    /// `date(from:)` accessors are called afterward, from any thread. Same
    /// pattern Apple documents as safe for a shared `DateFormatter`/
    /// `ISO8601DateFormatter` used strictly as a read-only formatter.
    nonisolated(unsafe) public static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public static func iso8601String(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(SyncJSON.iso8601String(date))
        }
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = SyncJSON.dateFormatter.date(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 date: \(raw)"
                )
            }
            return date
        }
        return decoder
    }()

    /// Encodes any `Encodable` value through `SyncJSON.encoder` and decodes
    /// the result back as a `JSONValue` tree — the bridge that lets a
    /// typed per-entity payload DTO (e.g. a small `Encodable` struct
    /// mirroring `Card`'s non-relational fields) become a `payload` cell
    /// inside a `SyncRow` without hand-writing a `JSONValue` builder for
    /// every field.
    public static func jsonValue(encoding value: some Encodable) throws -> JSONValue {
        let data = try encoder.encode(value)
        return try decoder.decode(JSONValue.self, from: data)
    }
}

// MARK: - Row body encoding

extension Array where Element == SyncRow {

    /// Serializes an array of rows into the JSON array PostgREST expects as
    /// a bulk-upsert request body.
    func encodedRequestBody() throws -> Data {
        try SyncJSON.encoder.encode(self.map(JSONValue.object))
    }
}
