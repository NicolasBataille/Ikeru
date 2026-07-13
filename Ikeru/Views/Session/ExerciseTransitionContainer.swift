import SwiftUI
import IkeruCore
import os

// MARK: - ExerciseTransitionContainer

/// Container that renders the current exercise with matchedGeometryEffect
/// transitions between exercise types for smooth 60fps morphing.
struct ExerciseTransitionContainer: View {

    /// The current exercise to display.
    let exercise: ExerciseItem?

    /// Callback when the user completes an SRS card via swipe.
    let onSwipeGrade: (SwipeDirection) -> Void

    /// Callback when the user completes an SRS card via button.
    let onButtonGrade: (Grade) -> Void

    /// Callback when the user completes a NON-SRS drill exercise (kanji study,
    /// writing practice, sentence construction). Distinct from the SRS grade
    /// closures above: this routes to `SessionViewModel.completeCurrentExercise`
    /// which advances the exercise pointer without moving the SRS queue pointer.
    /// Each drill maps its own internal result → `Grade` before calling this.
    let onExerciseComplete: (Grade) -> Void

    /// The current card for SRS review exercises.
    let currentCard: CardDTO?

    /// Upcoming cards (up to 3). The deck view renders a peek for each.
    let upcomingCards: [CardDTO]

    /// Feedback state for correct/incorrect overlay.
    let feedbackState: FeedbackState?

    /// Session vocabulary pool (level-scoped) for the audio drills (Shadowing +
    /// word/meaning Listening). The container is the composition root
    /// (blueprint §2): it holds the pool and builds each audio drill's view
    /// model lazily at render time, mirroring each view's `#Preview`. Empty when
    /// no content bundle was available; the hosts then show a skip affordance.
    let vocabularyPool: [VocabularyItem]

    @Namespace private var exerciseAnimation
    @State private var isRevealed = false

    var body: some View {
        ZStack {
            if let exercise {
                // SRS reviews are rendered with a stable view identity so the
                // DeckView's matchedGeometryEffect can smoothly promote peeks
                // into the current slot when cards advance. Destroying the view
                // via `.id()` on every card would break that animation.
                if case .srsReview = exercise {
                    srsReviewView
                        .transition(.opacity)
                } else {
                    exerciseView(for: exercise)
                        .matchedGeometryEffect(id: "exerciseCard", in: exerciseAnimation)
                        .transition(
                            .asymmetric(
                                insertion: .promoteFromPeek,
                                removal: .identity
                            )
                        )
                        .id(exercise.stableID)
                }
            } else {
                emptyStateView
            }
        }
        .animation(
            .spring(response: 0.48, dampingFraction: 0.82),
            value: currentCard?.id
        )
        .animation(
            .spring(response: 0.42, dampingFraction: 0.82),
            value: exercise?.stableID
        )
        .onChange(of: currentCard?.id) { _, _ in
            isRevealed = false
        }
    }

    // MARK: - Exercise View Router

    @ViewBuilder
    private func exerciseView(for exercise: ExerciseItem) -> some View {
        switch exercise {
        case .srsReview:
            srsReviewView

        case .kanjiStudy(let card):
            // Kanji study reuses the handwriting drill against the real card's
            // front character; completion writes a REAL FSRS grade for the card
            // (via SessionViewModel.completeCurrentExercise → gradeCard).
            HandwritingDrillHost(character: card.front, onComplete: onExerciseComplete)

        case .grammarExercise:
            placeholderExerciseView(
                icon: sfSymbol(for: .reading),
                title: "Grammar Exercise",
                detail: "Grammar point",
                skill: .reading
            )

        case .writingPractice(let card):
            // Writing practice reuses the same handwriting drill but is XP-only
            // (no FSRS write) — SessionViewModel awards XP for .writingPractice
            // without grading a card, per the ExerciseXP rule table.
            HandwritingDrillHost(character: card.front, onComplete: onExerciseComplete)

        case .listeningExercise:
            // Word/meaning listening drill built lazily from the session
            // vocabulary pool. XP-only completion (no FSRS write).
            ListeningDrillHost(vocabulary: vocabularyPool, onComplete: onExerciseComplete)

        case .speakingExercise:
            // Shadowing drill built lazily from the session vocabulary pool.
            // XP-only completion (no FSRS write).
            ShadowingDrillHost(vocabulary: vocabularyPool, onComplete: onExerciseComplete)

        case .sentenceConstruction:
            // Self-contained token-arrangement drill (built-in N5 templates);
            // XP-only completion.
            SentenceConstructionDrillHost(onComplete: onExerciseComplete)

        case .vocabularyStudy:
            // Multiple-choice recall built lazily from the session vocabulary
            // pool. XP-only completion (no FSRS write): `.vocabularyStudy` has
            // no backing SwiftData Card, so SessionViewModel awards XP without
            // grading a card (the card-grade branch is gated on `.kanjiStudy`).
            VocabularyRecallDrillHost(vocabulary: vocabularyPool, onComplete: onExerciseComplete)

        case .fillInBlank:
            placeholderExerciseView(
                icon: sfSymbol(for: .reading),
                title: "Fill in the Blank",
                detail: "Complete the sentence",
                skill: .reading
            )

        case .readingPassage:
            placeholderExerciseView(
                icon: sfSymbol(for: .reading),
                title: "Reading Passage",
                detail: "Read and comprehend",
                skill: .reading
            )
        }
    }

