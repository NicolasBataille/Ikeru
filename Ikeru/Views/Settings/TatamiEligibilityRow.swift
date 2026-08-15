import SwiftUI
import SwiftData
import IkeruCore

/// Settings row showing progress toward the Tatami-mode suggestion
/// (`DisplayModeAdvancedThresholdMonitor`): two independent eligibility
/// paths — cumulative competence (reviews AND mastery) OR longevity
/// (active days) — rendered as two separate groups joined by "ou", each
/// marked once ITS OWN criteria are met. Never flattened into one list of
/// three counters: that reads as a checklist (AND), when the real rule is
/// an OR between two routes (P1 fix, adversarial re-review of 353ac3e).
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

        /// Mirrors `DisplayModeAdvancedThresholdMonitor`'s competence path
        /// (reviews AND mastery). Computed here rather than sourced from
        /// `evaluate()` because the monitor only returns the combined
        /// eligible/not-eligible verdict, not which of the two OR'd paths
        /// produced it — the row needs the per-path breakdown to avoid
        /// presenting an OR as an AND.
        var competencePathMet: Bool {
            reviews >= DisplayModeAdvancedThresholdMonitor.reviewsThreshold
                && mastery >= DisplayModeAdvancedThresholdMonitor.masteryThreshold
        }

        var activeDaysPathMet: Bool {
            activeDays >= DisplayModeAdvancedThresholdMonitor.activeDaysThreshold
        }
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
        //
        // The cooldown deliberately does NOT gate the whole row anymore: it
        // suppresses the OFFER (Ready badge + "Later"), never the progress
        // tracker — dismissing must not hide the learner's own progress for
        // 14 days (second find of the same pass).
        VStack(spacing: 0) {
            if displayMode == .beginner, let signals {
                content(signals)
            }
        }
        .task { await load() }
    }

    /// The offer surface (Ready badge + Later) shows only when eligibility is
    /// reached AND the learner hasn't recently declined.
    private func isOffering(_ signals: Signals) -> Bool {
        signals.eligibility == .eligible && !isSuppressedByCooldown
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
                if isOffering(signals) {
                    Text("Settings.TatamiEligibility.Ready")
                        .ikeruScaledFont(11, relativeTo: .caption2)
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                }
            }

            // Two independent paths, either one sufficient — NOT a checklist
            // of three cumulative criteria. Showing all three flat, with
            // "Ready" sitting next to an untouched "Active days 0/30", read
            // as the display lying (the badge was true because of the OTHER
            // path). Explicit path groups + "ou" make the OR legible.
            pathSection(
                titleKey: "Settings.TatamiEligibility.PathCompetence",
                isMet: signals.competencePathMet
            ) {
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
            }

            HStack {
                Spacer()
                Text("Settings.TatamiEligibility.Or")
                    .ikeruScaledFont(9, relativeTo: .caption2)
                    .foregroundStyle(Color.ikeruTextTertiary)
                Spacer()
            }

            pathSection(
                titleKey: "Settings.TatamiEligibility.PathActiveDays",
                isMet: signals.activeDaysPathMet
            ) {
                progressLine(
                    label: "Settings.TatamiEligibility.ActiveDays",
                    current: signals.activeDays,
                    total: DisplayModeAdvancedThresholdMonitor.activeDaysThreshold
                )
            }

            // "Later" only makes sense as the answer to an actual OFFER —
            // while the learner is still short of the thresholds this row is
            // a progress tracker, and a postpone button under it reads as a
            // non-sequitur (Nico's question, device pass 2026-07-19).
            if isOffering(signals) {
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

    /// One eligibility path: a small header (title + a checkmark once THIS
    /// path's own criteria are met) followed by its progress lines. `isMet`
    /// is independent of the top "Ready" badge, which additionally accounts
    /// for the dismissal cooldown — a path can be met while "Ready" is
    /// suppressed, and that's not a contradiction to surface here.
    @ViewBuilder
    private func pathSection<Lines: View>(
        titleKey: LocalizedStringKey,
        isMet: Bool,
        @ViewBuilder lines: () -> Lines
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(titleKey)
                    .ikeruScaledFont(10, relativeTo: .caption2)
                    .foregroundStyle(Color.ikeruTextTertiary)
                    .textCase(.uppercase)
                if isMet {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                        .accessibilityLabel(Text("Settings.TatamiEligibility.PathMet"))
                }
                Spacer()
            }
            lines()
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
                //
                // Capped at `total`: once a learner blows past a threshold
                // (e.g. 250 cards mastered against a 75 threshold), showing
                // the raw count reads as a broken counter, not progress — the
                // bar below already clamps its fill the same way, so the
                // number and the bar now agree on the same effective state.
                // Int() here is a no-op on an already-Int value — it keeps
                // scripts/i18n-lint.py's type inference aligned (its
                // heuristic doesn't recognize `min(...)` as Int-like, so it
                // misclassifies the interpolation as %@ and flags a false
                // specifier-mismatch against the catalog's %lld/%lld key).
                Text("\(Int(min(current, total)))/\(total)")
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
        // Cooldown only mutes the OFFER — signals still load so the progress
        // tracker stays visible after a "Later".
        isSuppressedByCooldown = !TatamiSuggestionCooldown.shouldOffer(
            lastDismissedAt: dismissalRepository.lastDismissedAt()
        )

        let context = modelContainer.mainContext
        let rpg = fetchActiveRPGState(in: context)
        let activeDays = rpg?.activeDaysCount ?? 0

        // "Cumulative competence" reviews come from `ReviewLog` (GAP-13), not
        // `RPGState.totalReviewsCompleted` — that field only ever credited
        // the main SRS session and silently dropped every kana-drill review,
        // undercounting this exact figure (53 shown vs. 74 real reviews,
        // observed 2026-08-14). See `RPGState.totalReviewsCompleted`'s doc
        // comment.
        let cardRepository = CardRepository(modelContainer: modelContainer)
        let reviews = await cardRepository.activeProfileReviewCount()
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
