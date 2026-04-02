import SwiftUI
import IkeruCore

// MARK: - Card Variant

public enum IkeruCardVariant: Sendable {
    case standard
    case elevated
    case interactive
    case companion
}

// MARK: - IkeruCard ViewModifier

public struct IkeruCardModifier: ViewModifier {

    let variant: IkeruCardVariant
    @State private var isPressed = false

    public func body(content: Content) -> some View {
        content
            .padding(IkeruTheme.Spacing.md)
            .background {
                materialBackground
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                x: shadowX,
                y: shadowY
            )
            .scaleEffect(scaleValue)
            .animation(
                .spring(duration: IkeruTheme.Animation.quickDuration),
                value: isPressed
            )
            .modifier(InteractiveGestureModifier(
                isInteractive: variant == .interactive,
                isPressed: $isPressed
            ))
    }

    @ViewBuilder
    private var materialBackground: some View {
        switch variant {
        case .elevated:
            Rectangle().fill(.thickMaterial)
        default:
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    private var cornerRadius: CGFloat {
        switch variant {
        case .companion:
            return IkeruTheme.Radius.lg
        default:
            return IkeruTheme.Radius.md
        }
    }

    private var shadowColor: Color {
        switch variant {
        case .elevated:
            return Color.black.opacity(0.4)
        default:
            return Color.black.opacity(IkeruTheme.Shadow.card.opacity)
        }
    }

    private var shadowRadius: CGFloat {
        switch variant {
        case .elevated:
            return IkeruTheme.Shadow.card.radius + 4
        default:
            return IkeruTheme.Shadow.card.radius
        }
    }

    private var shadowX: CGFloat {
        IkeruTheme.Shadow.card.x
    }

    private var shadowY: CGFloat {
        switch variant {
        case .elevated:
            return IkeruTheme.Shadow.card.y + 2
        default:
            return IkeruTheme.Shadow.card.y
        }
    }

    private var scaleValue: CGFloat {
        guard variant == .interactive else { return 1.0 }
        return isPressed ? 0.98 : 1.0
    }
}

// MARK: - Interactive Gesture Modifier

private struct InteractiveGestureModifier: ViewModifier {
    let isInteractive: Bool
    @Binding var isPressed: Bool

    func body(content: Content) -> some View {
        if isInteractive {
            content
                .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                    isPressed = pressing
                }, perform: {})
        } else {
            content
        }
    }
}

// MARK: - View Extension

extension View {
    public func ikeruCard(_ variant: IkeruCardVariant = .standard) -> some View {
        modifier(IkeruCardModifier(variant: variant))
    }
}

// MARK: - Preview

#Preview("IkeruCard Variants") {
    ScrollView {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            Text("Standard Card")
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .ikeruCard(.standard)

            Text("Elevated Card")
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .ikeruCard(.elevated)

            Text("Interactive Card")
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .ikeruCard(.interactive)

            Text("Companion Card")
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .ikeruCard(.companion)
        }
        .padding(IkeruTheme.Spacing.md)
    }
    .background(Color(hex: IkeruTheme.Colors.background))
    .preferredColorScheme(.dark)
}
