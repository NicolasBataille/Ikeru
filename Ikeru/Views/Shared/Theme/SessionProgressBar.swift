import SwiftUI
import IkeruCore

// MARK: - SessionProgressBar (Segmented)

/// Segmented progress bar for immersive session mode.
/// Each segment represents one exercise, with skill type icons and timing display.
struct SessionProgressBar: View {

    /// The ordered list of exercises in the session.
    let exercises: [ExerciseItem]

    /// Index of the currently active exercise.
    let currentIndex: Int

    /// Elapsed time in seconds.
    let elapsedTime: TimeInterval

    /// Estimated total session duration in seconds.
    let estimatedTotalTime: TimeInterval

    /// Maximum visible segments before we collapse the trailing tail into a
    /// single quiet capsule. Five reads as a scroll/handscroll rhythm and
    /// keeps the bar calm even when a session has 20+ exercises.
    private let visibleSegmentCount = 5

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            // Time labels
            timeLabelsRow

            // Segmented progress bar (5-segment scroll line, with collapse
            // for longer sessions). Replaces the earlier book/pencil/ear
            // SF-Symbol row, which read as gamey clutter against the
            // wabi-sabi direction.
            segmentedBar
        }
        .padding(.horizontal, IkeruTheme.Spacing.md)
    }

    // MARK: - Time Labels

    private var timeLabelsRow: some View {
        HStack {
            Text(formatTime(elapsedTime))
                .font(.ikeruStats)
                .foregroundStyle(Color.ikeruTextSecondary)

            Spacer()

            Text("-" + formatTime(max(0, estimatedTotalTime - elapsedTime)))
                .font(.ikeruStats)
                .foregroundStyle(Color.ikeruTextTertiary)
        }
    }

    // MARK: - Segmented Bar

    /// 5-segment scroll-line representation. For sessions of 5 or fewer
    /// exercises every step gets its own segment; longer sessions are
    /// quantised into 5 buckets so the bar always reads at the same rhythm.
    private var segmentedBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<visibleSegmentCount, id: \.self) { segmentIndex in
                scrollSegment(at: segmentIndex)
            }
        }
        .frame(height: 6)
    }

    /// Returns the visible segment's filled state given the absolute progress.
    /// `currentIndex` is the active exercise; we bucket it into the visible
    /// segment count so 8/12/20 exercises all collapse to the same five-step
    /// rhythm.
    private func scrollSegment(at segmentIndex: Int) -> some View {
        let totalSteps = max(1, exercises.count)
        let progressFraction = Double(currentIndex) / Double(totalSteps)
        let segmentFraction = Double(segmentIndex) / Double(visibleSegmentCount)
        let nextSegmentFraction = Double(segmentIndex + 1) / Double(visibleSegmentCount)

        let isFilled = progressFraction >= nextSegmentFraction
        let isActive = progressFraction >= segmentFraction
            && progressFraction < nextSegmentFraction

        return ZStack {
            Capsule().fill(Color.white.opacity(0.08))
            if isFilled {
                Capsule().fill(
                    LinearGradient(
                        colors: [Color(hex: 0xE5BC8A), Color(hex: 0xD4A574)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            } else if isActive {
                Capsule().fill(
                    LinearGradient(
                        colors: [Color(hex: 0xF5F2EC), Color(hex: 0xE0DDD7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .animation(
            .spring(response: 0.42, dampingFraction: 0.86),
            value: currentIndex
        )
    }

    // MARK: - Helpers

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - SkillType SF Symbol Mapping

/// Maps a SkillType to the corresponding SF Symbol name.
func sfSymbol(for skill: SkillType) -> String {
    switch skill {
    case .reading: "book.fill"
    case .writing: "pencil.line"
    case .listening: "ear.fill"
    case .speaking: "mouth.fill"
    }
}

// MARK: - Preview

#Preview("SessionProgressBar (Segmented)") {
    let previewCard = CardDTO(
        id: UUID(),
        front: "\u{6F22}",
        back: "kanji",
        type: .kanji,
        fsrsState: FSRSState(),
        easeFactor: 2.5,
        interval: 0,
        dueDate: Date(),
        lapseCount: 0,
        leechFlag: false
    )
    let sampleExercises: [ExerciseItem] = [
        .srsReview(previewCard),
        .srsReview(previewCard),
        .writingPractice("kanji"),
        .listeningExercise(UUID()),
        .speakingExercise(UUID()),
        .srsReview(previewCard),
        .grammarExercise(UUID()),
        .kanjiStudy("test"),
    ]

    ZStack {
        Color.ikeruBackground.ignoresSafeArea()

        VStack(spacing: IkeruTheme.Spacing.xl) {
            SessionProgressBar(
                exercises: sampleExercises,
                currentIndex: 3,
                elapsedTime: 85,
                estimatedTotalTime: 300
            )

            SessionProgressBar(
                exercises: sampleExercises,
                currentIndex: 0,
                elapsedTime: 0,
                estimatedTotalTime: 300
            )

            SessionProgressBar(
                exercises: sampleExercises,
                currentIndex: 7,
                elapsedTime: 280,
                estimatedTotalTime: 300
            )
        }
        .padding(IkeruTheme.Spacing.lg)
    }
    .preferredColorScheme(.dark)
}
