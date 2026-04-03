import Foundation

/// JLPT (Japanese Language Proficiency Test) level classification.
/// Ordered from easiest (N5) to hardest (N1).
/// Comparable conformance ensures N5 < N4 < N3 < N2 < N1.
public enum JLPTLevel: String, Codable, CaseIterable, Sendable, Identifiable, Comparable {
    case n5
    case n4
    case n3
    case n2
    case n1

    public var id: String { rawValue }

    /// Numeric sort key: higher number = harder level.
    private var sortOrder: Int {
        switch self {
        case .n5: 0
        case .n4: 1
        case .n3: 2
        case .n2: 3
        case .n1: 4
        }
    }

    public static func < (lhs: JLPTLevel, rhs: JLPTLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    /// Numeric representation (5 for N5, 1 for N1).
    public var number: Int {
        switch self {
        case .n5: 5
        case .n4: 4
        case .n3: 3
        case .n2: 2
        case .n1: 1
        }
    }

    /// Display label (e.g., "N5"). Alias for displayName for backward compatibility.
    public var displayLabel: String {
        "N\(number)"
    }

    /// Human-readable display name (e.g., "N5").
    public var displayName: String {
        rawValue.uppercased()
    }
}
