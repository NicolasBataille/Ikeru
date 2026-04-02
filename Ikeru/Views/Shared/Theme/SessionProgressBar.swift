import SwiftUI
import IkeruCore

// MARK: - SessionProgressBar

/// A thin 4pt amber progress bar displayed at the top of the session screen.
/// Shows current exercise position and elapsed time.
struct SessionProgressBar: View {

    /// Progress fraction (0.0 to 1.0).
    let progress: Double

    /// Text showing exercise count (e.g., "3/10").
    let exerciseCountText: String

    /// Elapsed time formatted string (e.g., "2:35").
    let elapsedTime: String

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.xs) {
            // Thin amber progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.ikeruSurface)
                        .frame(height: 4)

                    // Fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.ikeruPrimaryAccent)
                        .frame(
                            width: geometry.size.width * max(0, min(1, progress)),
                            height: 4
                        )
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 4)

            // Exercise count and elapsed time
            HStack {
                Text(exerciseCountText)
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruTextSecondary)

                Spacer()

                Text(elapsedTime)
                    .font(.ikeruStats)
                    .foregroundStyle(.ikeruTextSecondary)
            }
        }
        .padding(.horizontal, IkeruTheme.Spacing.md)
    }
}

// MARK: - Preview

#Preview("SessionProgressBar") {
    ZStack {
        Color.ikeruBackground.ignoresSafeArea()

        VStack(spacing: IkeruTheme.Spacing.xl) {
            SessionProgressBar(
                progress: 0.3,
                exerciseCountText: "3/10",
                elapsedTime: "1:25"
            )

            SessionProgressBar(
                progress: 0.7,
                exerciseCountText: "7/10",
                elapsedTime: "4:10"
            )

            SessionProgressBar(
                progress: 1.0,
                exerciseCountText: "10/10",
                elapsedTime: "6:42"
            )
        }
        .padding(IkeruTheme.Spacing.lg)
    }
    .preferredColorScheme(.dark)
}
