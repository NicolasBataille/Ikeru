import SwiftUI
import IkeruCore

// MARK: - HandwritingExerciseView

/// Full handwriting recognition exercise with canvas, controls, and feedback.
/// Composes HandwritingCanvasView with toolbar and recognition results overlay.
struct HandwritingExerciseView: View {

    @Bindable var viewModel: HandwritingViewModel

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

            if viewModel.recognitionResult != nil {
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

                // Retry button
                if viewModel.feedbackState != .correct {
                    Button {
                        viewModel.retry()
                    } label: {
                        Label("Try Again", systemImage: "arrow.counterclockwise")
                            .ikeruScaledFont(IkeruTheme.Typography.Size.body, relativeTo: .body)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.ikeruPrimaryAccent)
                }
            }
            .tatamiRoom(.standard)
        }
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
        case .idle:
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
        case .idle:
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
        case .idle:
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
