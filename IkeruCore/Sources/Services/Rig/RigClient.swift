import Foundation
import os

// MARK: - RigClient
//
// HTTP client for the local ikeru-rig server (Story 7.3).
// Speaks the FastAPI REST API documented in `rig/README.md`.
//
// All endpoints except `/health` carry the `X-Ikeru-Token` shared-secret header.
// The base URL and token are read from `RigSettings` at call time so the user
// can change them in Settings without rebuilding the client.

public struct RigClient: Sendable {

    public let configuration: RigSettings
    private let urlSession: any URLSessionProvider

    public init(
        configuration: RigSettings,
        urlSession: any URLSessionProvider = URLSession.shared
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    // MARK: - Public API

    /// Liveness check. Does NOT require the shared token.
    public func health() async throws -> RigHealth {
        let url = try endpoint("/health")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        return try await decode(RigHealth.self, from: request)
    }

    /// Returns the catalogue of supported job types and (for TTS) speakers.
    public func capabilities() async throws -> RigCapabilities {
        let request = try authenticatedRequest(path: "/capabilities", method: "GET")
        return try await decode(RigCapabilities.self, from: request)
    }

    /// Enqueues a job and returns its server-side ID.
    public func enqueueJob(_ job: RigJobRequest) async throws -> String {
        var request = try authenticatedRequest(path: "/jobs", method: "POST")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(job)
        let response = try await decode(RigEnqueueResponse.self, from: request)
        return response.jobId
    }

    /// Returns the current status of a job.
    public func jobStatus(_ id: String) async throws -> RigJobRecord {
        let request = try authenticatedRequest(path: "/jobs/\(id)", method: "GET")
        return try await decode(RigJobRecord.self, from: request)
    }

    /// Streams the binary asset for a completed job.
    public func fetchAsset(_ id: String) async throws -> Data {
        let request = try authenticatedRequest(path: "/jobs/\(id)/asset", method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.validate(response: response)
        return data
    }

    /// Cancels or evicts a job.
    public func cancel(_ id: String) async throws {
        let request = try authenticatedRequest(path: "/jobs/\(id)", method: "DELETE")
        let (_, response) = try await urlSession.data(for: request)
        try Self.validate(response: response)
    }

    // MARK: - Private helpers

    private func endpoint(_ path: String) throws -> URL {
        guard let url = URL(string: configuration.baseURL.absoluteString + path) else {
            throw RigError.invalidURL
        }
        return url
    }

    private func authenticatedRequest(path: String, method: String) throws -> URLRequest {
        guard !configuration.sharedToken.isEmpty else {
            throw RigError.missingToken
        }
        var request = URLRequest(url: try endpoint(path))
        request.httpMethod = method
        request.addValue(configuration.sharedToken, forHTTPHeaderField: "X-Ikeru-Token")
        request.timeoutInterval = configuration.requestTimeout
        return request
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        from request: URLRequest
    ) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw RigError.network(error)
        }
        try Self.validate(response: response)
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            Logger.rig.error("RigClient decode error for \(String(describing: T.self))")
            throw RigError.invalidResponse
        }
    }

    private static func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw RigError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw RigError.unauthorized
        case 404:
            throw RigError.notFound
        case 409:
            throw RigError.notReady
        default:
            throw RigError.httpStatus(http.statusCode)
        }
    }
}

// MARK: - Errors

public enum RigError: Error, Sendable {
    case invalidURL
    case missingToken
    case unauthorized
    case notFound
    case notReady
    case httpStatus(Int)
    case invalidResponse
    case network(any Error)
    case timeout
}

// MARK: - DTOs

public struct RigHealth: Codable, Sendable, Equatable {
    public let status: String
    public let voicevox: String
    public let gpu: String
    public let version: String
}

public struct RigCapabilities: Codable, Sendable, Equatable {
    public let jobTypes: [String]
    public let voicevoxSpeakers: [Int]?

    enum CodingKeys: String, CodingKey {
        case jobTypes = "job_types"
        case voicevoxSpeakers = "voicevox_speakers"
    }
}

public struct RigJobRequest: Codable, Sendable {
    public let type: String
    public let params: [String: RigJSONValue]

    public init(type: String, params: [String: RigJSONValue]) {
        self.type = type
        self.params = params
    }

    /// Convenience builder for a TTS job.
    public static func tts(text: String, speaker: Int = 3) -> RigJobRequest {
        RigJobRequest(
            type: "tts",
            params: [
                "text": .string(text),
                "speaker_id": .int(speaker),
            ]
        )
    }
}

public struct RigEnqueueResponse: Codable, Sendable {
    public let jobId: String
    public let status: String

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status
    }
}

public struct RigJobRecord: Codable, Sendable, Equatable {
    public let id: String
    public let type: String
    public let status: String
    public let params: [String: RigJSONValue]
    public let createdAt: Date
    public let startedAt: Date?
    public let finishedAt: Date?
    public let assetPath: String?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case id, type, status, params, error
        case createdAt = "created_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case assetPath = "asset_path"
    }

    public var isDone: Bool { status == "done" }
    public var isError: Bool { status == "error" }
    public var isTerminal: Bool { isDone || isError }
}

/// Minimal JSON value union — enough to encode/decode arbitrary param dicts.
public enum RigJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "RigJSONValue: unsupported type"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - os.Logger extension

extension Logger {
    /// Subsystem-scoped logger for the rig bridge.
    public static let rig = Logger(subsystem: "com.ikeru.app", category: "rig")
}
