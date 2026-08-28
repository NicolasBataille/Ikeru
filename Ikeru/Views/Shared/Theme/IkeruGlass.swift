import SwiftUI
import IkeruCore

// MARK: - Glass Surface

/// A premium glass surface that handles material, tint, edge highlight, and border
/// in one composable shape. Use this as the background of any custom panel.
public struct IkeruGlassSurface: View {
    public var cornerRadius: CGFloat = IkeruTheme.Radius.lg
    public var tint: Color = .clear
    public var tintOpacity: Double = 0.06
    public var highlight: Double = 0.16
    public var strokeOpacity: Double = 0.18
    public var strokeWidth: CGFloat = 0.6

    public init(
        cornerRadius: CGFloat = IkeruTheme.Radius.lg,
        tint: Color = .clear,
        tintOpacity: Double = 0.06,
        highlight: Double = 0.16,
        strokeOpacity: Double = 0.18,
        strokeWidth: CGFloat = 0.6
    ) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.tintOpacity = tintOpacity
        self.highlight = highlight
        self.strokeOpacity = strokeOpacity
        self.strokeWidth = strokeWidth
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tint.opacity(tintOpacity))

            // Top edge sheen
            LinearGradient(
                colors: [
                    Color.white.opacity(highlight),
                    Color.white.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .center
            )
            .blendMode(.plusLighter)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .allowsHitTesting(false)

            // Border
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(strokeOpacity),
                            Color.white.opacity(strokeOpacity * 0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: strokeWidth
                )
        }
    }
}

// MARK: - Section Header

/// Premium section header with optional eyebrow label and trailing accessory.
public struct IkeruSectionHeader<Trailing: View>: View {
    /// `LocalizedStringKey`, pas `String` (OBS2-050). Avec `String`, l'init
    /// `Text(verbatim:)` est choisi : aucune recherche dans le catalogue, et
    /// surtout aucune EXTRACTION — ces libellés n'étaient même pas collectés,
    /// ce qui explique qu'ils aient traversé un lint i18n vert. Les littéraux
    /// aux sites d'appel continuent de compiler tels quels ; une variable doit
    /// être enveloppée explicitement.
    public let title: LocalizedStringKey
    public let eyebrow: LocalizedStringKey?
    public let trailing: Trailing

    public init(
        title: LocalizedStringKey,
        eyebrow: LocalizedStringKey? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.eyebrow = eyebrow
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow {
                    // `.textCase(.uppercase)` et non `.uppercased()` : une
                    // `LocalizedStringKey` n'est pas une chaîne, et la mise en
                    // capitales doit de toute façon se faire APRÈS la
                    // traduction, pas sur la clé.
                    Text(eyebrow)
                        .textCase(.uppercase)
                        .font(.ikeruMicro)
                        .ikeruTracking(.micro)
                        .foregroundStyle(Color.ikeruTextTertiary)
                }
                Text(title)
                    .font(.ikeruHeading2)
                    .ikeruTracking(.heading)
                    .foregroundStyle(Color.ikeruTextPrimary)
            }
            Spacer()
            trailing
        }
    }
}

// MARK: - Stat Pill

/// Small floating glass pill displaying a stat (icon + value + optional label).
struct IkeruStatPill: View {
    let icon: String
    let value: String
    let label: String?
    let tint: Color

    init(icon: String, value: String, label: String? = nil, tint: Color = Color.ikeruPrimaryAccent) {
        self.icon = icon
        self.value = value
        self.label = label
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.ikeruStats)
                .foregroundStyle(Color.ikeruTextPrimary)
                .lineLimit(1)
            if let label {
                Text(label)
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            IkeruGlassSurface(
                cornerRadius: IkeruTheme.Radius.full,
                tint: tint,
                tintOpacity: 0.08
            )
        }
    }
}

// MARK: - Divider

/// Subtle hairline divider with washi-paper feel.
public struct IkeruDivider: View {
    public init() {}
    public var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.0),
                        Color.white.opacity(0.10),
                        Color.white.opacity(0.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }
}

// MARK: - Premium Background

/// Use as the root background of any screen. Renders the Tatami marble
/// texture beneath the ink base. The `variant` parameter picks one of the
/// 5 baked marble PNGs deterministically per screen — see `MarbleVariant`
/// for the screen → variant mapping. Default is `.auxiliary` (Study /
/// Companion / Settings / Tab-bar overlay).
public struct IkeruScreenBackground: View {
    let variant: MarbleVariant

    public init(variant: MarbleVariant = .auxiliary) {
        self.variant = variant
    }

    public var body: some View {
        ZStack {
            Color.ikeruBackground
            MarbleBackground(variant: variant)
        }
    }
}

// MARK: - View extensions

extension View {
    /// Apply a premium glass surface as the background of any view.
    public func ikeruGlass(
        cornerRadius: CGFloat = IkeruTheme.Radius.lg,
        tint: Color = .clear,
        tintOpacity: Double = 0.06
    ) -> some View {
        self.background {
            IkeruGlassSurface(
                cornerRadius: cornerRadius,
                tint: tint,
                tintOpacity: tintOpacity
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
