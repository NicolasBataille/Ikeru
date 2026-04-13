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

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            // Time labels
            timeLabelsRow

            // Segmented progress bar
            segmentedBar

            // Skill type icons below segments
            skillIconsRow
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

    private var segmentedBar: some View {
        HStack(spacing: 3) {
            ForEach(Array(exercises.enumerated()), id: \.offset) { index, _ in
                segmentView(at: index)
            }
        }
        .frame(height: 6)
    }

    private func segmentView(at index: Int) -> some View {
        ZStack {
            Capsule().fill(Color.white.opacity(0.08))
            if index < currentIndex {
                Capsule().fill(
                    LinearGradient(
                        colors: [Color(hex: 0xE5BC8A), Color(hex: 0xD4A574)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            } else if index == currentIndex {
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

    // MARK: - Skill Icons

    private var skillIconsRow: some View {
        HStack(spacing: 0) {
            // Show icons only when there are a reasonable number
            if exercises.count <= 12 {
                ForEach(Array(exercises.enumerated()), id: \.offset) { index, exercise in
                    Image(systemName: sfSymbol(for: exercise.skill))
                        .font(.system(size: 8))
                        .foregroundStyle(iconColor(at: index))
                        .frame(maxWidth: .infinity)
                }
            } else {
                // For many exercises, show a compact count
                Text("\(currentIndex + 1)/\(exercises.count)")
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruTextSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func iconColor(at index: Int) -> Color {
        if index < currentIndex {
            return .ikeruPrimaryAccent
        } else if index == currentIndex {
            return .white
        } else {
            return .ikeruTextSecondary
        }
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
