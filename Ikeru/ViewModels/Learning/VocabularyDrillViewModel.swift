import Foundation
import IkeruCore
import os

// MARK: - VocabularyDrillViewModel

/// Drives flashcard and quiz drills for personal dictionary words.
/// Uses VocabularyRepository for FSRS grading (same algorithm as SRS cards).
@MainActor
@Observable
public final class VocabularyDrillViewModel {

    // MARK: - Input

    public private(set) var queue: [VocabularyEntryDTO]

    // MARK: - Current entry

    public private(set) var currentEntry: VocabularyEntryDTO?
    public private(set) var currentIndex: Int = 0
    public private(set) var isRevealed: Bool = false
    public private(set) var isAnswered: Bool = false

    // MARK: - Quiz state

    public private(set) var quizOptions: [String] = []
    public private(set) var selectedOption: String?
    public private(set) var correctOption: String = ""

    // MARK: - Session stats

    public private(set) var correctCount: Int = 0
    public private(set) var wrongCount: Int = 0
    public private(set) var startedAt: Date = Date()
    public private(set) var entryStartedAt: Date = Date()
    public private(set) var sessionEnded: Bool = false

    // MARK: - Predicted intervals (flashcard mode)

    public private(set) var predictedIntervals: [Grade: String] = [:]

    // MARK: - Dependencies

    private let vocabularyRepository: VocabularyRepository
    private let allEntries: [VocabularyEntryDTO]
    private let now: @Sendable () -> Date

    // MARK: - Init

    public init(
        queue: [VocabularyEntryDTO],
        allEntries: [VocabularyEntryDTO],
        vocabularyRepository: VocabularyRepository,
        now: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.allEntries = allEntries
        self.vocabularyRepository = vocabularyRepository
        self.now = now
        self.queue = queue.shuffled()
        let nowValue = now()
        self.startedAt = nowValue
        self.entryStartedAt = nowValue
        self.currentEntry = self.queue.first
        if self.currentEntry != nil {
            buildQuiz(for: self.queue[0])
        } else {
            sessionEnded = true
        }
    }

    // MARK: - Computed

    public var progressPercent: Double {
        guard !queue.isEmpty else { return 0 }
        return Double(currentIndex) / Double(queue.count)
    }

    // MARK: - Flashcard Actions

    /// Active profile's desired retention, fetched once — predictions must
    /// match what `gradeEntry` will actually schedule. See KanaDrillViewModel.
    private var cachedDesiredRetention: Double?

    public func reveal() {
        guard let entry = currentEntry, !isRevealed else { return }
        isRevealed = true
        predictedIntervals = computePredictedIntervals(
            fsrsState: entry.fsrsState,
            now: now(),
            desiredRetention: cachedDesiredRetention ?? 0.9
        )
        if cachedDesiredRetention == nil {
            Task {
                cachedDesiredRetention = await vocabularyRepository.activeDesiredRetention()
                if let current = currentEntry, isRevealed {
                    predictedIntervals = computePredictedIntervals(
                        fsrsState: current.fsrsState,
                        now: now(),
                        desiredRetention: cachedDesiredRetention ?? 0.9
                    )
                }
            }
        }
    }

    public func grade(_ grade: Grade) async {
        guard let entry = currentEntry else { return }
        let elapsed = Int(now().timeIntervalSince(entryStartedAt) * 1000)
        await vocabularyRepository.gradeEntry(
            entryId: entry.id,
            grade: grade,
            responseTimeMs: max(0, elapsed),
            now: now()
        )
        if grade == .again {
            wrongCount += 1
        } else {
            correctCount += 1
        }
        advance()
    }

    // MARK: - Quiz Actions

    public func selectOption(_ option: String) {
        guard !isAnswered else { return }
        selectedOption = option
    }

    public func submitQuizAnswer() async {
        guard let entry = currentEntry, let selected = selectedOption, !isAnswered else { return }
        isAnswered = true
        let elapsedMs = Int(now().timeIntervalSince(entryStartedAt) * 1000)
        let isCorrect = selected == correctOption
        let grade = mapQuizResultToGrade(
            correct: isCorrect,
            responseTimeMs: elapsedMs,
            isFirstEncounter: entry.fsrsState.reps == 0
        )

        await vocabularyRepository.gradeEntry(
            entryId: entry.id,
            grade: grade,
            responseTimeMs: max(0, elapsedMs),
            now: now()
        )
        if isCorrect {
            correctCount += 1
        } else {
            wrongCount += 1
        }
    }

    // MARK: - Navigation

