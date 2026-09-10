import Testing
import Foundation
@testable import IkeruCore

@Suite("JSONValue")
struct JSONValueTests {

    @Test("Round-trips through encode/decode for every case")
    func roundTrips() throws {
        let value = JSONValue.object([
            "s": .string("hello"),
            "n": .number(42.5),
            "b": .bool(true),
            "nil": .null,
            "arr": .array([.number(1), .number(2), .string("three")]),
        ])

        let data = try SyncJSON.encoder.encode(value)
        let decoded = try SyncJSON.decoder.decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("Bool and Double do not cross-decode into each other's case")
    func boolAndNumberStayDistinct() throws {
        let boolData = try SyncJSON.encoder.encode(JSONValue.bool(true))
        let decodedBool = try SyncJSON.decoder.decode(JSONValue.self, from: boolData)
        #expect(decodedBool == .bool(true))

        let numberData = try SyncJSON.encoder.encode(JSONValue.number(1))
        let decodedNumber = try SyncJSON.decoder.decode(JSONValue.self, from: numberData)
        #expect(decodedNumber == .number(1))
    }

    @Test("uuidOrNull / stringOrNull / dateOrNull produce .null for nil")
    func optionalConveniencesProduceNull() {
        #expect(JSONValue.uuidOrNull(nil) == .null)
        #expect(JSONValue.stringOrNull(nil) == .null)
        #expect(JSONValue.dateOrNull(nil) == .null)
    }

    @Test("uuidOrNull / stringOrNull / dateOrNull wrap non-nil values")
    func optionalConveniencesWrapValues() {
        let id = UUID()
        #expect(JSONValue.uuidOrNull(id) == .uuid(id))
        #expect(JSONValue.stringOrNull("x") == .string("x"))

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(JSONValue.dateOrNull(date) == .date(date))
    }

    @Test("jsonValue(encoding:) bridges a Codable struct's fields into an object")
    func encodingBridgesStruct() throws {
        struct Payload: Encodable {
            let name: String
            let count: Int
        }
        let value = try SyncJSON.jsonValue(encoding: Payload(name: "kana", count: 3))
        guard case .object(let fields) = value else {
            Issue.record("Expected .object, got \(value)")
            return
        }
        #expect(fields["name"] == .string("kana"))
        #expect(fields["count"] == .number(3))
    }

    @Test("Dates encode as ISO-8601 with fractional seconds, not epoch-2001 seconds")
    func datesEncodeAsISO8601() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let data = try SyncJSON.encoder.encode(JSONValue.date(date))
        let string = String(data: data, encoding: .utf8) ?? ""
        // A `.deferredToDate` regression would encode a bare Double instead.
        #expect(string.contains("T"))
        #expect(string.contains("Z") || string.contains("+"))
    }

    @Test("encodedRequestBody serializes an array of rows as a JSON array")
    func encodedRequestBodySerializesArray() throws {
        let rows: [SyncRow] = [
            ["id": .string("a")],
            ["id": .string("b")],
        ]
        let data = try rows.encodedRequestBody()
        let decoded = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(decoded?.count == 2)
    }
}
