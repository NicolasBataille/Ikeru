import SwiftUI
import IkeruCore

// MARK: - LootRevealView

/// Full-screen lootbox opening celebration with kintsugi-inspired reveal animation.
/// Tatami DA: gold-intensity rarity (dim → warm → bright), animated kintsugi seam trace,
/// Rectangle rarity badge with sumiCorners, haptic crescendo, sequential item reveal.
struct LootRevealView: View {

    /// The items to reveal.
    let items: [LootItem]

    /// Callback when the reveal is complete and dismissed.
    var onDismiss: (() -> Void)?

    @State private var revealPhase: RevealPhase = .buildup
    @State private var currentItemIndex: Int = 0
    @State private var backgroundOpacity: Double = 0
    @State private var itemScale: CGFloat = 0.88
    @State private var itemOpacity: Double = 0
    @State private var seamProgress: CGFloat = 0     // kintsugi seam [0..1]
    @State private var veinsOpacity: Double = 0      // radial gold vein bloom

    // Haptic triggers
    @State private var haptic1 = false
    @State private var haptic2 = false
    @State private var haptic3 = false
    @State private var hapticFinal = false

    var body: some View {
        ZStack {
            // Ink background
            Color.black.opacity(0.88)
                .ignoresSafeArea()
                .opacity(backgroundOpacity)

            // Radial gold bloom — replaces colored glow; intensity scales with rarity
            RadialGradient(
                colors: [
                    rarityGold.opacity(rarityBloomOpacity * veinsOpacity),
                    rarityGold.opacity(0)
                ],
                center: .center,
                startRadius: 10,
                endRadius: 220
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Kintsugi seam — radiates from centre after reveal
            KintsugiRevealSeams(
                progress: seamProgress,
                color: rarityGold
            )
            .allowsHitTesting(false)

            // Current item card
            if revealPhase == .reveal || revealPhase == .complete {
                currentItemCard
                    .scaleEffect(itemScale)
                    .opacity(itemOpacity)
            }

            // "Tap to continue" hint
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
        .onTapGesture { handleTap() }
        .onAppear { startRevealSequence() }
    }

    // MARK: - Current Item Card

    private var currentItemCard: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            // Item icon — gold-tinted, no colored shadow
            Image(systemName: currentItem.iconName)
                .font(.system(size: 60))
                .foregroundStyle(rarityGold)
                .shadow(color: rarityGold.opacity(0.45), radius: 16)

            // Item name
            Text(currentItem.name)
                .ikeruScaledFont(IkeruTheme.Typography.Size.heading1, weight: .semibold, design: .serif, relativeTo: .title)
                .foregroundStyle(Color.ikeruTextPrimary)

            // Rarity badge — Rectangle + sumiCorners (no Capsule)
            Text(currentItem.rarity.displayName)
                .font(.ikeruStats)
                .foregroundStyle(rarityGold)
                .textCase(.uppercase)
                .tracking(IkeruTheme.Typography.Tracking.micro)
                .padding(.horizontal, IkeruTheme.Spacing.md)
                .padding(.vertical, IkeruTheme.Spacing.xs)
                .background(
                    Rectangle()
                        .fill(rarityGold.opacity(0.08))
                )
                .overlay(
                    Rectangle()
                        .strokeBorder(rarityGold.opacity(0.55), lineWidth: 0.8)
                )
                .sumiCorners(color: rarityGold, size: 6, weight: 1.0)

            // Category — secondary text, decorative context
            Text(currentItem.category.displayName)
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)
        }
        .padding(IkeruTheme.Spacing.xl)
        .background(
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.122, green: 0.102, blue: 0.071, opacity: 0.92),
                            Color(red: 0.08, green: 0.07, blue: 0.05, opacity: 0.95)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(alignment: .top) { FusumaRail(gold: rarityGold, opacity: 1.0) }
        .overlay(alignment: .bottom) { FusumaRail(gold: rarityGold, opacity: 1.0, inverted: true) }
        .sumiCorners(color: rarityGold, size: 10, weight: 1.5)
        .padding(.horizontal, IkeruTheme.Spacing.xl)
    }

    // MARK: - State helpers

    private var currentItem: LootItem {
        guard !items.isEmpty else {
            return LootItem(
                category: .badge,
                rarity: .common,
                name: "Empty",
                iconName: "questionmark.circle.fill"
            )
        }
        let idx = min(currentItemIndex, items.count - 1)
        return items[idx]
    }

    private var hasMoreItems: Bool {
        currentItemIndex < items.count - 1
    }

    /// Gold intensity mapped from rarity. Forbidden colors (blue/purple/gray/green) replaced.
    private var rarityGold: Color {
        switch currentItem.rarity {
        case .common:    return TatamiTokens.goldDim                      // #8A6D4A dim gold
        case .uncommon:  return Color(hex: 0xAD8A58)                     // mid-dim gold
        case .rare:      return Color(hex: 0xC09060)                     // medium gold
        case .epic:      return Color(hex: 0xD4A574)                     // warm gold (primaryAccent)
        case .legendary: return Color(hex: 0xE5BC8A)                     // bright gold
        }
    }

    /// Radial bloom opacity by rarity — common is very subtle, legendary is rich.
    private var rarityBloomOpacity: Double {
        switch currentItem.rarity {
        case .common:    return 0.08
        case .uncommon:  return 0.12
        case .rare:      return 0.18
        case .epic:      return 0.25
        case .legendary: return 0.35
        }
    }

    // MARK: - Animation Sequence

    private func startRevealSequence() {
        // Background fade in
        withAnimation(.easeIn(duration: 0.3)) {
            backgroundOpacity = 1
        }

        // Haptic crescendo
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { haptic1.toggle() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { haptic2.toggle() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { haptic3.toggle() }

        // Gold bloom expands (gentle, not explosive)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.8)) {
                veinsOpacity = 1.0
            }
        }

        // Card settles in + haptic peak
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            hapticFinal.toggle()
            withAnimation(.spring(duration: 0.45, bounce: 0.10)) {
                itemScale = 1.0
                itemOpacity = 1.0
                revealPhase = .reveal
            }
        }

        // Kintsugi seam traces after card arrives
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            withAnimation(.easeInOut(duration: 0.6)) {
                seamProgress = 1.0
            }
        }
    }

    private func handleTap() {
        guard revealPhase == .reveal else { return }

        if hasMoreItems {
            // Fade out current item
            withAnimation(.easeOut(duration: 0.2)) {
                itemOpacity = 0
                itemScale = 0.92
                seamProgress = 0
                veinsOpacity = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                currentItemIndex += 1
                hapticFinal.toggle()

                // Settle next item in
                withAnimation(.spring(duration: 0.45, bounce: 0.10)) {
                    itemScale = 1.0
                    itemOpacity = 1.0
                }

                // Bloom for next rarity
                withAnimation(.easeOut(duration: 0.6)) {
                    veinsOpacity = 1.0
                }

                // Seam traces again
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeInOut(duration: 0.55)) {
                        seamProgress = 1.0
                    }
                }
            }
        } else {
            // Dismiss
            withAnimation(.easeOut(duration: 0.3)) {
                backgroundOpacity = 0
                itemOpacity = 0
                veinsOpacity = 0
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

// MARK: - KintsugiRevealSeams

/// Two kintsugi seam paths that draw out from the card centre, evoking a repair
/// spreading outward after a break is healed. Much more contained and meditative
/// than a particle burst.
private struct KintsugiRevealSeams: View {
    let progress: CGFloat   // [0..1]
    let color: Color

    var body: some View {
        Canvas { context, size in
            let cx = size.width * 0.5
            let cy = size.height * 0.5

            // Two diagonal seam arms emanating from centre
            // Arm 1: upper-left → lower-right diagonal
            // Arm 2: upper-right → lower-left diagonal
            let armLength: CGFloat = min(size.width, size.height) * 0.42

            var path = Path()

            // Arm 1 — upper-left direction
            let arm1Progress = min(progress * 2, 1.0)
            if arm1Progress > 0 {
                let endX = cx - armLength * arm1Progress * 0.7
                let endY = cy - armLength * arm1Progress * 0.9
                path.move(to: CGPoint(x: cx, y: cy))
                path.addQuadCurve(
                    to: CGPoint(x: endX, y: endY),
                    control: CGPoint(x: cx - armLength * arm1Progress * 0.3, y: cy - armLength * arm1Progress * 0.2)
                )
            }

            // Arm 2 — lower-right direction
            let arm2Progress = min(progress * 2, 1.0)
            if arm2Progress > 0 {
                let endX = cx + armLength * arm2Progress * 0.65
                let endY = cy + armLength * arm2Progress * 0.85
                path.move(to: CGPoint(x: cx, y: cy))
                path.addQuadCurve(
                    to: CGPoint(x: endX, y: endY),
                    control: CGPoint(x: cx + armLength * arm2Progress * 0.25, y: cy + armLength * arm2Progress * 0.25)
                )
            }

            // Short branch — upper-right accent (delayed to second half)
            let branchProgress = max((progress - 0.5) * 2, 0.0)
            if branchProgress > 0 {
                let startX = cx + armLength * 0.18
                let startY = cy - armLength * 0.12
                let endX = cx + armLength * branchProgress * 0.55
                let endY = cy - armLength * branchProgress * 0.72
                path.move(to: CGPoint(x: startX, y: startY))
                path.addLine(to: CGPoint(x: endX, y: endY))
            }

            // Glow pass
            var glowCtx = context
            glowCtx.addFilter(.blur(radius: 5))
            glowCtx.opacity = 0.4
            glowCtx.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: 5, lineCap: .round)
            )

            // Core seam
            context.stroke(
                path,
                with: .color(color.opacity(0.85)),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
            )
        }
    }
}

// MARK: - Preview

#Preview("LootRevealView — Legendary") {
    LootRevealView(
        items: [
            LootItem(
                category: .badge,
                rarity: .legendary,
                name: "Phoenix Feather",
                iconName: "flame.fill"
            )
        ]
    )
    .preferredColorScheme(.dark)
}

#Preview("LootRevealView — Common") {
    LootRevealView(
        items: [
            LootItem(
                category: .badge,
                rarity: .common,
                name: "Kana Shard",
                iconName: "hexagon.fill"
            )
        ]
    )
    .preferredColorScheme(.dark)
}

#Preview("LootRevealView — Multiple items") {
    LootRevealView(
        items: [
            LootItem(category: .badge, rarity: .common, name: "Kana Shard", iconName: "hexagon.fill"),
            LootItem(category: .scroll, rarity: .rare, name: "Proverb Scroll", iconName: "scroll.fill"),
            LootItem(category: .badge, rarity: .legendary, name: "Phoenix Feather", iconName: "flame.fill")
        ]
    )
    .preferredColorScheme(.dark)
}
