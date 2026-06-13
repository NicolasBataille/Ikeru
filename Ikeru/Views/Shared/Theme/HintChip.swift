import SwiftUI
import IkeruCore

// MARK: - HintChip
//
// Tiny icon+label pill floating at the bottom of a review card. Used for
// optional affordances (Listen / Hint / Mark on the question state; Listen /
// Strokes / Example on the answer state) without stealing focus from the
// glyph being studied.

struct HintChip: View {
    let icon: String
    let label: LocalizedStringKey
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .ikeruScaledFont(11, weight: .medium, relativeTo: .caption2)
            }
            .foregroundStyle(Color.ikeruTextSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.5), lineWidth: 0.6))
            }
            .sumiCorners(color: TatamiTokens.goldDim, size: 5, weight: 0.9)
        }
        .buttonStyle(.plain)
    }
}

#Preview("HintChip") {
    ZStack {
        Color.ikeruBackground.ignoresSafeArea()
        HStack(spacing: 8) {
            HintChip(icon: "ear", label: "Listen")
            HintChip(icon: "eye", label: "Hint")
            HintChip(icon: "star", label: "Mark")
        }
    }
    .preferredColorScheme(.dark)
}
