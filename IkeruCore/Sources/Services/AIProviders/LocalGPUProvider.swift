import Foundation
import Network
import os

// MARK: - BonjourEndpoint

/// A resolved Bonjour service endpoint.
public struct BonjourEndpoint: Sendable, Equatable {
    public let host: String
    public let port: UInt16

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    /// The base URL for the local GPU server.
    var baseURL: String {
        "http://\(host):\(port)"
    }
}

// MARK: - BonjourDiscovery Protocol

/// Abstraction over Bonjour/mDNS service discovery for testability.
public protocol BonjourDiscovery: Sendable {
    /// The currently discovered endpoint, or nil if no service found.
    var discoveredEndpoint: BonjourEndpoint? { get }

    /// Start browsing for services.
    func startBrowsing()

    /// Stop browsing for services.
    func stopBrowsing()
}

// MARK: - NWBonjourDiscovery

/// Production Bonjour discovery using NWBrowser.
public final class NWBonjourDiscovery: BonjourDiscovery, @unchecked Sendable {

    private let browser: NWBrowser
    private let queue = DispatchQueue(label: "com.ikeru.bonjour-discovery")
    private var _discoveredEndpoint: BonjourEndpoint?
    private let lock = NSLock()

    public static let serviceType = "_ikeruai._tcp"

    public var discoveredEndpoint: BonjourEndpoint? {
        lock.lock()
        defer { lock.unlock() }
        return _discoveredEndpoint
    }

