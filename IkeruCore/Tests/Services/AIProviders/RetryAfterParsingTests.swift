import Testing
import Foundation
@testable import IkeruCore

// MARK: - RetryAfterParsingTests
//
// Unit tests for the tolerant `Retry-After` header / Gemini `retryDelay` body
// parsers. Pure functions -- no network, no wall-clock `Date()` calls other
// than the caller-supplied fixed `now` for HTTP-date math, so these stay
// fully deterministic.

@Suite("RetryAfterParsing")
struct RetryAfterParsingTests {

    // MARK: - Header: delay-seconds form

    @Test("Integer seconds header parses to matching TimeInterval")
    func integerSecondsHeader() {
        let result = RetryAfterParsing.parseRetryAfterHeader("30")
        #expect(result == 30)
    }

    @Test("Integer seconds header with surrounding whitespace parses correctly")
    func whitespacePaddedHeader() {
        let result = RetryAfterParsing.parseRetryAfterHeader("  30 ")
        #expect(result == 30)
    }

    @Test("Nil header returns nil")
    func nilHeader() {
        let result = RetryAfterParsing.parseRetryAfterHeader(nil)
        #expect(result == nil)
    }

    @Test("Empty header returns nil")
    func emptyHeader() {
        let result = RetryAfterParsing.parseRetryAfterHeader("")
        #expect(result == nil)
    }

    @Test("Whitespace-only header returns nil")
    func whitespaceOnlyHeader() {
        let result = RetryAfterParsing.parseRetryAfterHeader("   ")
        #expect(result == nil)
    }

    @Test("Garbage header returns nil")
    func garbageHeader() {
        let result = RetryAfterParsing.parseRetryAfterHeader("not-a-number")
        #expect(result == nil)
    }

    @Test("Negative seconds header returns nil")
    func negativeSecondsHeader() {
        let result = RetryAfterParsing.parseRetryAfterHeader("-5")
        #expect(result == nil)
    }

    // A non-finite header ("infinity"/"inf") parses to Double.infinity, which
    // would trap in Duration.seconds(_:) if it reached the cooldown math. The
    // parser must reject it so untrusted upstream input can never crash the app.
    @Test("Infinity header returns nil (never reaches Duration.seconds)", arguments: ["infinity", "inf", "  inf  ", "-inf", "nan"])
    func nonFiniteHeaderReturnsNil(_ header: String) {
        #expect(RetryAfterParsing.parseRetryAfterHeader(header) == nil)
    }

    @Test("Infinity Gemini retryDelay ('infs') returns nil")
    func nonFiniteGeminiRetryDelayReturnsNil() {
        let body = Data("""
        {"error":{"details":[{"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"infs"}]}}
        """.utf8)
        #expect(RetryAfterParsing.parseGeminiRetryDelay(fromBody: body) == nil)
    }

    // MARK: - Header: HTTP-date form

    @Test("HTTP-date header in the future returns the correct positive offset from now")
    func futureHTTPDateHeader() {
        let now = fixedDate(year: 2026, month: 10, day: 21, hour: 7, minute: 27, second: 50)
        let result = RetryAfterParsing.parseRetryAfterHeader(
            "Wed, 21 Oct 2026 07:28:00 GMT",
            now: now
        )
        #expect(result == 10)
    }

    @Test("HTTP-date header in the past clamps to zero")
    func pastHTTPDateHeaderClampsToZero() {
        let now = fixedDate(year: 2026, month: 10, day: 21, hour: 7, minute: 28, second: 0)
        let result = RetryAfterParsing.parseRetryAfterHeader(
            "Wed, 21 Oct 2026 07:27:50 GMT",
            now: now
        )
        #expect(result == 0)
    }

    // MARK: - Gemini body retryDelay

    @Test("Gemini RetryInfo retryDelay '17s' parses to 17 seconds")
    func geminiRetryDelayWholeSeconds() {
        let body = Data("""
        {
          "error": {
            "details": [
              { "@type": "type.googleapis.com/google.rpc.RetryInfo", "retryDelay": "17s" }
            ]
          }
        }
        """.utf8)
        let result = RetryAfterParsing.parseGeminiRetryDelay(fromBody: body)
        #expect(result == 17)
    }

    @Test("Gemini RetryInfo retryDelay '1.5s' parses to 1.5 seconds")
    func geminiRetryDelayFractionalSeconds() {
        let body = Data("""
        {
          "error": {
            "details": [
              { "@type": "type.googleapis.com/google.rpc.RetryInfo", "retryDelay": "1.5s" }
            ]
          }
        }
        """.utf8)
        let result = RetryAfterParsing.parseGeminiRetryDelay(fromBody: body)
        #expect(result == 1.5)
    }

    @Test("Malformed Gemini body returns nil")
    func malformedGeminiBody() {
        let result = RetryAfterParsing.parseGeminiRetryDelay(fromBody: Data("not json".utf8))
        #expect(result == nil)
    }

    @Test("Gemini body missing RetryInfo detail returns nil")
    func geminiBodyMissingRetryInfo() {
        let body = Data("""
        {
          "error": {
            "details": [
              { "@type": "type.googleapis.com/google.rpc.DebugInfo", "detail": "oops" }
            ]
          }
        }
        """.utf8)
        let result = RetryAfterParsing.parseGeminiRetryDelay(fromBody: body)
        #expect(result == nil)
    }

    @Test("Gemini body with no error field returns nil")
    func geminiBodyNoErrorField() {
        let result = RetryAfterParsing.parseGeminiRetryDelay(fromBody: Data("{}".utf8))
        #expect(result == nil)
    }

    // MARK: - Test Helpers

    private func fixedDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = TimeZone(identifier: "GMT")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar.date(from: components)!
    }
}
