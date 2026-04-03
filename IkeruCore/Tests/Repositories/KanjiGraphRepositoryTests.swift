import Testing
import Foundation
@testable import IkeruCore

// MARK: - KanjiGraphRepository Tests

@Suite("KanjiGraphRepository")
struct KanjiGraphRepositoryTests {

    // MARK: - Test Data Helpers

    /// Creates a Radical with minimal required fields.
    private func makeRadical(_ character: String, meaning: String = "meaning", strokeCount: Int = 1) -> Radical {
        Radical(character: character, meaning: meaning, strokeCount: strokeCount)
    }

    /// Creates a Kanji with minimal required fields.
    private func makeKanji(
        _ character: String,
        radicals: [String] = [],
        meanings: [String] = ["meaning"],
        jlptLevel: JLPTLevel = .n5
    ) -> Kanji {
        Kanji(
            character: character,
            radicals: radicals,
            onReadings: [],
            kunReadings: [],
            meanings: meanings,
            jlptLevel: jlptLevel,
            strokeCount: 1,
            strokeOrderSVGRef: nil
        )
    }

    /// Creates a KanjiGraphRepository from a concise edge description.
    /// Each tuple is (radicalCharacter, kanjiCharacter).
    private func makeRepository(
        edgePairs: [(String, String)],
        radicals: [Radical] = [],
        kanji: [Kanji] = []
    ) -> KanjiGraphRepository {
        let edges = edgePairs.map { KanjiRadicalEdge(radicalCharacter: $0.0, kanjiCharacter: $0.1) }
        let radicalMap = Dictionary(uniqueKeysWithValues: radicals.map { ($0.character, $0) })
        let kanjiMap = Dictionary(uniqueKeysWithValues: kanji.map { ($0.character, $0) })
        return KanjiGraphRepository(edges: edges, radicals: radicalMap, kanjiMap: kanjiMap)
    }

    // MARK: - Topological Sort Tests

    @Test("Topological sort of linear chain preserves dependency order")
    func topologicalSortLinearChain() async {
        // Graph: R1 -> K1 -> K2 (R1 is radical for K1, K1 is radical for K2)
        let r1 = makeRadical("R1")
        let k1Radical = makeRadical("K1")
        let k1 = makeKanji("K1", radicals: ["R1"])
        let k2 = makeKanji("K2", radicals: ["K1"])

        let repo = makeRepository(
            edgePairs: [("R1", "K1"), ("K1", "K2")],
            radicals: [r1, k1Radical],
            kanji: [k1, k2]
        )

        let sorted = await repo.topologicalSort()

        let indexR1 = sorted.firstIndex(of: "R1")
        let indexK1 = sorted.firstIndex(of: "K1")
        let indexK2 = sorted.firstIndex(of: "K2")

        #expect(indexR1 != nil)
        #expect(indexK1 != nil)
        #expect(indexK2 != nil)

        if let iR1 = indexR1, let iK1 = indexK1, let iK2 = indexK2 {
            #expect(iR1 < iK1)
            #expect(iK1 < iK2)
        }
    }

    @Test("Topological sort of diamond shape places roots before dependent")
    func topologicalSortDiamond() async {
        // Graph: R1 -> K1, R2 -> K1 (K1 depends on both R1 and R2)
        let r1 = makeRadical("R1")
        let r2 = makeRadical("R2")
        let k1 = makeKanji("K1", radicals: ["R1", "R2"])

        let repo = makeRepository(
            edgePairs: [("R1", "K1"), ("R2", "K1")],
            radicals: [r1, r2],
            kanji: [k1]
        )

        let sorted = await repo.topologicalSort()

        let indexR1 = sorted.firstIndex(of: "R1")
        let indexR2 = sorted.firstIndex(of: "R2")
        let indexK1 = sorted.firstIndex(of: "K1")

        #expect(indexR1 != nil)
        #expect(indexR2 != nil)
        #expect(indexK1 != nil)

        if let iR1 = indexR1, let iR2 = indexR2, let iK1 = indexK1 {
            #expect(iR1 < iK1)
            #expect(iR2 < iK1)
        }
    }

