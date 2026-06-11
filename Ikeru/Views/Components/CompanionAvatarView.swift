import SwiftUI
import IkeruCore

// MARK: - Breathing Phase

private enum BreathingPhase: CaseIterable {
    case inhale
    case exhale
}

// MARK: - CompanionAvatarView

/// 44pt floating companion avatar with breathing animation and attention bounce.
/// Placed as an overlay on MainTabView, persistent across screens.
struct CompanionAvatarView: View {

    /// Whether the avatar should bounce (attention event).
    let hasAttention: Bool

    /// Whether to show the badge indicator (e.g., weekly check-in).
    let showBadge: Bool

    /// Action when the avatar is tapped.
    let onTap: () -> Void

    // MARK: - Private State

    @State private var bounceOffset: CGFloat = 0

    // MARK: - Constants

    private let avatarSize: CGFloat = 44
    private let badgeSize: CGFloat = 12

    // MARK: - Body

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                avatarCell
                if showBadge {
                    badgeIndicator
                }
            }
        }
        .buttonStyle(.plain)
        .offset(y: bounceOffset)
        .onChange(of: hasAttention) { _, attention in
            if attention {
                performBounce()
            }
        }
        .accessibilityLabel("Study companion")
        .accessibilityHint("Opens companion chat")
    }

    // MARK: - Avatar Cell

    /// Canonical Sakura cell: square sumi-bordered ink tile with the kanji 桜
    /// in serif gold (matches `CompanionTabView`'s tutor portrait).
    @ViewBuilder
    private var avatarCell: some View {
        PhaseAnimator(BreathingPhase.allCases) { phase in
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
                    .frame(width: avatarSize, height: avatarSize)
                    .sumiCorners(color: .ikeruPrimaryAccent, size: 7, weight: 1.1, inset: -1)
                    .scaleEffect(phase == .inhale ? 1.05 : 0.95)

                Text("\u{685C}") // 桜 — canonical Sakura crest
                    .font(.system(size: 24, weight: .light, design: .serif))
                    .foregroundStyle(Color.ikeruPrimaryAccent)
            }
            .shadow(
                color: Color(hex: IkeruTheme.Colors.primaryAccent, opacity: 0.4),
                radius: phase == .inhale ? 8 : 4
            )
        } animation: { phase in
            switch phase {
            case .inhale:
                .easeInOut(duration: 2.0)
            case .exhale:
                .easeInOut(duration: 2.0)
            }
        }
    }

    // MARK: - Badge Indicator

    @ViewBuilder
    private var badgeIndicator: some View {
        Circle()
            .fill(Color(hex: IkeruTheme.Colors.secondaryAccent))
            .frame(width: badgeSize, height: badgeSize)
            .offset(x: 2, y: -2)
    }

    // MARK: - Bounce Animation

    private func performBounce() {
        withAnimation(.spring(duration: 0.15, bounce: 0.6)) {
            bounceOffset = -12
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(duration: 0.3, bounce: 0.4)) {
                bounceOffset = 0
            }
        }
    }
}

// MARK: - Preview

#Preview("CompanionAvatarView") {
    ZStack {
        Color(hex: IkeruTheme.Colors.background)
            .ignoresSafeArea()

        VStack(spacing: IkeruTheme.Spacing.lg) {
            CompanionAvatarView(
                hasAttention: false,
                showBadge: false,
                onTap: {}
            )

            CompanionAvatarView(
                hasAttention: false,
                showBadge: true,
                onTap: {}
            )
        }
    }
    .preferredColorScheme(.dark)
}
