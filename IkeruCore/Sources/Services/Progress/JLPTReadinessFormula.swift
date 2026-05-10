import Foundation

public enum JLPTReadinessFormula {

    public static func compute(snapshot: LearnerSnapshot) -> JLPTReadinessReport {
        let perLevel = JLPTLevel.allCases.reduce(into: [JLPTLevel: Double]()) { acc, level in
            acc[level] = readinessForLevel(level, snapshot: snapshot)
        }
        let bestFit = JLPTLevel.allCases.reversed()
            .first { (perLevel[$0] ?? 0) >= JLPTReadinessReport.bestFitThreshold }
            ?? .n5
        return JLPTReadinessReport(
            perLevel: perLevel,
            bestFit: bestFit,
            bestFitConfidence: perLevel[bestFit] ?? 0
        )
    }

    private static func readinessForLevel(
        _ level: JLPTLevel,
        snapshot: LearnerSnapshot
    ) -> Double {
        let req = JLPTReadinessRequirements.requirements(for: level)

        if req.requiresHiragana && !snapshot.hiraganaMastered { return 0 }
        if req.requiresKatakana && !snapshot.katakanaMastered { return 0 }

        let vocab   = ratio(snapshot.vocabularyMasteredAtOrBelow[level] ?? 0,        req.vocab)
        let kanji   = ratio(snapshot.kanjiMasteredAtOrBelow[level] ?? 0,             req.kanji)
        let grammar = ratio(snapshot.grammarPointsMasteredAtOrBelow[level] ?? 0,     req.grammar)
        let listen  = ratioDouble(snapshot.listeningAccuracyLast30, req.listenAccuracy)
        let recall  = req.listenRecall.map {
            ratioDouble(snapshot.listeningRecallLast30Days, $0)
        } ?? 1.0

        return [vocab, kanji, grammar, listen, recall].min() ?? 0
    }

    private static func ratio(_ value: Int, _ required: Int) -> Double {
        guard required > 0 else { return 1.0 }
        return min(1.0, Double(value) / Double(required))
    }

    private static func ratioDouble(_ value: Double, _ required: Double) -> Double {
        guard required > 0 else { return 1.0 }
        return min(1.0, value / required)
    }
}
