import Foundation

public struct SessionEndState: Sendable, Equatable {
    public let elapsedSeconds: Int
    public let completedCount: Int
    public let activeItemInFlight: Bool

    public init(elapsedSeconds: Int, completedCount: Int, activeItemInFlight: Bool) {
        self.elapsedSeconds = elapsedSeconds
        self.completedCount = completedCount
        self.activeItemInFlight = activeItemInFlight
    }
}
