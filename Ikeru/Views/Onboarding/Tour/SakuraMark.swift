import SwiftUI

// MARK: - Sakura Mark
//
// A small static stand-in for the companion avatar (the breathing
// CompanionAvatarView is for the live floating button). Used to give the
// onboarding callouts a voice — they read as Sakura speaking to the user.
//
// Canonical treatment: square sumi-bordered ink tile with 桜 in serif gold.
// Matches CompanionAvatarView's avatarCell at any requested size.

struct SakuraMark: View {
    var size: CGFloat = 32

    // Sumi-corner size scales proportionally with the tile.
    private var cornerSize: CGFloat { max(4, size * 0.22) }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.165, green: 0.133, blue: 0.102),
                            Color(red: 0.078, green: 0.067, blue: 0.051)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim, lineWidth: 1))
                .frame(width: size, height: size)
                .sumiCorners(
                    color: .ikeruPrimaryAccent,
                    size: cornerSize,
                    weight: 1.1,
                    inset: -1
                )

            Text("\u{685C}") // 桜 — canonical Sakura crest
                .font(.system(size: size * 0.55, weight: .light, design: .serif))
                .foregroundStyle(Color.ikeruPrimaryAccent)
        }
        .shadow(color: Color.ikeruPrimaryAccent.opacity(0.4), radius: 5)
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview("SakuraMark") {
    HStack(spacing: 20) {
        SakuraMark(size: 24)
        SakuraMark(size: 32)
        SakuraMark(size: 40)
        SakuraMark(size: 44)
    }
    .padding(40)
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
