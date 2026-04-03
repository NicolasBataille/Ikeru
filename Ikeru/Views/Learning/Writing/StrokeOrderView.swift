import SwiftUI
import IkeruCore

// MARK: - Animation Speed

/// Playback speed for stroke order animation.
public enum StrokeAnimationSpeed: String, CaseIterable, Sendable {
    case slow
    case normal
    case fast

    /// Duration in seconds per stroke.
    var strokeDuration: Double {
        switch self {
        case .slow: 2.0
        case .normal: 1.0
        case .fast: 0.5
        }
    }

    var label: String {
        switch self {
        case .slow: "Slow"
        case .normal: "Normal"
        case .fast: "Fast"
        }
    }
}

// MARK: - StrokeOrderView

/// Displays animated stroke order for a character using SVG path data.
/// Strokes draw sequentially with visible progression.
struct StrokeOrderView: View {

    let strokeData: StrokeData
    let speed: StrokeAnimationSpeed
    let isPlaying: Bool
    let currentStrokeIndex: Int
    let onStrokeCompleted: () -> Void

    @State private var trimEnd: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let canvasSize = min(geometry.size.width, geometry.size.height)
            let scale = canvasSize / CGFloat(strokeData.viewBoxWidth)

            ZStack {
                // Guide strokes (faint, upcoming)
                ForEach(Array(strokeData.strokes.enumerated()), id: \.offset) { index, stroke in
                    StrokePath(points: stroke.points, scale: scale)
                        .stroke(
                            guideColor(for: index),
                            style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round, lineJoin: .round)
                        )
                }

                // Active stroke being animated
                if currentStrokeIndex < strokeData.strokes.count, isPlaying {
                    let activeStroke = strokeData.strokes[currentStrokeIndex]
                    StrokePath(points: activeStroke.points, scale: scale)
                        .trim(from: 0, to: trimEnd)
                        .stroke(
                            Color(hex: IkeruTheme.Colors.primaryAccent),
                            style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round, lineJoin: .round)
                        )
                }
            }
            .frame(width: canvasSize, height: canvasSize)
            .onChange(of: currentStrokeIndex) {
                animateCurrentStroke()
            }
            .onChange(of: isPlaying) {
                if isPlaying {
                    animateCurrentStroke()
                }
            }
            .onAppear {
                if isPlaying {
                    animateCurrentStroke()
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Colors

    private func guideColor(for index: Int) -> Color {
        if index < currentStrokeIndex {
            // Already drawn - warm white (kanji text)
            return Color(hex: IkeruTheme.Colors.kanjiText)
        } else if index == currentStrokeIndex {
            // Active - shown via animation overlay, guide is faint
            return Color(hex: IkeruTheme.Colors.kanjiText, opacity: 0.1)
        } else {
            // Upcoming - faint guide
            return Color(hex: IkeruTheme.Colors.kanjiText, opacity: 0.1)
        }
    }

    // MARK: - Animation

    private func animateCurrentStroke() {
        trimEnd = 0
        withAnimation(.spring(duration: speed.strokeDuration)) {
            trimEnd = 1
        }

        // Notify completion after animation duration
        let delay = speed.strokeDuration + 0.1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            onStrokeCompleted()
        }
    }
}

// MARK: - StrokePath Shape

/// A SwiftUI Shape that draws a path through the given points.
struct StrokePath: Shape {
    let points: [CGPoint]
    let scale: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }

        path.move(to: CGPoint(x: first.x * scale, y: first.y * scale))

        for i in 1..<points.count {
            path.addLine(to: CGPoint(x: points[i].x * scale, y: points[i].y * scale))
        }

        return path
    }
}