    @Test("Topological sort of multiple independent subgraphs includes all nodes")
    func topologicalSortMultipleRoots() async {
        // Two independent subgraphs: R1 -> K1, R2 -> K2
        let r1 = makeRadical("R1")
        let r2 = makeRadical("R2")
        let k1 = makeKanji("K1", radicals: ["R1"])
        let k2 = makeKanji("K2", radicals: ["R2"])

        let repo = makeRepository(
            edgePairs: [("R1", "K1"), ("R2", "K2")],
            radicals: [r1, r2],
            kanji: [k1, k2]
        )

        let sorted = await repo.topologicalSort()

        #expect(sorted.contains("R1"))
        #expect(sorted.contains("R2"))
        #expect(sorted.contains("K1"))
        #expect(sorted.contains("K2"))
        #expect(sorted.count == 4)

        // Each radical appears before its kanji
        if let iR1 = sorted.firstIndex(of: "R1"), let iK1 = sorted.firstIndex(of: "K1") {
            #expect(iR1 < iK1)
        }
        if let iR2 = sorted.firstIndex(of: "R2"), let iK2 = sorted.firstIndex(of: "K2") {
            #expect(iR2 < iK2)
        }
    }

    @Test("Topological sort of empty graph returns empty array")
    func topologicalSortEmpty() async {
        let repo = makeRepository(edgePairs: [])

        let sorted = await repo.topologicalSort()

        #expect(sorted.isEmpty)
    }

    @Test("Topological sort of single node returns that node")
    func topologicalSortSingleNode() async {
        let r1 = makeRadical("R1")

        let repo = makeRepository(
            edgePairs: [],
            radicals: [r1]
        )

        let sorted = await repo.topologicalSort()

        #expect(sorted == ["R1"])
    }

    @Test("Topological sort is deterministic across multiple calls")
    func topologicalSortDeterministic() async {
        // Build a graph with multiple valid orderings to test determinism
        let r1 = makeRadical("R1")
        let r2 = makeRadical("R2")
        let r3 = makeRadical("R3")
        let k1 = makeKanji("K1", radicals: ["R1", "R2", "R3"])

        let repo = makeRepository(
            edgePairs: [("R1", "K1"), ("R2", "K1"), ("R3", "K1")],
            radicals: [r1, r2, r3],
            kanji: [k1]
        )

        let first = await repo.topologicalSort()
        let second = await repo.topologicalSort()
        let third = await repo.topologicalSort()

        #expect(first == second)
        #expect(second == third)
    }

    // MARK: - Cycle Detection Tests

    @Test("Cycle between two nodes excludes cycle members without crashing")
    func cycleSimple() async {
        // A -> B and B -> A creates a cycle; both should be excluded
        let repo = makeRepository(
            edgePairs: [("A", "B"), ("B", "A")],
            radicals: [makeRadical("A"), makeRadical("B")],
            kanji: [makeKanji("A"), makeKanji("B")]
        )

        let sorted = await repo.topologicalSort()

        #expect(!sorted.contains("A"))
        #expect(!sorted.contains("B"))
    }

    @Test("Cycle in subgraph does not affect non-cycle members")
    func cycleInSubgraph() async {
        // R1 -> K1 (valid), C1 -> C2 -> C1 (cycle)
        let r1 = makeRadical("R1")
        let k1 = makeKanji("K1", radicals: ["R1"])

        let repo = makeRepository(
            edgePairs: [("R1", "K1"), ("C1", "C2"), ("C2", "C1")],
            radicals: [r1, makeRadical("C1"), makeRadical("C2")],
            kanji: [k1, makeKanji("C1"), makeKanji("C2")]
        )

        let sorted = await repo.topologicalSort()

        // R1 and K1 should still be present and ordered
        #expect(sorted.contains("R1"))
        #expect(sorted.contains("K1"))

        if let iR1 = sorted.firstIndex(of: "R1"), let iK1 = sorted.firstIndex(of: "K1") {
            #expect(iR1 < iK1)
        }

        // Cycle members excluded
        #expect(!sorted.contains("C1"))
        #expect(!sorted.contains("C2"))
    }

    // MARK: - Prerequisite Queries Tests

