import Foundation
import Network
import os

// MARK: - NetworkChecker Protocol

/// Abstraction over network reachability for testability.
public protocol NetworkChecker: Sendable {
    var isOnline: Bool { get }
}

// MARK: - URLSessionProvider Protocol

/// Abstraction over URLSession for testability.
public protocol URLSessionProvider: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

// MARK: - URLSession + URLSessionProvider

extension URLSession: URLSessionProvider {}

// MARK: - NWPathNetworkChecker

/// Production network checker using NWPathMonitor.
public final class NWPathNetworkChecker: NetworkChecker, @unchecked Sendable {

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.ikeru.network-monitor")
    private var _isOnline: Bool = false
    private let lock = NSLock()

    public var isOnline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isOnline
    }

    public init() {
        self.monitor = NWPathMonitor()
        self.monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self._isOnline = path.status == .satisfied
            self.lock.unlock()
            Logger.ai.info("Network status changed: \(path.status == .satisfied ? "online" : "offline")")
        }
        self.monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

// MARK: - MockNetworkChecker

/// Mock network checker for testing.
public final class MockNetworkChecker: NetworkChecker, @unchecked Sendable {

    private var _isOnline: Bool
    private let lock = NSLock()

    public var isOnline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isOnline
    }

    public init(online: Bool) {
        self._isOnline = online
    }

    /// Update the mock online status (for testing network transitions).
    public func setOnline(_ online: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _isOnline = online
    }
}

// MARK: - MockURLSessionProvider

/// Mock URL session for testing API providers.
public final class MockURLSessionProvider: URLSessionProvider, @unchecked Sendable {

    private let responseData: Data
    private let statusCode: Int
    private let error: (any Error)?
    private let delay: Duration?

    public init(
        responseData: Data = Data(),
        statusCode: Int = 200,
        error: (any Error)? = nil,
        delay: Duration? = nil
    ) {
        self.responseData = responseData
        self.statusCode = statusCode
        self.error = error
        self.delay = delay
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let delay {
            try await Task.sleep(for: delay)
        }

        if let error {
            throw error
        }

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!

        return (responseData, response)
    }
}