    // MARK: - SRS Review View

    @ViewBuilder
    private var srsReviewView: some View {
        if let card = currentCard {
            VStack(spacing: 0) {
                Spacer()

                SRSCardView(
                    card: card,
                    upcomingCards: upcomingCards,
                    isRevealed: $isRevealed
                ) { direction in
                    onSwipeGrade(direction)
                }
                .padding(.horizontal, IkeruTheme.Spacing.lg)
                // NOTE: the old `.overlay { feedbackOverlay }` drew a 3pt green/red
                // stroke around the whole deck for 300ms after each grade.
                // That border bled onto the newly-promoted current card,
                // making it look like the swipe colour carried over. The
                // outgoing ghost already conveys the grade colour via its
                // own border, so the deck-level feedback overlay is redundant.

                Spacer()

                if isRevealed {
                    GradeButtonsView { grade in
                        onButtonGrade(grade)
                    }
                    .padding(.horizontal, IkeruTheme.Spacing.md)
                    .padding(.bottom, IkeruTheme.Spacing.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    // Tap-to-reveal is handled directly by `SRSCardView`'s
                    // tap gesture. A quiet caption hints at the affordance
                    // without the visual weight of a primary button.
                    Text("Tap card to reveal", comment: "Hint shown below the SRS card before reveal — replaces the old 'Show answer' button")
                        .ikeruScaledFont(11, weight: .semibold, relativeTo: .caption2)
                        .tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(TatamiTokens.paperGhost)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, IkeruTheme.Spacing.md)
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isRevealed)
        }
    }

    // MARK: - Placeholder Exercise View

    /// Placeholder for exercise types not yet fully implemented.
    /// Displays the skill icon, title, and a "Complete" button.
    private func placeholderExerciseView(
        icon: String,
        title: String,
        detail: String,
        skill: SkillType
    ) -> some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(skillColor(for: skill))

            Text(title)
                .font(.ikeruHeading2)
                .foregroundStyle(.white)

            Text(detail)
                .font(.ikeruBody)
                .foregroundStyle(.ikeruTextSecondary)

            Spacer()

            Button("Complete") {
                // For placeholder exercises, grade as "good"
                onButtonGrade(.good)
            }
            .ikeruButtonStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .padding(.bottom, IkeruTheme.Spacing.md)
        }
    }

    // MARK: - Feedback Overlay

    @ViewBuilder
    private var feedbackOverlay: some View {
        if let feedback = feedbackState {
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.md)
                .strokeBorder(feedback.color, lineWidth: 3)
                .padding(.horizontal, IkeruTheme.Spacing.lg)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.3), value: feedbackState)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            Image(systemName: "tray.fill")
                .font(.system(size: 48))
                .foregroundStyle(.ikeruTextSecondary)

            Text("No exercises available")
                .font(.ikeruHeading3)
                .foregroundStyle(.ikeruTextSecondary)
        }
    }

    // MARK: - Helpers

    private func skillColor(for skill: SkillType) -> Color {
        switch skill {
        case .reading: Color(hex: IkeruTheme.Colors.Skills.reading)
        case .writing: Color(hex: IkeruTheme.Colors.Skills.writing)
        case .listening: Color(hex: IkeruTheme.Colors.Skills.listening)
        case .speaking: Color(hex: IkeruTheme.Colors.Skills.speaking)
        }
    }
}

// MARK: - Drill Grade Mapping

/// Pure mapping from each Tier-1 drill view's internal result to an FSRS
/// `Grade`, per Phase 4.1 blueprint §3. Kept as standalone static functions so
/// the mapping is unit-testable without instantiating a view or view model.
enum DrillGradeMapping {

