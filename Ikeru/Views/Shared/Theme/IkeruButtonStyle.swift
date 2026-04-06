import SwiftUI
import IkeruCore

// MARK: - Button Variant

public enum IkeruButtonVariant: Sendable {
    case primary       // gold-tinted glass, prominent
    case secondary     // outline glass
    case rpg           // gradient glass with glow
    case danger        // outlined terracotta
    case ghost         // text only
    case glassPill     // small floating pill
}

// MARK: - IkeruButtonStyle

public struct IkeruButtonStyle: ButtonStyle {

    let variant: IkeruButtonVariant

    public func makeBody(configuration: Configuration) -> some View {
        IkeruButtonContent(
            variant: variant,
            configuration: configuration
        )
    }
}

// MARK: - Button Content

private struct IkeruButtonContent: View {
    let variant: IkeruButtonVariant
    let configuration: ButtonStyleConfiguration

    var body: some View {
        configuration.label
            .font(font)
            .ikeruTracking(.body)
            .foregroundStyle(foregroundColor)
            .frame(minHeight: minHeight)
            .padding(.horizontal, horizontalPadding)
            .background(backgroundView)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(overlayBorder)
            .shadow(
                color: shadowColor,
                radius: configuration.isPressed ? shadowRadius * 0.6 : shadowRadius,
                y: configuration.isPressed ? 4 : 8
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: configuration.isPressed)
            .modifier(HapticFeedbackModifier(
                variant: variant,
                trigger: configuration.isPressed
            ))
    }

    // MARK: - Sizing

    private var minHeight: CGFloat {
        switch variant {
        case .glassPill: return 38
        case .ghost:     return 40
        default:         return 54
        }
    }

    private var horizontalPadding: CGFloat {
        switch variant {
        case .glassPill: return IkeruTheme.Spacing.md
        case .ghost:     return IkeruTheme.Spacing.sm
        default:         return IkeruTheme.Spacing.lg
        }
    }

    private var cornerRadius: CGFloat {
        switch variant {
        case .glassPill: return IkeruTheme.Radius.full
        case .primary, .rpg: return IkeruTheme.Radius.lg
        default:         return IkeruTheme.Radius.md
        }
    }

    private var font: Font {
        switch variant {
        case .glassPill, .ghost:
            return .system(size: IkeruTheme.Typography.Size.body, weight: .medium)
        default:
            return .system(size: IkeruTheme.Typography.Size.bodyLarge, weight: .semibold)
        }
    }

    // MARK: - Foreground

    private var foregroundColor: Color {
        switch variant {
        case .primary:    return Color(hex: 0x1A1218)
        case .secondary:  return Color.ikeruPrimaryAccent
        case .rpg:        return Color(hex: 0x1A1218)
        case .danger:     return Color.ikeruDanger
        case .ghost:      return Color.ikeruTextSecondary
        case .glassPill:  return Color.ikeruTextPrimary
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundView: some View {
        switch variant {
        case .primary:
            ZStack {
                LinearGradient.ikeruGold
                LinearGradient.ikeruGlassEdge
                    .blendMode(.plusLighter)
                    .opacity(0.6)
            }

        case .rpg:
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: 0xE5BC8A),
                        Color(hex: 0xE8B4B8),
                        Color(hex: 0xD4A574)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                LinearGradient.ikeruGlassEdge
                    .blendMode(.plusLighter)
                    .opacity(0.5)
            }

        case .secondary, .danger, .glassPill:
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color.white.opacity(0.04))
            }

        case .ghost:
            Color.clear
        }
    }

    // MARK: - Border Overlay

    @ViewBuilder
    private var overlayBorder: some View {
        switch variant {
        case .secondary:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.ikeruPrimaryAccent.opacity(0.6),
                            Color.ikeruPrimaryAccent.opacity(0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

        case .glassPill:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.18),
                    lineWidth: 0.6
                )

        case .danger:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    Color.ikeruDanger.opacity(0.55),
                    lineWidth: 1
                )

        case .primary, .rpg:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.45),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )

        default:
            EmptyView()
        }
    }

    // MARK: - Shadow

    private var shadowColor: Color {
        switch variant {
        case .primary, .rpg: return Color(hex: 0xD4A574, opacity: 0.35)
        case .secondary:     return Color.black.opacity(0.3)
        default:             return Color.clear
        }
    }

    private var shadowRadius: CGFloat {
        switch variant {
        case .primary, .rpg: return 24
        default:             return 12
        }
    }
}

// MARK: - Haptic Feedback Modifier

private struct HapticFeedbackModifier: ViewModifier {
    let variant: IkeruButtonVariant
    let trigger: Bool

    func body(content: Content) -> some View {
        switch variant {
        case .primary:
            content.sensoryFeedback(.impact(weight: .medium), trigger: trigger)
        case .secondary:
            content.sensoryFeedback(.impact(weight: .light), trigger: trigger)
        case .rpg:
            content.sensoryFeedback(.impact(weight: .heavy), trigger: trigger)
        case .danger:
            content.sensoryFeedback(.warning, trigger: trigger)
        case .ghost, .glassPill:
            content.sensoryFeedback(.impact(weight: .light), trigger: trigger)
        }
    }
}

// MARK: - View Extension

extension View {
    public func ikeruButtonStyle(_ variant: IkeruButtonVariant) -> some View {
        buttonStyle(IkeruButtonStyle(variant: variant))
    }
}

// MARK: - Preview

#Preview("IkeruButtonStyle Variants") {
    VStack(spacing: IkeruTheme.Spacing.lg) {
        Button("Begin") {}.ikeruButtonStyle(.primary)
        Button("Continue") {}.ikeruButtonStyle(.secondary)
        Button("Open Loot") {}.ikeruButtonStyle(.rpg)
        Button("End Session") {}.ikeruButtonStyle(.danger)
        Button("Skip") {}.ikeruButtonStyle(.ghost)
        Button("Filter") {}.ikeruButtonStyle(.glassPill)
    }
    .padding(IkeruTheme.Spacing.lg)
    .background(Color.ikeruBackground.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
