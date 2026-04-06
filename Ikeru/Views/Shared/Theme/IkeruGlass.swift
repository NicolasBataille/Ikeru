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
    public let title: String
    public let eyebrow: String?
    public let trailing: Trailing

    public init(
        title: String,
        eyebrow: String? = nil,
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
                    Text(eyebrow.uppercased())
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
            if let label {
                Text(label)
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
        }
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

/// Use as the root background of any screen. Combines deep base + radial warmth + grain.
public struct IkeruScreenBackground: View {
    public init() {}
    public var body: some View {
        ZStack {
            Color.ikeruBackground

            // Top warm radial glow
            RadialGradient(
                colors: [
                    Color(hex: 0xD4A574, opacity: 0.10),
                    Color(hex: 0xD4A574, opacity: 0.0)
                ],
                center: .init(x: 0.85, y: 0.05),
                startRadius: 0,
                endRadius: 480
            )
            .blendMode(.screen)

            // Bottom-left cool radial
            RadialGradient(
                colors: [
                    Color(hex: 0x6B92B5, opacity: 0.06),
                    Color(hex: 0x6B92B5, opacity: 0.0)
                ],
                center: .init(x: 0.1, y: 0.95),
                startRadius: 0,
                endRadius: 420
            )
            .blendMode(.screen)
        }
        .ignoresSafeArea()
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
