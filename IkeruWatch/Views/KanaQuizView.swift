import SwiftUI
import IkeruCore

// MARK: - KanaQuizView

/// Watch kana recognition quiz with 4-choice 2x2 grid.
/// Nano-session format: 10 questions, progress dots, haptic feedback.
struct KanaQuizView: View {

    @State private var viewModel = WatchQuizViewModel()

    var body: some View {
        ZStack {
            if !viewModel.hasSufficientPool {
                emptyStateView
            } else if viewModel.isComplete {
                completionView
            } else {
                quizContent
            }
        }
        .onAppear {
            viewModel.startSession()
        }
    }

    // MARK: - Empty State

    /// Shown when the synced eligible-kana set (chosen groups ∩ already
    /// graded at least once) has too few characters to run a session —
    /// never falls back to the full hiragana syllabary. See
    /// `WatchQuizViewModel.hasSufficientPool`.
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("Nothing to review here yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("Practice a few kana on iPhone first")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Quiz Content

    private var quizContent: some View {
        VStack(spacing: 4) {
            // Target kana display
            Text(viewModel.targetCharacter)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            // 2x2 answer grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                ForEach(viewModel.choices, id: \.id) { choice in
                    Button {
                        viewModel.selectAnswer(choice)
                    } label: {
                        Text(choice.romanization)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(answerTint(for: choice))
                }
            }

            // Correct-answer feedback (shown briefly after a wrong tap, before
            // advancing — a wrong answer without this teaches nothing).
            feedbackLine

            // Progress dots
            HStack(spacing: 3) {
                ForEach(0..<viewModel.totalQuestions, id: \.self) { index in
                    Circle()
                        .fill(dotColor(for: index))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Completion View

    private var completionView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)

            Text("\(viewModel.correctCount)/\(viewModel.totalQuestions)")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)

            Text("Nice work!")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Button("Again") {
                viewModel.startSession()
            }
            .buttonStyle(.bordered)
            .tint(IkeruPlatformTheme.gold)
        }
    }

    // MARK: - Feedback

    @ViewBuilder
    private var feedbackLine: some View {
        if let feedback = viewModel.correctAnswerFeedback {
            Text("The character for \(feedback.romaji) is \(feedback.kana)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.green)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else {
            Color.clear.frame(height: 12)
        }
    }

    // MARK: - Helpers

    private func answerTint(for choice: KanaData.Entry) -> Color {
        guard let lastAnswer = viewModel.lastAnswerResult else { return IkeruPlatformTheme.gold }
        guard viewModel.lastAnsweredId == choice.id else {
            // Show correct answer in green
            if !lastAnswer && choice.id == viewModel.correctId {
                return .green
            }
            return IkeruPlatformTheme.gold
        }
        return lastAnswer ? .green : IkeruPlatformTheme.danger
    }

    private func dotColor(for index: Int) -> Color {
        if index < viewModel.currentQuestion {
            return viewModel.questionResults[index] ? .green : IkeruPlatformTheme.danger
        } else if index == viewModel.currentQuestion {
            return .white
        }
        return .gray.opacity(0.3)
    }
}

// MARK: - Preview

#Preview {
    KanaQuizView()
}
