import Foundation
import os

// MARK: - KanjiGraphRepository

/// Repository that manages the kanji knowledge graph (DAG).
///
/// Builds an adjacency list from radical-to-kanji edges and provides:
/// - Topological sort (Kahn's algorithm) guaranteeing radicals before composites
/// - Prerequisite radical queries
/// - Dependent kanji queries
/// - Readiness checks for kanji based on learned radicals
///
/// This is a pure logic layer on top of ContentRepository.
public final class KanjiGraphRepository: Sendable {

    /// The background actor performing graph operations.
    private let actor: KanjiGraphActor

    /// Creates a KanjiGraphRepository from radical-to-kanji edges.
    /// - Parameters:
    ///   - edges: Array of KanjiRadicalEdge defining the DAG.
    ///   - radicals: Dictionary of radical character to Radical struct.
    ///   - kanjiMap: Dictionary of kanji character to Kanji struct.
    public init(
        edges: [KanjiRadicalEdge],
        radicals: [String: Radical],
        kanjiMap: [String: Kanji]
    ) {
        self.actor = KanjiGraphActor(
            edges: edges,
            radicals: radicals,
            kanjiMap: kanjiMap
        )
    }

    /// Returns kanji characters in topological (dependency) order.
    /// Radicals with no prerequisites appear first; composite kanji appear after their components.
    /// - Returns: Array of kanji character strings in learning order.
    public func topologicalSort() async -> [String] {
        await actor.topologicalSort()
    }

    /// Returns the radicals that must be learned before a given kanji.
    /// - Parameter kanji: The kanji character to look up.
    /// - Returns: Array of Radical structs that are prerequisites.
    public func prerequisiteRadicals(for kanji: String) async -> [Radical] {
        await actor.prerequisiteRadicals(for: kanji)
    }

    /// Returns kanji that depend on (contain) a given radical.
    /// - Parameter radical: The radical character to look up.
    /// - Returns: Array of Kanji structs that use this radical.
    public func dependentKanji(of radical: String) async -> [Kanji] {
        await actor.dependentKanji(of: radical)
    }

    /// Checks whether a kanji is ready to learn based on the set of learned radicals.
    /// A kanji is ready if all its prerequisite radicals have been learned.
    /// - Parameters:
    ///   - kanji: The kanji character to check.
    ///   - learnedRadicals: Set of radical characters the learner has mastered.
    /// - Returns: True if all prerequisites are met.
    public func isReady(kanji: String, learnedRadicals: Set<String>) async -> Bool {
        await actor.isReady(kanji: kanji, learnedRadicals: learnedRadicals)
    }
}

// MARK: - KanjiGraphActor

/// Actor that builds and queries the kanji knowledge graph.
/// Uses Kahn's algorithm for topological sort with cycle detection.
actor KanjiGraphActor {

    /// Adjacency list: radical -> [kanji that use this radical]
    private let adjacencyList: [String: [String]]

    /// Reverse adjacency: kanji -> [radicals it requires]
    private let prerequisites: [String: [String]]

    /// All unique nodes in the graph
    private let allNodes: Set<String>

    /// Radical lookup dictionary
    private let radicals: [String: Radical]

    /// Kanji lookup dictionary
    private let kanjiMap: [String: Kanji]

    /// Cached topological sort result
    private var cachedSort: [String]?

    init(
        edges: [KanjiRadicalEdge],
        radicals: [String: Radical],
        kanjiMap: [String: Kanji]
    ) {
        var adj: [String: [String]] = [:]
        var prereqs: [String: [String]] = [:]
        var nodes: Set<String> = []

        for edge in edges {
            adj[edge.radicalCharacter, default: []].append(edge.kanjiCharacter)
            prereqs[edge.kanjiCharacter, default: []].append(edge.radicalCharacter)
            nodes.insert(edge.radicalCharacter)
            nodes.insert(edge.kanjiCharacter)
        }

        // Also include isolated kanji/radicals from the maps
        for key in kanjiMap.keys {
            nodes.insert(key)
        }
        for key in radicals.keys {
            nodes.insert(key)
        }

        self.adjacencyList = adj
        self.prerequisites = prereqs
        self.allNodes = nodes
        self.radicals = radicals
        self.kanjiMap = kanjiMap
    }

    // MARK: - Topological Sort (Kahn's Algorithm)

    func topologicalSort() -> [String] {
        if let cachedSort {
            return cachedSort
        }

        // Compute in-degree for each node
        var inDegree: [String: Int] = [:]
        for node in allNodes {
            inDegree[node] = 0
        }
        for (_, dependents) in adjacencyList {
            for dependent in dependents {
                inDegree[dependent, default: 0] += 1
            }
        }

        // Enqueue all nodes with in-degree 0 (sorted for determinism)
        var queue: [String] = inDegree
            .filter { $0.value == 0 }
            .map(\.key)
            .sorted()

        var result: [String] = []
        var processedCount = 0

        while !queue.isEmpty {
            let node = queue.removeFirst()
            result.append(node)
            processedCount += 1

            // Decrement in-degree of dependents
            if let dependents = adjacencyList[node] {
                for dependent in dependents {
                    inDegree[dependent, default: 0] -= 1
                    if inDegree[dependent] == 0 {
                        queue.append(dependent)
                    }
                }
                // Sort queue for deterministic output
                queue.sort()
            }
        }

        // Cycle detection: if unprocessed nodes remain, a cycle exists
        let totalNodes = allNodes.count
        if processedCount < totalNodes {
            let cycleMembers = allNodes.filter { (inDegree[$0] ?? 0) > 0 }
            Logger.content.error("Cycle detected in kanji graph: \(cycleMembers.count) nodes in cycle. Excluding cycle members from topological ordering.")
            // Do NOT include cycle members in result — they are excluded
        }

        cachedSort = result
        Logger.content.debug("Topological sort complete: \(result.count) nodes ordered")
        return result
    }

    // MARK: - Prerequisite Queries

    func prerequisiteRadicals(for kanji: String) -> [Radical] {
        guard let radicalChars = prerequisites[kanji] else { return [] }
        return radicalChars.compactMap { radicals[$0] }
    }

    func dependentKanji(of radical: String) -> [Kanji] {
        guard let kanjiChars = adjacencyList[radical] else { return [] }
        return kanjiChars.compactMap { kanjiMap[$0] }
    }

    func isReady(kanji: String, learnedRadicals: Set<String>) -> Bool {
        guard let required = prerequisites[kanji] else {
            // No prerequisites — always ready
            return true
        }
        return required.allSatisfy { learnedRadicals.contains($0) }
    }
}
