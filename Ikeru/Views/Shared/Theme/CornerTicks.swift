import SwiftUI
import IkeruCore

// MARK: - CornerTicks
//
// Four faint right-angle ticks in the corners of a rectangle — a scroll-mount
// framing element borrowed from traditional Japanese hanging scrolls (掛軸,
// kakejiku). Used on Card Review cards to subtly frame the glyph without
// adding a full border.

struct CornerTicks: View {
    var color: Color = Color(red: 0.96, green: 0.95, blue: 0.93).opacity(0.15)
    var inset: CGFloat = 14
    var length: CGFloat = 14
    var lineWidth: CGFloat = 1

    var body: some View {
        GeometryReader { _ in
            ZStack {
                // Top-left
                tick(rotation: 0, alignment: .topLeading)
                // Top-right
                tick(rotation: 90, alignment: .topTrailing)
                // Bottom-right
                tick(rotation: 180, alignment: .bottomTrailing)
                // Bottom-left
                tick(rotation: 270, alignment: .bottomLeading)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func tick(rotation: Double, alignment: Alignment) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: length, y: 0))
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 0, y: length))
        }
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
        .frame(width: length, height: length)
        .rotationEffect(.degrees(rotation), anchor: .topLeading)
        .padding(rotation == 0 ? .init([.top, .leading]) :
                 rotation == 90 ? .init([.top, .trailing]) :
                 rotation == 180 ? .init([.bottom, .trailing]) :
                 .init([.bottom, .leading]), inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

#Preview("CornerTicks") {
    ZStack {
        Color.ikeruBackground.ignoresSafeArea()
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.ikeruSurface)
            .overlay(CornerTicks())
            .frame(width: 300, height: 380)
    }
    .preferredColorScheme(.dark)
}
