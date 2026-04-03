import SwiftUI
import IkeruCore

// MARK: - LootDropView

/// Displays a loot drop notification with bounce animation and haptic feedback.
/// Slides in from the bottom, bounces, and auto-dismisses after 2 seconds.
struct LootDropView: View {

    /// The loot item that was dropped.
    let item: LootItem

    /// Callback when the drop notification is dismissed.
    var onDismiss: (() -> Void)?

    @State private var offset: CGFloat = 200
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.8
    @State private var glowPulse = false
    @State private var hapticTrigger = false

    var body: some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            // Item icon with rarity glow
            Image(systemName: item.iconName)
                .font(.system(size: 28))
                .foregroundStyle(rarityColor)
                .shadow(color: rarityColor.opacity(glowPulse ? 0.6 : 0.2), radius: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.ikeruBody)
                    .foregroundStyle(.white)
                    .fontWeight(.semibold)

                Text(item.rarity.displayName)
                    .font(.ikeruCaption)
                    .foregroundStyle(rarityColor)
                    .textCase(.uppercase)
            }

            Spacer()

            Text(item.category.displayName)
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)
        }
        .padding(IkeruTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.md)
                .fill(Color.ikeruSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: IkeruTheme.Radius.md)
                        .stroke(rarityColor.opacity(0.4), lineWidth: 1)
                )
        )
        .shadow(color: rarityColor.opacity(0.3), radius: 16)
        .scaleEffect(scale)
        .offset(y: offset)
        .opacity(opacity)
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
        .onAppear {
            playEntrance()
        }
        .animation(
            .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
            value: glowPulse
        )
    }

    // MARK: - Animation Sequence

    private func playEntrance() {
        // Bounce in from bottom
        withAnimation(.spring(duration: 0.5, bounce: 0.4)) {
            offset = 0
            opacity = 1
            scale = 1.0
        }

        // Haptic on arrival
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            hapticTrigger.toggle()
            glowPulse = true
        }

        // Auto-dismiss after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                offset = 200
                opacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onDismiss?()
            }
        }
    }

    // MARK: - Rarity Color

    private var rarityColor: Color {
        switch item.rarity {
        case .common: Color(hex: IkeruTheme.Colors.Rarity.common)
        case .rare: Color(hex: IkeruTheme.Colors.Rarity.rare)
        case .epic: Color(hex: IkeruTheme.Colors.Rarity.epic)
        case .legendary: Color(hex: IkeruTheme.Colors.Rarity.legendary)
        }
    }
}

// MARK: - Loot Drop Overlay Modifier

/// View modifier that shows loot drop notifications as overlays.
struct LootDropOverlayModifier: ViewModifier {

    /// Binding to the current loot drop. Set to nil to hide.
    @Binding var lootDrop: LootItem?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let item = lootDrop {
                LootDropView(item: item) {
                    lootDrop = nil
                }
                .padding(.horizontal, IkeruTheme.Spacing.md)
                .padding(.bottom, IkeruTheme.Spacing.xl)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

extension View {
    /// Shows a loot drop notification when lootDrop is non-nil.
    func lootDropOverlay(item: Binding<LootItem?>) -> some View {
        modifier(LootDropOverlayModifier(lootDrop: item))
    }
}

// MARK: - Preview

#Preview("LootDropView — Common") {
    ZStack {
        Color.ikeruBackground.ignoresSafeArea()
        LootDropView(
            item: LootItem(category: .badge, rarity: .common, name: "Kana Shard", iconName: "hexagon.fill")
        )
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("LootDropView — Legendary") {
    ZStack {
        Color.ikeruBackground.ignoresSafeArea()
        LootDropView(
            item: LootItem(category: .badge, rarity: .legendary, name: "Phoenix Feather", iconName: "flame.fill")
        )
        .padding()
    }
    .preferredColorScheme(.dark)
}
