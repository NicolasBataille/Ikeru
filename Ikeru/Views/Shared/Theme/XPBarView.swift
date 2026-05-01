import SwiftUI
import IkeruCore

// MARK: - XPBarView Variant

enum XPBarVariant: Sendable {
    /// Full variant for home screen: shows level number + XP/total + animated bar.
    case full
    /// Compact variant for session header: thin bar only.
    case compact
}

// MARK: - XPBarView

/// Animated XP progress bar with full and compact variants.
/// Full variant shows level, XP text, and bar. Compact shows only the bar.
struct XPBarView: View {

    /// Current total XP.
    let totalXP: Int

    /// Current level.
    let level: Int

    /// Display variant.
    let variant: XPBarVariant

    /// Whether the bar is near level-up (triggers pulse glow).
    private var isNearLevelUp: Bool {
        RPGService.isNearLevelUp(totalXP: totalXP)
    }

    /// Progress fraction within the current level (0.0 to 1.0).
    private var progressFraction: Double {
        RPGConstants.progressFraction(totalXP: totalXP)
    }

    /// Progress within current level as (current, required).
    private var progressInLevel: (current: Int, required: Int) {
        RPGConstants.progressInLevel(totalXP: totalXP)
    }

    // MARK: - Pulse Animation State

    @State private var isPulsing = false

    /// Name of the equipped theme cosmetic, if any. Read from UserDefaults so
    /// every XP bar in the app reflects the current cosmetic without plumbing.
    @AppStorage("ikeru.equippedThemeName") private var equippedThemeName: String = ""

    var body: some View {
        switch variant {
        case .full:
            fullVariant
        case .compact:
            compactVariant
        }
    }

    // MARK: - Full Variant
    //
    // Rank chrome was removed here because the calling screens (RPGProfile,
    // Home) now lead with `EnsoRankView` + 第N段 — the brushed glyph carries
    // rank identity. Repeating "Lv. N" with a shield icon doubled the visual
    // weight and contradicted the wabi-sabi refinement direction.

    private var fullVariant: some View {
        VStack(alignment: .trailing, spacing: IkeruTheme.Spacing.xs) {
            HStack {
                Text("EXPERIENCE")
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(Color.ikeruTextTertiary)

                Spacer()

                Text("\(progressInLevel.current) / \(progressInLevel.required) XP")
                    .font(.ikeruStats)
                    .foregroundStyle(.ikeruTextSecondary)
            }

            // Animated bar
            xpBar(height: 8)
        }
    }

    // MARK: - Compact Variant

    private var compactVariant: some View {
        xpBar(height: 4)
    }

    // MARK: - XP Bar

    private func xpBar(height: CGFloat) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.ikeruSurface)
                    .frame(height: height)

                // Fill with amber-to-gold gradient
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(xpGradient)
                    .frame(
                        width: geometry.size.width * max(0, min(1, progressFraction)),
                        height: height
                    )
                    .animation(
                        .spring(duration: 0.5, bounce: 0.2),
                        value: progressFraction
                    )
                    .shadow(
                        color: isNearLevelUp
                            ? Color(hex: IkeruTheme.Colors.Rarity.legendary).opacity(isPulsing ? 0.6 : 0.2)
                            : .clear,
                        radius: isNearLevelUp ? 8 : 0
                    )
                    .animation(
                        isNearLevelUp
                            ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                            : .default,
                        value: isPulsing
                    )
            }
        }
        .frame(height: height)
        .onAppear {
            if isNearLevelUp {
                isPulsing = true
            }
        }
        .onChange(of: isNearLevelUp) { _, newValue in
            isPulsing = newValue
        }
    }

    // MARK: - Gradient

    private var xpGradient: LinearGradient {
        let palette = ThemePaletteService.palette(
            forThemeName: equippedThemeName.isEmpty ? nil : equippedThemeName
        )
        return LinearGradient(
            colors: [
                Color(hex: palette.startHex),
                Color(hex: palette.endHex)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Preview

#Preview("XPBarView Full") {
    ZStack {
        Color.ikeruBackground.ignoresSafeArea()

        VStack(spacing: IkeruTheme.Spacing.xl) {
            XPBarView(totalXP: 50, level: 1, variant: .full)
            XPBarView(totalXP: 95, level: 1, variant: .full)
            XPBarView(totalXP: 250, level: 3, variant: .full)
        }
        .padding(IkeruTheme.Spacing.lg)
    }
    .preferredColorScheme(.dark)
}

#Preview("XPBarView Compact") {
    ZStack {
        Color.ikeruBackground.ignoresSafeArea()

        VStack(spacing: IkeruTheme.Spacing.xl) {
            XPBarView(totalXP: 30, level: 1, variant: .compact)
            XPBarView(totalXP: 80, level: 1, variant: .compact)
        }
        .padding(IkeruTheme.Spacing.lg)
    }
    .preferredColorScheme(.dark)
}
