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

    /// Mirrors `RPGState.equippedTheme` (synced by `EquippedCosmeticsBridge`)
    /// so the filled-segment gradient recolors with the player's cosmetic
    /// theme — the single source of truth for that mapping is
    /// `ThemePaletteService`, shared with every other progress/XP bar.
    @AppStorage(EquippedCosmeticsBridge.Keys.themeName) private var equippedThemeName: String = ""

    /// The filled-segment (completed progress) gradient, themed via
    /// `ThemePaletteService`. Falls back to the original gold gradient when
    /// no cosmetic theme is equipped.
    private var filledPalette: ThemePaletteService.Palette {
        ThemePaletteService.palette(forThemeName: equippedThemeName.isEmpty ? nil : equippedThemeName)
    }

    var body: some View {
        // Calm segmented rail only. The live count-up stopwatch + "~Xm" estimate
        // were removed: a visible clock reads as time pressure, against the "at
        // your own rhythm" pitch. The session's time budget, one-minute warning
        // and auto-end still run in SessionViewModel — they're just not shown.
        segmentedBar
            .padding(.horizontal, IkeruTheme.Spacing.md)
    }

    // MARK: - Segmented Bar

    /// 5-segment fusuma rail. For sessions of 5 or fewer exercises every
    /// step gets its own panel; longer sessions are quantised into 5
    /// buckets so the bar always reads at the same rhythm. Paired
    /// FusumaRail hairlines frame the row above and below to honor the
    /// Tatami spec's "fusuma progress".
    private var segmentedBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<visibleSegmentCount, id: \.self) { segmentIndex in
                scrollSegment(at: segmentIndex)
            }
        }
        .frame(height: 6)
        .padding(.vertical, 4)
        .overlay(alignment: .top)    { FusumaRail(opacity: 0.6) }
        .overlay(alignment: .bottom) { FusumaRail(opacity: 0.6, inverted: true) }
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
            Rectangle().fill(Color.white.opacity(0.08))
            if isFilled {
                Rectangle().fill(
                    LinearGradient(
                        colors: [Color(hex: filledPalette.startHex), Color(hex: filledPalette.endHex)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            } else if isActive {
                Rectangle().fill(
                    LinearGradient(
                        colors: [
                            Color(hex: IkeruTheme.Colors.ProgressBar.activeStart),
                            Color(hex: IkeruTheme.Colors.ProgressBar.activeEnd),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .overlay(
            Rectangle().strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .animation(
            .spring(response: 0.42, dampingFraction: 0.86),
            value: currentIndex
        )
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
        .writingPractice(previewCard),
        .listeningExercise(UUID()),
        .speakingExercise(UUID()),
        .srsReview(previewCard),
        .grammarExercise(UUID()),
        .kanjiStudy(previewCard),
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
