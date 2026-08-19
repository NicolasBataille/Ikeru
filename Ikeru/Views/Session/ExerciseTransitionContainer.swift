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

    /// Les exercices de grammaire a trou du bundle. Vide sur un bundle
    /// anterieur au generateur — l'hote affiche alors l'echappatoire.
    var grammarClozes: [GrammarCloze] = []

    /// Profile retention snapshotted by the session — powers the per-card
    /// predicted intervals under the grade buttons.
    var desiredRetention: Double = 0.9

    /// Whether the current `.srsReview` exercise is a brand-new kana card's
    /// ungraded presentation pass (see `SessionViewModel.isPresentingNewCard`)
    /// rather than a normal graded touch-and-reveal test. Branches
    /// `srsReviewView` to `NewCardPresentationView`.
    var isPresentingNewCard: Bool = false

    /// Forwarded so the presentation view's auto-advance timer can pause
    /// itself while the session is paused, instead of ticking silently
    /// under the pause overlay (`ActiveSessionView.pauseOverlay`).
    var isPaused: Bool = false

    /// Callback when the user's new-card presentation pass auto-advances
    /// (or the user replays the audio, which does NOT call this — only the
    /// auto-advance timer does). Routes to
    /// `SessionViewModel.completeNewCardPresentation`, which writes no FSRS
    /// grade.
    var onPresentationAcknowledged: () -> Void = {}

    @Namespace private var exerciseAnimation
    @State private var isRevealed = false

    /// Read-only content repository used ONLY to fetch kana stroke-trace data
    /// for `NewCardPresentationView` (see below). Built once per process via
    /// `static let` (not `@State`) — `ActiveSessionView` re-renders this
    /// container on every elapsed-time timer tick, and a `@State` initial
    /// value re-evaluates on every construction, which would open (lazily,
    /// harmlessly, but pointlessly) a fresh actor each time.
    ///
    /// This is a SECOND connection to the same bundled `n5-content.sqlite`
    /// that `SessionViewModel` already opens for the vocabulary pool — that
    /// repository is `private` to `SessionViewModel` and threading it down
    /// here would mean editing `SessionViewModel`/`ActiveSessionView`, outside
    /// this pass's scope. Mirrors the existing per-screen pattern already
    /// used by `HomeView.makeContentRepository()` / `EtudeView.makeContentRepository()`
    /// — read-only bundle, so a second connection is redundant but not unsafe.
    private static let kanaContentRepository: ContentRepository? = BundledContent.makeRepository()

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
            GrammarClozeDrillHost(clozes: grammarClozes, onComplete: onExerciseComplete)

        case .writingPractice(let card):
            // Writing practice reuses the same handwriting drill and, like
            // .kanjiStudy, writes a REAL FSRS grade for its backing card (via
            // SessionViewModel.completeCurrentExercise → gradeCard). XP is also
            // awarded (.perCompletion, grade-independent).
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
            if isPresentingNewCard {
                // `.id(card.id)` is load-bearing, not decoration: when a
                // foundation-mode session introduces several new kana in a
                // row (the common day-one shape — no due reviews, several
                // intros back to back), consecutive intros stay in this SAME
                // if-branch with no other structural change, so WITHOUT this
                // id SwiftUI reuses the same `NewCardPresentationView`
                // instance across cards. Its `.task` (autoplay, no id) would
                // then never re-run for card #2+, and its `.task(id: isPaused)`
                // auto-advance timer would never re-arm either (`isPaused`
                // didn't change) — card #2 would sit silent and stuck
                // forever, with no button and no swipe to escape it. Forcing
                // a fresh identity per card makes both `.task`s fire again on
                // every card, intro or not.
                NewCardPresentationView(
                    card: card,
                    isPaused: isPaused,
                    onAcknowledged: onPresentationAcknowledged,
                    contentRepository: Self.kanaContentRepository
                )
                .id(card.id)
            } else {
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
                    GradeButtonsView(
                        onGrade: { grade in
                            onButtonGrade(grade)
                        },
                        predictedIntervals: computePredictedIntervals(
                            fsrsState: card.fsrsState,
                            now: Date(),
                            desiredRetention: desiredRetention
                        )
                    )
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

// MARK: - New Card Presentation

/// Ungraded "presentation" pass for a brand-new kana card the learner has
/// never seen before: the glyph, its romaji reading (visible immediately —
/// no reveal tap), and the pronunciation played automatically. No grading
/// affordance — ON RENCONTRE, on n'évalue pas (2026-08 pedagogy review,
/// "erreur de conception #1": grading a touch-and-reveal test on unseen
/// material produces a first FSRS note that's noise, not signal). A tap
/// anywhere replays the audio; the view advances on its own after
/// `autoAdvanceSeconds` — no button, no added tap versus today's flow (see
/// `SessionViewModel.completeNewCardPresentation`, called only by the
/// auto-advance timer here, never by the tap).
///
/// Reuses the SAME `ikeru.audio.autoplay` `@AppStorage` key `SRSCardView`
/// already gates its reveal-autoplay on, rather than introducing a second
/// audio-preference flag.
///
/// **Stroke-order trace**: plays ONCE, automatically, as a motor-encoding
/// reinforcement — not a drill. No tap, no grade, no button; it reuses the
/// SAME rendering engine `KanjiDisplayView` already drives for kanji
/// (`StrokeOrderViewModel` + `StrokeOrderView`), just fed kana SVG data from
/// `ContentRepository.kanaStrokeData(for:)`. Covers 142 of the 208 kana
/// catalogue characters (92 base + 50 dakuten); the 66 yōon digraphs
/// (きゃ, etc.) have no KanjiVG file for a two-codepoint combination, so the
/// lookup returns `nil` and the trace view is simply omitted — no reserved
/// frame, no placeholder, no dead affordance. The fetch runs in its own
/// `.task`, independent of the audio-autoplay and auto-advance tasks below,
/// so a slow or missing trace never delays the card's appearance, its audio,
/// or its 18s auto-advance.
///
/// **Mnemonic link**: `MnemonicService` (IkeruCore) exists but is
/// kanji/radical-oriented and isn't injected into `SessionViewModel`'s
/// dependency graph — wiring that reaches outside this pass's file scope.
/// Left unwired rather than half-wired; no dead "tip" button is shown.
private struct NewCardPresentationView: View {
    let card: CardDTO
    let isPaused: Bool
    let onAcknowledged: () -> Void
    /// `nil` when the bundle couldn't be resolved (see
    /// `ExerciseTransitionContainer.kanaContentRepository`) — the trace
    /// section just never appears in that case, same as a yōon lookup miss.
    let contentRepository: ContentRepository?

    @State private var audioService = AudioService()
    @State private var strokeOrderViewModel = StrokeOrderViewModel()
    @AppStorage("ikeru.audio.autoplay") private var isAudioAutoplayEnabled: Bool = true

    /// ~15-20s per the pedagogy review's "CARTE DE PRESENTATION" spec — long
    /// enough to read the glyph, hear it, and register the romaji before the
    /// card moves on by itself.
    private static let autoAdvanceSeconds: Double = 18

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            Spacer()

            Text("MEETING A NEW CHARACTER", comment: "Kicker above a brand-new kana's presentation card — there is nothing to answer here, only to notice")
                .ikeruScaledFont(11, weight: .semibold, relativeTo: .caption2)
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(Color.ikeruTextTertiary)

            Text(card.front)
                .font(.system(size: 180, weight: .light, design: .serif))
                .foregroundStyle(Color.ikeruTextPrimary)
                .shadow(color: Color.ikeruPrimaryAccent.opacity(0.25), radius: 32, y: 4)
                .minimumScaleFactor(0.4)
                .lineLimit(1)

            Text(card.back)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.ikeruPrimaryAccent)

            // Kana stroke-order trace: only appears once fetched (or never,
            // for a yōon digraph / missing bundle) — see the type's doc
            // comment. No fixed frame reserved for the absent case, so there
            // is no visual hole while it's missing or still loading.
            if let strokeData = strokeOrderViewModel.strokeData {
                StrokeOrderView(
                    strokeData: strokeData,
                    speed: .normal,
                    isPlaying: strokeOrderViewModel.isAnimating,
                    // Once the one-shot pass finishes, force the "fully
                    // drawn" guide color for every stroke instead of the
                    // view model's resting index (which sits ON the last
                    // stroke, rendering it at 0.1 opacity per
                    // `StrokeOrderView.guideColor` — fine for
                    // `KanjiDisplayView`'s tap-to-dismiss flow, but wrong
                    // here where the trace stays on screen for the
                    // remainder of the ~18s card).
                    currentStrokeIndex: strokeOrderViewModel.isAnimating
                        ? strokeOrderViewModel.currentStrokeIndex
                        : strokeData.strokes.count,
                    onStrokeCompleted: {
                        strokeOrderViewModel.advanceAnimationStroke()
                    }
                )
                .frame(width: 120, height: 120)
                .transition(.opacity)
            }

            Spacer()

            Text("Tap to hear it again", comment: "Hint under a new-card presentation card — tapping replays the audio; the card advances on its own after a few seconds")
                .ikeruScaledFont(11, weight: .semibold, relativeTo: .caption2)
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(TatamiTokens.paperGhost)
                .padding(.bottom, IkeruTheme.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, IkeruTheme.Spacing.lg)
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await audioService.playTTS(text: card.front) }
        }
        .task {
            guard isAudioAutoplayEnabled else { return }
            await audioService.playTTS(text: card.front)
        }
        // Independent of the audio task above: a missing/slow trace must
        // never delay the audio or the auto-advance timer. Unkeyed, like
        // the audio `.task` — this view already gets a fresh identity per
        // card via `.id(card.id)` in the parent, so it re-runs per card
        // without needing an explicit `id:`. Deliberately NOT gated on
        // `isPaused`: the trace is a few seconds of non-interactive
        // reinforcement, not a timer the learner can get stuck behind, so
        // pausing mid-trace just leaves it visually frozen rather than
        // needing its own pause/resume bookkeeping.
        .task {
            guard let contentRepository else { return }
            guard let result = await contentRepository.kanaStrokeData(for: card.front) else { return }
            await strokeOrderViewModel.loadStrokes(for: card.front, svgData: result.svg)
            strokeOrderViewModel.startAnimation()
        }
        .animation(.easeIn(duration: 0.3), value: strokeOrderViewModel.strokeData)
        // Keyed on `isPaused`: flipping it cancels whatever sleep is in
        // flight and restarts this task. Paused → returns immediately
        // (timer stops dead, nothing advances under the pause overlay).
        // Resumed → a FRESH full-length sleep starts (no partial-countdown
        // bookkeeping needed for a single ungraded intro step).
        .task(id: isPaused) {
            guard !isPaused else { return }
            try? await Task.sleep(for: .seconds(Self.autoAdvanceSeconds))
            guard !Task.isCancelled else { return }
            onAcknowledged()
        }
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
/// Tire une question a trou parmi celles du bundle et construit ses options.
///
/// Comme les autres hotes, il ne pose une question que s'il peut en poser une
/// honnete : deux propositions au minimum. Sous ce seuil il montre
/// `DrillUnavailableView` plutot qu'un QCM a un seul choix.
private struct GrammarClozeDrillHost: View {
    let clozes: [GrammarCloze]
    let onComplete: (Grade) -> Void
    @State private var question: Question?

    private struct Question: Equatable {
        let cloze: GrammarCloze
        let options: GrammarClozeOptions
    }

    init(clozes: [GrammarCloze], onComplete: @escaping (Grade) -> Void) {
        self.clozes = clozes
        self.onComplete = onComplete
        _question = State(initialValue: Self.buildQuestion(from: clozes))
    }

    var body: some View {
        if let question {
            GrammarClozeView(
                cloze: question.cloze,
                options: question.options,
                onComplete: onComplete
            )
        } else {
            DrillUnavailableView { onComplete(.again) }
        }
    }

    private static func buildQuestion(from clozes: [GrammarCloze]) -> Question? {
        guard let target = clozes.randomElement() else { return nil }
        let pool = clozes.map(\.answer).filter { $0 != target.answer }
        let options = GrammarClozeOptionsBuilder.build(answer: target.answer, pool: pool)
        guard options.options.count >= 2 else { return nil }
        return Question(cloze: target, options: options)
    }
}

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
