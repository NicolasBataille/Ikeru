import SwiftUI
import IkeruCore

// MARK: - SentenceConstructionView

/// Sentence construction exercise where the learner arranges shuffled tokens
/// to form a correct Japanese sentence.
struct SentenceConstructionView: View {

    @Bindable var viewModel: SentenceConstructionViewModel
    @Namespace private var tokenAnimation

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            // Translation prompt
            translationHeader

            // Arranged tokens drop zone
            arrangedArea

            // Available tokens
            availableArea

            // Action buttons
            actionButtons

            // Feedback section
            if viewModel.exercisePhase == .feedback {
                feedbackSection
            }
        }
        .padding(IkeruTheme.Spacing.md)
        .sensoryFeedback(.success, trigger: viewModel.feedbackState == .correct)
        .sensoryFeedback(.error, trigger: viewModel.feedbackState == .incorrect)
    }

    // MARK: - Translation Header

    @ViewBuilder
    private var translationHeader: some View {
        if let exercise = viewModel.currentExercise {
            VStack(spacing: IkeruTheme.Spacing.sm) {
                Text("Construct the sentence")
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruTextSecondary)

                Text(exercise.translation)
                    .font(.ikeruHeading2)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(exercise.reading)
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruTextSecondary)
            }
            .padding(.vertical, IkeruTheme.Spacing.sm)
        }
    }

    // MARK: - Arranged Area (Drop Zone)

    private var arrangedArea: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Text("Your answer")
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            WrappingHStack(tokens: viewModel.arrangedTokens, spacing: IkeruTheme.Spacing.sm) { token in
                tokenTile(
                    token: token,
                    highlight: tileHighlight(
                        token: token,
                        isIncorrect: incorrectPosition(for: token)
                    )
                )
                .matchedGeometryEffect(id: token.id, in: tokenAnimation)
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.removeToken(token)
                    }
                }
            }
            .frame(minHeight: 50)
            .frame(maxWidth: .infinity)
            .padding(IkeruTheme.Spacing.md)
            .ikeruCard(.elevated)
        }
    }

    // MARK: - Available Area

    private var availableArea: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Text("Available words")
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            WrappingHStack(tokens: viewModel.availableTokens, spacing: IkeruTheme.Spacing.sm) { token in
                tokenTile(token: token, highlight: .none)
                    .matchedGeometryEffect(id: token.id, in: tokenAnimation)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.selectToken(token)
                        }
                    }
            }
            .frame(minHeight: 50)
            .frame(maxWidth: .infinity)
            .padding(IkeruTheme.Spacing.md)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        switch viewModel.exercisePhase {
        case .constructing:
            HStack(spacing: IkeruTheme.Spacing.md) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.resetArrangement()
                    }
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.arrangedTokens.isEmpty)

                Spacer()

                Button {
                    viewModel.submitAnswer()
                } label: {
                    Label("Check", systemImage: "checkmark.circle")
                }
                .ikeruButtonStyle(.primary)
                .disabled(!viewModel.allTokensPlaced)
            }

        case .feedback:
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    viewModel.nextExercise()
                }
            } label: {
                Label("Next", systemImage: "arrow.right")
            }
            .ikeruButtonStyle(.primary)
        }
    }

    // MARK: - Feedback Section

    @ViewBuilder
    private var feedbackSection: some View {
        if let result = viewModel.validationResult {
            VStack(spacing: IkeruTheme.Spacing.sm) {
                HStack(spacing: IkeruTheme.Spacing.sm) {
                    Image(systemName: result.isCorrect
                        ? "checkmark.circle.fill"
                        : "xmark.circle.fill"
                    )
                    .font(.system(size: IkeruTheme.Typography.Size.heading2))

                    Text(result.isCorrect ? "Correct!" : "Not quite...")
                        .font(.ikeruHeading3)
                }
                .foregroundStyle(
                    result.isCorrect
                        ? Color(hex: IkeruTheme.Colors.success)
                        : Color(hex: IkeruTheme.Colors.secondaryAccent)
                )

                if !result.isCorrect {
                    VStack(spacing: IkeruTheme.Spacing.xs) {
                        Text("Correct answer:")
                            .font(.ikeruCaption)
                            .foregroundStyle(.ikeruTextSecondary)

                        Text(result.correctAnswer)
                            .font(.ikeruBody)
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(IkeruTheme.Spacing.md)
            .ikeruCard(.standard)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Token Tile

    private enum TileHighlight {
        case none
        case correct
        case incorrect
    }

    private func tokenTile(token: SentenceToken, highlight: TileHighlight) -> some View {
        Text(token.text)
            .font(.ikeruBody)
            .foregroundStyle(tokenForegroundColor(token: token, highlight: highlight))
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .padding(.vertical, IkeruTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(tokenBackgroundColor(highlight: highlight))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        tokenBorderColor(token: token, highlight: highlight),
                        lineWidth: 1.5
                    )
            )
    }

    private func tokenForegroundColor(token: SentenceToken, highlight: TileHighlight) -> Color {
        switch highlight {
        case .correct:
            Color(hex: IkeruTheme.Colors.success)
        case .incorrect:
            Color(hex: IkeruTheme.Colors.secondaryAccent)
        case .none:
            token.isParticle
                ? Color(hex: IkeruTheme.Colors.primaryAccent)
                : .white
        }
    }

    private func tokenBackgroundColor(highlight: TileHighlight) -> Color {
        switch highlight {
        case .correct:
            Color(hex: IkeruTheme.Colors.success).opacity(0.15)
        case .incorrect:
            Color(hex: IkeruTheme.Colors.secondaryAccent).opacity(0.15)
        case .none:
            Color(hex: IkeruTheme.Colors.surface)
        }
    }

    private func tokenBorderColor(token: SentenceToken, highlight: TileHighlight) -> Color {
        switch highlight {
        case .correct:
            Color(hex: IkeruTheme.Colors.success).opacity(0.5)
        case .incorrect:
            Color(hex: IkeruTheme.Colors.secondaryAccent).opacity(0.5)
        case .none:
            token.isParticle
                ? Color(hex: IkeruTheme.Colors.primaryAccent).opacity(0.4)
                : Color.white.opacity(0.15)
        }
    }

    // MARK: - Helpers

    private func incorrectPosition(for token: SentenceToken) -> Bool {
        guard let result = viewModel.validationResult,
              let index = viewModel.arrangedTokens.firstIndex(of: token) else {
            return false
        }
        return result.incorrectPositions.contains(index)
    }

    private func tileHighlight(token: SentenceToken, isIncorrect: Bool) -> TileHighlight {
        guard viewModel.exercisePhase == .feedback,
              let result = viewModel.validationResult else {
            return .none
        }

        if result.isCorrect {
            return .correct
        }

        return isIncorrect ? .incorrect : .correct
    }
}

// MARK: - WrappingHStack

/// A horizontally wrapping layout for token tiles.
private struct WrappingHStack<Content: View>: View {
    let tokens: [SentenceToken]
    let spacing: CGFloat
    let content: (SentenceToken) -> Content

    @State private var totalHeight: CGFloat = .zero

    var body: some View {
        GeometryReader { geometry in
            generateLayout(in: geometry)
        }
        .frame(height: totalHeight)
    }

    private func generateLayout(in geometry: GeometryProxy) -> some View {
        var width: CGFloat = 0
        var height: CGFloat = 0

        return ZStack(alignment: .topLeading) {
            ForEach(tokens) { token in
                content(token)
                    .padding(.trailing, spacing)
                    .padding(.bottom, spacing)
                    .alignmentGuide(.leading) { dimension in
                        if abs(width - dimension.width) > geometry.size.width {
                            width = 0
                            height -= dimension.height + spacing
                        }
                        let result = width
                        if token.id == tokens.last?.id {
                            width = 0
                        } else {
                            width -= dimension.width
                        }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if token.id == tokens.last?.id {
                            height = 0
                        }
                        return result
                    }
            }
        }
        .background(
            GeometryReader { reader in
                Color.clear.preference(
                    key: HeightPreferenceKey.self,
                    value: reader.size.height
                )
            }
        )
        .onPreferenceChange(HeightPreferenceKey.self) { value in
            totalHeight = value
        }
    }
}

private struct HeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Preview

#Preview {
    let viewModel = SentenceConstructionViewModel()

    SentenceConstructionView(viewModel: viewModel)
        .background(Color.ikeruBackground)
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.loadExercise(difficulty: .beginner)
        }
}
