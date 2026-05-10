import Foundation

/// Read-only global environment flags derived from launch arguments.
///
/// All values are computed lazily from `CommandLine.arguments` so they are
/// safe to read from any thread, and they cannot be mutated at runtime.
///
/// Used for E2E test fixtures and deterministic rendering — production code
/// should never branch on these in App Store builds (see `#if DEBUG` guards
/// in `TestFixtures`).
public enum AppEnvironment {

    /// Time-of-day greeting period override parsed from `-mockGreeting=...`.
    /// Returns `nil` when no override is present.
    public static var greetingOverride: GreetingPeriod? {
        guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("-mockGreeting=") }) else {
            return nil
        }
        let raw = String(arg.dropFirst("-mockGreeting=".count))
        return GreetingPeriod(rawValue: raw)
    }

    /// Returns the integer value for a `-flag=N` style argument, or `nil`.
    public static func intArg(_ name: String) -> Int? {
        let prefix = "-\(name)="
        guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        return Int(arg.dropFirst(prefix.count))
    }

    /// Returns true when a boolean-style flag (`-flag`) is present.
    public static func hasFlag(_ name: String) -> Bool {
        CommandLine.arguments.contains("-\(name)")
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
