import Foundation
import IkeruCore
import SwiftUI

// MARK: - KanaDrillViewModel

/// Shared view model that drives both the flashcard and the 4-choice quiz
/// drill views. Holds the queue of cards, per-card state (revealed / answered /
/// quiz options), and session-wide stats. Calls into `CardRepository.gradeCard`
/// to persist FSRS scheduling and review logs.
@MainActor
@Observable
public final class KanaDrillViewModel {

    // MARK: Input

    public let mode: KanaDrillMode
    public private(set) var queue: [CardDTO]
    /// Overrides the `mode.displayName` badge shown by the flashcard/quiz
    /// views — used by targeted sessions (e.g. a confusion-pair drill) whose
    /// label doesn't fit any of the three `KanaDrillMode` cases. `nil` (the
    /// default) preserves the existing mode-name badge everywhere else.
    public let sessionLabel: LocalizedStringKey?

    // MARK: Current card

    public private(set) var currentCard: CardDTO?
    public private(set) var currentIndex: Int = 0
    public private(set) var isRevealed: Bool = false
    public private(set) var isAnswered: Bool = false

    // MARK: Quiz state

    public private(set) var quizOptions: [String] = []
    public private(set) var selectedOption: String? = nil
    public private(set) var correctOption: String = ""
    public private(set) var selectedOptionCharacter: String? = nil

    // MARK: Session stats

    public private(set) var correctCount: Int = 0
    public private(set) var wrongCount: Int = 0
    public private(set) var startedAt: Date = Date()
    public private(set) var cardStartedAt: Date = Date()
    public private(set) var sessionEnded: Bool = false

    // MARK: Predicted intervals (flashcard mode)

    public private(set) var predictedIntervals: [Grade: String] = [:]

    // MARK: Dependencies

    private let cardRepository: CardRepository
    private let vocabularyRepository: VocabularyRepository?
    private let now: @Sendable () -> Date

    // MARK: - ReviewLog provenance (learner-telemetry lot 1)
    //
    // The kana drill predates `ExerciseType` and grades kana cards outside
    // the main session's exercise pipeline, so it uses its own small
    // vocabulary rather than borrowing `ExerciseType`'s — see
    // `ReviewLog.exerciseType`'s doc comment.

    private static let flashcardExerciseType = "kana.flashcard"
    private static let quizExerciseType = "kana.quiz"
    private static let surface = "iphone.drill"

    // MARK: Init

    public init(
        mode: KanaDrillMode,
        queue: [CardDTO],
        cardRepository: CardRepository,
        vocabularyRepository: VocabularyRepository? = nil,
        sessionLabel: LocalizedStringKey? = nil,
        now: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.mode = mode
        self.queue = queue.shuffled()
        self.cardRepository = cardRepository
        self.vocabularyRepository = vocabularyRepository
        self.sessionLabel = sessionLabel
        self.now = now
        let nowValue = now()
        self.startedAt = nowValue
        self.cardStartedAt = nowValue
        self.currentCard = self.queue.first
        if self.currentCard != nil {
            buildQuiz(for: self.queue[0])
        } else {
            sessionEnded = true
        }
    }

    // MARK: - Computed

    public var isFirstCard: Bool { currentIndex == 0 }
    public var isLastCard: Bool {
        guard !queue.isEmpty else { return true }
        return currentIndex == queue.count - 1
    }
    public var progressPercent: Double {
        guard !queue.isEmpty else { return 0 }
        return Double(currentIndex) / Double(queue.count)
    }

    /// The hiragana counterpart of the current card, shown as a "same sound,
    /// new shape" bridge (chantier #24a) — but only the first time this exact
    /// katakana is seen (`masteryLevel == .new`, i.e. FSRS reps == 0). Once
    /// the learner has graded it at least once, the bridge steps back so it
    /// doesn't clutter every later review. `nil` for hiragana cards (no
    /// bridge needed) and for non-kana cards.
    public var hiraganaBridgeCharacter: KanaCharacter? {
        guard let card = currentCard, card.masteryLevel == .new else { return nil }
        guard let group = card.kanaGroup,
              let character = group.characters.first(where: { $0.character == card.front })
        else { return nil }
        return character.hiraganaCounterpart
    }

