import SwiftUI
import IkeruCore

// MARK: - XPGainView

/// "+{amount} XP" text that floats up and fades over 500ms.
/// Triggered via overlay when XP is awarded.
/// Plays `.impact(.light)` haptic on appear.
struct XPGainView: View {

    /// The amount of XP gained.
    let amount: Int

    /// Callback when the animation completes and the view should be removed.
    var onComplete: (() -> Void)?

    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1.0
    @State private var hapticTrigger = false

    var body: some View {
        Text("+\(amount) XP")
            .font(.ikeruHeading3)
            .fontWeight(.bold)
            .foregroundStyle(Color(hex: IkeruTheme.Colors.Rarity.legendary))
            .shadow(
                color: Color(hex: IkeruTheme.Colors.primaryAccent).opacity(0.5),
                radius: 4
            )
            .offset(y: offset)
            .opacity(opacity)
            .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
            .onAppear {
                hapticTrigger.toggle()

                withAnimation(.easeOut(duration: 0.5)) {
                    offset = -40
                    opacity = 0
                }

                // Notify completion after animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    onComplete?()
                }
            }
    }
}

// MARK: - XP Gain Overlay Modifier

/// View modifier that shows a floating XP gain animation as an overlay.
struct XPGainOverlayModifier: ViewModifier {

    /// Binding to the XP amount to display. Set to nil to hide.
    @Binding var xpGained: Int?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let amount = xpGained {
                XPGainView(amount: amount) {
                    xpGained = nil
                }
                // Push the floating XP text below the Dynamic Island / notch.
                // Without this, the text is rendered at the very top of the
                // safe area and gets visually masked by the Island pill.
                .padding(.top, 64)
                .transition(.identity)
            }
        }
    }
}

extension View {
    /// Shows a floating "+XP" animation overlay when xpGained is non-nil.
    func xpGainOverlay(xpGained: Binding<Int?>) -> some View {
        modifier(XPGainOverlayModifier(xpGained: xpGained))
    }
}

// MARK: - Preview

#Preview("XPGainView") {
    ZStack {
        Color.ikeruBackground.ignoresSafeArea()

        VStack {
            XPGainView(amount: 10)
            XPGainView(amount: 5)
        }
    }
    .preferredColorScheme(.dark)
}
