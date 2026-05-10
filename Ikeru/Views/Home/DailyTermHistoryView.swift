import SwiftUI
import IkeruCore

// MARK: - DailyTermHistoryView

/// History of past daily terms — both seen and missed. Tapping a row
/// opens the same reveal popup so a learner can catch up on the days
/// they didn't open Ikeru.
struct DailyTermHistoryView: View {

    let terms: [DailyTermDTO]
    var onSelect: (DailyTermDTO) -> Void
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: IkeruTheme.Spacing.lg) {
                    header

                    if terms.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: IkeruTheme.Spacing.sm) {
                            ForEach(terms) { term in
                                row(term)
                            }
                        }
                    }
                }
                .padding(.horizontal, IkeruTheme.Spacing.md)
                .padding(.top, IkeruTheme.Spacing.lg)
                .padding(.bottom, IkeruTheme.Spacing.xl)
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ikeruTextSecondary)
                            .padding(10)
                            .background {
                                Circle().fill(.ultraThinMaterial)
                            }
                            .overlay(
                                Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, IkeruTheme.Spacing.md)
                .padding(.trailing, IkeruTheme.Spacing.md)
                Spacer()
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PAST TERMS")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
            Text("Catch up on missed days")
                .font(.ikeruDisplaySmall)
                .ikeruTracking(.display)
                .foregroundStyle(Color.ikeruTextPrimary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.ikeruPrimaryAccent.opacity(0.6))
            Text("No past terms yet")
                .font(.ikeruBody)
                .foregroundStyle(Color.ikeruTextSecondary)
            Text("Each day's term will appear here once a new one arrives.")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, IkeruTheme.Spacing.xl)
    }

    @ViewBuilder
    private func row(_ term: DailyTermDTO) -> some View {
        Button {
            onSelect(term)
        } label: {
            HStack(spacing: IkeruTheme.Spacing.md) {
                statusIndicator(term)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(term.word)
                            .font(.ikeruBodyLarge)
                            .foregroundStyle(Color.ikeruTextPrimary)
                        Text(term.reading)
                            .font(.ikeruCaption)
                            .foregroundStyle(Color.ikeruTextTertiary)
                    }
                    Text(term.meaning)
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(shortDate(term.date))
                        .font(.ikeruMicro)
                        .ikeruTracking(.micro)
                        .foregroundStyle(Color.ikeruTextTertiary)
                    if term.addedToDictionary {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.ikeruTertiaryAccent)
                    }
                }
            }
            .padding(IkeruTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                IkeruGlassSurface(
                    cornerRadius: IkeruTheme.Radius.lg,
                    tint: term.revealedAt == nil ? Color.ikeruWarning : Color.ikeruPrimaryAccent,
                    tintOpacity: term.revealedAt == nil ? 0.06 : 0.04,
                    highlight: 0.12,
                    strokeOpacity: 0.14
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusIndicator(_ term: DailyTermDTO) -> some View {
        ZStack {
            Circle()
                .fill(
                    (term.revealedAt == nil ? Color.ikeruWarning : Color.ikeruSuccess)
                        .opacity(0.18)
                )
                .frame(width: 32, height: 32)
            Image(systemName: term.revealedAt == nil ? "envelope.fill" : "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(term.revealedAt == nil ? Color.ikeruWarning : Color.ikeruSuccess)
        }
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
