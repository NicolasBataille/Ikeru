import SwiftUI
import IkeruCore

// MARK: - Button Variant

public enum IkeruButtonVariant: Sendable {
    case primary
    case secondary
    case rpg
    case danger
    case ghost
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
            .font(.system(size: IkeruTheme.Typography.Size.body, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .frame(minHeight: 44)
            .padding(.horizontal, IkeruTheme.Spacing.lg)
            .background(backgroundView)
            .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.md))
            .overlay(overlayBorder)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(
                .spring(duration: IkeruTheme.Animation.quickDuration),
                value: configuration.isPressed
            )
            .modifier(HapticFeedbackModifier(
                variant: variant,
                trigger: configuration.isPressed
            ))
    }

    // MARK: - Foreground

    private var foregroundColor: Color {
        switch variant {
        case .primary:
            return .white
        case .secondary:
            return Color(hex: IkeruTheme.Colors.primaryAccent)
        case .rpg:
            return .white
        case .danger:
            return Color(hex: IkeruTheme.Colors.secondaryAccent)
        case .ghost:
            return .white.opacity(IkeruTheme.Colors.textSecondaryOpacity)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundView: some View {
        switch variant {
        case .primary:
            Color(hex: IkeruTheme.Colors.primaryAccent)
        case .secondary:
            Color.clear
        case .rpg:
            LinearGradient(
                colors: [
                    Color(hex: IkeruTheme.Colors.primaryAccent),
                    Color(hex: IkeruTheme.Colors.secondaryAccent)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .danger:
            Color.clear
        case .ghost:
            Color.clear
        }
    }

    // MARK: - Border Overlay

    @ViewBuilder
    private var overlayBorder: some View {
        switch variant {
        case .secondary:
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.md)
                .strokeBorder(
                    Color(hex: IkeruTheme.Colors.primaryAccent).opacity(0.5),
                    lineWidth: 1
                )
        case .rpg:
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.md)
                .strokeBorder(
                    Color(hex: IkeruTheme.Colors.primaryAccent).opacity(0.6),
                    lineWidth: 2
                )
                .shadow(
                    color: Color(hex: IkeruTheme.Shadow.glow.colorHex)
                        .opacity(IkeruTheme.Shadow.glow.opacity),
                    radius: IkeruTheme.Shadow.glow.radius
                )
        case .danger:
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.md)
                .strokeBorder(
                    Color(hex: IkeruTheme.Colors.secondaryAccent),
                    lineWidth: 1
                )
        default:
            EmptyView()
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
        case .ghost:
            content
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
        Button("Primary Action") {}
            .ikeruButtonStyle(.primary)

        Button("Secondary Action") {}
            .ikeruButtonStyle(.secondary)

        Button("RPG Action") {}
            .ikeruButtonStyle(.rpg)

        Button("Danger Action") {}
            .ikeruButtonStyle(.danger)

        Button("Ghost Action") {}
            .ikeruButtonStyle(.ghost)
    }
    .padding(IkeruTheme.Spacing.lg)
    .background(Color(hex: IkeruTheme.Colors.background))
    .preferredColorScheme(.dark)
}
