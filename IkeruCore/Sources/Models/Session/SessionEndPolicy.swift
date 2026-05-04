import Foundation

public enum SessionEndAction: Sendable, Equatable {
    case continueSession
    case completeAfterCurrent
    case completeNow
}

public struct SessionEndPolicy: Sendable, Equatable {
    public let durationBudgetMinutes: Int
    public let queueLength: Int
    public let graceWindowSeconds: Int

    public init(durationBudgetMinutes: Int, queueLength: Int, graceWindowSeconds: Int = 60) {
        self.durationBudgetMinutes = durationBudgetMinutes
        self.queueLength = queueLength
        self.graceWindowSeconds = graceWindowSeconds
    }

    public func evaluate(state: SessionEndState) -> SessionEndAction {
        let queueExhausted = state.completedCount >= queueLength
        let budgetExhausted = state.elapsedSeconds >= durationBudgetMinutes * 60

        if queueExhausted || budgetExhausted {
            return state.activeItemInFlight ? .completeAfterCurrent : .completeNow
        }
        return .continueSession
    }
}
