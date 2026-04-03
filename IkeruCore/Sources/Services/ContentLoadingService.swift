import Foundation
import Observation
import os

// MARK: - ContentLoadingService

/// Service that manages progressive content loading from SQLite bundles.
///
/// N5 content is loaded automatically on first launch. Higher levels are
/// triggered when the learner masters 80%+ of the current level's kanji.
/// Loading always happens in the background and never blocks the UI.
///
/// Uses `LoadingState<T>` for tracking load progress — never boolean isLoading flags.
@Observable
@MainActor
public final class ContentLoadingService {

    /// Mastery threshold: fraction of kanji that must be learned before unlocking next level.
    public static let masteryThreshold: Double = 0.80

    /// Current loading state for the active level load operation.
    public private(set) var loadingState: LoadingState<JLPTLevel> = .idle

    /// Set of JLPT levels that have been successfully loaded.
    public private(set) var loadedLevels: Set<JLPTLevel> = []

    /// The base URL where content bundles are stored (e.g., app Resources/ContentBundles/).
    private let bundleDirectoryURL: URL

    /// Cached repository instances per level to avoid reopening SQLite connections.
    private var repositoryCache: [JLPTLevel: ContentRepository] = [:]

    /// Factory for creating ContentRepository instances for each level.
    private let repositoryFactory: @Sendable (URL) -> ContentRepository

    public init(
        bundleDirectoryURL: URL,
        repositoryFactory: @escaping @Sendable (URL) -> ContentRepository = { ContentRepository(bundleURL: $0) }
    ) {
        self.bundleDirectoryURL = bundleDirectoryURL
        self.repositoryFactory = repositoryFactory
    }

    // MARK: - Level Loading

    /// Loads content for the specified JLPT level from its SQLite bundle.
    /// This operation runs in the background and never blocks the UI.
    /// - Parameter level: The JLPT level to load.
    /// - Returns: A ContentRepository for the loaded level, or nil if loading failed.
    @discardableResult
    public func loadLevel(_ level: JLPTLevel) async -> ContentRepository? {
        guard !loadedLevels.contains(level) else {
            Logger.content.debug("Level \(level.rawValue) already loaded, skipping")
            return repositoryForLevel(level)
        }

        loadingState = .loading
        Logger.content.info("Loading content bundle for level \(level.rawValue)")

        let bundleURL = bundleURLForLevel(level)

        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            let errorMessage = "Content bundle not found: \(bundleURL.lastPathComponent)"
            Logger.content.error("\(errorMessage)")
            loadingState = .failed(ContentLoadingError.bundleNotFound(level))
            return nil
        }

        let repository = repositoryFactory(bundleURL)

        // Validate the bundle has content by making a lightweight query
        let testKanji = await repository.kanjiByLevel(level)
        guard !testKanji.isEmpty else {
            Logger.content.error("Content bundle for \(level.rawValue) appears empty")
            loadingState = .failed(ContentLoadingError.emptyBundle(level))
            return nil
        }

        loadedLevels.insert(level)
        loadingState = .loaded(level)
        Logger.content.info(
            "Loaded \(level.rawValue) content: \(testKanji.count) kanji"
        )

        return repository
    }

    // MARK: - Level Status

    /// Check if a given JLPT level has been loaded.
    /// - Parameter level: The JLPT level to check.
    /// - Returns: True if the level's content has been loaded.
    public func isLevelLoaded(_ level: JLPTLevel) -> Bool {
        loadedLevels.contains(level)
    }

    /// Returns all JLPT levels that have content bundles available on disk.
    /// - Returns: Array of available JLPTLevel values.
    public func availableLevels() -> [JLPTLevel] {
        JLPTLevel.allCases.filter { level in
            let url = bundleURLForLevel(level)
            return FileManager.default.fileExists(atPath: url.path)
        }
    }

    // MARK: - Progressive Loading

    /// Checks if the next JLPT level should be unlocked based on mastery of the current level.
    /// The next level is unlocked when the learner has mastered 80%+ of the current level's kanji.
    /// - Parameters:
    ///   - currentLevel: The learner's current JLPT level.
    ///   - masteredKanjiCount: Number of kanji mastered at the current level.
    ///   - totalKanjiCount: Total number of kanji at the current level.
    /// - Returns: The next level to load, or nil if threshold not met or no next level exists.
    public func nextLevelIfReady(
        currentLevel: JLPTLevel,
        masteredKanjiCount: Int,
        totalKanjiCount: Int
    ) -> JLPTLevel? {
        guard totalKanjiCount > 0 else { return nil }

        let masteryRatio = Double(masteredKanjiCount) / Double(totalKanjiCount)
        guard masteryRatio >= Self.masteryThreshold else { return nil }

        guard let nextLevel = nextLevel(after: currentLevel) else { return nil }
        guard !loadedLevels.contains(nextLevel) else { return nil }

        Logger.content.info("Mastery threshold met for \(currentLevel.rawValue): \(masteredKanjiCount)/\(totalKanjiCount) (\(Int(masteryRatio * 100))%). Unlocking \(nextLevel.rawValue)")

        return nextLevel
    }

    // MARK: - Private Helpers

    private func bundleURLForLevel(_ level: JLPTLevel) -> URL {
        bundleDirectoryURL.appendingPathComponent("\(level.rawValue)-content.sqlite")
    }

    private func repositoryForLevel(_ level: JLPTLevel) -> ContentRepository {
        if let cached = repositoryCache[level] {
            return cached
        }
        let bundleURL = bundleURLForLevel(level)
        let repository = repositoryFactory(bundleURL)
        repositoryCache[level] = repository
        return repository
    }

    private func nextLevel(after level: JLPTLevel) -> JLPTLevel? {
        let allLevels = JLPTLevel.allCases.sorted()
        guard let currentIndex = allLevels.firstIndex(of: level),
              currentIndex + 1 < allLevels.count else {
            return nil
        }
        return allLevels[currentIndex + 1]
    }
}

// MARK: - ContentLoadingError

/// Errors that can occur during content loading.
public enum ContentLoadingError: Error, Sendable {
    /// The content bundle file was not found on disk.
    case bundleNotFound(JLPTLevel)

    /// The content bundle exists but contains no data.
    case emptyBundle(JLPTLevel)
}
