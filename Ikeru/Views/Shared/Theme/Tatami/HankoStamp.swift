import SwiftUI

// MARK: - HankoStamp
//
// Vermilion clipped square containing a serif kanji. Used at most once per
// screen to mark the single most urgent thing — the only red in the entire
// UI. Slight clip-path irregularity is intentional: this has to read as a
// real ink seal impression, not a pristine button.

struct HankoStamp: View {
    let kanji: String
    var size: CGFloat = 32
    var opacity: Double = 0.95
    /// Set when the seal is pure ornament at this call site — its meaning
    /// already carried by adjacent text (e.g. a subtitle right below it).
    /// Hides it from VoiceOver instead of reading the raw kanji, which would
    /// otherwise be announced untranslated.
    var isDecorative: Bool = false

    var body: some View {
        ZStack {
            // Slightly irregular ink seal — clip-path mimics the tiny
            // unevenness of pressed-stone seal contact with paper.
            HankoMaskShape()
                .fill(TatamiTokens.vermilion)
                .opacity(opacity)
                .overlay(
                    HankoMaskShape()
                        .stroke(.black.opacity(0.25), lineWidth: 0.6)
                        .blur(radius: 0.5)
                )
            Text(kanji)
                .font(.system(size: size * 0.55, weight: .bold, design: .serif))
                .foregroundStyle(Color(red: 0.961, green: 0.949, blue: 0.925)) // ikeru paper
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHidden(isDecorative)
    }

    /// VoiceOver label for the seal. The two semantic kanji used across the
    /// app get a translated label (急 = urgency marker on Home, 選 = active
    /// pick in the language picker); anything else (achievement kanji, JLPT
    /// levels like "N5") is read as-is.
    private var accessibilityLabelText: String {
        switch kanji {
        case "急":
            return String(localized: "Hanko.Accessibility.Urgent")
        case "選":
            return String(localized: "Hanko.Accessibility.Selected")
        default:
            return kanji
        }
    }
}

private struct HankoMaskShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        // Tiny offsets each corner — irregularities of a stamp impression
        path.move(to: CGPoint(x: w * 0.02, y: 0))
        path.addLine(to: CGPoint(x: w * 0.98, y: h * 0.01))
        path.addLine(to: CGPoint(x: w, y: h * 0.97))
        path.addLine(to: CGPoint(x: w * 0.01, y: h * 0.99))
        path.closeSubpath()
        return path
    }
}

#Preview("HankoStamp") {
    HStack(spacing: 24) {
        HankoStamp(kanji: "急", size: 36)
        HankoStamp(kanji: "N5", size: 42)
        HankoStamp(kanji: "極", size: 28)
    }
    .padding(40)
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
