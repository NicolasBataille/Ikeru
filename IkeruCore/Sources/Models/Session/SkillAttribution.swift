import Foundation

public struct SkillSplit: Sendable, Equatable {
    public let reading: Double
    public let writing: Double
    public let listening: Double
    public let speaking: Double

    public init(reading: Double, writing: Double, listening: Double, speaking: Double) {
        self.reading = reading
        self.writing = writing
        self.listening = listening
        self.speaking = speaking
    }

    public func sum() -> Double { reading + writing + listening + speaking }
}
