import SwiftUI
import SwiftData
import IkeruCore

// MARK: - ProgressDashboardView
//
// Tatami-direction Study tab. JLPT estimate hero (glass), skill-balance
// room with hairline progress per skill, and a fusuma-railed decks list.
// Kana / Dictionary entry links are preserved because they are existing
// functional surfaces — they keep IkeruCard styling for now since they
// belong to navigation rather than study analytics.

struct ProgressDashboardView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ProgressDashboardViewModel?

    var body: some View {
        ZStack {
            IkeruScreenBackground(variant: .auxiliary)
                .ignoresSafeArea()

            if let vm = viewModel, vm.hasLoaded {
                dashboardContent(vm)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            initializeViewModel()
            await viewModel?.loadData()
        }
        .onAppear {
            if viewModel != nil {
                Task { await viewModel?.loadData() }
            }
        }
    }

    // MARK: - Dashboard Content

    @ViewBuilder
    private func dashboardContent(_ vm: ProgressDashboardViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                kanaEntryLink
                dictionaryEntryLink
                jlptHero(vm)
                skillBalanceSection(vm)
                decksSection
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 140)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            BilingualLabel(japanese: "進歩", chrome: "Progress")
            HStack(spacing: 0) {
                Text("Your study", comment: "Study tab heading")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextPrimary)
                Text("。")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(TatamiTokens.paperGhost)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 6)
    }

    // MARK: - Kana entry link

    private var kanaEntryLink: some View {
        NavigationLink {
            KanaPoolSelectorView()
        } label: {
            HStack(spacing: IkeruTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.ikeruPrimaryAccent.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Text("あ")
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kana")
                        .font(.ikeruHeading3)
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Text("Hiragana & katakana, by groups")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextTertiary)
            }
            .ikeruCard(.interactive)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dictionary entry link

    private var dictionaryEntryLink: some View {
        NavigationLink {
            VocabularyDictionaryView()
        } label: {
            HStack(spacing: IkeruTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.ikeruSecondaryAccent.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Text("辞")
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ikeruSecondaryAccent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dictionary")
                        .font(.ikeruHeading3)
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Text("Personal vocabulary collection")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextTertiary)
            }
            .ikeruCard(.interactive)
        }
        .buttonStyle(.plain)
    }

    // MARK: - JLPT Hero

    @ViewBuilder
    private func jlptHero(_ vm: ProgressDashboardViewModel) -> some View {
        let level = vm.jlptEstimate.level
        let percent = Int(vm.jlptEstimate.masteryFraction * 100)
        let progress = max(0, min(1, vm.jlptEstimate.masteryFraction))

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    BilingualLabel(japanese: "推定", chrome: "JLPT estimate")
                    Text("Based on your last 90 reviews",
                         comment: "JLPT estimate sub-caption")
                        .font(.system(size: 12, design: .serif))
                        .italic()
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
                Spacer()
                HankoStamp(kanji: level, size: 42)
            }

            HStack(alignment: .firstTextBaseline) {
                SerifNumeral(percent, size: 48)
                Text("%")
                    .font(.system(size: 12))
                    .foregroundStyle(TatamiTokens.paperGhost)
                    .tracking(1.4)
                Spacer()
                Text("READY FOR \(level)",
                     comment: "JLPT readiness label")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .tracking(1.2)
            }

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(TatamiTokens.goldDim.opacity(0.3))
                    .frame(height: 3)
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.ikeruPrimaryAccent)
                        .frame(width: geo.size.width * progress, height: 1)
                }
                .frame(height: 3)
            }
        }
        .tatamiRoom(.glass, padding: 22)
    }

    // MARK: - Skill Balance

    @ViewBuilder
    private func skillBalanceSection(_ vm: ProgressDashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            BilingualLabel(japanese: "技能", chrome: "Skill balance", mon: .asanoha)
            VStack(spacing: 14) {
                ForEach(skillRows(vm.skillBalance)) { skill in
                    skillRowView(skill)
                }
            }
        }
        .tatamiRoom(.standard, padding: 20)
    }

    @ViewBuilder
    private func skillRowView(_ skill: SkillRow) -> some View {
        HStack(spacing: 10) {
            MonCrest(kind: skill.mon, size: 16, color: .ikeruPrimaryAccent)
            VStack(alignment: .leading, spacing: 4) {
                Text(skill.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .tracking(1)
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(red: 0.094, green: 0.094, blue: 0.122))
                        .frame(height: 2)
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.ikeruPrimaryAccent.opacity(0.85))
                            .frame(width: geo.size.width * skill.progress, height: 2)
                    }
                    .frame(height: 2)
                }
            }
            SerifNumeral(Int(skill.progress * 100), size: 14, color: .ikeruPrimaryAccent)
        }
    }

    // MARK: - Decks

    private var decksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            BilingualLabel(japanese: "稽古場", chrome: "Decks", mon: .kikkou)
                .padding(.bottom, 10)
            // ProgressDashboardViewModel does not yet expose per-deck
            // counts, so the rows below are derived structurally from a
            // static deck catalog — mirrors the T4 streak / T7 achievements
            // placeholder pattern. When the VM gains a `decks` property
            // these can be swapped for `vm.decks`.
            ForEach(Array(placeholderDecks.enumerated()), id: \.offset) { index, deck in
                deckRow(deck, isFirst: index == 0)
            }
        }
    }

    @ViewBuilder
    private func deckRow(_ deck: DeckRow, isFirst: Bool) -> some View {
        HStack(spacing: 12) {
            MonCrest(kind: deck.mon, size: 16, color: .ikeruPrimaryAccent)
            VStack(alignment: .leading, spacing: 4) {
                Text(deck.japanese)
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(Color.ikeruTextPrimary)
                Text(deck.english)
                    .font(.system(size: 11))
                    .foregroundStyle(TatamiTokens.paperGhost)
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(red: 0.094, green: 0.094, blue: 0.122))
                        .frame(width: 80, height: 1)
                    Rectangle()
                        .fill(Color.ikeruPrimaryAccent.opacity(0.7))
                        .frame(width: 80 * deck.progress, height: 1)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                SerifNumeral(deck.learned, size: 14, color: .ikeruPrimaryAccent)
                Text("/\(deck.total)")
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(TatamiTokens.paperGhost)
            }
            Text("LEARNED")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(TatamiTokens.paperGhost)
                .tracking(1.2)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .overlay(alignment: .top) {
            if isFirst {
                Rectangle()
                    .fill(TatamiTokens.goldDim.opacity(0.7))
                    .frame(height: 1)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.ikeruPrimaryAccent.opacity(0.3))
                .frame(height: 1)
        }
    }

    // MARK: - Helpers

    private func initializeViewModel() {
        guard viewModel == nil else { return }
        let container = modelContext.container
        viewModel = ProgressDashboardViewModel(modelContainer: container)
    }

    private func skillRows(_ balance: SkillBalanceSnapshot) -> [SkillRow] {
        // Derive per-skill mons by hashing the skill name into MonKind.allCases
        // — same pattern as deck mon assignment; keeps a stable mapping.
        let entries: [(String, Double)] = [
            ("READING", balance.reading),
            ("WRITING", balance.writing),
            ("LISTENING", balance.listening),
            ("SPEAKING", balance.speaking)
        ]
        return entries.map { (name, value) in
            SkillRow(
                id: name,
                name: name,
                progress: max(0, min(1, value)),
                mon: monForName(name)
            )
        }
    }

    /// Static deck fixture used until ProgressDashboardViewModel exposes deck
    /// summaries. Mirrors the kana/vocabulary surfaces the app actually
    /// teaches today; values are 0/0 so no false progress is implied.
    private var placeholderDecks: [DeckRow] {
        let names: [(jp: String, en: String)] = [
            ("ひらがな", "Hiragana"),
            ("カタカナ", "Katakana"),
            ("漢字", "Kanji"),
            ("語彙", "Vocabulary")
        ]
        return names.map { entry in
            DeckRow(
                japanese: entry.jp,
                english: entry.en,
                learned: 0,
                total: 0,
                progress: 0,
                mon: monForName(entry.en)
            )
        }
    }

    /// Hash a stable string into one of the four `MonKind` cases. Keeps the
    /// crest assignment deterministic for a given deck/skill name.
    private func monForName(_ name: String) -> MonKind {
        let cases = MonKind.allCases
        let hash = abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        return cases[hash % cases.count]
    }
}

// MARK: - Local row models

private struct SkillRow: Identifiable {
    let id: String
    let name: String
    let progress: Double
    let mon: MonKind
}

private struct DeckRow {
    let japanese: String
    let english: String
    let learned: Int
    let total: Int
    let progress: Double
    let mon: MonKind
}

// MARK: - Preview

#Preview("Progress Dashboard") {
    NavigationStack {
        ProgressDashboardView()
    }
    .preferredColorScheme(.dark)
}
