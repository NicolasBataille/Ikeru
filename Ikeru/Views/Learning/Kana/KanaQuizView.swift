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
                .background { Capsule().fill(.ultraThinMaterial) }
            Spacer()
            Text(viewModel.mode.displayName.uppercased())
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruPrimaryAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background { Capsule().fill(Color.ikeruPrimaryAccent.opacity(0.10)) }
        }
        .padding(.top, IkeruTheme.Spacing.sm)
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

        let fill: Color = {
            if !answered { return isSelected ? Color.ikeruPrimaryAccent.opacity(0.18) : Color.white.opacity(0.05) }
            if isCorrect { return Color(red: 0.30, green: 0.70, blue: 0.45).opacity(0.30) }
            if isSelected { return Color(red: 0.85, green: 0.30, blue: 0.30).opacity(0.30) }
            return Color.white.opacity(0.04)
        }()

        let stroke: Color = {
            if !answered { return isSelected ? Color.ikeruPrimaryAccent : Color.white.opacity(0.18) }
            if isCorrect { return Color(red: 0.30, green: 0.70, blue: 0.45) }
            if isSelected { return Color(red: 0.85, green: 0.30, blue: 0.30) }
            return Color.white.opacity(0.10)
        }()

        Button {
            viewModel.selectOption(option)
        } label: {
            Text(option)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.ikeruTextPrimary)
                .frame(maxWidth: .infinity, minHeight: 76)
                .background {
                    RoundedRectangle(cornerRadius: IkeruTheme.Radius.md, style: .continuous).fill(fill)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: IkeruTheme.Radius.md, style: .continuous)
                        .strokeBorder(stroke, lineWidth: 1.0)
                }
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
                    .foregroundStyle(isCorrect ? Color(red: 0.30, green: 0.70, blue: 0.45) : Color(red: 0.85, green: 0.30, blue: 0.30))
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
            .background {
                RoundedRectangle(cornerRadius: IkeruTheme.Radius.md, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
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
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(Color(red: 0.30, green: 0.70, blue: 0.45))
                        .frame(width: proxy.size.width * pct)
                        .animation(.easeOut(duration: 0.4), value: pct)
                }
            }
            .frame(height: 6)
            Text("\(viewModel.correctCount) / \(viewModel.correctCount + viewModel.wrongCount) correct")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
        }
        .padding(.top, 4)
    }
}
