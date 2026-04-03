import Foundation
import IkeruCore
import os

// MARK: - KanjiStudyViewModel

/// ViewModel for the kanji study screen with radical decomposition.
/// Loads radicals and vocabulary from ContentRepository for a given kanji.
/// Optionally generates AI mnemonics when a MnemonicProvider is injected.
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

    /// AI-generated mnemonic for the current kanji.
    public private(set) var mnemonicText: String?

    /// Loading state for mnemonic generation.
    public private(set) var mnemonicLoadingState: LoadingState<Void> = .idle

    // MARK: - Dependencies

    private let contentRepository: ContentRepository
    private let mnemonicService: (any MnemonicProvider)?

    // MARK: - Init

    /// Creates a view model for studying a kanji character.
    /// - Parameters:
    ///   - kanji: The kanji to study.
    ///   - contentRepository: Repository for fetching content data.
    ///   - mnemonicService: Optional mnemonic provider for AI-generated mnemonics.
    public init(
        kanji: Kanji,
        contentRepository: ContentRepository,
        mnemonicService: (any MnemonicProvider)? = nil
    ) {
        self.kanji = kanji
        self.contentRepository = contentRepository
        self.mnemonicService = mnemonicService
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

        // Load mnemonic after content is available
        await loadMnemonic()
    }

    // MARK: - Mnemonic

    /// Loads or generates a mnemonic for the current kanji.
    public func loadMnemonic() async {
        guard let service = mnemonicService else { return }

        mnemonicLoadingState = .loading
        Logger.ai.info("Loading mnemonic for '\(self.kanji.character)'")

        do {
            let radicalNames = radicals.map(\.meaning)
            let allReadings = kanji.onReadings + kanji.kunReadings
            let result = try await service.generateMnemonic(
                for: kanji.character,
                radicals: radicalNames,
                readings: allReadings
            )
            mnemonicText = result.text
            mnemonicLoadingState = .loaded(())
            Logger.ai.info("Mnemonic loaded for '\(self.kanji.character)' via \(String(describing: result.tier))")
        } catch {
            mnemonicLoadingState = .failed(error)
            Logger.ai.error("Failed to load mnemonic for '\(self.kanji.character)': \(error)")
        }
    }

    /// Clears the cached mnemonic and generates a fresh one.
    public func regenerateMnemonic() async {
        guard let service = mnemonicService else { return }

        mnemonicText = nil
        mnemonicLoadingState = .loading
        Logger.ai.info("Regenerating mnemonic for '\(self.kanji.character)'")

        do {
            try await service.clearCache(for: kanji.character)

            let radicalNames = radicals.map(\.meaning)
            let allReadings = kanji.onReadings + kanji.kunReadings
            let result = try await service.generateMnemonic(
                for: kanji.character,
                radicals: radicalNames,
                readings: allReadings
            )
            mnemonicText = result.text
            mnemonicLoadingState = .loaded(())
            Logger.ai.info("Mnemonic regenerated for '\(self.kanji.character)' via \(String(describing: result.tier))")
        } catch {
            mnemonicLoadingState = .failed(error)
            Logger.ai.error("Failed to regenerate mnemonic for '\(self.kanji.character)': \(error)")
        }
    }
}
