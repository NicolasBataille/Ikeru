import SwiftUI

// MARK: - SumiCornerFrame
//
// Four sharp ink-brushed L-marks at the corners of the host view. Replaces
// rounded-corner radius — the Tatami direction insists on 0px corner radius
// and uses sumi marks to do the visual softening that radius normally does.
//
// Apply via the `.sumiCorners(...)` modifier; corners are drawn as overlays
// so the host view's intrinsic size is unchanged.

struct SumiCornerFrame: ViewModifier {
    var color: Color = .ikeruPrimaryAccent
    var size: CGFloat = 10
    var weight: CGFloat = 1.5
    var inset: CGFloat = -2 // sits slightly outside the rect, like a real brush

    func body(content: Content) -> some View {
        content.overlay {
            ZStack {
                cornerPath(corner: .topLeading)
                cornerPath(corner: .topTrailing)
                cornerPath(corner: .bottomTrailing)
                cornerPath(corner: .bottomLeading)
            }
            .allowsHitTesting(false)
        }
    }

    private enum Corner { case topLeading, topTrailing, bottomTrailing, bottomLeading }

    private func cornerPath(corner: Corner) -> some View {
        Path { p in
            switch corner {
            case .topLeading:
                p.move(to: CGPoint(x: 0, y: size))
                p.addLine(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: size, y: 0))
            case .topTrailing:
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: size, y: 0))
                p.addLine(to: CGPoint(x: size, y: size))
            case .bottomTrailing:
                p.move(to: CGPoint(x: size, y: 0))
                p.addLine(to: CGPoint(x: size, y: size))
                p.addLine(to: CGPoint(x: 0, y: size))
            case .bottomLeading:
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: 0, y: size))
                p.addLine(to: CGPoint(x: size, y: size))
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: weight, lineCap: .square))
        .frame(width: size, height: size)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(for: corner))
        .padding(corner == .topLeading || corner == .topTrailing
                 ? .top : .bottom, inset)
        .padding(corner == .topLeading || corner == .bottomLeading
                 ? .leading : .trailing, inset)
    }

    private func alignment(for corner: Corner) -> Alignment {
        switch corner {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomTrailing: return .bottomTrailing
        case .bottomLeading: return .bottomLeading
        }
    }
}

extension View {
    func sumiCorners(
        color: Color = .ikeruPrimaryAccent,
        size: CGFloat = 10,
        weight: CGFloat = 1.5,
        inset: CGFloat = -2
    ) -> some View {
        modifier(SumiCornerFrame(color: color, size: size, weight: weight, inset: inset))
    }
}

#Preview("SumiCornerFrame") {
    VStack(spacing: 24) {
        Rectangle()
            .fill(Color.ikeruSurface)
            .frame(width: 200, height: 100)
            .sumiCorners(color: .ikeruPrimaryAccent)
        Rectangle()
            .fill(Color.ikeruSurface)
            .frame(width: 200, height: 100)
            .sumiCorners(color: TatamiTokens.goldDim, size: 6, weight: 1.2)
    }
    .padding(40)
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
