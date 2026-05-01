import SwiftUI
import IkeruCore

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
                    xpGainRail
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
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.ikeruPrimaryAccent)
                .tracking(3)
                .textCase(.uppercase)
            Text("Practice complete", comment: "Session summary headline")
                .font(.system(size: 32, weight: .light, design: .serif))
                .foregroundStyle(Color.ikeruTextPrimary)
            Text("七転び八起き · Fall seven, rise eight")
                .font(.system(size: 12))
                .italic()
                .foregroundStyle(TatamiTokens.paperGhost)
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .tracking(1.6)
            }
            .frame(maxWidth: .infinity)

            verticalHairline

            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    SerifNumeral(recallPercentage, size: 56, color: .ikeruPrimaryAccent)
                    Text("%")
                        .font(.system(size: 18, design: .serif))
                        .foregroundStyle(TatamiTokens.paperGhost)
                }
                Text("RECALL", comment: "Summary stat label")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .tracking(1.6)
            }
            .frame(maxWidth: .infinity)

            verticalHairline

            VStack(spacing: 6) {
                SerifNumeral(timeString, size: 40, color: .ikeruPrimaryAccent)
                Text("TIME", comment: "Summary stat label")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .tracking(1.6)
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

    // MARK: - XP Gain Rail

    private var xpGainRail: some View {
        VStack(spacing: 8) {
            HStack {
                MonCrest(kind: .asanoha, size: 14, color: .ikeruPrimaryAccent)
                Text("XP EARNED", comment: "Summary XP label")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .tracking(1.4)
                Spacer()
                SerifNumeral("+\(viewModel.xpEarned)", size: 18,
                             weight: .regular, color: .ikeruPrimaryAccent)
            }
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(TatamiTokens.goldDim.opacity(0.3))
                    .frame(height: 3)
                GeometryReader { geo in
                    // Total earned-so-far rail.
                    Rectangle()
                        .fill(Color.ikeruPrimaryAccent)
                        .frame(width: geo.size.width * xpProgress, height: 1)
                    // Bright "new gain" segment, glowing.
                    Rectangle()
                        .fill(Color.ikeruPrimaryAccent)
                        .frame(width: geo.size.width * xpGainProgress, height: 1)
                        .offset(x: geo.size.width * max(0, xpProgress - xpGainProgress))
                        .shadow(color: .ikeruPrimaryAccent.opacity(0.8), radius: 6)
                }
                .frame(height: 3)
            }
            HStack {
                SerifNumeral(rankLabelStart, size: 10, color: TatamiTokens.paperGhost)
                Spacer()
                SerifNumeral(rankLabelEnd, size: 10, color: TatamiTokens.paperGhost)
            }
        }
        .tatamiRoom(.standard, padding: 18)
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
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(TatamiTokens.paperGhost)
                    .tracking(1.4)
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
                        .font(.system(size: 13, weight: .regular, design: .serif))
                    Text("CONTINUE", comment: "Summary primary CTA")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1.6)
                    Spacer()
                }
                .foregroundStyle(Color.ikeruBackground)
                .padding(.vertical, 14)
                .background(Color.ikeruPrimaryAccent)
                .sumiCorners(color: Color.ikeruBackground.opacity(0.6), size: 6, weight: 1.2, inset: -1)
            }
            .buttonStyle(.plain)

            Button { onReviewMistakes() } label: {
                Text("REVIEW MISTAKES", comment: "Summary secondary CTA")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .tracking(1.4)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private func onContinue() {
        viewModel.dismissSession()
    }

    private func onReviewMistakes() {
        // Review-mistakes flow is not yet wired — preserve dismiss behavior
        // so the secondary button still closes the summary cleanly.
        viewModel.dismissSession()
    }

    // MARK: - Derived display values
    //
    // The view-model does not expose recall % / xp-progress / rank labels
    // directly — derive them locally from the canonical fields on
    // `SessionViewModel` without mutating its state.

    private var cardsCount: Int { viewModel.reviewedCount }

    /// Approximate recall percentage. The session view-model does not track
    /// per-grade correctness; `consecutiveCorrect` is the closest available
    /// signal. When all reviews ended with a streak, recall reads as 100%;
    /// otherwise it is the proportion of cards in the active correct streak
    /// over the total reviewed. Returns 0 when no cards reviewed.
    private var recallPercentage: Int {
        guard viewModel.reviewedCount > 0 else { return 0 }
        let ratio = Double(viewModel.consecutiveCorrect) / Double(viewModel.reviewedCount)
        return Int((ratio * 100).rounded())
    }

    private var timeString: String { viewModel.elapsedTimeFormatted }

    /// Within-level XP progression after this session's gain.
    private var xpProgress: Double {
        let progress = RPGConstants.progressInLevel(totalXP: viewModel.totalXP)
        let required = max(1, progress.required)
        return min(1, max(0, Double(progress.current) / Double(required)))
    }

    /// Width of the bright "new gain" segment, expressed as a fraction of
    /// the level's required XP. Capped so it never exceeds the full bar.
    private var xpGainProgress: Double {
        let progress = RPGConstants.progressInLevel(totalXP: viewModel.totalXP)
        let required = max(1, progress.required)
        let gainFraction = Double(viewModel.xpEarned) / Double(required)
        return min(xpProgress, max(0, gainFraction))
    }

    private var rankLabelStart: String { "第\(viewModel.currentLevel)段" }
    private var rankLabelEnd: String { "第\(viewModel.currentLevel + 1)段" }

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
