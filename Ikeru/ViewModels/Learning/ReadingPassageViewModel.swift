import SwiftUI
import SwiftData
import IkeruCore
import os

// MARK: - ReadingPassageViewModel

@MainActor
@Observable
public final class ReadingPassageViewModel {

    // MARK: - Published State

    /// The current reading passage being displayed.
    public private(set) var currentPassage: ReadingPassage?

    /// The word currently selected by the learner (for definition popup).
    public private(set) var selectedWord: PassageWord?

    /// Whether a passage is currently loading.
    public private(set) var isLoading = false

    /// Whether the translation overlay is visible for the current sentence.
    public private(set) var showTranslation = false

    /// Index of the sentence whose translation is shown.
    public private(set) var translationSentenceIndex: Int?

    /// Set of kanji characters the learner has mastered.
    public private(set) var knownKanji: Set<String> = []

    // MARK: - Dependencies

    private let cardRepository: CardRepository

    // MARK: - Init

    public init(cardRepository: CardRepository) {
        self.cardRepository = cardRepository
    }

    // MARK: - Loading

    /// Loads mastered kanji from the card repository and prepares a sample passage.
    public func loadPassage(for level: JLPTLevel) async {
        isLoading = true

        // Load known kanji from mastered cards (cards with high interval = well-learned)
        let kanjiCards = await cardRepository.cards(byType: .kanji)
        let masteredKanji = kanjiCards
            .filter { $0.interval >= 7 }
            .map(\.front)
        knownKanji = Set(masteredKanji)

        // Build a sample passage graded at the given level
        let passage = Self.buildSamplePassage(level: level, knownKanji: knownKanji)
        currentPassage = passage

        isLoading = false

        Logger.content.info(
            "Loaded reading passage: level=\(level.displayName), knownKanji=\(self.knownKanji.count)"
        )
    }

    // MARK: - Word Selection

    /// Selects a word to show its definition popup.
    public func selectWord(_ word: PassageWord) {
        selectedWord = word
        Logger.ui.debug("Selected word: \(word.text)")
    }

    /// Dismisses the word definition popup.
    public func dismissWordDefinition() {
        selectedWord = nil
    }

    // MARK: - Translation Toggle

    /// Toggles the English translation for a sentence.
    public func toggleTranslation(for sentenceIndex: Int) {
        if translationSentenceIndex == sentenceIndex {
            showTranslation = false
            translationSentenceIndex = nil
        } else {
            showTranslation = true
            translationSentenceIndex = sentenceIndex
        }
    }

    /// Hides all translations.
    public func hideTranslation() {
        showTranslation = false
        translationSentenceIndex = nil
    }

    // MARK: - Furigana Logic

    /// Determines whether furigana should be shown for a word.
    /// Known kanji words hide furigana; unknown kanji words show it.
    public func shouldShowFurigana(for word: PassageWord) -> Bool {
        guard word.containsKanji, word.reading != nil else { return false }
        return !word.isKnown
    }

    // MARK: - Sample Passage Builder

    /// Builds a sample N5 passage with word annotations.
    /// In production, this would come from a content repository or AI generation.
    static func buildSamplePassage(
        level: JLPTLevel,
        knownKanji: Set<String>
    ) -> ReadingPassage {
        let sentences = sampleSentences(for: level, knownKanji: knownKanji)
        let content = sentences.map(\.japanese).joined(separator: "")

        return ReadingPassage(
            title: sampleTitle(for: level),
            content: content,
            jlptLevel: level,
            sentences: sentences
        )
    }

    private static func sampleTitle(for level: JLPTLevel) -> String {
        switch level {
        case .n5: "わたしの いちにち"
        case .n4: "週末の買い物"
        case .n3: "東京での生活"
        case .n2: "日本の文化について"
        case .n1: "現代社会の課題"
        }
    }

    private static func sampleSentences(
        for level: JLPTLevel,
        knownKanji: Set<String>
    ) -> [PassageSentence] {
        switch level {
        case .n5:
            n5Sentences(knownKanji: knownKanji)
        case .n4:
            n4Sentences(knownKanji: knownKanji)
        default:
            n5Sentences(knownKanji: knownKanji)
        }
    }

