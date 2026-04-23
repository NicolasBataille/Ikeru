import SwiftUI
import IkeruCore

// MARK: - Card Variant

public enum IkeruCardVariant: Sendable {
    case standard       // glass surface, soft border
    case elevated       // brighter glass, stronger shadow
    case interactive    // springy press feedback
    case companion      // larger radius, sakura tinted
    case hero           // tallest, used for top hero panels
}

// MARK: - IkeruCard ViewModifier

public struct IkeruCardModifier: ViewModifier {

    let variant: IkeruCardVariant
    let padding: CGFloat
    @State private var isPressed = false

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                cardBackground
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                cardBorder
            }
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
            .scaleEffect(isPressed ? 0.985 : 1.0)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isPressed)
            .modifier(InteractiveGestureModifier(
                isInteractive: variant == .interactive,
                isPressed: $isPressed
            ))
    }

    @ViewBuilder
    private var cardBackground: some View {
        ZStack {
            // Opaque base (interactive only) — prevents the deck peeks from
            // bleeding through the translucent material when the card is
            // being dragged across the stack.
            if variant == .interactive {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.ikeruSurface)
            }

            // Base glass material
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            // Tinted overlay (each variant has its own subtle tint)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tintFill)

            // Top edge highlight (gives the glass that "lifted" feel)
            LinearGradient(
                colors: [
                    Color.white.opacity(highlightOpacity),
                    Color.white.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.18),
                        Color.white.opacity(0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.6
            )
    }

    private var tintFill: Color {
        switch variant {
        case .standard:    return Color.white.opacity(0.04)
        case .elevated:    return Color.white.opacity(0.07)
        case .interactive: return Color.white.opacity(0.05)
        case .companion:   return Color(hex: 0xE8B4B8, opacity: 0.06)
        case .hero:        return Color.white.opacity(0.06)
        }
    }

    private var highlightOpacity: Double {
        switch variant {
        case .elevated, .hero: return 0.18
        case .companion:       return 0.16
        default:               return 0.12
        }
    }

    private var cornerRadius: CGFloat {
        switch variant {
        case .companion: return IkeruTheme.Radius.xl
        case .hero:      return IkeruTheme.Radius.xl
        case .elevated:  return IkeruTheme.Radius.lg
        default:         return IkeruTheme.Radius.lg
        }
    }

    private var shadowColor: Color {
        switch variant {
        case .elevated, .hero:
            return Color.black.opacity(0.55)
        default:
            return Color.black.opacity(0.4)
        }
    }

    private var shadowRadius: CGFloat {
        switch variant {
        case .elevated, .hero: return 32
        default:               return 20
        }
    }

    private var shadowY: CGFloat {
        switch variant {
        case .elevated, .hero: return 12
        default:               return 8
        }
    }
}

// MARK: - Interactive Gesture Modifier

private struct InteractiveGestureModifier: ViewModifier {
    let isInteractive: Bool
    @Binding var isPressed: Bool

    func body(content: Content) -> some View {
        if isInteractive {
            content
                .onLongPressGesture(
                    minimumDuration: .infinity,
                    maximumDistance: .infinity,
                    pressing: { pressing in
                        isPressed = pressing
                    },
                    perform: {}
                )
        } else {
            content
        }
    }
}

// MARK: - View Extension

extension View {
    /// Applies a premium glass card style.
    /// - Parameters:
    ///   - variant: visual treatment
    ///   - padding: inner padding (defaults to lg)
    public func ikeruCard(
        _ variant: IkeruCardVariant = .standard,
        padding: CGFloat = IkeruTheme.Spacing.lg
    ) -> some View {
        modifier(IkeruCardModifier(variant: variant, padding: padding))
    }
}

// MARK: - Preview

#Preview("IkeruCard Variants") {
    ScrollView {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            Text("Standard").foregroundStyle(.white).ikeruCard(.standard)
            Text("Elevated").foregroundStyle(.white).ikeruCard(.elevated)
            Text("Interactive").foregroundStyle(.white).ikeruCard(.interactive)
            Text("Companion").foregroundStyle(.white).ikeruCard(.companion)
            Text("Hero").foregroundStyle(.white).ikeruCard(.hero)
        }
        .padding(IkeruTheme.Spacing.md)
    }
    .background(Color.ikeruBackground.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