    /// Top-candidate confidence at/above which a *correct* handwriting result is
    /// graded `.easy` rather than `.good`. The recogniser's "correct" threshold
    /// is 0.7 (`HandwritingViewModel.correctThreshold`); a near-certain top
    /// match earns the longer `.easy` interval.
    static let easyConfidenceThreshold: Double = 0.95

    /// Handwriting recognition feedback → `Grade`.
    /// `.correct` → `.good` (or `.easy` on very high confidence),
    /// `.partial` → `.hard`, `.incorrect`/`.idle` → `.again`.
    ///
    /// `.unavailable` is NOT auto-graded here (remediation 7.8): when the
    /// recogniser can't read the scribble, the view shows an explicit self-grade
    /// affordance and calls `onComplete` with the learner's own honest verdict
    /// (`.good`/`.again`). This mapping is only a safe non-passing fallback so an
    /// unavailable state can never fabricate a pass if it ever reaches here.
    static func handwriting(
        feedback: HandwritingFeedbackState,
        topConfidence: Double?
    ) -> Grade {
        switch feedback {
        case .correct:
            if let confidence = topConfidence, confidence >= easyConfidenceThreshold {
                return .easy
            }
            return .good
        case .partial:
            return .hard
        case .incorrect, .idle, .unavailable:
            return .again
        }
    }

    /// Sentence-construction validation → `Grade`. A correct arrangement is
    /// `.good`, anything else `.again` (no partial-credit tier for ordering).
    static func sentenceConstruction(isCorrect: Bool) -> Grade {
        isCorrect ? .good : .again
    }

    /// Shadowing pronunciation accuracy (0…1) → `Grade`, per blueprint §3:
    /// ≥0.9 → `.easy`, ≥0.7 → `.good`, ≥0.4 → `.hard`, else `.again`. Shadowing
    /// is XP-only downstream (`speakingPractice` is `.perCompletion`), so this
    /// grade only shapes the completion signal — it is never written to FSRS.
    static func shadowing(accuracy: Double) -> Grade {
        switch accuracy {
        case 0.9...:     return .easy
        case 0.7..<0.9:  return .good
        case 0.4..<0.7:  return .hard
        default:         return .again
        }
    }

    /// Listening answer correctness → `Grade`, per blueprint §3: a correct
    /// choice is `.good`, anything else `.again` (a single multiple-choice
    /// answer has no partial tier). Listening is XP-only downstream
    /// (`listeningSubtitled`/`Unsubtitled` are `.perCompletion`).
    static func listening(isCorrect: Bool) -> Grade {
        isCorrect ? .good : .again
    }

    /// Vocabulary multiple-choice recall correctness → `Grade`: a correct
    /// choice is `.good`, anything else `.again` (one MC answer has no partial
    /// tier). Vocabulary recall is XP-only downstream — `.vocabularyStudy` has
    /// NO backing FSRS card, so this grade only scales the XP award
    /// (`vocabularyStudy` is `.perGrade`) and is NEVER written to FSRS.
    static func vocabularyRecall(isCorrect: Bool) -> Grade {
        isCorrect ? .good : .again
    }
}

// MARK: - Drill Hosts

/// Owns a `HandwritingViewModel` for the lifetime of one exercise (the
/// container keeps view identity stable via `.id(exercise.stableID)`, so the
/// `@State` model persists across body re-evaluations and resets when the
/// exercise changes). Loads the target character once and forwards completion
/// to `onComplete`. Shared by `.kanjiStudy` and `.writingPractice`; the FSRS
/// vs XP-only distinction is made downstream in `SessionViewModel` by exercise
/// kind, not here.
private struct HandwritingDrillHost: View {
    let character: String
    let onComplete: (Grade) -> Void
    @State private var viewModel = HandwritingViewModel()

    var body: some View {
        HandwritingExerciseView(viewModel: viewModel, onComplete: onComplete)
            .onAppear {
                if viewModel.targetCharacter != character {
                    viewModel.loadTarget(character: character)
                }
            }
    }
}

/// Owns a `SentenceConstructionViewModel`, loads a beginner-difficulty exercise
/// once on appear, and forwards completion to `onComplete`. (Difficulty is
/// fixed to `.beginner` for this Tier-1 pass; a JLPT-level mapping is a later
/// refinement.)
private struct SentenceConstructionDrillHost: View {
    let onComplete: (Grade) -> Void
    @State private var viewModel = SentenceConstructionViewModel()