    private static func n5Sentences(knownKanji: Set<String>) -> [PassageSentence] {
        [
            PassageSentence(
                japanese: "まいにち、あさ七じにおきます。",
                english: "Every day, I wake up at 7 in the morning.",
                words: [
                    word("まいにち", meaning: "every day", knownKanji: knownKanji),
                    word("、", meaning: "comma", knownKanji: knownKanji),
                    word("あさ", meaning: "morning", knownKanji: knownKanji),
                    word("七", reading: "なな", meaning: "seven", knownKanji: knownKanji),
                    word("じ", meaning: "o'clock", knownKanji: knownKanji),
                    word("に", meaning: "at (time)", knownKanji: knownKanji),
                    word("おきます", meaning: "to wake up", knownKanji: knownKanji),
                    word("。", meaning: "period", knownKanji: knownKanji),
                ]
            ),
            PassageSentence(
                japanese: "学校まであるいて行きます。",
                english: "I walk to school.",
                words: [
                    word("学校", reading: "がっこう", meaning: "school", knownKanji: knownKanji),
                    word("まで", meaning: "until / to", knownKanji: knownKanji),
                    word("あるいて", meaning: "walking", knownKanji: knownKanji),
                    word("行きます", reading: "いきます", meaning: "to go", knownKanji: knownKanji),
                    word("。", meaning: "period", knownKanji: knownKanji),
                ]
            ),
            PassageSentence(
                japanese: "日本語のべんきょうはたのしいです。",
                english: "Studying Japanese is fun.",
                words: [
                    word("日本語", reading: "にほんご", meaning: "Japanese language", knownKanji: knownKanji),
                    word("の", meaning: "possessive particle", knownKanji: knownKanji),
                    word("べんきょう", meaning: "study", knownKanji: knownKanji),
                    word("は", meaning: "topic marker", knownKanji: knownKanji),
                    word("たのしい", meaning: "fun / enjoyable", knownKanji: knownKanji),
                    word("です", meaning: "is (polite)", knownKanji: knownKanji),
                    word("。", meaning: "period", knownKanji: knownKanji),
                ]
            ),
            PassageSentence(
                japanese: "友だちといっしょにひるごはんを食べます。",
                english: "I eat lunch together with friends.",
                words: [
                    word("友だち", reading: "ともだち", meaning: "friend", knownKanji: knownKanji),
                    word("と", meaning: "with", knownKanji: knownKanji),
                    word("いっしょに", meaning: "together", knownKanji: knownKanji),
                    word("ひるごはん", meaning: "lunch", knownKanji: knownKanji),
                    word("を", meaning: "object marker", knownKanji: knownKanji),
                    word("食べます", reading: "たべます", meaning: "to eat", knownKanji: knownKanji),
                    word("。", meaning: "period", knownKanji: knownKanji),
                ]
            ),
        ]
    }

    private static func n4Sentences(knownKanji: Set<String>) -> [PassageSentence] {
        [
            PassageSentence(
                japanese: "週末にデパートへ買い物に行きました。",
                english: "I went shopping at the department store on the weekend.",
                words: [
                    word("週末", reading: "しゅうまつ", meaning: "weekend", knownKanji: knownKanji),
                    word("に", meaning: "on (time)", knownKanji: knownKanji),
                    word("デパート", meaning: "department store", knownKanji: knownKanji),
                    word("へ", meaning: "to (direction)", knownKanji: knownKanji),
                    word("買い物", reading: "かいもの", meaning: "shopping", knownKanji: knownKanji),
                    word("に", meaning: "for (purpose)", knownKanji: knownKanji),
                    word("行きました", reading: "いきました", meaning: "went", knownKanji: knownKanji),
                    word("。", meaning: "period", knownKanji: knownKanji),
                ]
            ),
            PassageSentence(
                japanese: "新しいくつを買おうと思っていました。",
                english: "I was thinking of buying new shoes.",
                words: [
                    word("新しい", reading: "あたらしい", meaning: "new", knownKanji: knownKanji),
                    word("くつ", meaning: "shoes", knownKanji: knownKanji),
                    word("を", meaning: "object marker", knownKanji: knownKanji),
                    word("買おう", reading: "かおう", meaning: "let's buy", knownKanji: knownKanji),
                    word("と", meaning: "quotation particle", knownKanji: knownKanji),
                    word("思っていました", reading: "おもっていました", meaning: "was thinking", knownKanji: knownKanji),
                    word("。", meaning: "period", knownKanji: knownKanji),
                ]
            ),
        ]
    }

    // MARK: - Word Factory

    /// Creates a PassageWord, automatically detecting kanji and known status.
    private static func word(
        _ text: String,
        reading: String? = nil,
        meaning: String,
        knownKanji: Set<String>
    ) -> PassageWord {
        let hasKanji = text.unicodeScalars.contains { scalar in
            // CJK Unified Ideographs range
            (0x4E00...0x9FFF).contains(scalar.value)
        }

        let isKnown = hasKanji && text.unicodeScalars.allSatisfy { scalar in
            guard (0x4E00...0x9FFF).contains(scalar.value) else { return true }
            return knownKanji.contains(String(scalar))
        }

        return PassageWord(
            text: text,
            reading: hasKanji ? reading : nil,
            meaning: meaning,
            isKnown: isKnown,
            containsKanji: hasKanji
        )
    }
}

// MARK: - Environment Key

private struct ReadingPassageViewModelKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: ReadingPassageViewModel? = nil
}

extension EnvironmentValues {
    public var readingPassageViewModel: ReadingPassageViewModel? {
        get { self[ReadingPassageViewModelKey.self] }
        set { self[ReadingPassageViewModelKey.self] = newValue }
    }
}
