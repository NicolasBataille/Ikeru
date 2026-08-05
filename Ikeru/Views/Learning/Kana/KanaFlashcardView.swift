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
    //
    // Same card experience as the Practice session (owner request, device
    // pass 2026-07-19): the SRSCardView deck (tap-to-reveal, swipe-to-grade,
    // audio, peeks) + the shared GradeButtonsView with real per-card FSRS
    // predictions. One principle, one UI — Étude flashcards and session
    // reviews are the same gesture language.

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            if let card = viewModel.currentCard {
                SRSCardView(
                    card: card,
                    upcomingCards: upcomingCards,
                    isRevealed: revealBinding
                ) { direction in
                    gradeAndAdvance(direction.grade)
                }
            }
            Spacer(minLength: 0)
            if viewModel.isRevealed {
                GradeButtonsView(
                    onGrade: { grade in gradeAndAdvance(grade) },
                    predictedIntervals: viewModel.predictedIntervals
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text("Tap card to reveal", comment: "Hint below the flashcard before reveal — mirrors the session's hint")
                    .ikeruScaledFont(11, weight: .semibold, relativeTo: .caption2)
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(TatamiTokens.paperGhost)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
            sessionFooter
        }
        .padding(.horizontal, IkeruTheme.Spacing.lg)
        .padding(.bottom, 88) // Floating tab bar clearance
    }

    /// SRSCardView owns reveal via a Binding, but the drill VM computes
    /// predicted intervals inside `reveal()` — route sets through it and
    /// ignore the deck's post-swipe resets (the VM's `advance()` handles
    /// those itself).
    private var revealBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isRevealed },
            set: { newValue in if newValue { viewModel.reveal() } }
        )
    }

    /// Up to two peeks behind the current card, matching the session deck.
    private var upcomingCards: [CardDTO] {
        Array(viewModel.queue.dropFirst(viewModel.currentIndex + 1).prefix(2))
    }

    private func gradeAndAdvance(_ grade: Grade) {
        Task {
            if grade == .again {
                errorTrigger &+= 1
            } else {
                feedbackTrigger &+= 1
            }
            await viewModel.grade(grade)
        }
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
            Text(LocalizedStringKey(viewModel.mode.displayName))
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
