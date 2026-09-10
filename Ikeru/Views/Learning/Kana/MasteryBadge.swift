import SwiftUI
import IkeruCore

/// Tiny visual indicator for a `MasteryLevel`: serif kanji glyph + optional label.
struct MasteryBadge: View {

    let level: MasteryLevel
    var showLabel: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Text(level.glyph)
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(Color.ikeruPrimaryAccent)
            if showLabel {
                // `level.label` is a catalog KEY (see MasteryLevel.label doc
                // comment), not display text — wrap it so the lookup runs
                // against the app's own localized bundle.
                Text(LocalizedStringKey(level.label))
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
        }
    }
}

#Preview("MasteryBadge") {
    VStack(spacing: 8) {
        ForEach(MasteryLevel.allCases, id: \.self) { level in
            MasteryBadge(level: level, showLabel: true)
        }
    }
    .padding()
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
