import SwiftUI

// MARK: - MonCrest
//
// Four geometric Japanese family-crest variants:
// - asanoha (hemp-leaf, 6-point star inside circle)
// - genji (4-fold cross inside circle)
// - kikkou (hexagon)
// - maru (simple ring)
//
// Used as deck identifiers, tab-bar active markers, status indicators.
// Replaces colored dots and SF Symbols.

struct MonCrest: View {
    let kind: MonKind
    var size: CGFloat = 14
    var color: Color = .ikeruPrimaryAccent
    var lineWidth: CGFloat? = nil  // defaults to size * 0.066

    var body: some View {
        MonCrestShape(kind: kind)
            .stroke(color, lineWidth: lineWidth ?? max(0.6, size * 0.066))
            .frame(width: size, height: size)
    }
}

struct MonCrestShape: Shape {
    let kind: MonKind

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) * 0.46
        var p = Path()

        switch kind {
        case .asanoha:
            p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            for i in 0..<6 {
                let a = (Double(i) * .pi / 3) - .pi / 2
                let endpoint = CGPoint(x: c.x + cos(a) * r * 0.88,
                                        y: c.y + sin(a) * r * 0.88)
                p.move(to: c)
                p.addLine(to: endpoint)
            }

        case .genji:
            p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            p.move(to: CGPoint(x: c.x, y: c.y - r))
            p.addLine(to: CGPoint(x: c.x, y: c.y + r))
            p.move(to: CGPoint(x: c.x - r, y: c.y))
            p.addLine(to: CGPoint(x: c.x + r, y: c.y))

        case .kikkou:
            for i in 0..<6 {
                let a = Double(i) * .pi / 3
                let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()

        case .maru:
            let inner = r * 0.85
            p.addEllipse(in: CGRect(x: c.x - inner, y: c.y - inner,
                                     width: inner * 2, height: inner * 2))
        }
        return p
    }
}

#Preview("MonCrest") {
    HStack(spacing: 24) {
        ForEach(MonKind.allCases, id: \.self) { kind in
            VStack {
                MonCrest(kind: kind, size: 32, color: .ikeruPrimaryAccent)
                Text(kind.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
    .padding(40)
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