    @Test("prerequisiteRadicals returns correct radicals for a kanji")
    func prerequisiteRadicalsFound() async {
        let r1 = makeRadical("R1", meaning: "fire")
        let r2 = makeRadical("R2", meaning: "water")
        let k1 = makeKanji("K1", radicals: ["R1", "R2"])

        let repo = makeRepository(
            edgePairs: [("R1", "K1"), ("R2", "K1")],
            radicals: [r1, r2],
            kanji: [k1]
        )

        let prereqs = await repo.prerequisiteRadicals(for: "K1")

        let characters = prereqs.map(\.character)
        #expect(characters.contains("R1"))
        #expect(characters.contains("R2"))
        #expect(prereqs.count == 2)
    }

    @Test("prerequisiteRadicals returns empty for unknown kanji")
    func prerequisiteRadicalsUnknown() async {
        let repo = makeRepository(
            edgePairs: [("R1", "K1")],
            radicals: [makeRadical("R1")],
            kanji: [makeKanji("K1")]
        )

        let prereqs = await repo.prerequisiteRadicals(for: "UNKNOWN")

        #expect(prereqs.isEmpty)
    }

    @Test("prerequisiteRadicals returns empty for node with no prerequisites")
    func prerequisiteRadicalsNone() async {
        let r1 = makeRadical("R1")

        let repo = makeRepository(
            edgePairs: [("R1", "K1")],
            radicals: [r1],
            kanji: [makeKanji("K1")]
        )

        // R1 is a root radical with no prerequisites
        let prereqs = await repo.prerequisiteRadicals(for: "R1")

        #expect(prereqs.isEmpty)
    }

    // MARK: - Dependent Kanji Tests

    @Test("dependentKanji returns kanji that use a radical")
    func dependentKanjiFound() async {
        let r1 = makeRadical("R1")
        let k1 = makeKanji("K1", radicals: ["R1"])
        let k2 = makeKanji("K2", radicals: ["R1"])

        let repo = makeRepository(
            edgePairs: [("R1", "K1"), ("R1", "K2")],
            radicals: [r1],
            kanji: [k1, k2]
        )

        let dependents = await repo.dependentKanji(of: "R1")

        let characters = dependents.map(\.character)
        #expect(characters.contains("K1"))
        #expect(characters.contains("K2"))
        #expect(dependents.count == 2)
    }

    @Test("dependentKanji returns empty for unknown radical")
    func dependentKanjiUnknown() async {
        let repo = makeRepository(
            edgePairs: [("R1", "K1")],
            radicals: [makeRadical("R1")],
            kanji: [makeKanji("K1")]
        )

        let dependents = await repo.dependentKanji(of: "UNKNOWN")

        #expect(dependents.isEmpty)
    }

    // MARK: - isReady Tests

    @Test("isReady returns true when all prerequisite radicals are learned")
    func isReadyAllLearned() async {
        let r1 = makeRadical("R1")
        let r2 = makeRadical("R2")
        let k1 = makeKanji("K1", radicals: ["R1", "R2"])

        let repo = makeRepository(
            edgePairs: [("R1", "K1"), ("R2", "K1")],
            radicals: [r1, r2],
            kanji: [k1]
        )

        let ready = await repo.isReady(kanji: "K1", learnedRadicals: ["R1", "R2"])

        #expect(ready == true)
    }

    @Test("isReady returns false when some prerequisite radicals are missing")
    func isReadyMissingPrereqs() async {
        let r1 = makeRadical("R1")
        let r2 = makeRadical("R2")
        let k1 = makeKanji("K1", radicals: ["R1", "R2"])

        let repo = makeRepository(
            edgePairs: [("R1", "K1"), ("R2", "K1")],
            radicals: [r1, r2],
            kanji: [k1]
        )

        let ready = await repo.isReady(kanji: "K1", learnedRadicals: ["R1"])

        #expect(ready == false)
    }

    @Test("isReady returns true for kanji with no prerequisites")
    func isReadyNoPrereqs() async {
        let k1 = makeKanji("K1")

        let repo = makeRepository(
            edgePairs: [],
            radicals: [],
            kanji: [k1]
        )

        let ready = await repo.isReady(kanji: "K1", learnedRadicals: [])

        #expect(ready == true)
    }
}
