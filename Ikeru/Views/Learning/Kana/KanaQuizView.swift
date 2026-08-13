import SwiftUI
import IkeruCore

// MARK: - KanaQuizView

/// 4-choice romaji recognition quiz, Sottaku-inspired with pedagogical
/// teaching moments on wrong answers.
struct KanaQuizView: View {

    @Environment(\.dismiss) private var dismiss
    @State var viewModel: KanaDrillViewModel
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
                KanaDrillSessionSummary(
                    correct: viewModel.correctCount,
                    wrong: viewModel.wrongCount,
                    duration: Date().timeIntervalSince(viewModel.startedAt),
                    onContinue: { dismiss() },
                    onRestart: { viewModel.restart() }
                )
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

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            topBar
            hiraganaBridgeHint
            Spacer(minLength: 0)
            if let card = viewModel.currentCard {
                Text(card.front)
                    .font(.system(size: 140, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            optionsGrid
            feedback
            actionButton
            accuracyBar
        }
        .padding(.horizontal, IkeruTheme.Spacing.lg)
        .padding(.bottom, 88) // Floating tab bar clearance
    }

    private var topBar: some View {
        HStack {
            Text("\(viewModel.currentIndex + 1) / \(viewModel.queue.count)")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.ikeruSurface.opacity(0.6))
                .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.5), lineWidth: 1))
                .sumiCorners(color: TatamiTokens.goldDim, size: 5, weight: 1.0)
            Spacer()
            Text(viewModel.sessionLabel ?? LocalizedStringKey(viewModel.mode.displayName))
                .textCase(.uppercase)
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruPrimaryAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.ikeruPrimaryAccent.opacity(0.10))
                .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.5), lineWidth: 1))
                .sumiCorners(color: TatamiTokens.goldDim, size: 5, weight: 1.0)
        }
        .padding(.top, IkeruTheme.Spacing.sm)
    }

    // MARK: Hiragana bridge hint (chantier #24a)
    //
    // "Même son, nouvelle forme": the first time a katakana card is seen
    // (masteryLevel == .new), show its hiragana counterpart grayed out above
    // the quiz glyph, so the new shape reads as a variant of something
    // already known rather than a completely unrelated character.

    @ViewBuilder
    private var hiraganaBridgeHint: some View {
        if let bridge = viewModel.hiraganaBridgeCharacter {
            HStack(spacing: 8) {
                Text(bridge.character)
                    .font(.system(size: 22, weight: .light, design: .serif))
                    .foregroundStyle(Color.ikeruTextTertiary.opacity(0.6))
                Text("Kana.HiraganaBridge.Caption")
                    .font(.ikeruMicro)
                    .foregroundStyle(Color.ikeruTextTertiary)
            }
            .transition(.opacity)
        }
    }

    // MARK: Options

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

        let cornerColor: Color = {
            if !answered { return isSelected ? Color.ikeruPrimaryAccent : TatamiTokens.goldDim }
            if isCorrect { return Color.ikeruPrimaryAccent }
            if isSelected { return Color.ikeruError.opacity(0.7) }
            return TatamiTokens.goldDim.opacity(0.3)
        }()

        Button {
            viewModel.selectOption(option)
        } label: {
            Text(option)
                .ikeruScaledFont(28, weight: .semibold, design: .rounded, relativeTo: .title2)
                .foregroundStyle(Color.ikeruTextPrimary)
                .frame(maxWidth: .infinity, minHeight: 76)
                .background {
                    if answered && isCorrect {
                        LinearGradient.ikeruGold
                    } else if answered && isSelected {
                        ZStack {
                            Rectangle().fill(.ultraThinMaterial)
                            Rectangle().fill(Color.ikeruError.opacity(0.22))
                        }
                    } else if isSelected {
                        ZStack {
                            Rectangle().fill(.ultraThinMaterial)
                            Rectangle().fill(Color.ikeruPrimaryAccent.opacity(0.18))
                        }
                    } else {
                        ZStack {
                            Rectangle().fill(.ultraThinMaterial)
                            Rectangle().fill(Color(red: 0.102, green: 0.102, blue: 0.133).opacity(0.6))
                        }
                    }
                }
                .sumiCorners(color: cornerColor, size: 8, weight: 1.2)
        }
        .buttonStyle(.plain)
        .disabled(answered)
        .scaleEffect(isSelected && !answered ? 0.97 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isSelected)
    }

    // MARK: Feedback

    @ViewBuilder
    private var feedback: some View {
        if viewModel.isAnswered {
            let isCorrect = viewModel.selectedOption == viewModel.correctOption
            HStack(spacing: 8) {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isCorrect ? Color.ikeruPrimaryAccent : Color.ikeruError)
                if isCorrect {
                    Text("Correct!")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextPrimary)
                } else if let wrongRomaji = viewModel.selectedOption,
                          let kana = viewModel.selectedOptionCharacter {
                    Text("The character for \(wrongRomaji) is \(kana)")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                } else {
                    Text("Try again")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Rectangle().fill(.ultraThinMaterial))
            .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.4), lineWidth: 1))
            .sumiCorners(color: TatamiTokens.goldDim, size: 6, weight: 1.0)
            .transition(.opacity)
        } else {
            Color.clear.frame(height: 44)
        }
    }

    // MARK: Action

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

    // MARK: Accuracy bar

    private var accuracyBar: some View {
        let total = max(viewModel.correctCount + viewModel.wrongCount, 1)
        let pct = Double(viewModel.correctCount) / Double(total)
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(TatamiTokens.goldDim.opacity(0.25))
                    Rectangle()
                        .fill(Color.ikeruPrimaryAccent)
                        .frame(width: proxy.size.width * pct)
                        .animation(.easeOut(duration: 0.4), value: pct)
                }
            }
            .frame(height: 2)
            Text("\(viewModel.correctCount) / \(viewModel.correctCount + viewModel.wrongCount) correct")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
        }
        .padding(.top, 4)
    }
}
