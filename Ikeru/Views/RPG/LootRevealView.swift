import SwiftUI
import IkeruCore

// MARK: - LootRevealView

/// Full-screen lootbox opening celebration with dramatic reveal animation.
/// Features: particle burst effect, rarity glow escalation (gray → blue → purple → gold),
/// haptic crescendo, and sequential item reveal.
struct LootRevealView: View {

    /// The items to reveal.
    let items: [LootItem]

    /// Callback when the reveal is complete and dismissed.
    var onDismiss: (() -> Void)?

    @State private var revealPhase: RevealPhase = .buildup
    @State private var currentItemIndex: Int = 0
    @State private var glowScale: CGFloat = 0.3
    @State private var glowOpacity: Double = 0
    @State private var itemScale: CGFloat = 0.1
    @State private var itemOpacity: Double = 0
    @State private var particleActive = false
    @State private var backgroundOpacity: Double = 0

    // Haptic triggers
    @State private var haptic1 = false
    @State private var haptic2 = false
    @State private var haptic3 = false
    @State private var hapticFinal = false

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .opacity(backgroundOpacity)

            // Rarity glow circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [currentRarityColor.opacity(0.8), currentRarityColor.opacity(0)],
                        center: .center,
                        startRadius: 20,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .scaleEffect(glowScale)
                .opacity(glowOpacity)

            // Particle burst
            if particleActive {
                particleBurst
            }

            // Current item reveal
            if revealPhase == .reveal || revealPhase == .complete {
                currentItemView
            }

            // "Tap to continue" at bottom
            if revealPhase == .reveal {
                VStack {
                    Spacer()
                    Text(hasMoreItems ? "Tap for next item" : "Tap to close")
                        .font(.ikeruCaption)
                        .foregroundStyle(.ikeruTextSecondary)
                        .padding(.bottom, IkeruTheme.Spacing.xxl)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: haptic1)
        .sensoryFeedback(.impact(weight: .medium), trigger: haptic2)
        .sensoryFeedback(.impact(weight: .heavy), trigger: haptic3)
        .sensoryFeedback(.success, trigger: hapticFinal)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
        .onAppear {
            startRevealSequence()
        }
    }

    // MARK: - Current Item View

    private var currentItemView: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            // Item icon with glow
            Image(systemName: currentItem.iconName)
                .font(.system(size: 64))
                .foregroundStyle(currentRarityColor)
                .shadow(color: currentRarityColor.opacity(0.6), radius: 24)
                .scaleEffect(itemScale)

            // Item name
            Text(currentItem.name)
                .font(.system(size: IkeruTheme.Typography.Size.heading1, weight: .bold))
                .foregroundStyle(.white)
                .opacity(itemOpacity)

            // Rarity badge
            Text(currentItem.rarity.displayName)
                .font(.ikeruStats)
                .foregroundStyle(currentRarityColor)
                .textCase(.uppercase)
                .padding(.horizontal, IkeruTheme.Spacing.md)
                .padding(.vertical, IkeruTheme.Spacing.xs)
                .background(
                    Capsule()
                        .fill(currentRarityColor.opacity(0.2))
                )
                .opacity(itemOpacity)

            // Category
            Text(currentItem.category.displayName)
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)
                .opacity(itemOpacity)
        }
    }

    // MARK: - Particle Burst

    private var particleBurst: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                Circle()
                    .fill(currentRarityColor)
                    .frame(width: 6, height: 6)
                    .offset(particleOffset(index: index))
                    .opacity(particleActive ? 0 : 1)
                    .animation(
                        .easeOut(duration: 0.8)
                            .delay(Double(index) * 0.03),
                        value: particleActive
                    )
            }
        }
    }

    private func particleOffset(index: Int) -> CGSize {
        let angle = (Double(index) / 12.0) * .pi * 2
        let distance: CGFloat = particleActive ? 150 : 0
        return CGSize(
            width: cos(angle) * distance,
            height: sin(angle) * distance
        )
    }

    // MARK: - State

    private var currentItem: LootItem {
        guard currentItemIndex < items.count else { return items.last! }
        return items[currentItemIndex]
    }

    private var hasMoreItems: Bool {
        currentItemIndex < items.count - 1
    }

    private var currentRarityColor: Color {
        switch currentItem.rarity {
        case .common: Color(hex: IkeruTheme.Colors.Rarity.common)
        case .rare: Color(hex: IkeruTheme.Colors.Rarity.rare)
        case .epic: Color(hex: IkeruTheme.Colors.Rarity.epic)
        case .legendary: Color(hex: IkeruTheme.Colors.Rarity.legendary)
        }
    }

    // MARK: - Animation Sequence

    private func startRevealSequence() {
        // Phase 1: Background fade in
        withAnimation(.easeIn(duration: 0.3)) {
            backgroundOpacity = 1
        }

        // Phase 2: Haptic crescendo (3 hits escalating)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { haptic1.toggle() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { haptic2.toggle() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { haptic3.toggle() }

        // Phase 3: Glow expansion
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(duration: 0.6, bounce: 0.3)) {
                glowScale = 1.5
                glowOpacity = 0.8
            }
        }

        // Phase 4: Particle burst + item reveal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            particleActive = true
            hapticFinal.toggle()

            withAnimation(.spring(duration: IkeruTheme.Animation.dramaticDuration, bounce: IkeruTheme.Animation.dramaticBounce)) {
                itemScale = 1.0
                itemOpacity = 1.0
                revealPhase = .reveal
            }

            // Settle glow
            withAnimation(.easeOut(duration: 1.0)) {
                glowScale = 1.0
                glowOpacity = 0.4
            }
        }
    }

    private func handleTap() {
        guard revealPhase == .reveal else { return }

        if hasMoreItems {
            // Reveal next item
            withAnimation(.easeOut(duration: 0.2)) {
                itemScale = 0.1
                itemOpacity = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                currentItemIndex += 1
                particleActive = false

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    particleActive = true
                    hapticFinal.toggle()

                    withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
                        itemScale = 1.0
                        itemOpacity = 1.0
                        glowScale = 1.5
                        glowOpacity = 0.8
                    }

                    withAnimation(.easeOut(duration: 0.8)) {
                        glowScale = 1.0
                        glowOpacity = 0.4
                    }
                }
            }
        } else {
            // Dismiss
            withAnimation(.easeOut(duration: 0.3)) {
                backgroundOpacity = 0
                itemOpacity = 0
                glowOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onDismiss?()
            }
        }
    }

    enum RevealPhase {
        case buildup
        case reveal
        case complete
    }
}

// MARK: - Preview

#Preview("LootRevealView — Single Epic") {
    LootRevealView(
        items: [
            LootItem(category: .badge, rarity: .epic, name: "Dragon Scale", iconName: "shield.lefthalf.filled"),
        ]
    )
    .preferredColorScheme(.dark)
}

#Preview("LootRevealView — Multiple Items") {
    LootRevealView(
        items: [
            LootItem(category: .badge, rarity: .common, name: "Kana Shard", iconName: "hexagon.fill"),
            LootItem(category: .scroll, rarity: .rare, name: "Proverb Scroll", iconName: "scroll.fill"),
            LootItem(category: .badge, rarity: .legendary, name: "Phoenix Feather", iconName: "flame.fill"),
        ]
    )
    .preferredColorScheme(.dark)
}
