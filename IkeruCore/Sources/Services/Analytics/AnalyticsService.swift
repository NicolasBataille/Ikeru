import Foundation
import os

// MARK: - AnalyticsValue

/// A typed wrapper for property values sent to the analytics backend.
/// Restricting to a closed set keeps the protocol `Sendable` while still
/// preserving numeric types so PostHog can aggregate (sum / avg) them in the
/// dashboard — stringifying everything would lose that.
public enum AnalyticsValue: Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    /// Unwraps to the raw `Any` value expected by the PostHog SDK.
    public var anyValue: Any {
        switch self {
        case .string(let v): return v
        case .int(let v):    return v
        case .double(let v): return v
        case .bool(let v):   return v
        }
    }
}

public typealias AnalyticsProperties = [String: AnalyticsValue]

// MARK: - AnalyticsService

/// Backend-agnostic analytics surface. All call sites talk to this protocol —
/// the only file that imports `PostHog` is `PostHogAnalyticsService`. Tests
/// and previews use `NoopAnalyticsService`.
@MainActor
public protocol AnalyticsService: AnyObject {

    /// Associates the current anonymous device with a stable user identifier
    /// (we use `UserProfile.id`). Idempotent — safe to call every launch.
    func identify(distinctId: String, properties: AnalyticsProperties)

    /// Records an event with optional structured properties.
    func track(_ event: String, properties: AnalyticsProperties)

    /// Suspends or resumes event capture. When opted-out, the backend buffers
    /// nothing — events are dropped at the SDK boundary.
    func setOptOut(_ optOut: Bool)

    /// Forgets the current `distinctId` and starts a fresh anonymous session.
    /// Called when the active profile is deleted or switched.
    func reset()
}

public extension AnalyticsService {
    func track(_ event: String) { track(event, properties: [:]) }
    func identify(distinctId: String) { identify(distinctId: distinctId, properties: [:]) }
}

// MARK: - NoopAnalyticsService

/// Default implementation used in tests, previews, and whenever the PostHog
/// API key is missing. Logs to OS Logger so developers can still see what
/// would have been sent.
@MainActor
public final class NoopAnalyticsService: AnalyticsService {
    public init() {}

    public func identify(distinctId: String, properties: AnalyticsProperties) {
        Logger.analytics.debug("noop.identify id=\(distinctId, privacy: .public)")
    }

    public func track(_ event: String, properties: AnalyticsProperties) {
        Logger.analytics.debug("noop.track \(event, privacy: .public)")
    }

    public func setOptOut(_ optOut: Bool) {
        Logger.analytics.debug("noop.setOptOut \(optOut, privacy: .public)")
    }

    public func reset() {
        Logger.analytics.debug("noop.reset")
    }
}

// MARK: - Global access

/// Process-wide singleton used by call sites that don't have an injected
/// service handy (view models, lifecycle hooks). The main app swaps this for
/// the live PostHog instance at startup; everywhere else gets the noop.
@MainActor
public enum Analytics {
    public private(set) static var shared: any AnalyticsService = NoopAnalyticsService()

    /// Installs the live analytics backend. Call once, from `IkeruApp.init`.
    public static func register(_ service: any AnalyticsService) {
        shared = service
    }
}
