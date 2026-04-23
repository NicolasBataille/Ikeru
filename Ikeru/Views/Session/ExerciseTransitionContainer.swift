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

    /// The current card for SRS review exercises.
    let currentCard: CardDTO?

    /// Upcoming cards (up to 3). The deck view renders a peek for each.
    let upcomingCards: [CardDTO]

    /// Feedback state for correct/incorrect overlay.
    let feedbackState: FeedbackState?

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

        case .kanjiStudy(let character):
            placeholderExerciseView(
                icon: sfSymbol(for: .reading),
                title: "Kanji Study",
                detail: character,
                skill: .reading
            )

        case .grammarExercise:
            placeholderExerciseView(
                icon: sfSymbol(for: .reading),
                title: "Grammar Exercise",
                detail: "Grammar point",
                skill: .reading
            )

        case .writingPractice(let text):
            placeholderExerciseView(
                icon: sfSymbol(for: .writing),
                title: "Writing Practice",
                detail: text,
                skill: .writing
            )

        case .listeningExercise:
            placeholderExerciseView(
                icon: sfSymbol(for: .listening),
                title: "Listening Exercise",
                detail: "Listen and respond",
                skill: .listening
            )

        case .speakingExercise:
            placeholderExerciseView(
                icon: sfSymbol(for: .speaking),
                title: "Speaking Exercise",
                detail: "Speak the phrase",
                skill: .speaking
            )

        case .sentenceConstruction:
            placeholderExerciseView(
                icon: sfSymbol(for: .writing),
                title: "Sentence Construction",
                detail: "Arrange words to form a sentence",
                skill: .writing
            )

        case .vocabularyStudy:
            placeholderExerciseView(
                icon: sfSymbol(for: .reading),
                title: "Vocabulary Study",
                detail: "Learn new vocabulary",
                skill: .reading
            )

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
                    revealCallToAction
                        .padding(.horizontal, IkeruTheme.Spacing.md)
                        .padding(.bottom, IkeruTheme.Spacing.md)
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isRevealed)
        }
    }

    // MARK: - Reveal Call To Action

    private var revealCallToAction: some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                isRevealed = true
            }
        } label: {
            Text("Show answer")
                .frame(maxWidth: .infinity)
        }
        .ikeruButtonStyle(.primary)
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
        case .kanjiStudy(let char): "kanji-\(char)"
        case .grammarExercise(let id): "grammar-\(id)"
        case .writingPractice(let text): "writing-\(text)"
        case .listeningExercise(let id): "listening-\(id)"
        case .speakingExercise(let id): "speaking-\(id)"
        case .sentenceConstruction(let id): "sentence-\(id)"
        case .vocabularyStudy(let id): "vocabulary-\(id)"
        case .fillInBlank(let id): "fillinblank-\(id)"
        case .readingPassage(let id): "reading-\(id)"
        }
    }
}
