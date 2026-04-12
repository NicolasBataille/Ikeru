import SwiftUI
import IkeruCore

// MARK: - VocabularyFlashcardView

/// Tap-to-reveal flashcard drill for personal dictionary words.
struct VocabularyFlashcardView: View {

    @Environment(\.dismiss) private var dismiss
    @State var viewModel: VocabularyDrillViewModel
    @State private var feedbackTrigger: Int = 0
    @State private var errorTrigger: Int = 0

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            if viewModel.sessionEnded {
                drillSummary
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
        .padding(.bottom, 88)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Text("\(viewModel.currentIndex + 1) / \(viewModel.queue.count)")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background { Capsule().fill(.ultraThinMaterial) }
            Spacer()
            Text("VOCABULARY")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruPrimaryAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background { Capsule().fill(Color.ikeruPrimaryAccent.opacity(0.10)) }
        }
        .padding(.top, IkeruTheme.Spacing.sm)
    }

    // MARK: - Card Area

    @ViewBuilder
    private var cardArea: some View {
        if let entry = viewModel.currentEntry {
            VStack(spacing: IkeruTheme.Spacing.lg) {
                Text(entry.word)
                    .font(.system(
                        size: viewModel.isRevealed ? 72 : 96,
                        weight: .regular,
                        design: .serif
                    ))
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .contentTransition(.numericText())

                if viewModel.isRevealed {
                    VStack(spacing: IkeruTheme.Spacing.sm) {
                        Text(entry.reading)
                            .font(.system(size: 28, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.ikeruPrimaryAccent)

                        Text(entry.meaning)
                            .font(.ikeruBody)
                            .foregroundStyle(Color.ikeruTextSecondary)
                    }
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

    // MARK: - Reveal CTA

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

    // MARK: - Grade Buttons

    private var gradeButtons: some View {
        HStack(spacing: 8) {
            gradeButton(.again, label: "Again", color: Color(red: 0.85, green: 0.30, blue: 0.30))
            gradeButton(.hard, label: "Hard", color: Color(red: 0.90, green: 0.55, blue: 0.20))
            gradeButton(.good, label: "Good", color: Color(red: 0.30, green: 0.55, blue: 0.85))
            gradeButton(.easy, label: "Easy", color: Color(red: 0.30, green: 0.70, blue: 0.45))
        }
        .padding(.top, IkeruTheme.Spacing.md)
    }

    @ViewBuilder
    private func gradeButton(_ grade: Grade, label: String, color: Color) -> some View {
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextPrimary)
                Text(viewModel.predictedIntervals[grade] ?? "—")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background {
                RoundedRectangle(cornerRadius: IkeruTheme.Radius.md, style: .continuous)
                    .fill(color.opacity(0.18))
            }
            .overlay {
                RoundedRectangle(cornerRadius: IkeruTheme.Radius.md, style: .continuous)
                    .strokeBorder(color.opacity(0.55), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Session Footer

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
