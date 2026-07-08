import SwiftUI
import IkeruCore

// MARK: - VocabularyQuizView

/// 4-choice meaning recognition quiz for personal dictionary words.
struct VocabularyQuizView: View {

    @Environment(\.dismiss) private var dismiss
    @State var viewModel: VocabularyDrillViewModel
    @State private var feedbackTrigger: Int = 0
    @State private var errorTrigger: Int = 0

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            if viewModel.sessionEnded {
                drillSummary
            } else {
                content
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Quiz")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
            }
        }
        .sensoryFeedback(.success, trigger: feedbackTrigger)
        .sensoryFeedback(.error, trigger: errorTrigger)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.isAnswered)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.currentIndex)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            topBar
            Spacer(minLength: 0)
            if let entry = viewModel.currentEntry {
                VStack(spacing: IkeruTheme.Spacing.sm) {
                    Text(entry.word)
                        .font(.system(size: 80, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ikeruTextPrimary)
                        .contentTransition(.numericText())

                    Text(entry.reading)
                        .ikeruScaledFont(20, weight: .medium, design: .rounded, relativeTo: .title3)
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                }
            }
            Spacer(minLength: 0)
            optionsGrid
            feedback
            actionButton
            accuracyBar
        }
        .padding(.horizontal, IkeruTheme.Spacing.lg)
        .padding(.bottom, 88)
    }

    private var topBar: some View {
        HStack {
            Text("\(viewModel.currentIndex + 1) / \(viewModel.queue.count)")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay { Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.5), lineWidth: 0.5) }
                }
                .sumiCorners(color: TatamiTokens.goldDim, size: 6, weight: 1.1)
            Spacer()
            Text("VOCABULARY")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruPrimaryAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Rectangle()
                        .fill(Color.ikeruPrimaryAccent.opacity(0.10))
                        .overlay { Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.4), lineWidth: 0.5) }
                }
                .sumiCorners(color: TatamiTokens.goldDim, size: 6, weight: 1.1)
        }
        .padding(.top, IkeruTheme.Spacing.sm)
    }

    // MARK: - Options

    private var optionsGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(viewModel.quizOptions, id: \.self) { option in
                optionButton(option)
            }
        }
    }

    @ViewBuilder
    private func optionButton(_ option: String) -> some View {
        let isSelected = viewModel.selectedOption == option
        let isCorrect = option == viewModel.correctOption
        let answered = viewModel.isAnswered

        let isHighlightedCorrect = answered && isCorrect
        let isHighlightedWrong = answered && isSelected && !isCorrect
        let cornerColor: Color = {
            if !answered { return isSelected ? Color.ikeruPrimaryAccent : TatamiTokens.goldDim }
            if isCorrect { return Color.ikeruPrimaryAccent }
            if isSelected { return Color.ikeruDanger.opacity(0.7) }
            return TatamiTokens.goldDim.opacity(0.3)
        }()

        Button {
            viewModel.selectOption(option)
        } label: {
            Text(option)
                .ikeruScaledFont(16, weight: .medium, relativeTo: .body)
                .foregroundStyle(isHighlightedCorrect ? Color(red: 0.102, green: 0.078, blue: 0.055) : Color.ikeruTextPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 76)
                .padding(.horizontal, 8)
                .background {
                    if isHighlightedCorrect {
                        LinearGradient.ikeruGold
                    } else if isHighlightedWrong {
                        ZStack {
                            Rectangle().fill(.ultraThinMaterial)
                            Rectangle().fill(Color.ikeruDanger.opacity(0.22))
                        }
                    } else {
                        ZStack {
                            Rectangle().fill(.ultraThinMaterial)
                            Rectangle().fill(isSelected ? Color.ikeruPrimaryAccent.opacity(0.18) : Color.white.opacity(0.05))
                        }
                    }
                }
                .overlay {
                    Rectangle().strokeBorder(cornerColor.opacity(answered ? 1.0 : 0.5), lineWidth: answered ? 1.0 : 0.5)
                }
                .sumiCorners(color: cornerColor, size: 8, weight: 1.2)
        }
        .buttonStyle(.plain)
        .disabled(answered)
        .scaleEffect(isSelected && !answered ? 0.97 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isSelected)
    }

    // MARK: - Feedback

    @ViewBuilder
    private var feedback: some View {
        if viewModel.isAnswered {
            let isCorrect = viewModel.selectedOption == viewModel.correctOption
            HStack(spacing: 8) {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isCorrect ? Color.ikeruPrimaryAccent : Color.ikeruDanger)
                if isCorrect {
                    Text("Correct!")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextPrimary)
                } else {
                    Text("The answer is: \(viewModel.correctOption)")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background {
                Rectangle().fill(.ultraThinMaterial)
                    .overlay { Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.3), lineWidth: 0.5) }
            }
            .sumiCorners(color: TatamiTokens.goldDim, size: 6, weight: 1.0)
            .transition(.opacity)
        } else {
            Color.clear.frame(height: 44)
        }
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Button {
            if viewModel.isAnswered {
                viewModel.advance()
            } else {
                Task {
                    let correctBefore = viewModel.correctCount
                    await viewModel.submitQuizAnswer()
                    if viewModel.correctCount > correctBefore {
                        feedbackTrigger &+= 1
                    } else {
                        errorTrigger &+= 1
                    }
                }
            }
        } label: {
            Text(viewModel.isAnswered ? "Next" : "Submit")
                .frame(maxWidth: .infinity)
        }
        .ikeruButtonStyle(.primary)
        .disabled(viewModel.selectedOption == nil)
        .opacity(viewModel.selectedOption == nil ? 0.5 : 1.0)
    }

    // MARK: - Accuracy Bar

    private var accuracyBar: some View {
        let total = max(viewModel.correctCount + viewModel.wrongCount, 1)
        let pct = Double(viewModel.correctCount) / Double(total)
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(TatamiTokens.goldDim.opacity(0.25))
                        .frame(height: 2)
                    Rectangle()
                        .fill(Color.ikeruPrimaryAccent)
                        .frame(width: proxy.size.width * pct, height: 2)
                        .animation(.easeOut(duration: 0.4), value: pct)
                }
                .frame(height: 2)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 2)
            Text("\(viewModel.correctCount) / \(viewModel.correctCount + viewModel.wrongCount) correct")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
        }
        .padding(.top, 4)
    }

    // MARK: - Summary

    private var drillSummary: some View {
        VocabularyDrillSummary(
            correct: viewModel.correctCount,
            wrong: viewModel.wrongCount,
            duration: Date().timeIntervalSince(viewModel.startedAt),
            onContinue: { dismiss() },
            onRestart: { viewModel.restart() }
        )
    }
}
