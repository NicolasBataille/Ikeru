import Foundation
import IkeruCore
import PostHog
import os

// MARK: - PostHogAnalyticsService

/// Live `AnalyticsService` backed by the PostHog Swift SDK.
///
/// Configuration is read from `Info.plist` at startup:
/// - `PostHogAPIKey`  → injected from the `POSTHOG_API_KEY` build setting.
/// - `PostHogHost`    → optional override; defaults to the EU cloud host
///   (`https://eu.i.posthog.com`) which keeps data inside the EU and avoids
///   adding a non-EU sub-processor to the privacy policy.
///
/// When the API key is missing or blank (e.g. on a contributor's machine that
/// hasn't set up secrets) the bootstrap returns `nil` and the app falls back
/// to `NoopAnalyticsService` — there is no runtime crash and no events are
/// queued silently.
@MainActor
final class PostHogAnalyticsService: AnalyticsService {

    private let posthog: PostHogSDK

    /// Builds the live service from `Info.plist`, or `nil` when the API key
    /// is absent. The caller is expected to register the result via
    /// `Analytics.register(_:)`.
    static func bootstrap(optedOut: Bool) -> PostHogAnalyticsService? {
        let info = Bundle.main.infoDictionary
        let rawKey = (info?["PostHogAPIKey"] as? String) ?? ""
        let apiKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !apiKey.isEmpty, apiKey != "$(POSTHOG_API_KEY)" else {
            Logger.analytics.notice("PostHog disabled — PostHogAPIKey missing in Info.plist")
            return nil
        }

        let host = (info?["PostHogHost"] as? String).flatMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } ?? "https://eu.i.posthog.com"

        let config = PostHogConfig(apiKey: apiKey, host: host)
        // Auto-captured lifecycle events ($app_opened, $app_backgrounded, etc.)
        // — these don't count against the free MTU quota beyond the usual
        // event budget and they give us crash-free engagement metrics for
        // free.
        config.captureApplicationLifecycleEvents = true
        // Screen views off — SwiftUI generates noisy names like `_TtGC7…`.
        // We'll capture readable screens manually if and when we need them.
        config.captureScreenViews = false
        // Session replay is a heavy quota item (5K / month on free) and would
        // need careful masking of card content for privacy. Off until asked.
        config.sessionReplay = false
        // Only create a person profile when we explicitly identify — avoids
        // burning a Monthly Tracked User on every anonymous launch.
        config.personProfiles = .identifiedOnly

        PostHogSDK.shared.setup(config)

        if optedOut {
            PostHogSDK.shared.optOut()
        } else {
            PostHogSDK.shared.optIn()
        }

        Logger.analytics.info(
            "PostHog initialized host=\(host, privacy: .public) optedOut=\(optedOut, privacy: .public)"
        )

        return PostHogAnalyticsService(posthog: PostHogSDK.shared)
    }

    private init(posthog: PostHogSDK) {
        self.posthog = posthog
    }

    // MARK: AnalyticsService

    func identify(distinctId: String, properties: AnalyticsProperties) {
        posthog.identify(distinctId, userProperties: properties.toAnyDict())
    }

    func track(_ event: String, properties: AnalyticsProperties) {
        posthog.capture(event, properties: properties.toAnyDict())
    }

    func setOptOut(_ optOut: Bool) {
        if optOut {
            posthog.optOut()
        } else {
            posthog.optIn()
        }
        Logger.analytics.info("analytics.optOut=\(optOut, privacy: .public)")
    }

    func reset() {
        posthog.reset()
    }
}

private extension AnalyticsProperties {
    /// Adapts the typed property bag to the `[String: Any]` shape expected by
    /// the PostHog SDK without leaking that detail to call sites.
    func toAnyDict() -> [String: Any] {
        mapValues { $0.anyValue }
    }
}
