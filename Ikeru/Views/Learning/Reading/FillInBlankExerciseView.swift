import SwiftUI
import IkeruCore

// MARK: - FillInBlankExerciseView

/// Interactive fill-in-the-blank exercise with 4-choice grid.
/// Jade flash + success haptic for correct, vermillion flash + warning haptic for wrong.
struct FillInBlankExerciseView: View {

    @State var viewModel: VocabularyStudyViewModel

    @State private var hapticTriggerCorrect = false
    @State private var hapticTriggerIncorrect = false

    var body: some View {
        ZStack {
            Color.ikeruBackground
                .ignoresSafeArea()

            if viewModel.isExerciseSessionComplete {
                completionView
            } else if let exercise = viewModel.currentExercise {
                exerciseContent(exercise: exercise)
            }
        }
        .sensoryFeedback(.success, trigger: hapticTriggerCorrect)
        .sensoryFeedback(.warning, trigger: hapticTriggerIncorrect)
    }

    // MARK: - Exercise Content

    private func exerciseContent(exercise: FillInBlankExercise) -> some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            progressHeader

            Spacer()

            exerciseTypeBadge(exercise.exerciseType)
            sentenceCard(exercise: exercise)

            if !exercise.hint.isEmpty {
                hintView(exercise.hint)
            }

            Spacer()

            optionsGrid(exercise: exercise)

            if viewModel.isAnswered {
                nextButton
            }

            xpCounter
        }
        .padding(IkeruTheme.Spacing.md)
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
        VStack(spacing: IkeruTheme.Spacing.xs) {
            Text("\(viewModel.currentExerciseIndex + 1)/\(viewModel.exercises.count)")
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)

            ProgressView(value: viewModel.exerciseProgress)
                .tint(Color.ikeruPrimaryAccent)
        }
        .padding(.horizontal, IkeruTheme.Spacing.lg)
    }

    // MARK: - Exercise Type Badge

    private func exerciseTypeBadge(_ type: FillInBlankType) -> some View {
        Text(type.displayLabel)
            .font(.ikeruCaption)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, IkeruTheme.Spacing.sm)
            .padding(.vertical, IkeruTheme.Spacing.xs)
            .background(
                Capsule()
                    .fill(type.badgeColor.opacity(0.8))
            )
    }

    // MARK: - Sentence Card

    private func sentenceCard(exercise: FillInBlankExercise) -> some View {
        let parts = exercise.sentence.components(separatedBy: "___")
        let blankDisplay = viewModel.isAnswered
            ? (viewModel.selectedAnswer ?? "___")
            : "___"

        return VStack(spacing: IkeruTheme.Spacing.sm) {
            HStack(spacing: 0) {
                if let first = parts.first {
                    Text(first)
                        .font(.custom(
                            IkeruTheme.Typography.FontFamily.kanjiSerifMedium,
                            size: IkeruTheme.Typography.Size.heading2
                        ))
                        .foregroundStyle(Color.ikeruKanjiText)
                }

                Text(blankDisplay)
                    .font(.custom(
                        IkeruTheme.Typography.FontFamily.kanjiSerifMedium,
                        size: IkeruTheme.Typography.Size.heading2
                    ))
                    .foregroundStyle(blankColor)
                    .padding(.horizontal, IkeruTheme.Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
                            .strokeBorder(blankColor.opacity(0.5), lineWidth: 1)
                            .padding(.horizontal, -IkeruTheme.Spacing.xs)
                    )

                if parts.count > 1 {
                    Text(parts[1])
                        .font(.custom(
                            IkeruTheme.Typography.FontFamily.kanjiSerifMedium,
                            size: IkeruTheme.Typography.Size.heading2
                        ))
                        .foregroundStyle(Color.ikeruKanjiText)
                }
            }

            if viewModel.isAnswered && !viewModel.isCorrect {
                Text("Correct: \(exercise.correctAnswer)")
                    .font(.ikeruBody)
                    .foregroundStyle(Color.ikeruSuccess)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, IkeruTheme.Spacing.xl)
        .ikeruCard(.elevated)
        .overlay {
            feedbackOverlay
        }
    }

    private var blankColor: Color {
        guard viewModel.isAnswered else {
            return Color.ikeruPrimaryAccent
        }
        return viewModel.isCorrect ? Color.ikeruSuccess : Color.ikeruSecondaryAccent
    }

    // MARK: - Feedback Overlay

    @ViewBuilder
    private var feedbackOverlay: some View {
        if let feedback = viewModel.feedbackState {
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.md)
                .strokeBorder(feedback.color, lineWidth: 3)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.3), value: viewModel.feedbackState)
        }
    }

    // MARK: - Hint

    private func hintView(_ hint: String) -> some View {
        HStack(spacing: IkeruTheme.Spacing.xs) {
            Image(systemName: "lightbulb")
                .foregroundStyle(Color.ikeruPrimaryAccent)
            Text(hint)
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)
        }
    }

    // MARK: - Options Grid

    private func optionsGrid(exercise: FillInBlankExercise) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: IkeruTheme.Spacing.sm),
                GridItem(.flexible(), spacing: IkeruTheme.Spacing.sm)
            ],
            spacing: IkeruTheme.Spacing.sm
        ) {
            ForEach(exercise.options, id: \.self) { option in
                OptionButton(
                    option: option,
                    isSelected: viewModel.selectedAnswer == option,
                    isCorrectAnswer: option == exercise.correctAnswer,
                    isAnswered: viewModel.isAnswered
                ) {
                    guard !viewModel.isAnswered else { return }
                    let isCorrect = option == exercise.correctAnswer
                    if isCorrect {
                        hapticTriggerCorrect.toggle()
                    } else {
                        hapticTriggerIncorrect.toggle()
                    }
                    Task {
                        await viewModel.submitAnswer(option)
                    }
                }
            }
        }
        .padding(.horizontal, IkeruTheme.Spacing.sm)
    }

    // MARK: - Next Button

    private var nextButton: some View {
        Button("Next") {
            withAnimation(.spring(duration: IkeruTheme.Animation.standardDuration)) {
                viewModel.advanceToNextExercise()
            }
        }
        .ikeruButtonStyle(.primary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, IkeruTheme.Spacing.lg)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - XP Counter

    private var xpCounter: some View {
        HStack(spacing: IkeruTheme.Spacing.xs) {
            Image(systemName: "star.fill")
                .foregroundStyle(Color(hex: IkeruTheme.Colors.Rarity.legendary))
            Text("\(viewModel.xpEarned) XP")
                .font(.ikeruStats)
                .foregroundStyle(.white)
        }
        .padding(.bottom, IkeruTheme.Spacing.sm)
    }

    // MARK: - Completion View

    private var completionView: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.ikeruSuccess)

            Text("Exercises Complete!")
                .font(.ikeruHeading1)
                .foregroundStyle(.white)

            Text("\(viewModel.correctCount)/\(viewModel.exercises.count) correct")
                .font(.ikeruHeading3)
                .foregroundStyle(.ikeruTextSecondary)

            HStack(spacing: IkeruTheme.Spacing.xs) {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.Rarity.legendary))
                Text("+\(viewModel.xpEarned) XP earned")
                    .font(.ikeruHeading3)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
            }
        }
        .padding(IkeruTheme.Spacing.xl)
    }
}

