import SwiftUI

// MARK: - RPGRankCrest
//
// Hero rank crest for the RPG profile. Wraps `ToriiFrame` with the rank
// kanji (大字: 一 二 三 …) centered between the pillars in a serif weight.
//
// Use only at sizes ≥ 80. For smaller rank glyphs (Home pill, hero rank
// row), keep `EnsoRankView` — the torii's architecture loses detail under
// 60pt and reads as noise.

struct RPGRankCrest: View {
    let level: Int
    var size: CGFloat = 96
    var dashed: Bool = false  // for the "next rank" teaser

    var body: some View {
        ToriiFrame(
            color: dashed ? TatamiTokens.goldDim : .ikeruPrimaryAccent,
            lineWidth: dashed ? 2.5 : 4,
            dashed: dashed
        ) {
            Text(rankKanji(level))
                .font(.system(size: size * 0.40, weight: .light, design: .serif))
                .foregroundStyle(dashed ? TatamiTokens.goldDim : Color.ikeruPrimaryAccent)
        }
        .frame(width: size, height: size)
    }

    private func rankKanji(_ n: Int) -> String {
        // Daiji (formal numerals) feel ceremonial enough for ranks. Falls
        // back to the ASCII numeral for ranks beyond the prepared range —
        // the glyph still reads inside the gate.
        let lookup: [Int: String] = [
            1: "一", 2: "二", 3: "三", 4: "四", 5: "五",
            6: "六", 7: "七", 8: "八", 9: "九", 10: "十"
        ]
        return lookup[n] ?? "\(n)"
    }
}

#Preview("RPGRankCrest") {
    HStack(spacing: 32) {
        RPGRankCrest(level: 3, size: 96)
        RPGRankCrest(level: 4, size: 56, dashed: true)
    }
    .padding(40)
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
