import SwiftUI
import IkeruCore

// MARK: - DailyTermHistoryView

/// History of past daily terms — both seen and missed. Tapping a row
/// opens the same reveal popup so a learner can catch up on the days
/// they didn't open Ikeru, or revisit a term they already saw.
struct DailyTermHistoryView: View {

    let terms: [DailyTermDTO]
    var onSelect: (DailyTermDTO) -> Void
    var onDismiss: () -> Void

    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all
        case missed
        case seen

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all:    return "All"
            case .missed: return "Missed"
            case .seen:   return "Seen"
            }
        }
    }

    private var filtered: [DailyTermDTO] {
        switch filter {
        case .all:    return terms
        case .missed: return terms.filter { $0.revealedAt == nil }
        case .seen:   return terms.filter { $0.revealedAt != nil }
        }
    }

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: IkeruTheme.Spacing.lg) {
                    header
                    filterPicker

                    if filtered.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: IkeruTheme.Spacing.sm) {
                            ForEach(filtered) { term in
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
            Text("Your discovery trail")
                .font(.ikeruDisplaySmall)
                .ikeruTracking(.display)
                .foregroundStyle(Color.ikeruTextPrimary)
        }
    }

    private var filterPicker: some View {
        HStack(spacing: IkeruTheme.Spacing.xs) {
            ForEach(Filter.allCases) { option in
                let count = terms.filter { term in
                    switch option {
                    case .all:    return true
                    case .missed: return term.revealedAt == nil
                    case .seen:   return term.revealedAt != nil
                    }
                }.count
                Button {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                        filter = option
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(option.label)
                            .font(.ikeruCaption)
                        Text("\(count)")
                            .font(.ikeruMicro)
                            .ikeruTracking(.micro)
                            .foregroundStyle(Color.ikeruTextTertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundStyle(filter == option ? Color.ikeruTextPrimary : Color.ikeruTextSecondary)
                    .background {
                        Capsule()
                            .fill(filter == option
                                  ? Color.ikeruPrimaryAccent.opacity(0.16)
                                  : Color.white.opacity(0.04))
                    }
                    .overlay(
                        Capsule().strokeBorder(
                            filter == option ? Color.ikeruPrimaryAccent.opacity(0.4) : Color.white.opacity(0.08),
                            lineWidth: 0.6
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.ikeruPrimaryAccent.opacity(0.6))
            Text(filter == .all ? "No past terms yet" : "Nothing here for this filter")
                .font(.ikeruBody)
                .foregroundStyle(Color.ikeruTextSecondary)
            Text(filter == .all
                 ? "Each day's term will appear here once a new one arrives."
                 : "Switch filter to see your other terms.")
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
                    tintOpacity: term.revealedAt == nil ? 0.08 : 0.04,
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
        let isMissed = term.revealedAt == nil
        ZStack {
            Circle()
                .fill((isMissed ? Color.ikeruWarning : Color.ikeruSuccess).opacity(0.18))
                .frame(width: 32, height: 32)
            Image(systemName: isMissed ? "envelope.fill" : "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isMissed ? Color.ikeruWarning : Color.ikeruSuccess)
        }
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