    var body: some View {
        SentenceConstructionView(viewModel: viewModel, onComplete: onComplete)
            .onAppear {
                if viewModel.currentExercise == nil {
                    viewModel.loadExercise(difficulty: .beginner)
                }
            }
    }
}

/// Owns a `ShadowingViewModel` (with a fresh `AudioService` +
/// `SpeechRecognitionService`) for the lifetime of one `.speakingExercise`.
/// Loads a word-level exercise from the session vocabulary pool on appear and
/// forwards completion to `onComplete`. The exercise level is derived from the
/// pool (which is already level-scoped) so generation never filters to empty on
/// a level mismatch. If the pool can't produce an exercise (e.g. no content
/// bundle), a skip affordance keeps the session from dead-ending.
private struct ShadowingDrillHost: View {
    let vocabulary: [VocabularyItem]
    let onComplete: (Grade) -> Void
    @State private var viewModel: ShadowingViewModel
    @State private var didAttemptLoad = false

    init(vocabulary: [VocabularyItem], onComplete: @escaping (Grade) -> Void) {
        self.vocabulary = vocabulary
        self.onComplete = onComplete
        _viewModel = State(initialValue: ShadowingViewModel(
            audioService: AudioService(),
            speechService: SpeechRecognitionService(),
            vocabulary: vocabulary
        ))
    }

    var body: some View {
        Group {
            if viewModel.currentExercise != nil || viewModel.loadingState.isLoading {
                ShadowingExerciseView(viewModel: viewModel, onComplete: onComplete)
            } else if didAttemptLoad {
                DrillUnavailableView { onComplete(.again) }
            } else {
                ProgressView().tint(Color.ikeruPrimaryAccent)
            }
        }
        .task {
            guard viewModel.currentExercise == nil, !didAttemptLoad else { return }
            await viewModel.loadExercise(
                difficulty: .word,
                level: vocabulary.first?.jlptLevel ?? .n5
            )
            didAttemptLoad = true
        }
    }
}

/// Owns a `ListeningViewModel` (with a fresh `AudioService`) for the lifetime of
/// one `.listeningExercise`. Loads a word-recognition exercise from the session
/// vocabulary pool on appear and forwards completion to `onComplete`. Passes an
/// EMPTY passages array so ONLY the word/meaning subtypes generate — there is no
/// passages table in the content bundle (blueprint §1.4), so passage
/// comprehension is intentionally out of scope for this pass. Falls back to a
/// skip affordance when the pool is too small to build an exercise
/// (`wordRecognition` needs ≥4 items at the level).
private struct ListeningDrillHost: View {
    let vocabulary: [VocabularyItem]
    let onComplete: (Grade) -> Void
    @State private var viewModel: ListeningViewModel
    @State private var didAttemptLoad = false

    init(vocabulary: [VocabularyItem], onComplete: @escaping (Grade) -> Void) {
        self.vocabulary = vocabulary
        self.onComplete = onComplete
        _viewModel = State(initialValue: ListeningViewModel(
            audioService: AudioService(),
            vocabulary: vocabulary,
            passages: []
        ))
    }

    var body: some View {
        Group {
            if viewModel.currentExercise != nil || viewModel.loadingState.isLoading {
                ListeningExerciseView(viewModel: viewModel, onComplete: onComplete)
            } else if didAttemptLoad {
                DrillUnavailableView { onComplete(.again) }
            } else {
                ProgressView().tint(Color.ikeruPrimaryAccent)
            }
        }
        .task {
            guard viewModel.currentExercise == nil, !didAttemptLoad else { return }
            await viewModel.loadExercise(
                type: .wordRecognition,
                level: vocabulary.first?.jlptLevel ?? .n5
            )
            didAttemptLoad = true
        }
    }
}

/// Owns one multiple-choice vocabulary-recall question for the lifetime of a
/// `.vocabularyStudy` exercise. Picks a random target from the session
/// vocabulary pool and builds its answer options ONCE (the container keeps view
/// identity stable via `.id(exercise.stableID)`, so the `@State` question
/// persists across body re-evaluations and resets only when the exercise
/// changes), then renders `VocabularyRecallView`.
///
/// XP-only completion (intentional, FSRS deferred): `.vocabularyStudy` has NO
/// backing SwiftData `Card` — vocabulary lives only in the read-only content DB
/// — so `SessionViewModel.completeCurrentExercise` awards XP for it WITHOUT
/// grading a card or writing a `ReviewLog` (the card-grade branch there is
/// gated on `.kanjiStudy`). FSRS scheduling for vocabulary waits on the
/// vocab-dictionary feature that would make vocab cards gradeable.
///
/// Falls back to `DrillUnavailableView` when the pool can't yield a full
/// question (needs ≥ N+1 distinct meanings, e.g. an empty content bundle) so
/// the session never dead-ends on a degenerate one-option question.
private struct VocabularyRecallDrillHost: View {
    let vocabulary: [VocabularyItem]
    let onComplete: (Grade) -> Void
    @State private var question: Question?

