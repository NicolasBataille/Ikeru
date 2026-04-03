import Foundation
import IkeruCore
import os

// MARK: - KanjiStudyViewModel

/// ViewModel for the kanji study screen with radical decomposition.
/// Loads radicals and vocabulary from ContentRepository for a given kanji.
@MainActor
@Observable
public final class KanjiStudyViewModel {

    // MARK: - State

    /// The kanji being studied.
    public private(set) var kanji: Kanji

    /// Radical components of the kanji.
    public private(set) var radicals: [Radical] = []

    /// Vocabulary items using this kanji.
    public private(set) var vocabulary: [Vocabulary] = []

    /// Loading state for async content fetch.
    public private(set) var loadingState: LoadingState<Void> = .idle

    // MARK: - Dependencies

    private let contentRepository: ContentRepository

    // MARK: - Init

    /// Creates a view model for studying a kanji character.
    /// - Parameters:
    ///   - kanji: The kanji to study.
    ///   - contentRepository: Repository for fetching content data.
    public init(kanji: Kanji, contentRepository: ContentRepository) {
        self.kanji = kanji
        self.contentRepository = contentRepository
    }

    // MARK: - Loading

    /// Loads radicals and vocabulary for the current kanji.
    public func loadContent() async {
        loadingState = .loading
        Logger.content.info("Loading content for kanji '\(self.kanji.character)'")

        async let radicalsFetch = contentRepository.radicalsForKanji(kanji.character)
        async let vocabularyFetch = contentRepository.vocabularyForKanji(kanji.character)
        let (fetchedRadicals, fetchedVocabulary) = await (radicalsFetch, vocabularyFetch)

        radicals = fetchedRadicals
        vocabulary = fetchedVocabulary
        loadingState = .loaded(())

        if fetchedRadicals.isEmpty && fetchedVocabulary.isEmpty {
            Logger.content.warning("Both radicals and vocabulary empty for '\(self.kanji.character)' — possible load failure")
        } else {
            Logger.content.info("Loaded \(fetchedRadicals.count) radicals and \(fetchedVocabulary.count) vocabulary for '\(self.kanji.character)'")
        }
    }
}
