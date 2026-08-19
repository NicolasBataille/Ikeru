import SwiftUI
import SwiftData
import IkeruCore
import os

// MARK: - TextImportStage

/// Where the learner is in the journey. One value, so no screen can disagree
/// with another about what is happening.
public enum TextImportStage: Equatable {
    /// Pasting, typing, or correcting what the camera read.
    case capture
    /// Reading the analysed text, tapping words.
    case reading
    /// Choosing which unknown words to keep.
    case selection
    /// Saved; the mini-session is offered, never imposed.
    case saved(wordsKept: Int)
}

// MARK: - TextImportViewModel

/// Drives « apporte ton propre texte » end to end: capture, analysis, the
/// known/unknown split, selection, and saving.
///
/// ## The suggestion cap is a feature, not a limit
///
/// `suggestionCap` bounds how many unknown words are **pre-selected**, never
/// how many the learner may keep and never how the SRS schedules them. The
/// vision is explicit — « on plafonne la charge, jamais l'espacement » — and
/// the anti-pattern it names is the guide that tells you to add 95 % of what
/// you see, which is the direct road to review debt. Everything above the cap
/// stays listed and one tap away.
///
/// Words are pre-selected in i+1 order: the ones whose sentence the learner
/// **already understands best** come first, because a word met in an otherwise
/// clear sentence is the one that will stick.
@MainActor
@Observable
public final class TextImportViewModel {

    // MARK: Exposed state

    public private(set) var stage: TextImportStage = .capture

    /// The text being worked on. Bound directly by the capture field, which is
    /// also how an OCR result gets corrected — the vision asks for correction
    /// to be a normal edit, not a separate mode.
    public var draft: String = ""

    /// Where the draft came from. Set by the capture screen.
    public private(set) var source: ImportSource = .paste

    public private(set) var analysis: AnalyzedText?
    public private(set) var isAnalyzing = false

    /// Dictionary forms the learner already knows.
    public private(set) var knownForms: Set<String> = []

    /// Selected dictionary forms, the geste central of the whole feature.
    public private(set) var selected: Set<String> = []

    /// Entries created by the last `save()`, in selection order — what the
    /// « pratique ce que tu viens de lire » mini-session drills. Proposed,
    /// never imposed.
    public private(set) var savedEntryIDs: [UUID] = []

    /// True while the dictionary is unavailable — the feature says so rather
    /// than failing word by word.
    public private(set) var dictionaryAvailable = true

    /// How many unknown words are pre-ticked.
    public static let suggestionCap = 8

    // MARK: Derived

    /// Share of content words already known, 0…1. `nil` when nothing is
    /// measurable — an empty text, or one with no content word at all.
    public var coverage: Double? {
        analysis?.coverage(known: knownForms)
    }

    /// Unknown learnable words, in i+1 order.
    public var unknownWords: [AnalyzedToken] {
        guard let analysis else { return [] }
        return analysis.unknownWords(known: knownForms)
            .sorted { comprehension(of: $0) > comprehension(of: $1) }
    }

    public var selectedCount: Int { selected.count }

    // MARK: Dependencies

    private let analyzer: JapaneseTextAnalyzer
    private let dictionary: DictionaryRepository
    private let vocabulary: VocabularyRepository
    private let imports: TextImportRepository

    public init(analyzer: JapaneseTextAnalyzer,
                dictionary: DictionaryRepository,
                vocabulary: VocabularyRepository,
                imports: TextImportRepository) {
        self.analyzer = analyzer
        self.dictionary = dictionary
        self.vocabulary = vocabulary
        self.imports = imports
    }

    // MARK: Journey

    public func begin(with text: String, source: ImportSource) {
        draft = text
        self.source = source
        stage = .capture
    }

