import Foundation

/// A single day in a review forecast, showing expected review counts.
public struct ForecastDay: Sendable, Equatable, Identifiable {
    public var id: Date { date }

    /// The date this forecast applies to.
    public let date: Date

    /// Number of cards due for review on this date.
    public let dueCount: Int

    /// Number of new cards scheduled for this date.
    public let newCount: Int

    public init(date: Date, dueCount: Int, newCount: Int) {
        self.date = date
        self.dueCount = dueCount
        self.newCount = newCount
    }
}