    /// A resolved recall question: the target word plus its shuffled options.
    private struct Question: Equatable {
        let target: VocabularyItem
        let options: VocabularyRecallOptions
    }

    init(vocabulary: [VocabularyItem], onComplete: @escaping (Grade) -> Void) {
        self.vocabulary = vocabulary
        self.onComplete = onComplete
        _question = State(initialValue: Self.buildQuestion(from: vocabulary))
    }

    var body: some View {
        if let question {
            VocabularyRecallView(
                target: question.target,
                options: question.options,
                onComplete: onComplete
            )
        } else {
            DrillUnavailableView { onComplete(.again) }
        }
    }

    /// Builds a full recall question from the pool, or `nil` when the pool has
    /// fewer than `defaultDistractorCount + 1` DISTINCT meanings — in that case
    /// no honest multiple-choice question can be formed, so the host shows a
    /// skip affordance instead of a degenerate 1–3 option question.
    private static func buildQuestion(from vocabulary: [VocabularyItem]) -> Question? {
        guard let target = vocabulary.randomElement() else { return nil }
        let options = VocabularyRecallOptionsBuilder.build(target: target, pool: vocabulary)
        let requiredOptionCount = VocabularyRecallOptionsBuilder.defaultDistractorCount + 1
        guard options.options.count >= requiredOptionCount else { return nil }
        return Question(target: target, options: options)
    }
}

/// Fail-safe surface shown when an audio drill can't build an exercise from the
/// session pool (e.g. the content bundle was missing so `vocabularyPool` is
/// empty, or the level has too few items). Rather than dead-ending the session
/// on a blank view, it offers a single "Continue" that completes the exercise so
/// the session advances. Graded `.again` (like the mic-denied Shadowing skip): XP-only kinds
/// ignore the grade amount, and marking an un-attempted drill "incorrect" avoids inflating the
/// session's correct-streak / accuracy stats for content the learner never actually saw.
private struct DrillUnavailableView: View {
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            Spacer()

            Image(systemName: "speaker.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(.ikeruTextSecondary)

            Text("This exercise isn't available right now")
                .font(.ikeruBody)
                .foregroundStyle(.ikeruTextSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button("Continue") {
                onSkip()
            }
            .ikeruButtonStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .padding(.bottom, IkeruTheme.Spacing.md)
        }
    }
}

// MARK: - Promote From Peek Transition

/// Matches SRSCardView.peekingCard styling (slightly smaller, offset, faded)
/// when `active == true`, identity otherwise. Both states use the same
/// concrete modifier type so `AnyTransition.modifier(active:identity:)`
/// compiles without generic-parameter conflicts.
private struct PromoteFromPeekModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(active ? 0.96 : 1.0)
            .offset(y: active ? 8 : 0)
            .opacity(active ? 0.0 : 1.0)
    }
}

extension AnyTransition {
    /// Insertion transition that animates a view from the peek position
    /// (slightly smaller, offset down, faded) to full presentation.
    /// Pairs cleanly with SRSCardView's fly-off dismissal.
    static var promoteFromPeek: AnyTransition {
        .modifier(
            active: PromoteFromPeekModifier(active: true),
            identity: PromoteFromPeekModifier(active: false)
        )
    }
}

// MARK: - ExerciseItem Stable ID

extension ExerciseItem {
    /// A stable identifier for animation purposes.
    /// Uses the exercise index position rather than content identity.
    var stableID: String {
        switch self {
        case .srsReview(let card): "srs-\(card.id)"
        case .kanjiStudy(let card): "kanji-\(card.id)"
        case .grammarExercise(let id): "grammar-\(id)"
        case .writingPractice(let card): "writing-\(card.id)"
        case .listeningExercise(let id): "listening-\(id)"
        case .speakingExercise(let id): "speaking-\(id)"
        case .sentenceConstruction(let id): "sentence-\(id)"
        case .vocabularyStudy(let id): "vocabulary-\(id)"
        case .fillInBlank(let id): "fillinblank-\(id)"
        case .readingPassage(let id): "reading-\(id)"
        }
    }
}
