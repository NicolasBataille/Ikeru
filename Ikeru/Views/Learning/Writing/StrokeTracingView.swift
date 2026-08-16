import SwiftUI
import IkeruCore
#if IKERU_DEV_TOOLS
import os
#endif

#if IKERU_DEV_TOOLS
// MARK: - StrokeCaptureLog (dev tools only)

/// Dumps every finished stroke, in viewBox coordinates, as JSON.
///
/// Why this exists: **no genuine human stroke has ever been recorded in this
/// repo.** Every fixture `StrokeAccuracyService` is tested against is
/// synthetic, and the only positive test feeds the reference path straight
/// back into the scorer — so the scorer has never met a real, imperfect
/// stroke. Its tolerances (endpoint gap 0.08, length ratio 0.60-2.00, …) are
/// therefore reasoned from geometry and from constructed failures, not from
/// measurement of a finger. That is a guess, and it is labelled as one.
///
/// This hook is what makes a future device-trace pass possible: trace a
/// handful of characters on a real device, pull the JSON, replay it through
/// the scorer, and replace the guessed constants with measured ones.
///
/// Writes to the app's Documents directory (reachable via Xcode's "Download
/// Container…" or the Files app) because `os.Logger` truncates a dynamic
/// string well below the size of a 100-point stroke. The log line carries the
/// path so the file is findable. Gated by `IKERU_DEV_TOOLS`, which ships in
/// Release/TestFlight today and is removed before App Store submission — see
/// CLAUDE.md, "Removing IKERU_DEV_TOOLS".
enum StrokeCaptureLog {

    private static let logger = Logger(subsystem: "com.ikeru.app", category: "StrokeCapture")

    static func capture(_ points: [CGPoint], strokeIndex: Int, viewBox: (width: Int, height: Int)) {
        let payload: [String: Any] = [
            "capturedAt": ISO8601DateFormatter().string(from: Date()),
            "strokeIndex": strokeIndex,
            "viewBoxWidth": viewBox.width,
            "viewBoxHeight": viewBox.height,
            "pointCount": points.count,
            "points": points.map { ["x": $0.x, "y": $0.y] },
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else {
            logger.error("Stroke capture failed: could not serialize or locate Documents")
            return
        }

        let directory = documents.appendingPathComponent("StrokeCaptures", isDirectory: true)
        let file = directory.appendingPathComponent("stroke-\(Int(Date().timeIntervalSince1970 * 1000)).json")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            logger.info("Captured stroke \(strokeIndex) — \(points.count) points → \(file.path, privacy: .public)")
        } catch {
            logger.error("Stroke capture failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif

// MARK: - StrokeTracingView

/// Guided tracing canvas that lets the learner draw over a character.
/// Displays the target character as a faint guide and highlights the current target stroke.
struct StrokeTracingView: View {

    let strokeData: StrokeData
    let currentStrokeIndex: Int
    let drawnStrokes: [[CGPoint]]
    let onStrokeDrawn: ([CGPoint]) -> Void
    let onReset: () -> Void

    @State private var currentDrawingPoints: [CGPoint] = []
    @State private var isDrawing = false

    var body: some View {
        GeometryReader { geometry in
            let canvasSize = min(geometry.size.width, geometry.size.height)
            let scale = canvasSize / CGFloat(strokeData.viewBoxWidth)

            ZStack {
                // Background guide - all strokes at very low opacity
                ForEach(Array(strokeData.strokes.enumerated()), id: \.offset) { index, stroke in
                    StrokePath(points: stroke.points, scale: scale)
                        .stroke(
                            guideColor(for: index),
                            style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round, lineJoin: .round)
                        )
                }

                // Start-point indicator for current target stroke
                if currentStrokeIndex < strokeData.strokes.count {
                    let targetStroke = strokeData.strokes[currentStrokeIndex]
                    if let startPoint = targetStroke.points.first {
                        Circle()
                            .fill(Color(hex: IkeruTheme.Colors.primaryAccent))
                            .frame(width: 12 * scale, height: 12 * scale)
                            .position(
                                x: startPoint.x * scale,
                                y: startPoint.y * scale
                            )
                            .opacity(isDrawing ? 0 : 1)
                    }
                }

                // Previously completed drawn strokes (warm white, in viewBox coords)
                ForEach(Array(drawnStrokes.enumerated()), id: \.offset) { _, points in
                    StrokePath(points: points, scale: scale)
                        .stroke(
                            Color(hex: IkeruTheme.Colors.kanjiText),
                            style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round, lineJoin: .round)
                        )
                }

                // Current stroke being drawn
                if !currentDrawingPoints.isEmpty {
                    DrawnStrokePath(points: currentDrawingPoints)
                        .stroke(
                            Color(hex: IkeruTheme.Colors.primaryAccent),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                        )
                }
            }
            .frame(width: canvasSize, height: canvasSize)
            .contentShape(Rectangle())
            .gesture(
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
                        let screenPoints = currentDrawingPoints
                        currentDrawingPoints = []
                        if !screenPoints.isEmpty {
                            // Convert screen coordinates back to viewBox coordinates
                            let inverseScale = 1.0 / scale
                            let viewBoxPoints = screenPoints.map { pt in
                                CGPoint(x: pt.x * inverseScale, y: pt.y * inverseScale)
                            }
                            #if IKERU_DEV_TOOLS
                            StrokeCaptureLog.capture(
                                viewBoxPoints,
                                strokeIndex: currentStrokeIndex,
                                viewBox: (strokeData.viewBoxWidth, strokeData.viewBoxHeight)
                            )
                            #endif
                            onStrokeDrawn(viewBoxPoints)
                        }
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Colors

    private func guideColor(for index: Int) -> Color {
        if index < currentStrokeIndex {
            // Already traced - shown via drawnStrokes overlay
            return Color(hex: IkeruTheme.Colors.kanjiText, opacity: 0.05)
        } else if index == currentStrokeIndex {
            // Current target - highlighted amber
            return Color(hex: IkeruTheme.Colors.primaryAccent, opacity: 0.3)
        } else {
            // Upcoming - very faint
            return Color(hex: IkeruTheme.Colors.kanjiText, opacity: 0.08)
        }
    }
}

// MARK: - DrawnStrokePath Shape

/// A SwiftUI Shape for rendering the currently-being-drawn path in screen coordinates.
struct DrawnStrokePath: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }

        path.move(to: first)
        for i in 1..<points.count {
            path.addLine(to: points[i])
        }

        return path
    }
}
