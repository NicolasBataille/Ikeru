import SwiftUI
import IkeruCore

// MARK: - VocabularyRecallView

/// Multiple-choice vocabulary recall drill (Phase 4.1 Tier-2 part 2).
///
/// Shows a Japanese word (+ reading) and 3–4 English meaning options (one
/// correct, the rest distractors drawn from OTHER session vocabulary). The
/// learner taps one; the choice locks and reveals correct/incorrect styling;
/// a single "Continue" then fires `onComplete(Grade)` exactly once.
///
/// XP-only: `.vocabularyStudy` has no backing FSRS card, so the mapped `Grade`
/// only scales the XP award (`vocabularyStudy` is `.perGrade`) — it is never
/// written to FSRS. The word/reading/meanings are runtime content from the
/// read-only content DB, so they render via the non-localizing `Text(String)`
/// overload; only the UI chrome uses `LocalizedStringKey` literals.
struct VocabularyRecallView: View {

    /// The vocabulary item being tested (the correct answer).
    let target: VocabularyItem

    /// The pre-built, pre-shuffled answer options (target + distractors) with
    /// the correct index recorded — see `VocabularyRecallOptionsBuilder`.
    let options: VocabularyRecallOptions

    /// Invoked once when the learner taps "Continue" after answering. The
    /// selected correctness is mapped to a `Grade` via
    /// `DrillGradeMapping.vocabularyRecall`. Defaults to a no-op so the
    /// standalone `#Preview` compiles; the session container routes it to
    /// `SessionViewModel.completeCurrentExercise`.
    var onComplete: (Grade) -> Void = { _ in }

    /// Index of the option the learner tapped; `nil` until they answer.
    @State private var selectedIndex: Int?

    /// Guards `onComplete` against a double-fire (two rapid Continue taps).
    @State private var didComplete = false

    private var isRevealed: Bool { selectedIndex != nil }
    private var isCorrect: Bool { selectedIndex == options.correctIndex }

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            Spacer(minLength: 0)

            wordHeader

            optionsList

            Spacer(minLength: 0)

            footer
        }
        .padding(IkeruTheme.Spacing.md)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedIndex)
        .sensoryFeedback(.success, trigger: isRevealed && isCorrect)
        .sensoryFeedback(.error, trigger: isRevealed && !isCorrect)
    }

    // MARK: - Word Header

    private var wordHeader: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Text("What does this word mean?")
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)

            // Runtime content (content DB) → non-localizing Text(String) overload.
            Text(target.japanese)
                .font(.ikeruHeading1)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(target.reading)
                .font(.ikeruBody)
                .foregroundStyle(.ikeruTextSecondary)
        }
        .padding(.vertical, IkeruTheme.Spacing.sm)
    }

    // MARK: - Options

    private var optionsList: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            ForEach(options.options.indices, id: \.self) { index in
                optionButton(index)
            }
        }
    }

    private func optionButton(_ index: Int) -> some View {
        let state = optionState(index)
        return Button {
            // Only the first tap counts; once revealed the choice is locked.
            guard selectedIndex == nil else { return }
            selectedIndex = index
        } label: {
            HStack(spacing: IkeruTheme.Spacing.sm) {
                // Runtime meaning content → non-localizing Text(String) overload.
                Text(options.options[index].meaning)
                    .font(.ikeruBody)
                    .foregroundStyle(foreground(for: state))
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                if let symbol = trailingSymbol(for: state) {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent(for: state))
                }
            }
            .padding(IkeruTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: IkeruTheme.Radius.md, style: .continuous)
                    .fill(background(for: state))
            )
            .overlay(
                RoundedRectangle(cornerRadius: IkeruTheme.Radius.md, style: .continuous)
                    .strokeBorder(border(for: state), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isRevealed)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if isRevealed {
            VStack(spacing: IkeruTheme.Spacing.sm) {
                Text(isCorrect ? "Correct!" : "Not quite")
                    .font(.ikeruHeading3)
                    .foregroundStyle(isCorrect ? Color.ikeruPrimaryAccent : Color.ikeruDanger)

                Button("Continue") {
                    complete()
                }
                .ikeruButtonStyle(.primary)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .padding(.bottom, IkeruTheme.Spacing.md)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            Text("Tap an answer")
                .ikeruScaledFont(11, weight: .semibold, relativeTo: .caption2)
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(TatamiTokens.paperGhost)
                .frame(maxWidth: .infinity)
                .padding(.bottom, IkeruTheme.Spacing.md)
                .transition(.opacity)
        }
    }

    // MARK: - Completion

    private func complete() {
        // Fire once — a rapid double tap on Continue must not double-complete
        // the exercise (which would over-advance the session).
        guard !didComplete else { return }
        didComplete = true
        onComplete(DrillGradeMapping.vocabularyRecall(isCorrect: isCorrect))
    }

    // MARK: - Option Styling

    private enum OptionState {
        case idle          // not yet answered
        case correct       // the correct answer (highlighted on reveal)
        case wrongPicked   // the learner's incorrect pick
        case dimmed        // a non-selected, non-correct option after reveal
    }

    private func optionState(_ index: Int) -> OptionState {
        guard isRevealed else { return .idle }
        if index == options.correctIndex { return .correct }
        if index == selectedIndex { return .wrongPicked }
        return .dimmed
    }

    private func accent(for state: OptionState) -> Color {
        switch state {
        case .correct: Color.ikeruPrimaryAccent
        case .wrongPicked: Color.ikeruDanger
        case .idle, .dimmed: Color.ikeruTextSecondary
        }
    }

    private func trailingSymbol(for state: OptionState) -> String? {
        switch state {
        case .correct: "checkmark.circle.fill"
        case .wrongPicked: "xmark.circle.fill"
        case .idle, .dimmed: nil
        }
    }

    private func foreground(for state: OptionState) -> Color {
        switch state {
        case .correct: Color.ikeruPrimaryAccent
        case .wrongPicked: Color.ikeruDanger
        case .dimmed: Color.ikeruTextSecondary
        case .idle: .white
        }
    }

    private func background(for state: OptionState) -> Color {
        switch state {
        case .correct: Color.ikeruPrimaryAccent.opacity(0.15)
        case .wrongPicked: Color.ikeruDanger.opacity(0.15)
        case .idle, .dimmed: Color.ikeruSurface
        }
    }

    private func border(for state: OptionState) -> Color {
        switch state {
        case .correct: Color.ikeruPrimaryAccent.opacity(0.6)
        case .wrongPicked: Color.ikeruDanger.opacity(0.6)
        case .dimmed: TatamiTokens.goldDim.opacity(0.25)
        case .idle: TatamiTokens.goldDim.opacity(0.4)
        }
    }
}

// MARK: - Preview

#Preview {
    let target = VocabularyItem(
        japanese: "猫",
        reading: "ねこ",
        meaning: "cat",
        jlptLevel: .n5
    )
    let pool = [
        target,
        VocabularyItem(japanese: "犬", reading: "いぬ", meaning: "dog", jlptLevel: .n5),
        VocabularyItem(japanese: "鳥", reading: "とり", meaning: "bird", jlptLevel: .n5),
        VocabularyItem(japanese: "魚", reading: "さかな", meaning: "fish", jlptLevel: .n5)
    ]

    return VocabularyRecallView(
        target: target,
        options: VocabularyRecallOptionsBuilder.build(target: target, pool: pool)
    )
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
