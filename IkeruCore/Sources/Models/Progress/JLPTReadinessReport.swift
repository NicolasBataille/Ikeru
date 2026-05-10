import Foundation

public struct JLPTReadinessReport: Sendable, Equatable {
    public let perLevel: [JLPTLevel: Double]
    public let bestFit: JLPTLevel
    public let bestFitConfidence: Double

    public static let bestFitThreshold: Double = 0.85

    public init(perLevel: [JLPTLevel: Double], bestFit: JLPTLevel, bestFitConfidence: Double) {
        self.perLevel = perLevel
        self.bestFit = bestFit
        self.bestFitConfidence = bestFitConfidence
    }
}
