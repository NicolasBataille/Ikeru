import SwiftUI
import IkeruCore
import os

// MARK: - SessionSummaryView
//
// Tatami-direction restyle (Plan T6a): a triumph header (kanji kicker +
// serif "Practice complete" + italic proverb), three large serif numerals
// for cards / recall % / time, an XP-fusuma rail with the bright "new gain"
// segment glow, two split cells (NEW LEARNED / RE-LEARN) crested with mon,
// and a sharp gold "続ける · CONTINUE" CTA framed in sumi corners.
//
// All numerals render in serif. The summary uses `IkeruScreenBackground`
// with the `.summary` marble variant — the calmer of the five textures.

struct SessionSummaryView: View {

    let viewModel: SessionViewModel

    var body: some View {
        ZStack {
            IkeruScreenBackground(variant: .summary)
                .ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    triumphHeader
                    heroStatRow
                    splitCells
                    actions
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Triumph Header

    private var triumphHeader: some View {
        VStack(spacing: 6) {
            Text("稽古終わり")
                .ikeruScaledFont(11, weight: .bold, relativeTo: .caption2)
                .foregroundStyle(Color.ikeruPrimaryAccent)
                .tracking(3)
                .textCase(.uppercase)
            Text("Practice complete", comment: "Session summary headline")
                .ikeruScaledFont(32, weight: .light, design: .serif, relativeTo: .title)
                .foregroundStyle(Color.ikeruTextPrimary)
            Text("七転び八起き · Fall seven, rise eight")
                .ikeruScaledFont(12, relativeTo: .caption2)
                .italic()
                .foregroundStyle(Color.ikeruTextSecondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hero Stat Row (Cards / Recall % / Time)

    private var heroStatRow: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                SerifNumeral(cardsCount, size: 56, color: .ikeruPrimaryAccent)
                Text("CARDS", comment: "Summary stat label")
                    .ikeruScaledFont(10, weight: .semibold, relativeTo: .caption2)
                    .tracking(1.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
            .frame(maxWidth: .infinity)

            verticalHairline

            VStack(spacing: 6) {
                // 100% used to wrap onto two lines because the column width
                // couldn't host "100" at 56pt + a "%" beside it. Combine
                // into a single Text so it scales as one unit.
                Text("\(recallPercentage)%")
                    .font(.system(size: 56, weight: .light, design: .serif))
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("RECALL", comment: "Summary stat label")
                    .ikeruScaledFont(10, weight: .semibold, relativeTo: .caption2)
                    .tracking(1.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
            .frame(maxWidth: .infinity)

            verticalHairline

            VStack(spacing: 6) {
                SerifNumeral(timeString, size: 40, color: .ikeruPrimaryAccent)
                Text("TIME", comment: "Summary stat label")
                    .ikeruScaledFont(10, weight: .semibold, relativeTo: .caption2)
                    .tracking(1.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .tatamiRoom(.glass, padding: 22)
    }

    private var verticalHairline: some View {
        Rectangle()
            .fill(TatamiTokens.goldDim.opacity(0.4))
            .frame(width: 1, height: 56)
    }

    // MARK: - Split Cells (NEW LEARNED / RE-LEARN)

    private var splitCells: some View {
        HStack(spacing: 10) {
            cell(label: "NEW LEARNED", count: newCount,
                 color: Color(red: 0.616, green: 0.729, blue: 0.486),
                 mon: .maru)
            cell(label: "RE-LEARN", count: relearnCount,
                 color: TatamiTokens.vermilion,
                 mon: .kikkou)
        }
    }

    @ViewBuilder
    private func cell(label: LocalizedStringKey, count: Int, color: Color, mon: MonKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                MonCrest(kind: mon, size: 11, color: color)
                Text(label)
                    .ikeruScaledFont(10, weight: .semibold, relativeTo: .caption2)
                    .foregroundStyle(TatamiTokens.paperGhost)
                    .tracking(1.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                SerifNumeral(count, size: 28, color: color)
                Text("札")
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(TatamiTokens.paperGhost)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tatamiRoom(.standard, padding: 14)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 8) {
            Button { onContinue() } label: {
                HStack {
                    Spacer()
                    Text("続ける · ")
                        .ikeruScaledFont(13, weight: .regular, design: .serif, relativeTo: .caption)
                    Text("CONTINUE", comment: "Summary primary CTA")
                        .ikeruScaledFont(13, weight: .bold, relativeTo: .caption)
                        .tracking(1.6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                }
                .foregroundStyle(Color.ikeruBackground)
                .padding(.vertical, 14)
                .background(Color.ikeruPrimaryAccent)
                .sumiCorners(color: Color.ikeruBackground.opacity(0.6), size: 6, weight: 1.2, inset: -1)
            }
            .buttonStyle(.plain)

            // Hide the secondary CTA when there are no mistakes — there's
            // nothing to re-queue, so the button would dead-end.
            if !viewModel.missedCardIDs.isEmpty {
                Button { onReviewMistakes() } label: {
                    Text("REVIEW MISTAKES", comment: "Summary secondary CTA")
                        .ikeruScaledFont(11, weight: .semibold, relativeTo: .caption2)
                        .tracking(1.4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Color.ikeruTextSecondary)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func onContinue() {
        viewModel.dismissSession()
    }

    private func onReviewMistakes() {
        Task { await viewModel.startReviewMistakes() }
    }

    // MARK: - Derived display values
    //
    // The view-model does not expose recall % / xp-progress / rank labels
    // directly — derive them locally from the canonical fields on
    // `SessionViewModel` without mutating its state.

    private var cardsCount: Int { viewModel.reviewedCount }

    /// Recall percentage = total correct grades over total reviewed.
    /// Uses the dedicated `correctCount` (incremented per-card) instead of
    /// the streak-based `consecutiveCorrect`, which used to read 0% the
    /// moment the user hit a single .hard or .again even if every other
    /// card was correct. Returns 0 when no cards reviewed.
    private var recallPercentage: Int {
        guard viewModel.reviewedCount > 0 else { return 0 }
        let ratio = Double(viewModel.correctCount) / Double(viewModel.reviewedCount)
        return Int((ratio * 100).rounded())
    }

    private var timeString: String { viewModel.elapsedTimeFormatted }

    private var newCount: Int { viewModel.newItemsLearned }
    private var relearnCount: Int {
        max(0, viewModel.reviewedCount - viewModel.newItemsLearned)
    }
}

// MARK: - Preview

#Preview("SessionSummaryView") {
    ZStack {
        IkeruScreenBackground(variant: .summary)
        Text("Preview: See ActiveSessionView preview for full flow")
            .foregroundStyle(Color.ikeruTextPrimary)
    }
    .preferredColorScheme(.dark)
}
