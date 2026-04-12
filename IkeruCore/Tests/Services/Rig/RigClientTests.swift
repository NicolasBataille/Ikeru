import Testing
import Foundation
@testable import IkeruCore

@Suite("RigClient")
struct RigClientTests {

    private let url = URL(string: "http://192.168.1.42:8787")!

    @Test("Health request omits the X-Ikeru-Token header")
    func healthDoesNotRequireToken() async throws {
        let healthJSON = Data("""
        {"status":"ok","voicevox":"ok","gpu":"available","version":"0.1.0"}
        """.utf8)
        let session = MockURLSessionProvider(responseData: healthJSON, statusCode: 200)
        let client = RigClient(
            configuration: RigSettings(baseURL: url, sharedToken: ""),
            urlSession: session
        )
        let health = try await client.health()
        #expect(health.status == "ok")
        #expect(health.voicevox == "ok")
    }

    @Test("Authenticated requests fail when token is empty")
    func authenticatedRequestRequiresToken() async {
        let session = MockURLSessionProvider(responseData: Data(), statusCode: 200)
        let client = RigClient(
            configuration: RigSettings(baseURL: url, sharedToken: ""),
            urlSession: session
        )
        await #expect(throws: RigError.self) {
            _ = try await client.capabilities()
        }
    }

    @Test("Capabilities decodes job_types")
    func capabilitiesDecodesJobTypes() async throws {
        let json = Data("""
        {"job_types":["tts"],"voicevox_speakers":[3]}
        """.utf8)
        let session = MockURLSessionProvider(responseData: json, statusCode: 200)
        let client = RigClient(
            configuration: RigSettings(baseURL: url, sharedToken: "token"),
            urlSession: session
        )
        let caps = try await client.capabilities()
        #expect(caps.jobTypes == ["tts"])
        #expect(caps.voicevoxSpeakers == [3])
    }

    @Test("Enqueue returns the job_id")
    func enqueueReturnsJobId() async throws {
        let json = Data("""
        {"job_id":"abc123","status":"queued"}
        """.utf8)
        let session = MockURLSessionProvider(responseData: json, statusCode: 202)
        let client = RigClient(
            configuration: RigSettings(baseURL: url, sharedToken: "token"),
            urlSession: session
        )
        let id = try await client.enqueueJob(.tts(text: "こんにちは"))
        #expect(id == "abc123")
    }

    @Test("401 maps to RigError.unauthorized")
    func unauthorizedMaps() async {
        let session = MockURLSessionProvider(responseData: Data("{}".utf8), statusCode: 401)
        let client = RigClient(
            configuration: RigSettings(baseURL: url, sharedToken: "wrong"),
            urlSession: session
        )
        await #expect(throws: RigError.self) {
            _ = try await client.capabilities()
        }
    }

    @Test("404 maps to RigError.notFound")
    func notFoundMaps() async {
        let session = MockURLSessionProvider(responseData: Data("{}".utf8), statusCode: 404)
        let client = RigClient(
            configuration: RigSettings(baseURL: url, sharedToken: "token"),
            urlSession: session
        )
        await #expect(throws: RigError.self) {
            _ = try await client.jobStatus("nope")
        }
    }

    @Test("RigJobRecord decodes terminal status flags")
    func jobRecordTerminalFlags() async throws {
        let json = Data("""
        {
          "id":"abc",
          "type":"tts",
          "status":"done",
          "params":{"text":"x","speaker_id":3},
          "created_at":"2026-04-07T19:00:00Z",
          "started_at":"2026-04-07T19:00:01Z",
          "finished_at":"2026-04-07T19:00:02Z",
          "asset_path":"/app/assets/abc.opus",
          "error":null
        }
        """.utf8)
        let session = MockURLSessionProvider(responseData: json, statusCode: 200)
        let client = RigClient(
            configuration: RigSettings(baseURL: url, sharedToken: "token"),
            urlSession: session
        )
        let record = try await client.jobStatus("abc")
        #expect(record.isDone == true)
        #expect(record.isError == false)
        #expect(record.isTerminal == true)
        #expect(record.assetPath == "/app/assets/abc.opus")
    }
}

@Suite("RigSettings + Store")
struct RigSettingsStoreTests {

    @Test("Store round-trips URL via UserDefaults and token via Keychain")
    func roundTrip() throws {
        let suite = "test-rig-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let keychain = MockKeychainStore()
        let store = RigSettingsStore(keychain: keychain, defaults: defaults)

        let settings = RigSettings(
            baseURL: URL(string: "http://10.0.0.1:8787")!,
            sharedToken: "secret-token"
        )
        try store.save(settings)

        let loaded = store.load()
        #expect(loaded?.baseURL.absoluteString == "http://10.0.0.1:8787")
        #expect(loaded?.sharedToken == "secret-token")
    }

    @Test("Clear removes both URL and token")
    func clearRemovesAll() throws {
        let suite = "test-rig-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let keychain = MockKeychainStore()
        let store = RigSettingsStore(keychain: keychain, defaults: defaults)

        try store.save(RigSettings(baseURL: URL(string: "http://x")!, sharedToken: "t"))
        try store.clear()
        #expect(store.load() == nil)
    }

    @Test("isConfigured reports false when token missing")
    func isConfiguredFalseOnMissingToken() {
        let settings = RigSettings(
            baseURL: URL(string: "http://x")!,
            sharedToken: ""
        )
        #expect(settings.isConfigured == false)
    }
}
