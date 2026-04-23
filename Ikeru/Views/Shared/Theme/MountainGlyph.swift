import SwiftUI
import IkeruCore

// MARK: - MountainGlyph
//
// A minimalist mountain silhouette used as the RPG tab icon. The metaphor
// is the learner's journey toward a summit — more aligned with the
// wabi-sabi / ikebana / Fuji visual vocabulary than the heraldic shield it
// replaces.
//
// Two-peak outline, stroked by default (matches the SF Symbol weight of the
// other tab icons) and fillable via `filled` for the selected state.

struct MountainGlyph: View {
    var filled: Bool = false
    var color: Color = .ikeruTextSecondary

    var body: some View {
        MountainShape()
            .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            .background {
                if filled {
                    MountainShape()
                        .fill(color.opacity(0.22))
                }
            }
    }
}

struct MountainShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + w * x, y: rect.minY + h * y)
        }
        // Baseline (two low anchors) + two peaks — the tall peak on the left,
        // the shorter one on the right, with a valley between. Inspired by
        // Hokusai's 三十六景 (thirty-six views) silhouette language.
        p.move(to: pt(0.08, 0.84))
        p.addLine(to: pt(0.42, 0.26))   // tall peak apex
        p.addLine(to: pt(0.56, 0.52))   // valley shoulder
        p.addLine(to: pt(0.70, 0.38))   // short peak apex
        p.addLine(to: pt(0.92, 0.84))   // right baseline
        p.closeSubpath()

        // A small snow cap hint on the tall peak (drawn as a tiny chevron).
        p.move(to: pt(0.36, 0.36))
        p.addLine(to: pt(0.42, 0.30))
        p.addLine(to: pt(0.48, 0.36))
        return p
    }
}

#Preview("MountainGlyph") {
    ZStack {
        Color.ikeruBackground.ignoresSafeArea()
        HStack(spacing: 24) {
            MountainGlyph()
                .frame(width: 28, height: 28)
            MountainGlyph(filled: true, color: .ikeruPrimaryAccent)
                .frame(width: 40, height: 40)
            MountainGlyph(filled: true, color: .ikeruPrimaryAccent)
                .frame(width: 80, height: 80)
        }
    }
    .preferredColorScheme(.dark)
}
