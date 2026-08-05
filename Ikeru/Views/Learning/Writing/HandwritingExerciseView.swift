import SwiftUI
import IkeruCore

// MARK: - HandwritingExerciseView

/// Full handwriting recognition exercise with canvas, controls, and feedback.
/// Composes HandwritingCanvasView with toolbar and recognition results overlay.
struct HandwritingExerciseView: View {

    @Bindable var viewModel: HandwritingViewModel

    /// Invoked when the learner accepts the current recognition result and
    /// advances the session. The feedback tier is mapped to an FSRS `Grade`
    /// via `DrillGradeMapping.handwriting` (blueprint §3). Defaults to a no-op
    /// so the standalone `#Preview` (and any non-session use) still compiles.
    var onComplete: (Grade) -> Void = { _ in }

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            // Header with target character
            characterHeader

            // Drawing canvas
            HandwritingCanvasView(
                targetCharacter: viewModel.targetCharacter,
                strokes: viewModel.strokes,
                onStrokeCompleted: { points in
                    viewModel.addStroke(points: points)
                }
            )
            .tatamiRoom(.standard, padding: 0)

            // Control toolbar
            controlBar

            // Recognition results
            if viewModel.recognitionState.isLoading {
                recognizingIndicator
            }

            // When the recogniser couldn't read the scribble (error, no
            // candidates, or below the confidence threshold) we show an honest
            // self-grade panel instead of an automatic verdict — even when
            // there is no `recognitionResult` (e.g. Vision threw). Otherwise, a
            // real recognition result drives the normal feedback + candidates.
            if viewModel.feedbackState == .unavailable {
                selfGradeSection
            } else if viewModel.recognitionResult != nil {
                resultsSection
            }
        }
        .padding(IkeruTheme.Spacing.md)
        .sensoryFeedback(.success, trigger: viewModel.feedbackState == .correct)
        .sensoryFeedback(
            .warning,
            trigger: viewModel.feedbackState == .incorrect
        )
    }

    // MARK: - Character Header

    private var characterHeader: some View {
        VStack(spacing: IkeruTheme.Spacing.xs) {
            Text(viewModel.targetCharacter)
                .font(.custom(
                    IkeruTheme.Typography.FontFamily.kanjiSerif,
                    size: IkeruTheme.Typography.Size.kanjiDisplay
                ))
                .foregroundStyle(Color(hex: IkeruTheme.Colors.kanjiText))

            Text("Write the character freehand")
                .ikeruScaledFont(IkeruTheme.Typography.Size.body, relativeTo: .body)
                .foregroundStyle(.ikeruTextSecondary)
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: IkeruTheme.Spacing.md) {
            // Undo button
            Button {
                viewModel.undoLastStroke()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .ikeruScaledFont(IkeruTheme.Typography.Size.body, relativeTo: .body)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.strokes.isEmpty)

            // Clear button
            Button {
                viewModel.clearCanvas()
            } label: {
                Label("Clear", systemImage: "trash")
                    .ikeruScaledFont(IkeruTheme.Typography.Size.body, relativeTo: .body)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.strokes.isEmpty)

            Spacer()

            // Submit button
            Button {
                Task {
                    await viewModel.submitForRecognition()
                }
            } label: {
                Label("Check", systemImage: "checkmark.circle")
                    .ikeruScaledFont(IkeruTheme.Typography.Size.body, relativeTo: .body)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.strokes.isEmpty || viewModel.recognitionState.isLoading)
        }
    }

    // MARK: - Recognizing Indicator

    private var recognizingIndicator: some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            ProgressView()
            Text("Recognizing...")
                .ikeruScaledFont(IkeruTheme.Typography.Size.caption, relativeTo: .caption)
                .foregroundStyle(.ikeruTextSecondary)
        }
    }

    // MARK: - Results Section

    @ViewBuilder
    private var resultsSection: some View {
        if let result = viewModel.recognitionResult {
            VStack(spacing: IkeruTheme.Spacing.sm) {
                // Feedback banner
                feedbackBanner

                // Candidate list
                candidateList(result: result)

                // Recognition duration
                Text("Recognized in \(result.formattedDuration)")
                    .ikeruScaledFont(IkeruTheme.Typography.Size.caption, relativeTo: .caption)
                    .foregroundStyle(.ikeruTextSecondary)

                // Retry button — only when the result wasn't a clean match, so
                // the learner can improve their grade before continuing.
                if viewModel.feedbackState != .correct {
                    Button {
                        viewModel.retry()
                    } label: {
                        Label("Try Again", systemImage: "arrow.counterclockwise")
                            .ikeruScaledFont(IkeruTheme.Typography.Size.body, relativeTo: .body)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.ikeruPrimaryAccent)
                }

                // Continue — accept the current result and advance the session.
                // Maps the feedback tier → FSRS Grade (DrillGradeMapping).
                Button {
                    onComplete(DrillGradeMapping.handwriting(
                        feedback: viewModel.feedbackState,
                        topConfidence: viewModel.recognitionResult?.candidates.first?.confidence
                    ))
                } label: {
                    Label("Continue", systemImage: "arrow.right")
                        .ikeruScaledFont(IkeruTheme.Typography.Size.body, relativeTo: .body)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.ikeruPrimaryAccent)
            }
            .tatamiRoom(.standard)
        }
    }

    // MARK: - Self-Grade Section

    /// Shown when recognition is unavailable/inconclusive (remediation 7.8).
    /// Rather than auto-passing (or silently failing) a scribble the recogniser
    /// couldn't read, the learner compares the target (in the header) against
    /// their own drawing (still on the canvas above) and grades themselves
    /// honestly. Both verdicts advance the session via the same `onComplete`
    /// contract: "I got it" → `.good`, "Missed it" → `.again`.
    private var selfGradeSection: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            HStack(spacing: IkeruTheme.Spacing.sm) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: IkeruTheme.Typography.Size.heading2))
                Text("Recognition unavailable — grade yourself")
                    .ikeruScaledFont(IkeruTheme.Typography.Size.body, weight: .medium, relativeTo: .body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.ikeruTextSecondary)

            Text("Compare your writing above with the target. Did you get it right?")
                .ikeruScaledFont(IkeruTheme.Typography.Size.caption, relativeTo: .caption)
                .foregroundStyle(.ikeruTextSecondary)
                .multilineTextAlignment(.center)

            // Redraw without grading.
            Button {
                viewModel.retry()
            } label: {
                Label("Try Again", systemImage: "arrow.counterclockwise")
                    .ikeruScaledFont(IkeruTheme.Typography.Size.body, relativeTo: .body)
            }
            .buttonStyle(.bordered)
            .tint(Color.ikeruPrimaryAccent)

            // Honest self-verdict. Both advance the session via `onComplete`.
            HStack(spacing: IkeruTheme.Spacing.md) {
                Button {
                    onComplete(.again)
                } label: {
                    Label("Missed it", systemImage: "xmark")
                        .ikeruScaledFont(IkeruTheme.Typography.Size.body, relativeTo: .body)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.ikeruDanger)

                Button {
                    onComplete(.good)
                } label: {
                    Label("I got it", systemImage: "checkmark")
                        .ikeruScaledFont(IkeruTheme.Typography.Size.body, relativeTo: .body)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.ikeruPrimaryAccent)
            }
        }
        .tatamiRoom(.standard)
    }

    // MARK: - Feedback Banner

    private var feedbackBanner: some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            Image(systemName: feedbackIcon)
                .font(.system(size: IkeruTheme.Typography.Size.heading2))
            Text(feedbackText)
                .ikeruScaledFont(IkeruTheme.Typography.Size.body, weight: .medium, relativeTo: .body)
        }
        .foregroundStyle(feedbackColor)
    }

    private var feedbackIcon: String {
        switch viewModel.feedbackState {
        case .correct:
            "checkmark.circle.fill"
        case .partial:
            "exclamationmark.circle.fill"
        case .incorrect:
            "xmark.circle.fill"
        case .idle, .unavailable:
            "questionmark.circle"
        }
    }

    private var feedbackText: String {
        switch viewModel.feedbackState {
        case .correct:
            "Correct! Well done."
        case .partial:
            "Close! Your character was recognized but not as the top match."
        case .incorrect:
            "Not quite. Try again!"
        case .idle, .unavailable:
            ""
        }
    }

    private var feedbackColor: Color {
        switch viewModel.feedbackState {
        case .correct:
            Color.ikeruPrimaryAccent
        case .partial:
            Color.ikeruPrimaryAccent
        case .incorrect:
            Color.ikeruDanger
        case .idle, .unavailable:
            .ikeruTextSecondary
        }
    }

    // MARK: - Candidate List

    private func candidateList(result: RecognitionResult) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
            Text("Candidates")
                .ikeruScaledFont(IkeruTheme.Typography.Size.caption, weight: .semibold, relativeTo: .caption)
                .foregroundStyle(.ikeruTextSecondary)

            ForEach(Array(result.candidates.enumerated()), id: \.offset) { index, candidate in
                candidateRow(candidate: candidate, rank: index + 1)
            }

            if result.candidates.isEmpty {
                Text("No characters recognized")
                    .ikeruScaledFont(IkeruTheme.Typography.Size.caption, relativeTo: .caption)
                    .foregroundStyle(.ikeruTextSecondary)
            }
        }
    }

    private func candidateRow(candidate: RecognitionCandidate, rank: Int) -> some View {
        let isTarget = candidate.character == viewModel.targetCharacter

        return HStack(spacing: IkeruTheme.Spacing.sm) {
            Text("\(rank).")
                .ikeruScaledFont(IkeruTheme.Typography.Size.caption, design: .monospaced, relativeTo: .caption)
                .foregroundStyle(.ikeruTextSecondary)
                .frame(width: 24, alignment: .trailing)

            Text(candidate.character)
                .font(.custom(
                    IkeruTheme.Typography.FontFamily.kanjiSerif,
                    size: IkeruTheme.Typography.Size.heading3
                ))
                .foregroundStyle(
                    isTarget
                        ? Color.ikeruPrimaryAccent
                        : Color(hex: IkeruTheme.Colors.kanjiText)
                )

            Spacer()

            Text("\(Int(candidate.confidence * 100))%")
                .ikeruScaledFont(IkeruTheme.Typography.Size.caption, design: .monospaced, relativeTo: .caption)
                .foregroundStyle(
                    isTarget
                        ? Color.ikeruPrimaryAccent
                        : .ikeruTextSecondary
                )
        }
        .padding(.vertical, IkeruTheme.Spacing.xs)
        .background(
            isTarget
                ? Color.ikeruPrimaryAccent.opacity(0.1)
                : Color.clear
        )
    }
}

// MARK: - Preview

#Preview("HandwritingExerciseView") {
    let viewModel = HandwritingViewModel()
    viewModel.loadTarget(character: "\u{5c71}")

    return HandwritingExerciseView(viewModel: viewModel)
        .background(Color(hex: IkeruTheme.Colors.background))
        .preferredColorScheme(.dark)
}
