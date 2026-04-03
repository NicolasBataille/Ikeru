import SwiftUI
import IkeruCore

// MARK: - HandwritingCanvasView

/// Freehand drawing canvas for handwriting recognition exercises.
/// Captures finger/pencil input as strokes and renders them in real time.
/// Displays the target character as a faint watermark guide.
struct HandwritingCanvasView: View {

    /// The target character shown as a faint watermark guide.
    let targetCharacter: String

    /// All completed strokes to render.
    let strokes: [[CGPoint]]

    /// Called when a new stroke is completed (finger lifted).
    let onStrokeCompleted: ([CGPoint]) -> Void

    @State private var currentDrawingPoints: [CGPoint] = []
    @State private var isDrawing = false

    var body: some View {
        GeometryReader { geometry in
            let canvasSize = min(geometry.size.width, geometry.size.height)

            ZStack {
                // Canvas background
                RoundedRectangle(cornerRadius: IkeruTheme.Radius.md)
                    .fill(Color(hex: IkeruTheme.Colors.surface))

                // Grid lines for writing guidance
                gridOverlay(size: canvasSize)

                // Target character watermark
                Text(targetCharacter)
                    .font(.custom(
                        IkeruTheme.Typography.FontFamily.kanjiSerif,
                        size: canvasSize * 0.7
                    ))
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.kanjiText, opacity: 0.10))

                // Completed strokes
                ForEach(Array(strokes.enumerated()), id: \.offset) { _, points in
                    DrawnStrokePath(points: points)
                        .stroke(
                            Color(hex: IkeruTheme.Colors.kanjiText),
                            style: StrokeStyle(
                                lineWidth: 4,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                }

                // Current stroke being drawn
                if !currentDrawingPoints.isEmpty {
                    DrawnStrokePath(points: currentDrawingPoints)
                        .stroke(
                            Color(hex: IkeruTheme.Colors.primaryAccent),
                            style: StrokeStyle(
                                lineWidth: 4,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                }
            }
            .frame(width: canvasSize, height: canvasSize)
            .contentShape(Rectangle())
            .gesture(drawingGesture)
            .sensoryFeedback(.impact(.light), trigger: isDrawing)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Grid Overlay

    /// Light grid lines to help with character proportions.
    @ViewBuilder
    private func gridOverlay(size: CGFloat) -> some View {
        Canvas { context, _ in
            let lineColor = Color(hex: IkeruTheme.Colors.kanjiText, opacity: 0.06)

            // Vertical center line
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: size / 2, y: 0))
                    path.addLine(to: CGPoint(x: size / 2, y: size))
                },
                with: .color(lineColor),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )

            // Horizontal center line
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: 0, y: size / 2))
                    path.addLine(to: CGPoint(x: size, y: size / 2))
                },
                with: .color(lineColor),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: - Drawing Gesture

    private var drawingGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if !isDrawing {
                    isDrawing = true
                    currentDrawingPoints = []
                }
                currentDrawingPoints.append(value.location)
            }
            .onEnded { _ in
                isDrawing = false
                let completedPoints = currentDrawingPoints
                currentDrawingPoints = []
                if !completedPoints.isEmpty {
                    onStrokeCompleted(completedPoints)
                }
            }
    }
}

// MARK: - Preview

#Preview("HandwritingCanvasView") {
    HandwritingCanvasView(
        targetCharacter: "\u{5c71}",
        strokes: [],
        onStrokeCompleted: { _ in }
    )
    .padding(IkeruTheme.Spacing.md)
    .background(Color(hex: IkeruTheme.Colors.background))
    .preferredColorScheme(.dark)
}