    /// Analyses the draft and moves to reading.
    public func analyzeDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }

        dictionaryAvailable = await dictionary.isAvailable()
        guard dictionaryAvailable else { return }

        knownForms = Set(await vocabulary.allEntries().map(\.word))
        analysis = await analyzer.analyze(text)
        stage = .reading
    }

    public func moveToSelection() {
        // Le plafond pré-coche, il n'interdit rien : le reste de la liste est
        // là, décoché, à un tap.
        selected = Set(unknownWords.prefix(Self.suggestionCap).compactMap(\.dictionaryForm))
        stage = .selection
    }

    public func backToReading() { stage = .reading }

    public func toggle(_ token: AnalyzedToken) {
        guard let form = token.dictionaryForm else { return }
        if selected.contains(form) { selected.remove(form) } else { selected.insert(form) }
    }

    public func isSelected(_ token: AnalyzedToken) -> Bool {
        token.dictionaryForm.map(selected.contains) ?? false
    }

    /// Creates one SRS entry per selected word, each keeping the sentence it
    /// was met in, then records the import.
    ///
    /// The words are **due immediately**, and that is correct here: the learner
    /// chose them one by one. It is the opposite of the grammar seeding that
    /// was removed on 2026-08-19, which filled the queue with 51 cards nobody
    /// asked for. Consent is what makes the difference, not the count.
    public func save() async {
        guard let analysis else { return }
        var createdIDs: [UUID] = []

        for token in analysis.learnableWords {
            guard let form = token.dictionaryForm, selected.contains(form),
                  let entry = token.entry else { continue }
            let gloss = entry.glossFR ?? entry.glossEN
            let created = await vocabulary.addEntry(word: form, reading: entry.reading,
                                                    meaning: gloss)
            createdIDs.append(created.id)
            await vocabulary.logEncounter(
                entryId: created.id,
                source: .importedText,
                contextSnippet: Self.sentence(containing: token, in: analysis)
            )
        }

        _ = await imports.create(content: analysis.source, source: source,
                                 coverage: coverage, entryIDs: createdIDs)
        savedEntryIDs = createdIDs
        stage = .saved(wordsKept: createdIDs.count)
    }

    public func reset() {
        draft = ""
        analysis = nil
        selected = []
        knownForms = []
        savedEntryIDs = []
        stage = .capture
    }

    // MARK: - i+1 and context

    /// How much of the sentence around `token` the learner already knows, 0…1.
    ///
    /// Drives the pre-selection order: a word standing in an otherwise
    /// understood sentence is the one worth learning next. That is the i+1
    /// idea the vision asks for, computed rather than asserted.
    func comprehension(of token: AnalyzedToken) -> Double {
        let sentence = Self.sentenceTokens(containing: token, in: analysis)
        let content = sentence.filter(\.isLearnable)
        guard !content.isEmpty else { return 0 }
        let known = content.filter { knownForms.contains($0.dictionaryForm ?? "") }.count
        return Double(known) / Double(content.count)
    }

    /// The sentence a token sits in, as text — what the SRS card keeps.
    ///
    /// « Le contexte est la moitié de la valeur » : a mined card without its
    /// sentence is a list card with extra steps.
    nonisolated static func sentence(containing token: AnalyzedToken,
                                     in analysis: AnalyzedText) -> String {
        sentenceTokens(containing: token, in: analysis)
            .map(\.surface).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Sentence boundaries are the Japanese full stop, the question and
    /// exclamation marks, and line breaks — the marks a reader actually stops
    /// at. Closing quotes are deliberately not boundaries: 「おい、そこで何を
    /// している！」 is one utterance.
    nonisolated static let sentenceBreaks: Set<Character> = ["。", "！", "？", ".", "!", "?", "\n"]

    nonisolated static func sentenceTokens(containing token: AnalyzedToken,
                                           in analysis: AnalyzedText?) -> [AnalyzedToken] {
        guard let analysis, let index = analysis.tokens.firstIndex(where: { $0.id == token.id })
        else { return [] }

        var start = index
        while start > 0 {
            let previous = analysis.tokens[start - 1]
            if !previous.isWord, previous.surface.contains(where: sentenceBreaks.contains) { break }
            start -= 1
        }
        var end = index
        while end < analysis.tokens.count - 1 {
            let current = analysis.tokens[end]
            if !current.isWord, current.surface.contains(where: sentenceBreaks.contains) { break }
            end += 1
        }
        return Array(analysis.tokens[start...end])
    }
}
