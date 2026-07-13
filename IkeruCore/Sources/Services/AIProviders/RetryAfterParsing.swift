import Foundation

// MARK: - RetryAfterParsing
//
// Tolerant parsing helpers for the "how long should we back off" signal a
// rate-limited (HTTP 429) provider sends back. Two shapes are supported:
//   1. The standard `Retry-After` HTTP header (integer seconds, or an HTTP-date).
//   2. Gemini's JSON body `error.details[].retryDelay` duration string (e.g. "17s").
// Both parsers are pure and take their inputs as parameters (including "now"
// for date math) so they stay deterministic and unit-testable without the network.
enum RetryAfterParsing {

    /// Parses the `Retry-After` HTTP header value into a `TimeInterval`.
    ///
    /// Supports the two forms defined by RFC 9110 §10.2.3:
    /// - delay-seconds: a non-negative integer, e.g. `"30"` (surrounding
    ///   whitespace is tolerated).
    /// - HTTP-date: an absolute timestamp, e.g. `"Wed, 21 Oct 2026 07:28:00 GMT"`.
    ///   The returned interval is `max(0, date - now)`, clamped to zero for a
    ///   date that is already in the past.
    ///
    /// Returns `nil` when `header` is `nil`, empty, or neither form parses.
    /// - Parameters:
    ///   - header: The raw `Retry-After` header value.
    ///   - now: The reference time used for HTTP-date math. Defaults to `Date()`
    ///     but tests should pass a fixed value for determinism.
    static func parseRetryAfterHeader(_ header: String?, now: Date = Date()) -> TimeInterval? {
        guard let header else { return nil }
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let seconds = TimeInterval(trimmed), seconds >= 0 {
            return seconds
        }

        if let date = httpDateFormatter.date(from: trimmed) {
            return max(0, date.timeIntervalSince(now))
        }

        return nil
    }

    /// Parses Gemini's 429 error body, extracting the `retryDelay` duration
    /// string (e.g. `"17s"`, `"1.5s"`) from `error.details[]` where
    /// `@type` ends in `RetryInfo`. Defensive: any shape mismatch returns `nil`
    /// rather than throwing, since this is a best-effort fallback when the
    /// `Retry-After` header is absent.
    static func parseGeminiRetryDelay(fromBody data: Data) -> TimeInterval? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let details = error["details"] as? [[String: Any]] else {
            return nil
        }

        for detail in details {
            guard let type = detail["@type"] as? String, type.hasSuffix("RetryInfo") else { continue }
            guard let retryDelay = detail["retryDelay"] as? String else { continue }
            if let seconds = parseDurationString(retryDelay) {
                return seconds
            }
        }

        return nil
    }

    /// Parses a Protobuf-style duration string like `"17s"` or `"1.5s"` into
    /// seconds. Returns `nil` for any other shape.
    private static func parseDurationString(_ value: String) -> TimeInterval? {
        guard value.hasSuffix("s") else { return nil }
        let numericPart = value.dropLast()
        guard let seconds = TimeInterval(numericPart), seconds >= 0 else { return nil }
        return seconds
    }

    /// RFC 1123 / HTTP-date formatter (`Wed, 21 Oct 2026 07:28:00 GMT`).
    /// Fixed locale/timezone so parsing is deterministic regardless of the
    /// device's current locale settings.
    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}
