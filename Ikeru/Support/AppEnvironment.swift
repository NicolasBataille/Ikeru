import Foundation

/// Read-only global environment flags derived from launch arguments.
///
/// All values are computed lazily and cannot be mutated at runtime, so they
/// are safe to read from any thread.
///
/// Used for E2E test fixtures and deterministic rendering — production code
/// should never branch on these in App Store builds (see the
/// `#if IKERU_DEV_TOOLS` guards in `TestFixtures`).
///
/// ## One read point — and a correction worth keeping
///
/// Every launch-flag read in the app funnels through here. `IkeruApp`,
/// `MainTabView` and `HomeView` used to call `CommandLine.arguments` directly
/// while `TestFixtures` went through this type, so "which flags exist" had no
/// single answer. That is the whole justification for the centralization: one
/// place to read, one place to document.
///
/// ⚠️ It is **not** a bug fix, despite an earlier version of this comment (and
/// its commit message) claiming at length that it was. That draft asserted
/// `XCUIApplication.launchArguments` never reach `CommandLine.arguments`, and
/// that this was why the whole UI-test target was inert. **Falsified the same
/// day**, by running the two argument-dependent suites against `dev` — i.e.
/// against the `CommandLine` code — and reading the app's own log: `wipeData
/// flag set`, `Skip onboarding flag set`, `Seeding fixture profile`. All three
/// tests passed. `CommandLine.arguments` receives XCUITest launch arguments
/// perfectly well.
///
/// What produced the false reading: flag-less app launches interleaved in the
/// log with flagged ones. They were attributed to XCUITest; they are much more
/// likely system relaunches (a session leaves a Live Activity running) plus
/// contamination from the manual `simctl launch` runs being used to compare —
/// never reproduced in a clean full-suite run. `ProcessInfo.processInfo
/// .arguments` is kept because it is the documented API for this and the two
/// are equivalent here, not because it fixed anything.
///
/// Recorded rather than quietly deleted: this repo's recurring failure mode is
/// an unmeasured claim propagating until it reads as fact, and this one got as
/// far as a commit message before the measurement caught it.
public enum AppEnvironment {

    /// The launch arguments this process was started with.
    private static var arguments: [String] {
        ProcessInfo.processInfo.arguments
    }

    /// Time-of-day greeting period override parsed from `-mockGreeting=...`.
    /// Returns `nil` when no override is present.
    public static var greetingOverride: GreetingPeriod? {
        guard let raw = stringArg("mockGreeting") else { return nil }
        return GreetingPeriod(rawValue: raw)
    }

    /// Returns the raw value for a `-flag=value` style argument, or `nil`.
    public static func stringArg(_ name: String) -> String? {
        let prefix = "-\(name)="
        guard let arg = arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        return String(arg.dropFirst(prefix.count))
    }

    /// Returns the integer value for a `-flag=N` style argument, or `nil`.
    public static func intArg(_ name: String) -> Int? {
        stringArg(name).flatMap(Int.init)
    }

    /// Returns true when a boolean-style flag (`-flag`) is present.
    ///
    /// Pass the name **without** its leading dash — `hasFlag("skipTour")`.
    public static func hasFlag(_ name: String) -> Bool {
        arguments.contains("-\(name)")
    }
}

/// Time-of-day periods used by the home greeting.
public enum GreetingPeriod: String, Sendable {
    case morning
    case afternoon
    case evening
    case night

    public var phrase: String {
        switch self {
        case .morning:   "Good morning"
        case .afternoon: "Good afternoon"
        case .evening:   "Good evening"
        case .night:     "Good night"
        }
    }
}
