import SwiftUI
import IkeruCore

// MARK: - KanaFlashcardView

/// Tap-to-reveal flashcard drill with 4 FSRS grade buttons.
struct KanaFlashcardView: View {

    @Environment(\.dismiss) private var dismiss
    @State var viewModel: KanaDrillViewModel
    @State private var feedbackTrigger: Int = 0
    @State private var errorTrigger: Int = 0

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
                .transition(.opacity)
            } else {
                content
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Flashcard")
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
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.isRevealed)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.currentIndex)
        .animation(.easeInOut(duration: 0.25), value: viewModel.sessionEnded)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            cardArea
            Spacer(minLength: 0)
            if viewModel.isRevealed {
                gradeButtons
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                revealCallToAction
                    .transition(.opacity)
            }
            sessionFooter
        }
        .padding(.horizontal, IkeruTheme.Spacing.lg)
        .padding(.bottom, 88) // Floating tab bar clearance
    }

    // MARK: Top bar

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
            Text(viewModel.mode.displayName.uppercased())
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

    // MARK: Card area

    @ViewBuilder
    private var cardArea: some View {
        if let card = viewModel.currentCard {
            VStack(spacing: IkeruTheme.Spacing.lg) {
                Text(card.front)
                    .font(.system(
                        size: viewModel.isRevealed ? 96 : 144,
                        weight: .regular,
                        design: .serif
                    ))
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .contentTransition(.numericText())

                if viewModel.isRevealed {
                    Text(romaji(for: card))
                        .ikeruScaledFont(40, weight: .semibold, design: .rounded, relativeTo: .title2)
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, IkeruTheme.Spacing.xl)
            .contentShape(Rectangle())
            .onTapGesture {
                if !viewModel.isRevealed {
                    viewModel.reveal()
                }
            }
        }
    }

    private func romaji(for card: CardDTO) -> String {
        if let group = card.kanaGroup,
           let match = group.characters.first(where: { $0.character == card.front }) {
            return match.romaji
        }
        return card.back
    }

    // MARK: Reveal CTA

    private var revealCallToAction: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Text("Tap to reveal")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextTertiary)
            Button {
                viewModel.reveal()
            } label: {
                Text("Show answer")
                    .frame(maxWidth: .infinity)
            }
            .ikeruButtonStyle(.primary)
        }
    }

    // MARK: Grade buttons

    private var gradeButtons: some View {
        HStack(spacing: 8) {
            gradeButton(.again, label: "Again", accent: Color.ikeruError)
            gradeButton(.hard, label: "Hard", accent: TatamiTokens.goldDim)
            gradeButton(.good, label: "Good", accent: TatamiTokens.goldDim)
            gradeButton(.easy, label: "Easy", accent: Color.ikeruPrimaryAccent)
        }
        .padding(.top, IkeruTheme.Spacing.md)
    }

    @ViewBuilder
    private func gradeButton(_ grade: Grade, label: String, accent: Color) -> some View {
        Button {
            Task {
                if grade == .again {
                    errorTrigger &+= 1
                } else {
                    feedbackTrigger &+= 1
                }
                await viewModel.grade(grade)
            }
        } label: {
            VStack(spacing: 4) {
                Text(label)
                    .ikeruScaledFont(13, weight: .semibold, relativeTo: .caption)
                    .foregroundStyle(Color.ikeruTextPrimary)
                Text(viewModel.predictedIntervals[grade] ?? "—")
                    .ikeruScaledFont(11, weight: .regular, relativeTo: .caption2)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Rectangle().fill(accent.opacity(0.12))
                }
            }
            .overlay(Rectangle().strokeBorder(accent.opacity(0.45), lineWidth: 0.8))
            .sumiCorners(color: accent.opacity(0.7), size: 7, weight: 1.1)
        }
        .buttonStyle(.plain)
    }

    // MARK: Session footer

    private var sessionFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.ikeruPrimaryAccent)
            Text("\(viewModel.correctCount) correct · \(viewModel.wrongCount) missed")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
        }
        .padding(.top, IkeruTheme.Spacing.sm)
    }
}
