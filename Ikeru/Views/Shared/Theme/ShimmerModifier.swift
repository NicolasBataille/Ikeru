import SwiftUI
import IkeruCore

// MARK: - Shimmer ViewModifier

public struct ShimmerModifier: ViewModifier {

    @State private var phase: CGFloat = 0

    public func body(content: Content) -> some View {
        content
            .overlay { shimmerGradient }
            .clipped()
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }

    private var shimmerGradient: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            LinearGradient(
                gradient: Gradient(colors: [
                    Color.clear,
                    Color(hex: IkeruTheme.Colors.primaryAccent).opacity(0.3),
                    Color.clear
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 0.6)
            .offset(x: -width * 0.3 + (width * 1.6) * phase)
            .clipped()
        }
        .allowsHitTesting(false)
    }
}

// MARK: - View Extension

extension View {
    /// Applies an amber shimmer loading animation over the view.
    public func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Preview

#Preview("Shimmer Effect") {
    VStack(spacing: IkeruTheme.Spacing.lg) {
        RoundedRectangle(cornerRadius: IkeruTheme.Radius.md)
            .fill(Color(hex: IkeruTheme.Colors.surface))
            .frame(height: 120)
            .shimmer()

        RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
            .fill(Color(hex: IkeruTheme.Colors.surface))
            .frame(height: 20)
            .shimmer()

        RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
            .fill(Color(hex: IkeruTheme.Colors.surface))
            .frame(width: 200, height: 20)
            .shimmer()
    }
    .padding(IkeruTheme.Spacing.md)
    .background(Color(hex: IkeruTheme.Colors.background))
    .preferredColorScheme(.dark)
}
