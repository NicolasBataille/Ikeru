import SwiftUI
import IkeruCore

// MARK: - KanaQuizView

/// Watch kana recognition quiz with 4-choice 2x2 grid.
/// Nano-session format: 10 questions, progress dots, haptic feedback.
struct KanaQuizView: View {

    @State private var viewModel = WatchQuizViewModel()

    var body: some View {
        ZStack {
            if viewModel.isComplete {
                completionView
            } else {
                quizContent
            }
        }
        .onAppear {
            viewModel.startSession()
        }
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
            .tint(.blue)
        }
    }

    // MARK: - Helpers

    private func answerTint(for choice: KanaData.Entry) -> Color {
        guard let lastAnswer = viewModel.lastAnswerResult else { return .blue }
        guard viewModel.lastAnsweredId == choice.id else {
            // Show correct answer in green
            if !lastAnswer && choice.id == viewModel.correctId {
                return .green
            }
            return .blue
        }
        return lastAnswer ? .green : .red
    }

    private func dotColor(for index: Int) -> Color {
        if index < viewModel.currentQuestion {
            return viewModel.questionResults[index] ? .green : .red
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
