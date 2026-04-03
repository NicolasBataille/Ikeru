import SwiftUI
import IkeruCore

// MARK: - PitchContourView

/// Draws a pitch accent contour visualization showing target and detected patterns.
/// Uses Canvas for high-performance drawing of mora labels, pitch lines, and color coding.
struct PitchContourView: View {

    /// The target pattern with per-mora high/low.
    let targetPattern: PitchAccentPattern

    /// The detected per-mora high/low from analysis (nil if not yet analyzed).
    let detectedHighLow: [Bool]?

    /// Mora labels to show on the x-axis (e.g. ["か", "ぜ"]).
    let moraLabels: [String]

    // MARK: - Layout Constants

    private let topPadding: CGFloat = 12
    private let bottomPadding: CGFloat = 28
    private let horizontalPadding: CGFloat = 20
    private let highY: CGFloat = 0.2
    private let lowY: CGFloat = 0.8

    var body: some View {
        Canvas { context, size in
            let drawableHeight = size.height - topPadding - bottomPadding
            let drawableWidth = size.width - horizontalPadding * 2
            let moraCount = targetPattern.moraCount

            guard moraCount > 0 else { return }

            let stepX = moraCount > 1
                ? drawableWidth / CGFloat(moraCount - 1)
                : drawableWidth

            // Draw target contour (dashed line)
            drawContour(
                context: context,
                moraHighLow: targetPattern.moraHighLow,
                stepX: stepX,
                drawableHeight: drawableHeight,
                size: size,
                color: Color.ikeruSecondaryAccent.opacity(0.5),
                lineWidth: 2,
                isDashed: true
            )

            // Draw detected contour if available
            if let detected = detectedHighLow, detected.count == moraCount {
                drawContour(
                    context: context,
                    moraHighLow: detected,
                    stepX: stepX,
                    drawableHeight: drawableHeight,
                    size: size,
                    color: .clear,
                    lineWidth: 3,
                    isDashed: false,
                    colorPerSegment: segmentColors(
                        target: targetPattern.moraHighLow,
                        detected: detected
                    )
                )
            }

            // Draw mora labels along x-axis
            for i in 0..<min(moraLabels.count, moraCount) {
                let x = horizontalPadding + CGFloat(i) * stepX
                let labelY = size.height - bottomPadding + 8

                let text = Text(moraLabels[i])
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.ikeruTextSecondary)

                context.draw(
                    context.resolve(text),
                    at: CGPoint(x: x, y: labelY),
                    anchor: .top
                )
            }

            // Draw dots at mora positions for target
            for i in 0..<moraCount {
                let x = horizontalPadding + CGFloat(i) * stepX
                let isHigh = targetPattern.moraHighLow[i]
                let yRatio = isHigh ? highY : lowY
                let y = topPadding + yRatio * drawableHeight

                context.fill(
                    Circle().path(in: CGRect(
                        x: x - 4, y: y - 4,
                        width: 8, height: 8
                    )),
                    with: .color(Color.ikeruSecondaryAccent.opacity(0.5))
                )
            }

            // Draw dots for detected
            if let detected = detectedHighLow, detected.count == moraCount {
                let colors = segmentColors(
                    target: targetPattern.moraHighLow,
                    detected: detected
                )
                for i in 0..<moraCount {
                    let x = horizontalPadding + CGFloat(i) * stepX
                    let isHigh = detected[i]
                    let yRatio = isHigh ? highY : lowY
                    let y = topPadding + yRatio * drawableHeight
                    let color = colors[i]

                    context.fill(
                        Circle().path(in: CGRect(
                            x: x - 5, y: y - 5,
                            width: 10, height: 10
                        )),
                        with: .color(color)
                    )
                }
            }
        }
        .frame(height: 120)
    }

    // MARK: - Drawing Helpers

    private func drawContour(
        context: GraphicsContext,
        moraHighLow: [Bool],
        stepX: CGFloat,
        drawableHeight: CGFloat,
        size: CGSize,
        color: Color,
        lineWidth: CGFloat,
        isDashed: Bool,
        colorPerSegment: [Color]? = nil
    ) {
        let moraCount = moraHighLow.count
        guard moraCount > 1 else { return }

        if let colors = colorPerSegment {
            // Draw each segment with its own color
            for i in 0..<(moraCount - 1) {
                let x1 = horizontalPadding + CGFloat(i) * stepX
                let x2 = horizontalPadding + CGFloat(i + 1) * stepX
                let y1Ratio = moraHighLow[i] ? highY : lowY
                let y2Ratio = moraHighLow[i + 1] ? highY : lowY
                let y1 = topPadding + y1Ratio * drawableHeight
                let y2 = topPadding + y2Ratio * drawableHeight

                var path = Path()
                path.move(to: CGPoint(x: x1, y: y1))
                path.addLine(to: CGPoint(x: x2, y: y2))

                context.stroke(
                    path,
                    with: .color(colors[i]),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }
        } else {
            var path = Path()
            for i in 0..<moraCount {
                let x = horizontalPadding + CGFloat(i) * stepX
                let yRatio = moraHighLow[i] ? highY : lowY
                let y = topPadding + yRatio * drawableHeight

                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            let style = isDashed
                ? StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [6, 4])
                : StrokeStyle(lineWidth: lineWidth, lineCap: .round)

            context.stroke(path, with: .color(color), style: style)
        }
    }

    /// Returns a color per mora based on whether target and detected match.
    private func segmentColors(target: [Bool], detected: [Bool]) -> [Color] {
        zip(target, detected).map { targetHigh, detectedHigh in
            targetHigh == detectedHigh ? Color.ikeruSuccess : Color.ikeruSecondaryAccent
        }
    }
}

// MARK: - Preview

#Preview("PitchContourView — Atamadaka") {
    let target = PitchAccentPattern.make(moraCount: 3, accentPosition: 1)
    PitchContourView(
        targetPattern: target,
        detectedHighLow: [true, false, false],
        moraLabels: ["あ", "め", "り"]
    )
    .padding()
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}

#Preview("PitchContourView — Heiban with mismatch") {
    let target = PitchAccentPattern.make(moraCount: 4, accentPosition: 0)
    PitchContourView(
        targetPattern: target,
        detectedHighLow: [false, true, false, true],
        moraLabels: ["さ", "く", "ら", "ん"]
    )
    .padding()
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
