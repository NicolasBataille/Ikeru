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

    /// The next card for peek/pre-load.
    let nextCard: CardDTO?

    /// Feedback state for correct/incorrect overlay.
    let feedbackState: FeedbackState?

    @Namespace private var exerciseAnimation

    var body: some View {
        ZStack {
            if let exercise {
                exerciseView(for: exercise)
                    .matchedGeometryEffect(id: "exerciseCard", in: exerciseAnimation)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )
                    .id(exercise.stableID)
            } else {
                emptyStateView
            }
        }
        .animation(
            .spring(duration: 0.4, bounce: 0.15),
            value: exercise?.stableID
        )
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
                    nextCard: nextCard
                ) { direction in
                    onSwipeGrade(direction)
                }
                .padding(.horizontal, IkeruTheme.Spacing.lg)
                .overlay {
                    feedbackOverlay
                }

                Spacer()

                GradeButtonsView { grade in
                    onButtonGrade(grade)
                }
                .padding(.horizontal, IkeruTheme.Spacing.md)
                .padding(.bottom, IkeruTheme.Spacing.md)
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
        }
    }
}
