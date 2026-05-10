import Foundation

public struct JLPTReadinessRequirements: Sendable, Equatable {
    public let vocab: Int
    public let kanji: Int
    public let grammar: Int
    public let requiresHiragana: Bool
    public let requiresKatakana: Bool
    public let listenAccuracy: Double
    public let listenRecall: Double?

    public static func requirements(for level: JLPTLevel) -> JLPTReadinessRequirements {
        switch level {
        case .n5:
            return .init(vocab: 100,  kanji: 50,   grammar: 5,
                         requiresHiragana: true,  requiresKatakana: false,
                         listenAccuracy: 0.60, listenRecall: nil)
        case .n4:
            return .init(vocab: 300,  kanji: 150,  grammar: 30,
                         requiresHiragana: true,  requiresKatakana: true,
                         listenAccuracy: 0.60, listenRecall: nil)
        case .n3:
            return .init(vocab: 650,  kanji: 300,  grammar: 100,
                         requiresHiragana: true,  requiresKatakana: true,
                         listenAccuracy: 0.65, listenRecall: 0.30)
        case .n2:
            return .init(vocab: 1000, kanji: 600,  grammar: 150,
                         requiresHiragana: true,  requiresKatakana: true,
                         listenAccuracy: 0.70, listenRecall: 0.50)
        case .n1:
            return .init(vocab: 2000, kanji: 1000, grammar: 250,
                         requiresHiragana: true,  requiresKatakana: true,
                         listenAccuracy: 0.75, listenRecall: 0.70)
        }
    }
}
