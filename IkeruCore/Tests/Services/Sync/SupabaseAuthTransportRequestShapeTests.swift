import Testing
import Foundation
@testable import IkeruCore

/// Wire-level tests for `URLSessionSupabaseAuthTransport` — the ONLY thing
/// standing between "the client sends `link_identity: true`" and "the
/// client silently doesn't" is the request body actually built here.
/// `AppleIdentityLinkingTests` exercises every other lot-3 behavior against
/// `MockSupabaseAuthTransport`, which never touches this code path at all —
/// so nothing else in this lot proves the literal byte the task brief calls
/// "la SEULE chose qui distingue" a link from an identity switch is ever
/// actually serialized onto the request. This file is that proof: it
/// intercepts the real `URLRequest` `URLSessionSupabaseAuthTransport`
/// builds (via a stub `URLProtocol`, no network) and asserts on it
/// literally, rather than assuming Swift's `Encodable` synthesis behaves
/// the way the production code's comments claim it does.
@Suite("SupabaseAuthTransportRequestShape")
struct SupabaseAuthTransportRequestShapeTests {

    private func makeTransport(status: Int, jsonBody: [String: Any]) -> URLSessionSupabaseAuthTransport {
        RecordingURLProtocol.reset(status: status, jsonBody: jsonBody)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        let session = URLSession(configuration: config)
        return URLSessionSupabaseAuthTransport(
            baseURL: URL(string: "https://example.supabase.co")!,
            apiKey: "test-api-key",
            session: session
        )
    }

    private func successBody(userID: UUID) -> [String: Any] {
        [
            "access_token": "new-access-token",
            "refresh_token": "new-refresh-token",
            "expires_in": 3600,
            "user": ["id": userID.uuidString],
        ]
    }

    @Test("linkAppleIdentity: URL is grant_type=id_token, Authorization Bearer is the CURRENT session's token, body has link_identity:true, provider:apple, and the RAW nonce")
    func linkAppleIdentityRequestShape() async throws {
        let userID = UUID()
        let transport = makeTransport(status: 200, jsonBody: successBody(userID: userID))

        _ = try await transport.linkAppleIdentity(idToken: "APPLE_ID_TOKEN", rawNonce: "RAW_NONCE_VALUE", accessToken: "ANON_ACCESS_TOKEN")

        let request = try #require(RecordingURLProtocol.lastRequest)
        let url = try #require(request.url)
        #expect(url.path.hasSuffix("/auth/v1/token"))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "grant_type", value: "id_token")))

        #expect(request.value(forHTTPHeaderField: "apikey") == "test-api-key")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ANON_ACCESS_TOKEN")

        let bodyData = try #require(RecordingURLProtocol.bodyData(from: request))
        let json = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(json["provider"] as? String == "apple")
        #expect(json["id_token"] as? String == "APPLE_ID_TOKEN")
        // The RAW nonce, never a hash of it — Supabase hashes server-side.
        #expect(json["nonce"] as? String == "RAW_NONCE_VALUE")
        #expect(json["link_identity"] as? Bool == true)
    }

    @Test("signInWithApple: SAME URL shape, but NO Authorization header and NO link_identity key at all (not even false)")
    func signInWithAppleRequestShape() async throws {
        let userID = UUID()
        let transport = makeTransport(status: 200, jsonBody: successBody(userID: userID))

        _ = try await transport.signInWithApple(idToken: "APPLE_ID_TOKEN", rawNonce: "RAW_NONCE_VALUE")

        let request = try #require(RecordingURLProtocol.lastRequest)
        let url = try #require(request.url)
        #expect(url.path.hasSuffix("/auth/v1/token"))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "grant_type", value: "id_token")))

        // The empirical proof behind this file's whole reason to exist:
        // a plain sign-in must NOT carry the flag that promises identity
        // preservation, and must not authenticate as any prior session.
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

        let bodyData = try #require(RecordingURLProtocol.bodyData(from: request))
        let json = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(json["provider"] as? String == "apple")
        #expect(json["id_token"] as? String == "APPLE_ID_TOKEN")
        #expect(json["nonce"] as? String == "RAW_NONCE_VALUE")
        // `encodeIfPresent`-on-nil must OMIT the key entirely — not encode
        // `"link_identity": null`. `json["link_identity"]` being merely
        // `nil` from a Swift dictionary lookup wouldn't distinguish those
        // two cases, so check key presence directly.
        #expect(json.keys.contains("link_identity") == false)
    }

    @Test("linkAppleIdentity: a 422 identity_already_exists response throws SyncAuthError.identityAlreadyLinked, not the generic .requestFailed")
    func identityAlreadyLinkedErrorCodeMapsToDistinctError() async throws {
        RecordingURLProtocol.reset(status: 422, jsonBody: ["code": 422, "error_code": "identity_already_exists", "msg": "Identity is already linked to another user"])
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        let transport = URLSessionSupabaseAuthTransport(
            baseURL: URL(string: "https://example.supabase.co")!,
            apiKey: "test-api-key",
            session: URLSession(configuration: config)
        )

        do {
            _ = try await transport.linkAppleIdentity(idToken: "TOKEN", rawNonce: "NONCE", accessToken: "ACCESS")
            Issue.record("Expected an error to be thrown")
        } catch SyncAuthError.identityAlreadyLinked(let status, _) {
            #expect(status == 422)
        } catch {
            Issue.record("Expected .identityAlreadyLinked, got \(error)")
        }
    }

    @Test("linkAppleIdentity: any OTHER error_code maps to the generic .requestFailed, not silently to .identityAlreadyLinked")
    func unrelatedErrorCodeStaysGeneric() async throws {
        RecordingURLProtocol.reset(status: 401, jsonBody: ["code": 401, "error_code": "invalid_grant", "msg": "bad token"])
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        let transport = URLSessionSupabaseAuthTransport(
            baseURL: URL(string: "https://example.supabase.co")!,
            apiKey: "test-api-key",
            session: URLSession(configuration: config)
        )

        do {
            _ = try await transport.linkAppleIdentity(idToken: "TOKEN", rawNonce: "NONCE", accessToken: "ACCESS")
            Issue.record("Expected an error to be thrown")
        } catch SyncAuthError.requestFailed(let status, let errorCode, _) {
            #expect(status == 401)
            #expect(errorCode == "invalid_grant")
        } catch {
            Issue.record("Expected .requestFailed, got \(error)")
        }
    }
}

// MARK: - RecordingURLProtocol

/// Minimal stub `URLProtocol` — no network, records the last outgoing
/// request and replays a canned JSON response. `URLSession` sometimes moves
/// a request's `httpBody` into `httpBodyStream` before handing it to a
/// custom `URLProtocol` (a well-known gotcha), so `bodyData(from:)` reads
/// whichever one is actually populated.
final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _lastRequest: URLRequest?
    nonisolated(unsafe) private static var responseStatus = 200
    nonisolated(unsafe) private static var responseBody = Data()

    static var lastRequest: URLRequest? {
        lock.withLock { _lastRequest }
    }

    static func reset(status: Int, jsonBody: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: jsonBody)) ?? Data()
        lock.withLock {
            _lastRequest = nil
            responseStatus = status
            responseBody = data
        }
    }

    static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body): (Int, Data) = Self.lock.withLock {
            Self._lastRequest = request
            return (Self.responseStatus, Self.responseBody)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