    public func advance() {
        let next = currentIndex + 1
        if next >= queue.count {
            sessionEnded = true
            currentEntry = nil
            isRevealed = false
            isAnswered = false
            selectedOption = nil
            quizOptions = []
            return
        }
        currentIndex = next
        let entry = queue[next]
        currentEntry = entry
        isRevealed = false
        isAnswered = false
        selectedOption = nil
        predictedIntervals = [:]
        entryStartedAt = now()
        buildQuiz(for: entry)
    }

    public func restart() {
        queue = queue.shuffled()
        currentIndex = 0
        correctCount = 0
        wrongCount = 0
        isRevealed = false
        isAnswered = false
        selectedOption = nil
        predictedIntervals = [:]
        sessionEnded = false
        let nowValue = now()
        startedAt = nowValue
        entryStartedAt = nowValue
        if let first = queue.first {
            currentEntry = first
            buildQuiz(for: first)
        } else {
            currentEntry = nil
            sessionEnded = true
        }
    }

    // MARK: - Helpers

    /// Build 4 quiz options: correct meaning + 3 distractors from other dictionary entries.
    ///
    /// ## Distractors must be in the same language as the answer
    ///
    /// This is a correctness requirement, not polish — the same lesson the
    /// listening drill learned with homophones and the grammar cloze learned
    /// with suffixes: **a distractor that gives the answer away is a broken
    /// question.**
    ///
    /// Words mined from imported texts carry an English gloss whenever JMdict
    /// has no French one, which is about one mined card in three (measured
    /// 2026-08-20 on the reference sample: 14 of 45 non-curated words). Drawn
    /// from a dictionary that is otherwise 97 % French, the English answer was
    /// the only English option roughly nine times out of ten — so
    /// « pluie / ami / to be crowded; to be packed / film » is answerable
    /// without reading a single kanji.
    ///
    /// So distractors are drawn from the same language bucket as the answer,
    /// and only fall back to the other bucket when that one cannot fill three
    /// slots. A question with mixed languages is still better than a question
    /// with two options, but it is a last resort, not the default.
    private func buildQuiz(for entry: VocabularyEntryDTO) {
        let correctMeaning = entry.meaning
        correctOption = correctMeaning

        let pool = Array(Set(allEntries.filter { $0.id != entry.id }.map(\.meaning)))
        let answerLooksEnglish = Self.looksEnglish(correctMeaning)
        let sameLanguage = pool.filter { Self.looksEnglish($0) == answerLooksEnglish }
        let otherLanguage = pool.filter { Self.looksEnglish($0) != answerLooksEnglish }

        var distractors = Array(sameLanguage.shuffled().prefix(3))
        if distractors.count < 3 {
            distractors += otherLanguage.shuffled().prefix(3 - distractors.count)
        }
        while distractors.count < 3 {
            distractors.append("—")
        }

        var options = distractors
        options.append(correctMeaning)
        quizOptions = options.shuffled()
    }

    /// Whether a gloss reads as English rather than French.
    ///
    /// A heuristic, deliberately: the entry carries no language field, and
    /// adding one means a schema version plus a sync column for something the
    /// text itself already says. It only has to be right often enough to keep
    /// the four options looking alike — being wrong makes one question
    /// slightly easier, never wrong.
    ///
    /// French glosses in this app are accented far more often than not, and the
    /// short function words differ completely. Both signals are checked because
    /// either alone misfires: « pluie » has no accent, and « information » is
    /// spelled identically in both languages.
    nonisolated static func looksEnglish(_ gloss: String) -> Bool {
        let lowered = gloss.lowercased()
        if lowered.contains(where: { "àâäéèêëîïôöùûüÿçœæ".contains($0) }) { return false }
        let words = Set(lowered.split(whereSeparator: { !$0.isLetter }).map(String.init))
        let french: Set<String> = ["le", "la", "les", "un", "une", "des", "du", "de",
                                   "qui", "que", "dans", "pour", "avec", "sur", "être",
                                   "faire", "chose", "personne", "sans"]
        let english: Set<String> = ["the", "a", "an", "of", "to", "in", "for", "with",
                                    "on", "be", "is", "that", "which", "something",
                                    "someone", "one's", "etc", "esp"]
        let frenchHits = words.intersection(french).count
        let englishHits = words.intersection(english).count
        if frenchHits != englishHits { return englishHits > frenchHits }
        // Aucun indice : on ne devine pas, on suppose la langue de l'app —
        // c'est le cas majoritaire, et se tromper ne fait qu'élargir le vivier.
        return false
    }

}
