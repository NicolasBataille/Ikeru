import SwiftUI
import IkeruCore

// MARK: - DailyTermBanner

/// Discreet banner shown on the Home screen when a new daily term is
/// available. Tapping it opens the reveal popup.
struct DailyTermBanner: View {

    let term: DailyTermDTO
    let yesterday: DailyTermDTO?
    var onTap: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
                HStack(alignment: .center, spacing: IkeruTheme.Spacing.sm) {
                    icon
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NEW TERM ARRIVED")
                            .font(.ikeruMicro)
                            .ikeruTracking(.micro)
                            .foregroundStyle(Color.ikeruPrimaryAccent)
                        Text("Tap to discover today's word")
                            .font(.ikeruBody)
                            .foregroundStyle(Color.ikeruTextPrimary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ikeruTextTertiary)
                }
                if let yesterday {
                    yesterdayReminder(yesterday)
                }
            }
            .padding(IkeruTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                IkeruGlassSurface(
                    cornerRadius: IkeruTheme.Radius.lg,
                    tint: Color.ikeruPrimaryAccent,
                    tintOpacity: 0.10,
                    highlight: 0.18,
                    strokeOpacity: 0.22
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg, style: .continuous))
            .shadow(color: Color.black.opacity(0.4), radius: 18, y: 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens today's new vocabulary term")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(Color.ikeruPrimaryAccent.opacity(0.18))
                .frame(width: 36, height: 36)
            Circle()
                .stroke(Color.ikeruPrimaryAccent.opacity(pulse ? 0.55 : 0.0), lineWidth: 1)
                .frame(width: 46, height: 46)
                .scaleEffect(pulse ? 1.15 : 1.0)
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ikeruPrimaryAccent)
        }
    }

    @ViewBuilder
    private func yesterdayReminder(_ term: DailyTermDTO) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.ikeruTextTertiary)
            Text("Yesterday")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
            Text(term.word)
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextSecondary)
            Text("·")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextTertiary)
            Text(term.meaning)
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextSecondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Revealed-state pill

/// Compact pill replacing the banner once today's term has been opened.
/// Lets the user re-open the popup, while staying out of the way.
struct DailyTermRevealedPill: View {

    let term: DailyTermDTO
    let yesterday: DailyTermDTO?
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                Text("Today")
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(Color.ikeruTextTertiary)
                Text(term.word)
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextPrimary)
                Text("·")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextTertiary)
                Text(term.meaning)
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if yesterday != nil {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.ikeruTextTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Capsule().fill(.ultraThinMaterial)
            }
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Re-open today's term")
    }
}