    // MARK: - Flashcard actions

    /// Active profile's desired retention, fetched once — predictions must
    /// match what `gradeCard` will actually schedule (it reads the same
    /// setting). Before the first fetch lands we render with the 0.9 default
    /// and immediately recompute when the real value arrives.
    private var cachedDesiredRetention: Double?

    public func reveal() {
        guard let card = currentCard, !isRevealed else { return }
        isRevealed = true
        predictedIntervals = computePredictedIntervals(
            fsrsState: card.fsrsState,
            now: now(),
            desiredRetention: cachedDesiredRetention ?? 0.9
        )
        if cachedDesiredRetention == nil {
            Task {
                cachedDesiredRetention = await cardRepository.activeDesiredRetention()
                if let current = currentCard, isRevealed {
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
        guard let card = currentCard else { return }
        let elapsed = Int(now().timeIntervalSince(cardStartedAt) * 1000)
        // Flashcard grading is self-evaluated — the learner grades their own
        // recall, there is no "chosen value" to log (answeredValue stays nil).
        await cardRepository.gradeCard(
            cardId: card.id,
            grade: grade,
            responseTimeMs: max(0, elapsed),
            now: now(),
            exerciseType: Self.flashcardExerciseType,
            surface: Self.surface
        )
        if grade == .again {
            wrongCount += 1
        } else {
            correctCount += 1
        }
        await logKanaEncounter(card)
        advance()
    }

    // MARK: - Quiz actions

    public func selectOption(_ option: String) {
        guard !isAnswered else { return }
        selectedOption = option
    }

    public func submitQuizAnswer() async {
        guard let card = currentCard, let selected = selectedOption, !isAnswered else { return }
        isAnswered = true
        let elapsedMs = Int(now().timeIntervalSince(cardStartedAt) * 1000)
        let isCorrect = selected == correctOption
        let grade = mapQuizResultToGrade(
            correct: isCorrect,
            responseTimeMs: elapsedMs,
            isFirstEncounter: card.fsrsState.reps == 0
        )

        // Track which kana corresponds to the selected (potentially wrong) romaji
        // for the pedagogical "Le caractère pour {romaji} est {kana}" feedback,
        // AND as the persisted answeredValue (learner-telemetry lot 1) — the
        // character, not the romaji label, is what makes a confusion pair
        // analyzable (e.g. シ vs ツ). Falls back to the raw romaji option if a
        // character can't be resolved (e.g. the "?N" pad distractor), so the
        // datum is never silently dropped. Recorded on correct answers too.
        selectedOptionCharacter = lookupCharacter(forRomaji: selected, in: card)

        await cardRepository.gradeCard(
            cardId: card.id,
            grade: grade,
            responseTimeMs: max(0, elapsedMs),
            now: now(),
            answeredValue: selectedOptionCharacter ?? selected,
            exerciseType: Self.quizExerciseType,
            surface: Self.surface
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
            currentCard = nil
            isRevealed = false
            isAnswered = false
            selectedOption = nil
            selectedOptionCharacter = nil
            quizOptions = []
            return
        }
        currentIndex = next
        let card = queue[next]
        currentCard = card
        isRevealed = false
        isAnswered = false
        selectedOption = nil
        selectedOptionCharacter = nil
        predictedIntervals = [:]
        cardStartedAt = now()
        buildQuiz(for: card)
    }

    public func restart() {
        queue = queue.shuffled()
        currentIndex = 0
        correctCount = 0
        wrongCount = 0
        isRevealed = false
        isAnswered = false
        selectedOption = nil
        selectedOptionCharacter = nil
        predictedIntervals = [:]
        sessionEnded = false
        let nowValue = now()
        startedAt = nowValue
        cardStartedAt = nowValue
        if let first = queue.first {
            currentCard = first
            buildQuiz(for: first)
        } else {
            currentCard = nil
            sessionEnded = true
        }
    }

    // MARK: - Encounter Tracking

    private func logKanaEncounter(_ card: CardDTO) async {
        guard let repo = vocabularyRepository else { return }
        await repo.logEncounterByWord(
            word: card.front,
            reading: card.back,
            meaning: card.back,
            source: .kanaDrill,
            contextSnippet: "Kana drill: \(card.front) → \(card.back)"
        )
    }

    // MARK: - Helpers

    /// Build the 4 quiz options for a given card. Distractors are drawn in
    /// priority order — (0) for a labelled session only (see below), other
    /// cards actually in this session's queue; then (1) the same KanaGroup —
    /// the original, primary source; then (2) sibling groups in the same
    /// script + section. Final order is shuffled.
    ///
    /// Priority 0 is gated on `sessionLabel != nil` — today that means a
    /// confusion-pair drill (chantier #24b), whose queue IS the 2-3 character
    /// cluster. It guarantees the pair-mate is offered as a distractor
    /// instead of leaving it to chance in step 1/2. The gate matters: a
    /// normal freePractice/dueReview/weakReinforcement queue can span many
    /// groups, and "the rest of the queue" there is not a deliberate contrast
    /// set — unconditionally prioritising it would replace the original,
    /// pedagogically-intentional same-row distractors (き/く/け/こ for a か
    /// review) with arbitrary unrelated characters. Untagged sessions keep
    /// the original priority order (same group first, then siblings) — the
    /// one behavioural difference is that a small group (Y row, W/N row,
    /// every yōon group: only 2 non-correct members) now guarantees both
    /// group-mates as distractors instead of the old code's probabilistic
    /// sampling across the merged group+sibling pool (~11% chance of both
    /// appearing together before). Arguably a pedagogical improvement, but
    /// worth flagging as a change, not a no-op.
    private func buildQuiz(for card: CardDTO) {
        guard let group = card.kanaGroup,
              let correctChar = group.characters.first(where: { $0.character == card.front })
        else {
            quizOptions = [card.back]
            correctOption = card.back
            return
        }
        let correctRomaji = correctChar.romaji
        correctOption = correctRomaji

        var distractors: [String] = []

        if sessionLabel != nil {
            let queueMates = Array(Set(
                queue
                    .filter { $0.front != card.front }
                    .compactMap { other in
                        other.kanaGroup?.characters.first(where: { $0.character == other.front })?.romaji
                    }
            ))
            .filter { $0 != correctRomaji }
            .shuffled()
            distractors.append(contentsOf: queueMates.prefix(3))
        }

        if distractors.count < 3 {
            let groupMates = group.characters
                .filter { $0.character != correctChar.character }
                .map { $0.romaji }
                .filter { !distractors.contains($0) }
                .shuffled()
            for romaji in groupMates {
                distractors.append(romaji)
                if distractors.count >= 3 { break }
            }
        }

        if distractors.count < 3 {
            let siblings = KanaGroup.allCases
                .filter { $0.script == group.script && $0.section == group.section && $0 != group }
                .flatMap { $0.characters }
                .map { $0.romaji }
                .filter { $0 != correctRomaji && !distractors.contains($0) }
            for romaji in Array(Set(siblings)).shuffled() {
                distractors.append(romaji)
                if distractors.count >= 3 { break }
            }
        }

        // Pad if still short (extreme edge: tiny dataset)
        while distractors.count < 3 {
            distractors.append("?\(distractors.count)")
        }

        var options = distractors
        options.append(correctRomaji)
        quizOptions = options.shuffled()
    }

    /// Find the kana character whose romaji matches `romaji`, searching the
    /// current card's group first then any sibling group in the same script.
    private func lookupCharacter(forRomaji romaji: String, in card: CardDTO) -> String? {
        guard let group = card.kanaGroup else { return nil }
        if let hit = group.characters.first(where: { $0.romaji == romaji }) {
            return hit.character
        }
        let siblings = KanaGroup.allCases
            .filter { $0.script == group.script }
            .flatMap { $0.characters }
        return siblings.first(where: { $0.romaji == romaji })?.character
    }

}