    public init() {
        self.browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: nil),
            using: .tcp
        )
        setupHandlers()
    }

    public func startBrowsing() {
        browser.start(queue: queue)
        Logger.ai.info("LocalGPU Bonjour discovery started for \(Self.serviceType)")
    }

    public func stopBrowsing() {
        browser.cancel()
        Logger.ai.info("LocalGPU Bonjour discovery stopped")
    }

    deinit {
        browser.cancel()
    }

    // MARK: - Private

    private func setupHandlers() {
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Logger.ai.info("Bonjour browser ready")
            case let .failed(error):
                Logger.ai.error("Bonjour browser failed: \(error)")
                self?.clearEndpoint()
            case .cancelled:
                Logger.ai.info("Bonjour browser cancelled")
            default:
                break
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }

            if let firstResult = results.first {
                self.resolveEndpoint(from: firstResult)
            } else {
                self.clearEndpoint()
                Logger.ai.info("LocalGPU service no longer discovered")
            }
        }
    }

    private func resolveEndpoint(from result: NWBrowser.Result) {
        if case let .service(name, _, _, _) = result.endpoint {
            Logger.ai.info("LocalGPU service discovered: \(name)")
        }

        let connection = NWConnection(to: result.endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if let endpoint = connection.currentPath?.remoteEndpoint {
                    self.extractHostPort(from: endpoint)
                }
                connection.cancel()
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func extractHostPort(from endpoint: NWEndpoint) {
        switch endpoint {
        case let .hostPort(host, port):
            let hostString: String
            switch host {
            case let .ipv4(ipv4):
                hostString = "\(ipv4)"
            case let .ipv6(ipv6):
                hostString = "\(ipv6)"
            case let .name(name, _):
                hostString = name
            @unknown default:
                hostString = "\(host)"
            }

            lock.lock()
            _discoveredEndpoint = BonjourEndpoint(host: hostString, port: port.rawValue)
            lock.unlock()

            Logger.ai.info("LocalGPU resolved to \(hostString):\(port.rawValue)")
        default:
            break
        }
    }

    private func clearEndpoint() {
        lock.lock()
        _discoveredEndpoint = nil
        lock.unlock()
    }
}

// MARK: - MockBonjourDiscovery

/// Mock Bonjour discovery for testing.
public final class MockBonjourDiscovery: BonjourDiscovery, @unchecked Sendable {

    private var _endpoint: BonjourEndpoint?
    private let lock = NSLock()

    public var discoveredEndpoint: BonjourEndpoint? {
        lock.lock()
        defer { lock.unlock() }
        return _endpoint
    }

    public init(endpoint: BonjourEndpoint?) {
        self._endpoint = endpoint
    }

    public func startBrowsing() {}
    public func stopBrowsing() {}

    /// Update the mock endpoint (for testing discovery changes).
    public func setEndpoint(_ endpoint: BonjourEndpoint?) {
        lock.lock()
        defer { lock.unlock() }
        _endpoint = endpoint
    }
}

// MARK: - LocalGPUProvider

/// AI provider for the local RTX 5090 GPU server discovered via Bonjour.
public final class LocalGPUProvider: AIProvider, @unchecked Sendable {

    public let name = "LocalGPU"
    public let tier = AITier.localGPU

    private let bonjourDiscovery: any BonjourDiscovery
    private let urlSession: any URLSessionProvider
    private let timeoutSeconds: Double

    public init(
        bonjourDiscovery: any BonjourDiscovery = NWBonjourDiscovery(),
        urlSession: any URLSessionProvider = URLSession.shared,
        timeoutSeconds: Double = 30
    ) {
        self.bonjourDiscovery = bonjourDiscovery
        self.urlSession = urlSession
        self.timeoutSeconds = timeoutSeconds
    }

    public var isAvailable: Bool {
        get async {
            bonjourDiscovery.discoveredEndpoint != nil
        }
    }

    /// Start Bonjour service discovery. Call once at app launch.
    public func startDiscovery() {
        bonjourDiscovery.startBrowsing()
    }

    /// Stop Bonjour service discovery.
    public func stopDiscovery() {
        bonjourDiscovery.stopBrowsing()
    }

    public func generate(prompt: AIPrompt) async throws -> AIResponse {
        let start = ContinuousClock.now

        guard let endpoint = bonjourDiscovery.discoveredEndpoint else {
            Logger.ai.warning("LocalGPU not discovered via Bonjour")
            throw AIError.providerUnavailable(.localGPU)
        }

        // Build request
        let request = try buildRequest(prompt: prompt, endpoint: endpoint)

        // Execute
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch is CancellationError {
            throw AIError.timeout(.localGPU)
        } catch {
            Logger.ai.error("LocalGPU network error: \(error.localizedDescription)")
            throw AIError.networkError(error)
        }

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            Logger.ai.error("LocalGPU HTTP error: \(httpResponse.statusCode)")
            throw AIError.invalidResponse
        }

        // Parse response
        let (content, tokenCount) = try parseResponse(data: data)

        let elapsed = ContinuousClock.now - start
        let latencyMs = Int(elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000)

        Logger.ai.info("LocalGPU generated response in \(latencyMs)ms")

        return AIResponse(
            content: content,
            tier: .localGPU,
            latencyMs: latencyMs,
            tokenCount: tokenCount
        )
    }

    // MARK: - Private Helpers

    private func buildRequest(prompt: AIPrompt, endpoint: BonjourEndpoint) throws -> URLRequest {
        guard let url = URL(string: "\(endpoint.baseURL)/generate") else {
            throw AIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutSeconds

        let body = LocalGPURequestBody(
            systemPrompt: prompt.systemPrompt,
            userMessage: prompt.userMessage,
            context: prompt.context
        )

        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func parseResponse(data: Data) throws -> (String, Int?) {
        let decoded: LocalGPUResponseBody
        do {
            decoded = try JSONDecoder().decode(LocalGPUResponseBody.self, from: data)
        } catch {
            Logger.ai.error("LocalGPU response parsing failed")
            throw AIError.invalidResponse
        }

        return (decoded.text, decoded.tokens)
    }
}

// MARK: - LocalGPU API Data Types

private struct LocalGPURequestBody: Encodable {
    let systemPrompt: String
    let userMessage: String
    let context: [String: String]

    enum CodingKeys: String, CodingKey {
        case systemPrompt = "system_prompt"
        case userMessage = "user_message"
        case context
    }
}

private struct LocalGPUResponseBody: Decodable {
    let text: String
    let tokens: Int?
}
