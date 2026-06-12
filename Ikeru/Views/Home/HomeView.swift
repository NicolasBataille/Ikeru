import SwiftUI
import SwiftData
import IkeruCore
import os

#if canImport(UIKit)
import UIKit
#endif

// MARK: - DailyTermSheet

/// Single source of truth for which daily-term sheet is showing.
/// Driving all sheets via one Identifiable enum lets SwiftUI handle the
/// cross-fade between e.g. "history" and "reveal a history row" — stacked
/// `.sheet` modifiers can only present one at a time and silently swallow
/// transitions on iOS.
private enum DailyTermSheet: Identifiable {
    case reveal(DailyTermDTO)
    case history

    var id: String {
        switch self {
        case .reveal(let term): return "reveal-\(term.id)"
        case .history: return "history"
        }
    }
}

// MARK: - HomeView
//
// Wabi-sabi refined home. The hero card is proverb-centric (七転八起 promoted
// to the focal element), rank sits as chrome (EnsoRank brush glyph + 第N段),
// progression reads as carved segments not a gradient smear, and the stats
// row weights "Due Now" as the action card over the two quieter metrics.

struct HomeView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayMode) private var displayMode
    @Environment(\.displayModeRepository) private var displayModeRepo
    @Environment(AppLocale.self) private var appLocale
    @State private var viewModel: HomeViewModel?
    @State private var sessionViewModel: SessionViewModel?
    @State private var dailyTermViewModel: DailyTermViewModel?
    @State private var suggestionController: DisplayModeSuggestionCardController?
    @State private var showSession = false
    @State private var heroAppeared = false
    @State private var dailyTermSheet: DailyTermSheet?
    @AppStorage(DailyTermSettings.enabledKey) private var dailyTermEnabled: Bool = false
    @AppStorage("ikeru.equippedTitleName") private var equippedTitleName: String = ""

    var body: some View {
        ZStack {
            IkeruScreenBackground(variant: .home)

            if let vm = viewModel {
                homeContent(vm)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showSession) {
            if let svm = sessionViewModel {
                ActiveSessionView(viewModel: svm)
                    .onChange(of: svm.isActive) { _, isActive in
                        if !isActive {
                            showSession = false
                        }
                    }
            }
        }
        .sheet(item: $dailyTermSheet) { sheet in
            dailyTermSheetContent(sheet)
        }
        .task {
            initializeViewModels()
            await viewModel?.loadData()
            await dailyTermViewModel?.load()
            await viewModel?.refreshRestDay()
            await refreshSuggestionController()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86).delay(0.05)) {
                heroAppeared = true
            }
            if CommandLine.arguments.contains("-autoStartSession") {
                startSession()
            }
        }
        .onChange(of: displayMode) { _, new in
            suggestionController?.setMode(new)
        }
        .onAppear {
            if viewModel != nil {
                Task { await viewModel?.loadData() }
                Task { await dailyTermViewModel?.reloadIfDayChanged() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await dailyTermViewModel?.reloadIfDayChanged() }
            }
        }
        .onChange(of: dailyTermEnabled) { _, _ in
            Task { await dailyTermViewModel?.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startQuizFromShortcut)) { _ in
            initializeViewModels()
            startSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: .startReviewFromShortcut)) { _ in
            initializeViewModels()
            startSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDailyTerm)) { _ in
            Task {
                await dailyTermViewModel?.reloadIfDayChanged()
                if let term = dailyTermViewModel?.today {
                    dailyTermSheet = .reveal(term)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ikeruActiveProfileDidChange)) { _ in
            Task {
                await viewModel?.loadData()
                await refreshSuggestionController()
            }
        }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            Task { await dailyTermViewModel?.reloadIfDayChanged() }
        }
        #endif
    }

    // MARK: - Daily-term sheet content

    @ViewBuilder
    private func dailyTermSheetContent(_ sheet: DailyTermSheet) -> some View {
        switch sheet {
        case .reveal(let snapshot):
            if let dvm = dailyTermViewModel {
                DailyTermRevealHostView(
                    initialTerm: snapshot,
                    viewModel: dvm,
                    onDismiss: { dailyTermSheet = nil },
                    onShowHistory: { dailyTermSheet = .history }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        case .history:
            if let dvm = dailyTermViewModel {
                DailyTermHistoryView(
                    terms: dvm.recent,
                    onSelect: { term in
                        dailyTermSheet = .reveal(term)
                    },
                    onDismiss: { dailyTermSheet = nil }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Suggestion Card Controller

    private func refreshSuggestionController() async {
        guard let profileID = ActiveProfileResolver.activeProfileID(),
              let vm = viewModel
        else { return }

        let controller = suggestionController ?? DisplayModeSuggestionCardController(
            profileID: profileID,
            currentMode: displayMode
        )
        controller.setMode(displayMode)
        let signals = await vm.advancedThresholdSignals()
        controller.onSignalsChanged(
            streak: signals.streak,
            reviews: signals.reviews,
            mastery: signals.mastery
        )
        suggestionController = controller
    }

    // MARK: - Home Content

    @ViewBuilder
    private func homeContent(_ vm: HomeViewModel) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: IkeruTheme.Spacing.lg) {
                if let controller = suggestionController, controller.shouldShow {
                    DisplayModeSuggestionCard(
                        onAccept: {
                            displayModeRepo?.set(.tatami)
                            controller.dismiss()
                        },
                        onDismiss: { controller.dismiss() }
                    )
                }
                topBar(vm)
                proverbHero(vm)
                dailyTermSection
                sessionBreakdown(vm)
                if vm.hasLoaded && vm.dueCardCount == 0 {
                    quietState
                }
            }
            .padding(.horizontal, IkeruTheme.Spacing.lg)
            .padding(.top, IkeruTheme.Spacing.md)
            .padding(.bottom, 140) // Space for floating tab bar
            .opacity(heroAppeared ? 1 : 0)
            .offset(y: heroAppeared ? 0 : 16)
        }
    }

    // MARK: - Quiet state (when no cards due)

    private var quietState: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.ikeruSuccess)
            Text("All caught up — enjoy the calm")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.5), lineWidth: 0.6))
        }
        .sumiCorners(color: TatamiTokens.goldDim, size: 5, weight: 0.9)
    }

    // MARK: - Top Bar

    @ViewBuilder
    private func topBar(_ vm: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Serif kanji date row — sits where the SF status time bar lives
            HStack {
                Spacer()
                Text(serifJapaneseDate())
                    .font(.system(size: 11, weight: .regular, design: .serif))
                    .foregroundStyle(TatamiTokens.paperGhost)
                    .tracking(1)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeOfDayGreetingJP())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                        .tracking(2.4)
                        .textCase(.uppercase)

                    HStack(spacing: 0) {
                        Text(vm.displayName.isEmpty
                             ? String(localized: "Welcome")
                             : vm.displayName)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.ikeruTextPrimary)
                        Text("。")
                            .font(.system(size: 22, weight: .semibold, design: .serif))
                            .foregroundStyle(TatamiTokens.paperGhost)
                    }

                    if !equippedTitleName.isEmpty {
                        Text(equippedTitleName.uppercased())
                            .font(.ikeruMicro)
                            .ikeruTracking(.micro)
                            .foregroundStyle(Color.ikeruPrimaryAccent)
                    }
                }
                Spacer()
                levelPill(level: vm.level)
            }
        }
        .padding(.top, IkeruTheme.Spacing.xs)
    }

    /// Returns "四月二十九日 · 火" (Japanese serif kanji date).
    private func serifJapaneseDate() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日 · E"
        return f.string(from: Date())
    }

    // MARK: - Daily Term

    @ViewBuilder
    private var dailyTermSection: some View {
        if dailyTermEnabled, let dvm = dailyTermViewModel, let term = dvm.today {
            if dvm.todayNeedsReveal {
                DailyTermBanner(
                    term: term,
                    yesterday: dvm.yesterday,
                    onTap: { dailyTermSheet = .reveal(term) }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                DailyTermRevealedPill(
                    term: term,
                    yesterday: dvm.yesterday,
                    onTap: { dailyTermSheet = .reveal(term) }
                )
                .transition(.opacity)
            }
        }
    }

    /// Returns "こんばんは" / "おはよう" / "こんにちは" depending on the hour.
    private func timeOfDayGreetingJP() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<11: return "おはよう"
        case 11..<17: return "こんにちは"
        default: return "こんばんは"
        }
    }

    // Level pill (top-right) per the design brief — replaces the earlier streak
    // pill, which contradicted the product brief's anti-gamification stance
    // ("no streaks, no gems, no daily login pressure").
    @ViewBuilder
    private func levelPill(level: Int) -> some View {
        HStack(spacing: 7) {
            EnsoRankView(level: level, size: 16)
            Text("\u{7B2C}\(level)\u{6BB5}") // 第N段
                .font(.system(size: 12, weight: .medium, design: .serif))
                .foregroundStyle(Color.ikeruTextPrimary)
                .tracking(1.4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.5), lineWidth: 0.6))
        }
        .sumiCorners(color: TatamiTokens.goldDim, size: 5, weight: 0.9)
    }

    // MARK: - Rest Day Block

    private var restDayBlock: some View {
        VStack(spacing: 6) {
            Text("\u{4ECA}\u{65E5}\u{306F}\u{4F11}") // 今日は休
                .font(.system(size: 26, design: .serif))
                .foregroundStyle(Color.ikeruPrimaryAccent)
            Text("Home.RestDay.Title", comment: "Rest day chrome label")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Color.ikeruTextSecondary)
            Text("Home.RestDay.Body", comment: "Rest day body copy")
                .font(.system(size: 11))
                .italic()
                .foregroundStyle(Color.ikeruTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
    }

    // MARK: - Proverb Hero

    @ViewBuilder
    private func proverbHero(_ vm: HomeViewModel) -> some View {
        let proverb = HomeProverb.dailyProverb(level: vm.level)
        let progress = Double(vm.xpInCurrentLevel) / Double(max(1, vm.xpRequiredForLevel))

        VStack(alignment: .leading, spacing: 14) {
            // Top row — bilingual "本日 · TODAY" + Hanko stamp when work is due
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    BilingualLabel(japanese: "本日", chrome: "Today", mon: nil)
                    Text(proverb.kanji)
                        .font(.system(size: 19, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ikeruTextPrimary)
                        .lineLimit(1)
                        .tracking(2)
                    Text(proverb.translation)
                        .font(.system(size: 11))
                        .italic()
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
                Spacer()
                if vm.dueCardCount > 0 {
                    HankoStamp(kanji: "急", size: 36)
                }
            }

            // Due count — large serif numeral
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                SerifNumeral(vm.dueCardCount, size: 56, color: .ikeruTextPrimary)
                Text("CARDS DUE", comment: "Hero stat label on Home")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .tracking(1.4)
                    .textCase(.uppercase)
            }

            // Practice CTA — sharp gold, bilingual, sumi corners.
            // Replaced by the rest-day surface when conditions hold.
            if vm.restDayActive {
                restDayBlock
            } else {
                Button {
                    startSession()
                } label: {
                    HStack {
                        Spacer()
                        Text("稽古を始める · ")
                            .font(.system(size: 13, weight: .regular, design: .serif))
                        Text("BEGIN PRACTICE", comment: "Hero CTA on Home")
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
                .tourAnchor(.sessionCTA)
            }

            // XP progress — fusuma rail with serif numerals
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    BilingualLabel(japanese: "経験", chrome: "Experience", mon: nil)
                    Spacer()
                    HStack(spacing: 0) {
                        SerifNumeral(vm.xpInCurrentLevel, size: 12,
                                     weight: .regular, color: .ikeruPrimaryAccent)
                        Text(" / ")
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(TatamiTokens.paperGhost)
                        SerifNumeral(vm.xpRequiredForLevel, size: 12,
                                     weight: .regular, color: TatamiTokens.paperGhost)
                    }
                }

                // Hairline fusuma progress
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(TatamiTokens.goldDim.opacity(0.3))
                        .frame(height: 2)
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.ikeruPrimaryAccent)
                            .frame(width: geo.size.width * progress, height: 2)
                            .shadow(color: .ikeruPrimaryAccent.opacity(0.6), radius: 3)
                    }
                    .frame(height: 2)
                }

                Text("\(vm.xpToNextLevel) XP to next rank",
                     comment: "Subtle XP-remaining label on the Home hero")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .tatamiRoom(.glass, padding: 20)
    }

    // MARK: - Session breakdown
    //
    // Quiet preview of what the next session contains: split between brand-new
    // exposures and reviews. Sits under the CTA so the user knows what they're
    // walking into without having to start the session first.

    @ViewBuilder
    private func sessionBreakdown(_ vm: HomeViewModel) -> some View {
        if vm.sessionPreviewCardCount > 0 {
            HStack(spacing: 0) {
                breakdownCell(
                    icon: "sparkles",
                    label: Text("New", comment: "Session preview: number of brand-new cards"),
                    count: vm.sessionPreviewNewCount,
                    tint: .ikeruSecondaryAccent
                )
                Divider()
                    .frame(width: 0.6, height: 28)
                    .overlay(Color.white.opacity(0.10))
                breakdownCell(
                    icon: "arrow.triangle.2.circlepath",
                    label: Text("Review", comment: "Session preview: number of review cards"),
                    count: vm.sessionPreviewReviewCount,
                    tint: .ikeruPrimaryAccent
                )
                Divider()
                    .frame(width: 0.6, height: 28)
                    .overlay(Color.white.opacity(0.10))
                breakdownCell(
                    icon: "timer",
                    label: Text("Approx", comment: "Session preview: approximate duration"),
                    valueText: "\(max(1, vm.sessionPreviewMinutes))m",
                    tint: .ikeruTertiaryAccent
                )
            }
            .tatamiRoom(.standard, padding: 14)
        }
    }

    @ViewBuilder
    private func breakdownCell(
        icon: String,
        label: Text,
        count: Int? = nil,
        valueText: String? = nil,
        tint: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                label
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Color.ikeruTextTertiary)
                    .textCase(.uppercase)
                Text(valueText ?? "\(count ?? 0)")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.ikeruTextPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    // MARK: - Helpers

    private func initializeViewModels() {
        guard viewModel == nil else { return }
        let container = modelContext.container

        viewModel = HomeViewModel(modelContainer: container)
        dailyTermViewModel = DailyTermViewModel(
            modelContainer: container,
            locale: appLocale.currentLocale
        )

        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)
        sessionViewModel = SessionViewModel(
            plannerService: planner,
            cardRepository: repo,
            modelContainer: container
        )
    }

    private func startSession() {
        guard let svm = sessionViewModel else { return }
        Task {
            let container = modelContext.container
            let repo = CardRepository(modelContainer: container)
            let allCards = await repo.allCards()
            await ContentSeedService.seedBeginnerKanaIfNeeded(
                repository: repo,
                existingCardCount: allCards.count
            )
            await svm.startSession()
            showSession = true
        }
    }
}

