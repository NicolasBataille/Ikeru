import SwiftUI
import IkeruCore

// MARK: - LevelUpView
//
// Quiet celebration overlay replacing the old star-burst "LEVEL UP!"
// treatment: an ensō ring holding the new level, a small hanko accent, and
// one line of copy. Tap anywhere to dismiss — the whole card is the button,
// there's no separate dismiss chrome to hunt for.

struct LevelUpView: View {
    let level: Int
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var contentScale: CGFloat = 0.86
    @State private var contentOpacity: Double = 0
    @State private var glowPulse = false

    var body: some View {
        Button(action: onDismiss) {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()

                VStack(spacing: IkeruTheme.Spacing.xl) {
                    ZStack {
                        glow
                        EnsoRankView(level: level, size: 148, color: .ikeruPrimaryAccent)
                        HankoStamp(kanji: "昇段", size: 32, isDecorative: true)
                            .offset(x: 50, y: 50)
                    }

                    VStack(spacing: 8) {
                        Text("New rank achieved")
                            .ikeruScaledFont(19, weight: .regular, design: .serif, relativeTo: .title3)
                            .foregroundStyle(Color.ikeruTextPrimary)

                        Text("Tap to dismiss")
                            .font(.ikeruMicro)
                            .ikeruTracking(.micro)
                            .foregroundStyle(Color.ikeruTextTertiary)
                    }
                }
                .scaleEffect(contentScale)
                .opacity(contentOpacity)
            }
        }
        .buttonStyle(.plain)
        .transition(.opacity)
        .onAppear {
            AccessibilityNotification.Announcement(announcementMessage).post()
            animateIn()
        }
    }

    /// Ambient breathing glow behind the ring. Purely decorative — skipped
    /// entirely under Reduce Motion rather than frozen mid-pulse.
    private var glow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color.ikeruPrimaryAccent.opacity(glowPulse ? 0.32 : 0.16), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 110
                )
            )
            .frame(width: 220, height: 220)
            .accessibilityHidden(true)
    }

    private var announcementMessage: String {
        "\(String(localized: "Rank")) \(level) — \(String(localized: "New rank achieved"))"
    }

    private func animateIn() {
        guard !reduceMotion else {
            // Reduce Motion: show the final state immediately, no spring-in,
            // no ambient pulse loop.
            contentScale = 1
            contentOpacity = 1
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
            contentScale = 1
            contentOpacity = 1
        }
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            glowPulse = true
        }
    }
}

#Preview("LevelUpView") {
    LevelUpView(level: 12, onDismiss: {})
        .preferredColorScheme(.dark)
}
