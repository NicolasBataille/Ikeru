import Foundation

public struct SessionSkillContribution: Sendable, Codable, Equatable {
    public var reading: Int
    public var writing: Int
    public var listening: Int
    public var speaking: Int

    public init(reading: Int, writing: Int, listening: Int, speaking: Int) {
        self.reading = reading
        self.writing = writing
        self.listening = listening
        self.speaking = speaking
    }

    public static let zero = SessionSkillContribution(reading: 0, writing: 0, listening: 0, speaking: 0)

    public var total: Int { reading + writing + listening + speaking }
}
