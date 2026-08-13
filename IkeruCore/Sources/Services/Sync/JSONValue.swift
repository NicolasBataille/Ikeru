import Foundation

/// A minimal, safe representation of an arbitrary JSON value.
///
/// Used to build PostgREST request bodies (row dictionaries, jsonb `payload`
/// columns) without hand-rolling `[String: Any]` — `Any` isn't `Sendable` or
/// `Encodable`, which matters because sync rows cross an actor boundary
/// (`SyncModelActor` → `SyncDataTransport`, see `CloudSyncCoordinator`).
public enum JSONValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])
}

// MARK: - Codable

extension JSONValue: Codable {

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Order matters: Foundation's JSONDecoder is strict about type
        // matching (a JSON number never decodes as Bool and vice versa), so
        // trying Bool before Double before String is safe — no case can
        // accidentally swallow another's input.
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - Convenience

extension JSONValue {

    /// Wraps a `UUID` as its string form (`UUID.uuidString`, which Foundation
    /// renders uppercase, e.g. `"E621E1F8-…"`) — Postgres's `uuid` type
    /// parses this case-insensitively, so PostgREST accepts it as-is.
    public static func uuid(_ value: UUID) -> JSONValue {
        .string(value.uuidString)
    }

    /// Wraps an optional `UUID`, producing `.null` for `nil`. Named distinctly
    /// from the `.uuid(UUID)` overload above (rather than relying on
    /// Optional-vs-non-Optional overload resolution against the synthesized
    /// `case string(String)` constructor) to keep call sites unambiguous.
    public static func uuidOrNull(_ value: UUID?) -> JSONValue {
        value.map(JSONValue.uuid) ?? .null
    }

    /// Wraps an optional `String`, producing `.null` for `nil`.
    public static func stringOrNull(_ value: String?) -> JSONValue {
        value.map(JSONValue.string) ?? .null
    }

    /// Wraps a `Date` using the sync ISO-8601 (with fractional seconds)
    /// format — see `SyncJSON.iso8601String`.
    public static func date(_ value: Date) -> JSONValue {
        .string(SyncJSON.iso8601String(value))
    }

    /// Wraps an optional `Date`, producing `.null` for `nil`.
    public static func dateOrNull(_ value: Date?) -> JSONValue {
        value.map(JSONValue.date) ?? .null
    }
}

/// One PostgREST row: a flat map of column name → JSON value, where a
/// `payload` entry (when present) is itself a nested `.object`.
public typealias SyncRow = [String: JSONValue]
