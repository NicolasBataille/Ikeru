import SwiftUI
import IkeruCore

// MARK: - Skill Radar Variant

enum SkillRadarVariant {
    case mini
    case full
}

// MARK: - Skill Radar View

/// 4-axis radar chart showing skill balance: Reading, Writing, Listening, Speaking.
/// Supports `.mini` (compact, no labels) and `.full` (with labels and values).
struct SkillRadarView: View {

    let skillBalance: SkillBalanceSnapshot
    let variant: SkillRadarVariant

    /// Animatable data points for the four axes.
    private var dataPoints: [Double] {
        [
            skillBalance.reading,
            skillBalance.listening,
            skillBalance.writing,
            skillBalance.speaking
        ]
    }

    private var size: CGFloat {
        switch variant {
        case .mini: return 120
        case .full: return 220
        }
    }

    private var labelPadding: CGFloat {
        switch variant {
        case .mini: return 0
        case .full: return 56
        }
    }

    var body: some View {
        ZStack {
            radarCanvas
                .frame(width: size, height: size)

            if variant == .full {
                axisLabels
            }
        }
        .frame(width: size + labelPadding, height: size + labelPadding)
        .animation(.spring(duration: IkeruTheme.Animation.standardDuration), value: dataPoints)
    }

    // MARK: - Canvas Drawing

    private var radarCanvas: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = min(canvasSize.width, canvasSize.height) / 2

            // Draw grid rings
            drawGridRings(context: context, center: center, radius: radius)

            // Draw axis lines
            drawAxisLines(context: context, center: center, radius: radius)

            // Draw data polygon with gradient fill
            drawDataPolygon(context: context, center: center, radius: radius)
        }
    }

    private func drawGridRings(
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat
    ) {
        let ringCount = 4
        let gridColor = Color.white.opacity(0.1)

        for ring in 1...ringCount {
            let ringRadius = radius * CGFloat(ring) / CGFloat(ringCount)
            let ringPath = polygonPath(
                center: center,
                radius: ringRadius,
                sides: 4
            )
            context.stroke(ringPath, with: .color(gridColor), lineWidth: 0.5)
        }
    }

    private func drawAxisLines(
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat
    ) {
        let axisColor = Color.white.opacity(0.15)

        for index in 0..<4 {
            let angle = angleForAxis(index)
            let endpoint = pointOnCircle(center: center, radius: radius, angle: angle)

            var path = Path()
            path.move(to: center)
            path.addLine(to: endpoint)
            context.stroke(path, with: .color(axisColor), lineWidth: 0.5)
        }
    }

    private func drawDataPolygon(
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat
    ) {
        guard !dataPoints.isEmpty else { return }

        let points = dataPoints.enumerated().map { index, value in
            let clampedValue = min(1.0, max(0, value))
            let angle = angleForAxis(index)
            return pointOnCircle(
                center: center,
                radius: radius * clampedValue,
                angle: angle
            )
        }

        var dataPath = Path()
        for (index, point) in points.enumerated() {
            if index == 0 {
                dataPath.move(to: point)
            } else {
                dataPath.addLine(to: point)
            }
        }
        dataPath.closeSubpath()

        // Gradient fill
        let fillGradient = Gradient(colors: [
            Color(hex: IkeruTheme.Colors.Skills.reading).opacity(0.4),
            Color(hex: IkeruTheme.Colors.success).opacity(0.3)
        ])

        context.fill(
            dataPath,
            with: .linearGradient(
                fillGradient,
                startPoint: CGPoint(x: center.x, y: center.y - radius),
                endPoint: CGPoint(x: center.x, y: center.y + radius)
            )
        )

        // Stroke outline
        context.stroke(
            dataPath,
            with: .color(Color(hex: IkeruTheme.Colors.success).opacity(0.8)),
            lineWidth: 2
        )

        // Draw data point dots
        for point in points {
            let dotRect = CGRect(
                x: point.x - 3,
                y: point.y - 3,
                width: 6,
                height: 6
            )
            context.fill(
                Path(ellipseIn: dotRect),
                with: .color(Color(hex: IkeruTheme.Colors.success))
            )
        }
    }

    // MARK: - Axis Labels (full variant)

    private var axisLabels: some View {
        let labels: [(String, UInt32, Int)] = [
            ("Reading", IkeruTheme.Colors.Skills.reading, 0),
            ("Listening", IkeruTheme.Colors.Skills.listening, 1),
            ("Writing", IkeruTheme.Colors.Skills.writing, 2),
            ("Speaking", IkeruTheme.Colors.Skills.speaking, 3)
        ]

        return ZStack {
            ForEach(labels, id: \.2) { label, colorHex, index in
                let offset = labelOffset(for: index)
                VStack(spacing: 2) {
                    Text(label)
                        .font(.ikeruCaption)
                        .foregroundStyle(Color(hex: colorHex))
                    Text(percentageText(for: index))
                        .font(.ikeruStats)
                        .foregroundStyle(.white)
                }
                .offset(x: offset.x, y: offset.y)
            }
        }
    }

    private func percentageText(for index: Int) -> String {
        let value = dataPoints[index]
        return "\(Int(value * 100))%"
    }

    private func labelOffset(for index: Int) -> CGPoint {
        let distance = (size / 2) + 28
        let angle = angleForAxis(index)
        return CGPoint(
            x: cos(angle) * distance,
            y: sin(angle) * distance
        )
    }

    // MARK: - Geometry Helpers

    /// Axis angles: 0 = top, 1 = right, 2 = bottom, 3 = left
    /// Arranged clockwise starting from top (-π/2).
    private func angleForAxis(_ index: Int) -> Double {
        let startAngle = -Double.pi / 2
        return startAngle + (Double(index) * Double.pi / 2)
    }

    private func pointOnCircle(
        center: CGPoint,
        radius: CGFloat,
        angle: Double
    ) -> CGPoint {
        CGPoint(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)
        )
    }

    /// Creates a regular polygon path centered at a point.
    private func polygonPath(
        center: CGPoint,
        radius: CGFloat,
        sides: Int
    ) -> Path {
        var path = Path()
        for index in 0..<sides {
            let angle = angleForAxis(index)
            let point = pointOnCircle(center: center, radius: radius, angle: angle)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

#Preview("Skill Radar — Full") {
    ZStack {
        Color(hex: IkeruTheme.Colors.background)
            .ignoresSafeArea()

        VStack(spacing: IkeruTheme.Spacing.xl) {
            SkillRadarView(
                skillBalance: SkillBalanceSnapshot(
                    reading: 0.7,
                    writing: 0.4,
                    listening: 0.6,
                    speaking: 0.3
                ),
                variant: .full
            )

            SkillRadarView(
                skillBalance: SkillBalanceSnapshot(
                    reading: 0.7,
                    writing: 0.4,
                    listening: 0.6,
                    speaking: 0.3
                ),
                variant: .mini
            )
        }
    }
    .preferredColorScheme(.dark)
}
