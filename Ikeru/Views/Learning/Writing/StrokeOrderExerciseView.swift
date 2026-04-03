import SwiftUI
import IkeruCore

// MARK: - Exercise Mode

/// The two modes of the stroke order exercise.
public enum StrokeExerciseMode: Sendable, Equatable {
    case watch
    case practice
}

// MARK: - StrokeOrderExerciseView

/// Combines stroke order animation (Watch) and guided tracing (Practice) into a single exercise.
/// Default flow: watch animation first, then switch to practice mode.
struct StrokeOrderExerciseView: View {

    @Bindable var viewModel: StrokeOrderViewModel

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            // Header with character display
            characterHeader

            // Exercise canvas
            exerciseCanvas
                .ikeruCard(.interactive)

            // Controls
            controlBar

            // Feedback overlay (after practice attempt)
            if viewModel.overallResult != nil {
                feedbackSection
            }
        }
        .padding(IkeruTheme.Spacing.md)
        .sensoryFeedback(.success, trigger: viewModel.overallResult?.passed == true)
        .sensoryFeedback(
            .warning,
            trigger: viewModel.overallResult != nil && viewModel.overallResult?.passed == false
        )
    }

    // MARK: - Character Header

    @ViewBuilder
    private var characterHeader: some View {
        if viewModel.strokeData != nil {
            Text(viewModel.character)
                .font(.custom(
                    IkeruTheme.Typography.FontFamily.kanjiSerif,
                    size: IkeruTheme.Typography.Size.kanjiDisplay
                ))
                .foregroundStyle(Color(hex: IkeruTheme.Colors.kanjiText))

            Text(viewModel.mode == .watch ? "Watch the stroke order" : "Trace the character")
                .font(.system(size: IkeruTheme.Typography.Size.body))
                .foregroundStyle(.ikeruTextSecondary)
        }
    }

    // MARK: - Exercise Canvas

    @ViewBuilder
    private var exerciseCanvas: some View {
        if let strokeData = viewModel.strokeData {
            switch viewModel.mode {
            case .watch:
                StrokeOrderView(
                    strokeData: strokeData,
                    speed: viewModel.animationSpeed,
                    isPlaying: viewModel.isAnimating,
                    currentStrokeIndex: viewModel.currentStrokeIndex,
                    onStrokeCompleted: {
                        viewModel.advanceAnimationStroke()
                    }
                )
                .sensoryFeedback(.impact(weight: .light), trigger: viewModel.currentStrokeIndex)

            case .practice:
                StrokeTracingView(
                    strokeData: strokeData,
                    currentStrokeIndex: viewModel.currentStrokeIndex,
                    drawnStrokes: viewModel.drawnStrokes,
                    onStrokeDrawn: { points in
                        viewModel.recordStroke(points: points)
                    },
                    onReset: {
                        viewModel.retry()
                    }
                )
            }
        } else if viewModel.loadingState.isLoading {
            ProgressView()
                .frame(width: 200, height: 200)
        } else {
            Text("No stroke data available")
                .foregroundStyle(.ikeruTextSecondary)
                .frame(width: 200, height: 200)
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: IkeruTheme.Spacing.md) {
            switch viewModel.mode {
            case .watch:
                // Speed picker
                Picker("Speed", selection: $viewModel.animationSpeed) {
                    ForEach(StrokeAnimationSpeed.allCases, id: \.self) { speed in
                        Text(speed.label).tag(speed)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                Spacer()

                // Replay button
                Button {
                    viewModel.replayAnimation()
                } label: {
                    Label("Replay", systemImage: "arrow.counterclockwise")
                        .font(.system(size: IkeruTheme.Typography.Size.body))
                }
                .buttonStyle(.bordered)

                // Start practice button
                Button {
                    viewModel.beginTracing()
                } label: {
                    Label("Practice", systemImage: "pencil.tip")
                        .font(.system(size: IkeruTheme.Typography.Size.body))
                }
                .buttonStyle(.borderedProminent)

            case .practice:
                // Show Again button
                Button {
                    viewModel.replayAnimation()
                } label: {
                    Label("Show Again", systemImage: "play.circle")
                        .font(.system(size: IkeruTheme.Typography.Size.body))
                }
                .buttonStyle(.bordered)

                Spacer()

                // Retry button
                Button {
                    viewModel.retry()
                } label: {
                    Label("Retry", systemImage: "arrow.counterclockwise")
                        .font(.system(size: IkeruTheme.Typography.Size.body))
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Feedback Section

    @ViewBuilder
    private var feedbackSection: some View {
        if let result = viewModel.overallResult {
            VStack(spacing: IkeruTheme.Spacing.sm) {
                // Per-stroke feedback
                HStack(spacing: IkeruTheme.Spacing.xs) {
                    ForEach(Array(result.strokeResults.enumerated()), id: \.offset) { _, strokeResult in
                        Image(systemName: strokeResult.isPassing ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(strokeResult.isPassing
                                ? Color(hex: IkeruTheme.Colors.success)
                                : Color(hex: IkeruTheme.Colors.secondaryAccent)
                            )
                            .font(.system(size: IkeruTheme.Typography.Size.heading3))
                    }
                }

                // Overall feedback text
                Text(feedbackText(for: result))
                    .font(.system(size: IkeruTheme.Typography.Size.body, weight: .medium))
                    .foregroundStyle(result.passed
                        ? Color(hex: IkeruTheme.Colors.success)
                        : Color(hex: IkeruTheme.Colors.secondaryAccent)
                    )
            }
            .padding(IkeruTheme.Spacing.md)
            .ikeruCard(.standard)
        }
    }

    // MARK: - Feedback Text

    private func feedbackText(for result: CharacterResult) -> String {
        if result.passed {
            let correctCount = result.strokeResults.filter { $0 == .correct }.count
            if correctCount == result.strokeResults.count {
                return "Perfect! All strokes correct."
            } else {
                return "Good job! Keep practicing for precision."
            }
        } else {
            let incorrectCount = result.strokeResults.filter { !$0.isPassing }.count
            return "\(incorrectCount) stroke\(incorrectCount == 1 ? "" : "s") need\(incorrectCount == 1 ? "s" : "") improvement. Try again!"
        }
    }
}