// MARK: - OptionButton

private struct OptionButton: View {

    let option: String
    let isSelected: Bool
    let isCorrectAnswer: Bool
    let isAnswered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(option)
                .font(.custom(
                    IkeruTheme.Typography.FontFamily.kanjiSerifMedium,
                    size: IkeruTheme.Typography.Size.heading3
                ))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: IkeruTheme.Radius.md)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                )
        }
        .buttonStyle(.plain)
        .disabled(isAnswered)
    }

    private var foregroundColor: Color {
        guard isAnswered else { return .white }
        if isCorrectAnswer { return Color.ikeruSuccess }
        if isSelected { return Color.ikeruSecondaryAccent }
        return .white.opacity(0.4)
    }

    private var backgroundColor: Color {
        guard isAnswered else { return Color.ikeruSurface }
        if isCorrectAnswer { return Color.ikeruSuccess.opacity(0.15) }
        if isSelected { return Color.ikeruSecondaryAccent.opacity(0.15) }
        return Color.ikeruSurface.opacity(0.5)
    }

    private var borderColor: Color {
        guard isAnswered else { return Color.ikeruSurface }
        if isCorrectAnswer { return Color.ikeruSuccess }
        if isSelected { return Color.ikeruSecondaryAccent }
        return Color.clear
    }

    private var borderWidth: CGFloat {
        guard isAnswered else { return 0 }
        if isCorrectAnswer || isSelected { return 2 }
        return 0
    }
}

// MARK: - FillInBlankType Display Extension

extension FillInBlankType {
    var displayLabel: String {
        switch self {
        case .particle: "Particle"
        case .conjugation: "Conjugation"
        case .vocabulary: "Vocabulary"
        }
    }

    var badgeColor: Color {
        switch self {
        case .particle: Color(hex: IkeruTheme.Colors.Skills.reading)
        case .conjugation: Color(hex: IkeruTheme.Colors.Skills.writing)
        case .vocabulary: Color(hex: IkeruTheme.Colors.Skills.listening)
        }
    }
}
