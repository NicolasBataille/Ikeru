import SwiftUI
import IkeruCore

// MARK: - InlineQuizView

/// Mini-quiz embedded in a chat bubble with multiple choice options.
struct InlineQuizView: View {

    let character: String
    let correctAnswer: String
    let options: [String]

    @State private var selectedAnswer: String?
    @State private var hasAnswered = false

    var body: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            quizHeader
            optionButtons
            if hasAnswered {
                resultText
            }
        }
        .padding(IkeruTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
                .fill(Color(hex: IkeruTheme.Colors.surface, opacity: 0.6))
        }
        .padding(.vertical, IkeruTheme.Spacing.xs)
    }

    // MARK: - Header

    @ViewBuilder
    private var quizHeader: some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            Text(character)
                .font(.custom(
                    IkeruTheme.Typography.FontFamily.kanjiSerif,
                    size: IkeruTheme.Typography.Size.heading2
                ))
                .foregroundStyle(Color(hex: IkeruTheme.Colors.primaryAccent))

            Image(systemName: "questionmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color(hex: IkeruTheme.Colors.secondaryAccent))

            Text("Quick Quiz")
                .font(.ikeruCaption)
                .foregroundStyle(Color(hex: IkeruTheme.Colors.secondaryAccent))
        }
    }

    // MARK: - Options

    @ViewBuilder
    private var optionButtons: some View {
        VStack(spacing: IkeruTheme.Spacing.xs) {
            ForEach(options, id: \.self) { option in
                Button {
                    selectAnswer(option)
                } label: {
                    HStack {
                        Text(option)
                            .font(.ikeruCaption)
                            .foregroundStyle(optionTextColor(for: option))

                        Spacer()

                        if hasAnswered {
                            optionIcon(for: option)
                        }
                    }
                    .padding(.horizontal, IkeruTheme.Spacing.sm)
                    .padding(.vertical, IkeruTheme.Spacing.xs + 2)
                    .background {
                        RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
                            .fill(optionBackground(for: option))
                    }
                }
                .buttonStyle(.plain)
                .disabled(hasAnswered)
            }
        }
    }

    // MARK: - Result

    @ViewBuilder
    private var resultText: some View {
        let isCorrect = selectedAnswer == correctAnswer
        Text(isCorrect ? "Correct! Well done!" : "Not quite. The answer is: \(correctAnswer)")
            .font(.ikeruCaption)
            .foregroundStyle(
                isCorrect
                    ? Color(hex: IkeruTheme.Colors.success)
                    : Color(hex: IkeruTheme.Colors.secondaryAccent)
            )
    }

    // MARK: - Helpers

    private func selectAnswer(_ answer: String) {
        guard !hasAnswered else { return }
        selectedAnswer = answer
        withAnimation(.easeInOut(duration: IkeruTheme.Animation.quickDuration)) {
            hasAnswered = true
        }
    }

    private func optionTextColor(for option: String) -> Color {
        guard hasAnswered else {
            return Color(hex: IkeruTheme.Colors.kanjiText)
        }

        if option == correctAnswer {
            return Color(hex: IkeruTheme.Colors.success)
        }

        if option == selectedAnswer {
            return Color(hex: IkeruTheme.Colors.secondaryAccent)
        }

        return .ikeruTextSecondary
    }

    private func optionBackground(for option: String) -> Color {
        guard hasAnswered else {
            return Color(hex: IkeruTheme.Colors.background, opacity: 0.4)
        }

        if option == correctAnswer {
            return Color(hex: IkeruTheme.Colors.success, opacity: 0.15)
        }

        if option == selectedAnswer, option != correctAnswer {
            return Color(hex: IkeruTheme.Colors.secondaryAccent, opacity: 0.15)
        }

        return Color(hex: IkeruTheme.Colors.background, opacity: 0.2)
    }

    @ViewBuilder
    private func optionIcon(for option: String) -> some View {
        if option == correctAnswer {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color(hex: IkeruTheme.Colors.success))
        } else if option == selectedAnswer {
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color(hex: IkeruTheme.Colors.secondaryAccent))
        }
    }
}

// MARK: - Preview

#Preview("InlineQuizView") {
    ZStack {
        Color(hex: IkeruTheme.Colors.background).ignoresSafeArea()

        InlineQuizView(
            character: "食",
            correctAnswer: "to eat",
            options: ["to eat", "to drink", "to read"]
        )
        .padding()
    }
    .preferredColorScheme(.dark)
}
