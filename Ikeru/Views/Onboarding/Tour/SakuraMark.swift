import SwiftUI

// MARK: - Sakura Mark
//
// A small static stand-in for the companion avatar (the breathing
// CompanionAvatarView is for the live floating button). Used to give the
// onboarding callouts a voice — they read as Sakura speaking to the user.

struct SakuraMark: View {
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient.ikeruGold)
            Text("\u{3055}") // さ — first kana of さくら (Sakura)
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(Color.ikeruBackground)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.ikeruPrimaryAccent.opacity(0.4), radius: 5)
        .accessibilityHidden(true)
    }
}