// MARK: - Proverb pool
//
// Curated 四字熟語 (yojijukugo) only — four-kanji idioms. Restricting the pool
// to four-character entries keeps the hero typography stable: longer
// proverbs (千里の道も一歩から, 塵も積もれば山となる) wrap and break the layout
// because the kanji line is sized for four glyphs at 40pt with tracking 4.

struct HomeProverb {
    let kanji: String
    let romaji: String
    let translation: String

    static let pool: [HomeProverb] = [
        HomeProverb(
            kanji: "七転八起",
            romaji: "nana korobi ya oki",
            translation: "Fall seven times, rise eight."
        ),
        HomeProverb(
            kanji: "一期一会",
            romaji: "ichi go ichi e",
            translation: "One time, one meeting — treasure every encounter."
        ),
        HomeProverb(
            kanji: "\u{6E29}\u{6545}\u{77E5}\u{65B0}", // 温故知新
            romaji: "onko chishin",
            translation: "Learn the new by warming the old."
        ),
        HomeProverb(
            kanji: "\u{4E00}\u{5FC3}\u{4E0D}\u{4E71}", // 一心不乱
            romaji: "isshin furan",
            translation: "One mind, no scattering — wholehearted focus."
        ),
        HomeProverb(
            kanji: "\u{521D}\u{5FD7}\u{8CAB}\u{5FB9}", // 初志貫徹
            romaji: "shoshi kantetsu",
            translation: "Carry your first intention through to the end."
        ),
        HomeProverb(
            kanji: "\u{6709}\u{8A00}\u{5B9F}\u{884C}", // 有言実行
            romaji: "yūgen jikkō",
            translation: "Words become deeds."
        )
    ]

    static func dailyProverb(level: Int) -> HomeProverb {
        // Seed by day + level so it changes daily but stays stable across
        // re-renders of the same screen.
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let idx = abs(day + level) % pool.count
        return pool[idx]
    }
}

// MARK: - Preview

#Preview("HomeView") {
    NavigationStack {
        HomeView()
    }
    .preferredColorScheme(.dark)
}
