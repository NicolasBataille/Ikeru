import SwiftUI
import IkeruCore

// MARK: - KanjiDisplayView

/// Displays a kanji character at hero size with tap-to-reveal stroke order.
struct KanjiDisplayView: View {

    let kanji: Kanji

    @State private var showStrokeOrder = false
    @State private var strokeOrderViewModel = StrokeOrderViewModel()

    var body: some View {
        ZStack {
            if showStrokeOrder, kanji.strokeOrderSVGRef != nil {
                strokeOrderOverlay
                    .transition(.opacity)
            } else {
                kanjiCharacter
                    .transition(.opacity)
            }
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .ikeruCard(.elevated)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
        .accessibilityLabel("Kanji \(kanji.character)")
        .accessibilityHint(
            kanji.strokeOrderSVGRef != nil
            ? "Tap to toggle stroke order"
            : "No stroke order available"
        )
    }

    // MARK: - Subviews

    private var kanjiCharacter: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Text(kanji.character)
                .font(.custom(
                    IkeruTheme.Typography.FontFamily.kanjiSerif,
                    size: IkeruTheme.Typography.Size.kanjiHero
                ))
                .foregroundStyle(Color(hex: IkeruTheme.Colors.kanjiText))

            if !kanji.meanings.isEmpty {
                Text(kanji.meanings.joined(separator: ", "))
                    .font(.system(size: IkeruTheme.Typography.Size.caption))
                    .foregroundStyle(
                        Color(hex: IkeruTheme.Colors.textPrimary)
                            .opacity(IkeruTheme.Colors.textSecondaryOpacity)
                    )
            }
        }
    }

    @ViewBuilder
    private var strokeOrderOverlay: some View {
        if let strokeData = strokeOrderViewModel.strokeData {
            VStack(spacing: IkeruTheme.Spacing.sm) {
                StrokeOrderView(
                    strokeData: strokeData,
                    speed: strokeOrderViewModel.animationSpeed,
                    isPlaying: strokeOrderViewModel.isAnimating,
                    currentStrokeIndex: strokeOrderViewModel.currentStrokeIndex,
                    onStrokeCompleted: {
                        strokeOrderViewModel.advanceAnimationStroke()
                    }
                )
                .frame(width: 120, height: 120)

                Text("Tap to dismiss")
                    .font(.system(size: IkeruTheme.Typography.Size.caption))
                    .foregroundStyle(
                        Color(hex: IkeruTheme.Colors.textPrimary)
                            .opacity(IkeruTheme.Colors.textSecondaryOpacity)
                    )
            }
        } else {
            ProgressView()
                .tint(Color(hex: IkeruTheme.Colors.primaryAccent))
        }
    }

    // MARK: - Actions

    private func handleTap() {
        guard kanji.strokeOrderSVGRef != nil else { return }

        withAnimation(.easeInOut(duration: IkeruTheme.Animation.standardDuration)) {
            showStrokeOrder.toggle()
        }

        if showStrokeOrder {
            loadStrokeDataIfNeeded()
        }
    }

    private func loadStrokeDataIfNeeded() {
        guard let svgData = kanji.strokeOrderSVGRef,
              strokeOrderViewModel.strokeData == nil else {
            // Already loaded, just replay
            if strokeOrderViewModel.strokeData != nil {
                strokeOrderViewModel.replayAnimation()
            }
            return
        }

        Task {
            await strokeOrderViewModel.loadStrokes(
                for: kanji.character,
                svgData: svgData
            )
            strokeOrderViewModel.startAnimation()
        }
    }
}
