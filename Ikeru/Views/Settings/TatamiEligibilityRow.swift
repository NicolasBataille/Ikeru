import SwiftUI
import SwiftData
import IkeruCore

/// Settings row showing progress toward the Tatami-mode suggestion
/// (`DisplayModeAdvancedThresholdMonitor`): reviews, mastery, and active-days
/// counters against their thresholds, plus which path (if any) is met.
///
/// Hidden once the active profile is already in `.tatami` mode (nothing left
/// to work toward) and, after "Later" is tapped, hidden again until the
/// `TatamiSuggestionCooldown` (14 days) lapses.
struct TatamiEligibilityRow: View {

    let modelContainer: ModelContainer
    let activeProfileID: @Sendable () -> UUID?
    let displayMode: DisplayMode

    @State private var signals: Signals?
    @State private var isSuppressedByCooldown = false

    private struct Signals {
        let reviews: Int
        let mastery: Int
        let activeDays: Int
        let eligibility: DisplayModeThresholdResult
    }

    private var dismissalRepository: UserDefaultsTatamiSuggestionDismissalRepository {
        UserDefaultsTatamiSuggestionDismissalRepository(activeProfileID: activeProfileID)
    }

    var body: some View {
        // VStack, not Group: a Group forwards modifiers to its CHILDREN, and
        // before `load()` completes the `if` renders no child — so the
        // `.task` never fired and `signals` never loaded. The row was
        // deadlocked invisible for everyone (found by Nico, device pass
        // 2026-07-19). A VStack is a real container: its `.task` runs on
        // appear even while empty.
        VStack(spacing: 0) {
            if displayMode == .beginner, !isSuppressedByCooldown, let signals {
                content(signals)
            }
        }
        .task { await load() }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ signals: Signals) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Text("畳")
                    .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                    .foregroundStyle(TatamiTokens.paperGhost)
                Text("Settings.TatamiEligibility.Title")
                    .ikeruScaledFont(13, relativeTo: .caption)
                    .foregroundStyle(Color.ikeruTextPrimary)
                Spacer()
                if signals.eligibility == .eligible {
                    Text("Settings.TatamiEligibility.Ready")
                        .ikeruScaledFont(11, relativeTo: .caption2)
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                }
            }

            progressLine(
                label: "Settings.TatamiEligibility.Reviews",
                current: signals.reviews,
                total: DisplayModeAdvancedThresholdMonitor.reviewsThreshold
            )
            progressLine(
                label: "Settings.TatamiEligibility.Mastery",
                current: signals.mastery,
                total: DisplayModeAdvancedThresholdMonitor.masteryThreshold
            )
            progressLine(
                label: "Settings.TatamiEligibility.ActiveDays",
                current: signals.activeDays,
                total: DisplayModeAdvancedThresholdMonitor.activeDaysThreshold
            )

            // "Later" only makes sense as the answer to an actual OFFER —
            // while the learner is still short of the thresholds this row is
            // a progress tracker, and a postpone button under it reads as a
            // non-sequitur (Nico's question, device pass 2026-07-19).
            if signals.eligibility == .eligible {
                Button {
                    dismissForCooldown()
                } label: {
                    Text("Settings.TatamiEligibility.Later")
                        .ikeruScaledFont(12, relativeTo: .caption2)
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TatamiTokens.goldDim.opacity(0.2))
                .frame(height: 1).padding(.horizontal, 16)
        }
    }

    private func progressLine(label: LocalizedStringKey, current: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .ikeruScaledFont(11, relativeTo: .caption2)
                    .foregroundStyle(Color.ikeruTextSecondary)
                Spacer()
                // Plain numeric fragment — not a translatable phrase, mirrors
                // the non-localized `value:` slot pattern used throughout
                // SettingsView's rowChrome (verbatim `Text(String)`).
                Text("\(current)/\(total)")
                    .ikeruScaledFont(11, design: .serif, relativeTo: .caption2)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
            }
            progressBar(ratio: total > 0 ? Double(current) / Double(total) : 0)
        }
    }

    private func progressBar(ratio: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(TatamiTokens.goldDim.opacity(0.15))
                Rectangle().fill(Color.ikeruPrimaryAccent)
                    .frame(width: proxy.size.width * min(1, max(0, ratio)))
            }
        }
        .frame(height: 3)
    }

    // MARK: - Data

    private func load() async {
        guard TatamiSuggestionCooldown.shouldOffer(lastDismissedAt: dismissalRepository.lastDismissedAt()) else {
            isSuppressedByCooldown = true
            return
        }

        let context = modelContainer.mainContext
        let rpg = fetchActiveRPGState(in: context)
        let reviews = rpg?.totalReviewsCompleted ?? 0
        let activeDays = rpg?.activeDaysCount ?? 0

        let cardRepository = CardRepository(modelContainer: modelContainer)
        let allCards = await cardRepository.allCards()
        let masteryCount = allCards.filter { card in
            MasteryLevel.from(fsrsState: card.fsrsState).rawValue
                >= MasteryLevel.familiar.rawValue
        }.count

        signals = Signals(
            reviews: reviews,
            mastery: masteryCount,
            activeDays: activeDays,
            eligibility: DisplayModeAdvancedThresholdMonitor.evaluate(
                totalReviewsCompleted: reviews,
                cardsAtFamiliarOrAbove: masteryCount,
                activeDaysCount: activeDays
            )
        )
    }

    /// Resolves the profile via `ActiveProfileResolver.fetchActiveProfile` so
    /// this row shares the app-wide fallback-to-oldest-profile semantics (a
    /// fresh install without a persisted id must not read as 0/0/0 progress),
    /// but reads `.rpgState` directly rather than `fetchActiveRPGState` to
    /// avoid that helper's lazy-create side effect in a read-only progress row.
    private func fetchActiveRPGState(in context: ModelContext) -> RPGState? {
        ActiveProfileResolver.fetchActiveProfile(in: context)?.rpgState
    }

    private func dismissForCooldown() {
        dismissalRepository.recordDismissal(at: Date())
        isSuppressedByCooldown = true
    }
}
