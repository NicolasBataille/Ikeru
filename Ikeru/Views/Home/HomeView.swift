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
    @State private var showSession = false
    @State private var heroAppeared = false
    @State private var dailyTermSheet: DailyTermSheet?
    @State private var showStudySetChooser = false
    @AppStorage(DailyTermSettings.enabledKey) private var dailyTermEnabled: Bool = false

    /// Lifetime review count captured right before `startSession()` launches
    /// the session sheet — compared against the post-session count to detect
    /// the learner's first-ever completed session (0 → >0 crossing) so the
    /// one-time daily-term prompt fires exactly once, right after it.
    @State private var reviewsBeforeSession = 0
    @State private var showFirstSessionDailyTermPrompt = false
    @State private var showCaughtUpExplainer = false

    var body: some View {
        ZStack {
            IkeruScreenBackground(variant: .home)

            if let vm = viewModel {
                homeContent(vm)
            }

            // Sakura's one-time "all caught up — what now?" explainer. The
            // first time Home lands on the quiet state (every chosen kana
            // begun, nothing due), a fresh learner is otherwise staring at a
            // silent dead-end (owner request, device pass 2026-07-19).
            if showCaughtUpExplainer {
                caughtUpExplainerOverlay
                    .zIndex(10)
                    .transition(.opacity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showSession) {
            if let svm = sessionViewModel {
                ActiveSessionView(viewModel: svm)
                    .onChange(of: svm.isActive) { _, isActive in
                        if !isActive {
                            showSession = false
                            Task {
                                await viewModel?.refreshAfterSession()
                                evaluateFirstSessionDailyTermPrompt()
                                evaluateCaughtUpExplainer()
                            }
                        }
                    }
            }
        }
        .alert(
            "Home.DailyTermPrompt.Title",
            isPresented: $showFirstSessionDailyTermPrompt
        ) {
            Button("Home.DailyTermPrompt.Enable") {
                enableDailyTermFromPrompt()
            }
            Button("Home.DailyTermPrompt.NotNow", role: .cancel) {}
        } message: {
            Text("Home.DailyTermPrompt.Message")
        }
        .sheet(item: $dailyTermSheet) { sheet in
            dailyTermSheetContent(sheet)
        }
        .sheet(isPresented: $showStudySetChooser) {
            NavigationStack {
                KanaPoolSelectorView(onStudySetConfirmed: {
                    showStudySetChooser = false
                    // "Commencer ces kana" keeps its promise: confirm flows
                    // straight into the first session instead of dropping the
                    // learner back on Home (owner feedback, device pass). The
                    // short pause lets the sheet finish dismissing before the
                    // session cover presents — presenting mid-dismissal gets
                    // silently dropped by UIKit.
                    Task {
                        await viewModel?.loadData()
                        try? await Task.sleep(for: .milliseconds(500))
                        startSession()
                    }
                })
            }
            .presentationDragIndicator(.visible)
        }
        .task {
            initializeViewModels()
            await viewModel?.loadData()
            await dailyTermViewModel?.load()
            await viewModel?.refreshRestDay()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86).delay(0.05)) {
                heroAppeared = true
            }
            // Also covers opening the app already caught-up (the state can be
            // reached without a session ending this launch).
            evaluateCaughtUpExplainer()
            if CommandLine.arguments.contains("-autoStartSession") {
                startSession()
            }
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

    // MARK: - Home Content

    @ViewBuilder
    private func homeContent(_ vm: HomeViewModel) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: IkeruTheme.Spacing.lg) {
                topBar(vm)
                proverbHero(vm)
                dailyTermSection
                sessionBreakdown(vm)
                competencyBookSection(vm)
                nextStepSection(vm)
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

    // MARK: - Choose-your-kana CTA (soft study-set gate)

    /// Shown when the learner hasn't yet chosen a study set. A calm invitation
    /// to pick their kana first — no urgency, no locked wall — so Practice
    /// always matches what they actually started learning.
    private var chooseKanaCTA: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Home.ChooseKana.Hint")
                .ikeruScaledFont(12, relativeTo: .caption)
                .italic()
                .foregroundStyle(Color.ikeruTextSecondary)

            Button {
                showStudySetChooser = true
            } label: {
                HStack {
                    Spacer()
                    Text("\u{4EEE}\u{540D}\u{3092}\u{9078}\u{3076} \u{00B7} ") // 仮名を選ぶ
                        .ikeruScaledFont(15, weight: .regular, design: .serif, relativeTo: .body)
                    Text("CHOOSE YOUR KANA", comment: "Home CTA: pick a kana study set first")
                        .ikeruScaledFont(15, weight: .bold, relativeTo: .body)
                        .tracking(1.4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                }
            }
            .ikeruButtonStyle(.primary)
            // Share the feature-tour anchor with BEGIN PRACTICE: exactly one of
            // the two CTAs renders at a time, so the tour's session step always
            // spotlights whichever is on screen. A brand-new profile sees this
            // "choose your kana" gate (no cards yet), not BEGIN PRACTICE — the
            // tour fires the instant onboarding finishes, so without this the
            // step would point at a button that isn't there.
            .tourAnchor(.sessionCTA)
        }
    }

    // MARK: - Top Bar

    @ViewBuilder
    private func topBar(_ vm: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Serif kanji date row — sits where the SF status time bar lives
            HStack {
                Spacer()
                Text(serifJapaneseDate())
                    .ikeruScaledFont(11, weight: .regular, design: .serif, relativeTo: .caption2)
                    .foregroundStyle(TatamiTokens.paperGhost)
                    .tracking(1)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeOfDayGreetingJP())
                        .ikeruScaledFont(11, weight: .semibold, relativeTo: .caption2)
                        .tracking(2.4)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Color.ikeruPrimaryAccent)

                    HStack(spacing: 0) {
                        Text(vm.displayName.isEmpty
                             ? String(localized: "Welcome")
                             : vm.displayName)
                            .ikeruScaledFont(22, weight: .semibold, relativeTo: .title2)
                            .foregroundStyle(Color.ikeruTextPrimary)
                        Text("。")
                            .ikeruScaledFont(22, weight: .semibold, design: .serif, relativeTo: .title2)
                            .foregroundStyle(TatamiTokens.paperGhost)
                    }
                }
                Spacer()
            }
        }
        .padding(.top, IkeruTheme.Spacing.xs)
    }

    /// Returns "四月二十九日 · 火" (Japanese serif kanji date).
    private func serifJapaneseDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日 · E"
        return formatter.string(from: Date())
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

    // MARK: - Rest Day Block

    private var restDayBlock: some View {
        VStack(spacing: 6) {
            Text("\u{4ECA}\u{65E5}\u{306F}\u{4F11}") // 今日は休
                .font(.system(size: 26, design: .serif))
                .foregroundStyle(Color.ikeruPrimaryAccent)
            Text("Home.RestDay.Title", comment: "Rest day chrome label")
                .ikeruScaledFont(11, weight: .semibold, relativeTo: .caption2)
                .tracking(1.6)
                .foregroundStyle(Color.ikeruTextSecondary)
            Text("Home.RestDay.Body", comment: "Rest day body copy")
                .ikeruScaledFont(11, relativeTo: .caption2)
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
        // Rotate the proverb by day of year (was keyed to RPG level, now removed).
        let dayIndex = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let proverb = HomeProverb.dailyProverb(level: dayIndex)

        VStack(alignment: .leading, spacing: 14) {
            // Proverb header — calm by design, no urgency stamp.
            VStack(alignment: .leading, spacing: 8) {
                BilingualLabel(japanese: "本日", chrome: "Today", mon: nil)
                Text(proverb.kanji)
                    .ikeruScaledFont(19, weight: .regular, design: .serif, relativeTo: .title3)
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .lineLimit(1)
                    .tracking(2)
                Text(proverb.translation)
                    .ikeruScaledFont(11, relativeTo: .caption2)
                    .italic()
                    .foregroundStyle(Color.ikeruTextSecondary)
            }

            // Today's count — the *composed-session* size with an honest label
            // that always matches the new/review breakdown below it.
            if vm.todayKind != .empty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    SerifNumeral(vm.todayCount, size: 56, color: .ikeruTextPrimary)
                    Text(heroCountLabel(for: vm.todayKind))
                        .ikeruScaledFont(12, weight: .semibold, relativeTo: .caption2)
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
            }

            // CTA / rest-day / all-caught-up — the CTA only exists when there is
            // actually something composable, so it can never launch an empty session.
            if vm.restDayActive {
                restDayBlock
            } else if vm.needsStudySetChoice {
                // Soft gate: invite the learner to pick their kana before any
                // practice, so the session always matches what they chose.
                chooseKanaCTA
            } else if vm.todayKind == .empty {
                quietState
            } else {
                // Hero CTA — speaks the shared .primary ink-block language
                // (owner feedback: every gold action should look like ONE
                // family). Inner texts keep their own fonts; the style
                // supplies the block, brackets, glow and press feel.
                Button {
                    startSession()
                } label: {
                    HStack {
                        Spacer()
                        Text("稽古を始める · ")
                            .ikeruScaledFont(15, weight: .regular, design: .serif, relativeTo: .body)
                        Text("BEGIN PRACTICE", comment: "Hero CTA on Home")
                            .ikeruScaledFont(15, weight: .bold, relativeTo: .body)
                            .tracking(1.6)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer()
                    }
                }
                .ikeruButtonStyle(.primary)
                .tourAnchor(.sessionCTA)
                .accessibilityIdentifier("home.beginPracticeButton")
            }

            // Beginner's compass — kana mastery, always visible (the honest
            // progress number that replaces XP/streak chrome). Identifier is
            // on the count `Text` leaf inside, not this call site — see
            // `kanaProgressLine`'s body.
            kanaProgressLine(vm)
        }
        .tatamiRoom(.glass, padding: 20)
    }

    /// Honest hero label keyed to the composed session's mix.
    private func heroCountLabel(for kind: HomeViewModel.TodayKind) -> LocalizedStringKey {
        switch kind {
        case .allNew:    return "Home.Hero.ToLearn"
        case .allReview: return "Home.Hero.ToReview"
        case .mixed:     return "Home.Hero.Today"
        case .empty:     return ""
        }
    }

    /// "かな X/92 learned" — the calm progress signal for beginners.
    ///
    /// Also carries the "in progress" count (`learningTotal`) whenever it's
    /// nonzero. Without it, a beginner's first-ever session ends with this
    /// line stuck at "0/92" — mathematically correct (mastery requires
    /// `reps >= 2`, see `MasteryLevel`) but silent, exactly the "anti-burnout
    /// without a mirror" gap the 2026-08-10 review names. The in-progress
    /// count is the trace that makes session one visible.
    private func kanaProgressLine(_ vm: HomeViewModel) -> some View {
        HStack(spacing: 8) {
            Text("\u{304B}\u{306A}") // かな
                .ikeruScaledFont(12, design: .serif, relativeTo: .caption)
                .foregroundStyle(Color.ikeruPrimaryAccent)
            Text("\(vm.kanaProgress.total)/\(KanaProgress.grandTotal)")
                .ikeruScaledFont(12, design: .serif, relativeTo: .caption)
                .monospacedDigit()
                .foregroundStyle(Color.ikeruTextSecondary)
                // Applied to this leaf `Text`, not the parent `HStack`: a
                // SwiftUI container isn't itself an accessibility element
                // unless explicitly combined (`.accessibilityElement(children:
                // .combine)`), so an identifier on the HStack would not be
                // queryable from XCUITest — see `IkeruUITests/Pages/HomePage.swift`.
                .accessibilityIdentifier("home.kanaProgressCount")
            Text("Home.KanaLearned")
                .ikeruScaledFont(10, relativeTo: .caption2)
                .textCase(.uppercase)
                .tracking(1.0)
                .foregroundStyle(Color.ikeruTextTertiary)

            if vm.kanaProgress.learningTotal > 0 {
                Text("\u{00B7}")
                    .foregroundStyle(Color.ikeruTextTertiary)
                Text("\(vm.kanaProgress.learningTotal)")
                    .ikeruScaledFont(12, design: .serif, relativeTo: .caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.ikeruTextSecondary)
                Text("Home.KanaInProgress")
                    .ikeruScaledFont(10, relativeTo: .caption2)
                    .textCase(.uppercase)
                    .tracking(1.0)
                    .foregroundStyle(Color.ikeruTextTertiary)
            }
            Spacer()
        }
        .padding(.top, 2)
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
                    .ikeruScaledFont(10, weight: .heavy, relativeTo: .caption2)
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Color.ikeruTextTertiary)
                Text(valueText ?? "\(count ?? 0)")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Color.ikeruTextPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    // MARK: - Competency booklet (the "miroir" — see CompetencyBookCard)
    //
    // Only renders once there is something to mirror (at least one card or
    // dictionary entry has been touched) — an untouched profile still gets
    // the choose-your-kana gate or the hero CTA, never an empty booklet.

    @ViewBuilder
    private func competencyBookSection(_ vm: HomeViewModel) -> some View {
        if vm.masteryBook.totalCount > 0 {
            CompetencyBookCard(
                masteryBook: vm.masteryBook,
                weeklyDelta: vm.masteryBookWeeklyDelta
            )
        }
    }

    // MARK: - Next-step suggestion (calm progression nudge)
    //
    // One gentle "do this next" card derived from the learner's progress (the
    // first unmet rung of the ladder). Shown only once the learner has started
    // (not while the choose-your-kana gate is up). The ladder's terminal rung
    // is `.converseWithSakura` — once a learner clears every earlier rung the
    // card keeps recommending Sakura rather than disappearing, since
    // `NextStepRecommender` has no "already caught up" state to fall back to
    // (see its doc comment: there is no "has conversed with Sakura" signal to
    // retire the rung with). Kana rungs are tappable (open the chooser to add
    // the next groups); later rungs are calm, informational — never dead taps.

    @ViewBuilder
    private func nextStepSection(_ vm: HomeViewModel) -> some View {
        if !vm.needsStudySetChoice,
           let step = vm.nextStep {
            if isKanaStage(step.stage) {
                Button { showStudySetChooser = true } label: { nextStepCard(step) }
                    .buttonStyle(.plain)
            } else {
                nextStepCard(step)
            }
        }
    }

    private func isKanaStage(_ stage: NextStep.Stage) -> Bool {
        stage == .learnHiragana || stage == .learnKatakana
    }

    @ViewBuilder
    private func nextStepCard(_ step: NextStep) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Home.NextStep.Eyebrow")
                    .ikeruScaledFont(10, weight: .semibold, relativeTo: .caption2)
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                Spacer()
                if step.required > 0 {
                    Text("\(step.current)/\(step.required)")
                        .ikeruScaledFont(11, design: .serif, relativeTo: .caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.ikeruTextTertiary)
                }
            }
            Text(nextStepTitle(step.stage))
                .ikeruScaledFont(15, weight: .regular, design: .serif, relativeTo: .body)
                .foregroundStyle(Color.ikeruTextPrimary)
            Text(nextStepBody(step.stage))
                .ikeruScaledFont(11, relativeTo: .caption2)
                .foregroundStyle(Color.ikeruTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tatamiRoom(.standard, padding: 14)
    }

    private func nextStepTitle(_ stage: NextStep.Stage) -> LocalizedStringKey {
        switch stage {
        case .learnHiragana:      return "Home.NextStep.Hiragana.Title"
        case .learnKatakana:      return "Home.NextStep.Katakana.Title"
        case .buildVocabulary:    return "Home.NextStep.Vocabulary.Title"
        case .learnKanji:         return "Home.NextStep.Kanji.Title"
        case .studyGrammar:       return "Home.NextStep.Grammar.Title"
        case .readingListening:   return "Home.NextStep.Reading.Title"
        case .converseWithSakura: return "Home.NextStep.Sakura.Title"
        }
    }

    private func nextStepBody(_ stage: NextStep.Stage) -> LocalizedStringKey {
        switch stage {
        case .learnHiragana:      return "Home.NextStep.Hiragana.Body"
        case .learnKatakana:      return "Home.NextStep.Katakana.Body"
        case .buildVocabulary:    return "Home.NextStep.Vocabulary.Body"
        case .learnKanji:         return "Home.NextStep.Kanji.Body"
        case .studyGrammar:       return "Home.NextStep.Grammar.Body"
        case .readingListening:   return "Home.NextStep.Reading.Body"
        case .converseWithSakura: return "Home.NextStep.Sakura.Body"
        }
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
            modelContainer: container,
            contentRepository: Self.makeContentRepository()
        )
    }

    /// Resolves the bundled `n5-content.sqlite` and builds a read-only
    /// `ContentRepository` for the session (blueprint 4.1 Step 0 — the app has
    /// never stood one up before). Fail-safe: a missing resource logs and
    /// returns nil so the session still starts; the audio drills just get an
    /// empty vocabulary pool rather than crashing.
    private static func makeContentRepository() -> ContentRepository? {
        BundledContent.makeRepository()
    }

    private func startSession() {
        guard let svm = sessionViewModel else { return }
        reviewsBeforeSession = viewModel?.totalReviewsCompleted ?? 0
        Task {
            // Beginner content is seeded in HomeViewModel.loadData() before the
            // preview is composed, so cards already exist by the time this CTA
            // is reachable. Only present the session if one actually started —
            // an empty plan must never show a hollow "0 cards / 0% recall" summary.
            let started = await svm.startSession()
            showSession = started
        }
    }

    // MARK: - First-session daily-term prompt

    /// Fires once, right after the learner's first-ever completed session
    /// (lifetime review count crossing 0 → >0). Never re-prompts once shown
    /// (accepted or declined — the flag is set unconditionally before the
    /// alert is shown), and never prompts if the feature is already on.
    ///
    /// Scoping note (deliberate asymmetry): the seen-flag is per-profile
    /// (`OnboardingFlags`), while the daily-term toggle itself is app-level
    /// (`@AppStorage`) — the daily term is a device-level habit shared across
    /// profiles, so enabling it once answers the question for everyone.
    // MARK: - Caught-up explainer (Sakura, one-time)

    /// Shows Sakura's explainer the FIRST time Home lands on the quiet
    /// "all caught up" state: every chosen kana begun, nothing due right now.
    /// Without it, a fresh learner who just powered through their study set
    /// faces a silent dead-end — no hint that spaced repetition will bring
    /// the kana back, or that more rows await in Explore → Kana.
    private func evaluateCaughtUpExplainer() {
        guard let vm = viewModel,
              vm.todayKind == .empty,
              !vm.restDayActive,
              !vm.needsStudySetChoice,
              // A THRESHOLD ("has this learner ever reviewed anything"), so it
              // reads the `ReviewLog`-derived count, not `RPGState`. GAP-13's
              // residual: on the RPG counter this was wrong for exactly the
              // learner this explainer exists for — kana-drill-only work
              // journals ReviewLog rows without ever touching RPGState, so
              // they stayed at 0 forever and never saw it.
              // `evaluateFirstSessionDailyTermPrompt` below deliberately does
              // NOT switch: it keys on a 0 → >0 TRANSITION, where the derived
              // count would already be >0 and the prompt would never fire.
              vm.derivedReviewCount > 0,
              !showFirstSessionDailyTermPrompt,   // never stack on the daily-term alert
              let profileID = ActiveProfileResolver.activeProfileID(),
              !OnboardingFlags.hasSeenCaughtUpExplainer(profileID: profileID)
        else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            showCaughtUpExplainer = true
        }
    }

    private func dismissCaughtUpExplainer() {
        if let profileID = ActiveProfileResolver.activeProfileID() {
            OnboardingFlags.markCaughtUpExplainerSeen(profileID: profileID)
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            showCaughtUpExplainer = false
        }
    }

    /// Dim scrim + Sakura callout card — same visual language as the feature
    /// tour's bubble (SakuraMark header, material card, gold hairline).
    private var caughtUpExplainerOverlay: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissCaughtUpExplainer() }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    SakuraMark(size: 30)
                    Text(verbatim: "Sakura")
                        .ikeruScaledFont(12, weight: .bold, relativeTo: .caption2)
                        .tracking(1.5)
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                    Spacer()
                }

                Text("Sakura.CaughtUp.Title")
                    .ikeruScaledFont(20, weight: .semibold, relativeTo: .title3)
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Sakura.CaughtUp.Message")
                    .ikeruScaledFont(15, relativeTo: .body)
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    dismissCaughtUpExplainer()
                } label: {
                    Text("Sakura.CaughtUp.Dismiss")
                        .frame(maxWidth: .infinity)
                }
                .ikeruButtonStyle(.primary)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.ikeruPrimaryAccent.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 24, y: 8)
            .padding(.horizontal, 28)
        }
    }

    private func evaluateFirstSessionDailyTermPrompt() {
        guard reviewsBeforeSession == 0,
              let vm = viewModel,
              vm.totalReviewsCompleted > 0,
              !dailyTermEnabled,
              let profileID = ActiveProfileResolver.activeProfileID(),
              !OnboardingFlags.hasSeenFirstSessionDailyTermPrompt(profileID: profileID)
        else { return }

        OnboardingFlags.markFirstSessionDailyTermPromptSeen(profileID: profileID)
        showFirstSessionDailyTermPrompt = true
    }

    /// Enables the daily-term feature equivalently to Settings: request
    /// notification authorization, schedule the reminder at the default time
    /// on success, then flip the on/off flag. (Settings flips its bound
    /// toggle optimistically FIRST and reverts on denial; here the flag flips
    /// last — same end state on every path, slightly different ordering, so
    /// any observer of the transient `true` behaves the same either way.)
    /// Declining the system permission leaves the feature off, matching
    /// Settings' behavior.
    private func enableDailyTermFromPrompt() {
        Task {
            let authorized = await NotificationManager.shared.requestAuthorization()
            guard authorized else { return }
            await NotificationManager.shared.scheduleDailyTermReminder(
                hour: DailyTermSettings.defaultHour,
                minute: DailyTermSettings.defaultMinute
            )
            dailyTermEnabled = true
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
    /// Localizable: each English meaning is also a catalogue key, so the line
    /// renders in FR via `Localizable.xcstrings` (the proverb itself stays JP).
    let translation: LocalizedStringKey

    // Computed (not a stored static) so it isn't a non-Sendable shared global —
    // LocalizedStringKey isn't Sendable, which a `static let` array would flag.
    static var pool: [HomeProverb] { [
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
    ] }

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
