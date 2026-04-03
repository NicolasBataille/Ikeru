import SwiftUI
import IkeruCore

// MARK: - PlaybackRateSelector

/// Horizontal pill-shaped segmented control for selecting audio playback rate.
/// Current rate is highlighted with IkeruTheme amber.
struct PlaybackRateSelector: View {

    /// The currently selected playback rate.
    @Binding var selectedRate: PlaybackRate

    /// Whether to use the compact variant (for inline use within exercise views).
    var isCompact: Bool = false

    /// Haptic trigger for rate change.
    @State private var selectionTrigger = false

    var body: some View {
        HStack(spacing: isCompact ? IkeruTheme.Spacing.xs : IkeruTheme.Spacing.sm) {
            ForEach(PlaybackRate.allCases) { rate in
                rateButton(for: rate)
            }
        }
        .padding(.horizontal, isCompact ? IkeruTheme.Spacing.sm : IkeruTheme.Spacing.md)
        .padding(.vertical, isCompact ? IkeruTheme.Spacing.xs : IkeruTheme.Spacing.sm)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
        .sensoryFeedback(.selection, trigger: selectionTrigger)
    }

    // MARK: - Rate Button

    @ViewBuilder
    private func rateButton(for rate: PlaybackRate) -> some View {
        let isSelected = selectedRate == rate

        Button {
            selectedRate = rate
            selectionTrigger.toggle()
        } label: {
            Text(rate.displayLabel)
                .font(isCompact ? .ikeruCaption : .ikeruBody)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundStyle(isSelected ? .white : .ikeruTextSecondary)
                .padding(.horizontal, isCompact ? IkeruTheme.Spacing.sm : IkeruTheme.Spacing.md)
                .padding(.vertical, isCompact ? IkeruTheme.Spacing.xs : IkeruTheme.Spacing.sm)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color(hex: IkeruTheme.Colors.primaryAccent))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: IkeruTheme.Animation.quickDuration), value: isSelected)
    }
}

// MARK: - Preview

#Preview("PlaybackRateSelector") {
    VStack(spacing: IkeruTheme.Spacing.xl) {
        PlaybackRateSelector(selectedRate: .constant(.normal))

        PlaybackRateSelector(selectedRate: .constant(.slow), isCompact: true)
    }
    .padding(IkeruTheme.Spacing.lg)
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
