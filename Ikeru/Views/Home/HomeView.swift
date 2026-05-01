import SwiftUI
import SwiftData
import IkeruCore
import os

// MARK: - HomeView
//
// Wabi-sabi refined home. The hero card is proverb-centric (七転八起 promoted
// to the focal element), rank sits as chrome (EnsoRank brush glyph + 第N段),
// progression reads as carved segments not a gradient smear, and the stats
// row weights "Due Now" as the action card over the two quieter metrics.

struct HomeView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: HomeViewModel?
    @State private var sessionViewModel: SessionViewModel?
    @State private var showSession = false
    @State private var heroAppeared = false
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
        .task {
            initializeViewModels()
            await viewModel?.loadData()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86).delay(0.05)) {
                heroAppeared = true
            }
            if CommandLine.arguments.contains("-autoStartSession") {
                startSession()
            }
        }
        .onAppear {
            if viewModel != nil {
                Task { await viewModel?.loadData() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startQuizFromShortcut)) { _ in
            initializeViewModels()
            startSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: .startReviewFromShortcut)) { _ in
            initializeViewModels()
            startSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ikeruActiveProfileDidChange)) { _ in
            Task { await viewModel?.loadData() }
        }
    }

    // MARK: - Home Content

    @ViewBuilder
    private func homeContent(_ vm: HomeViewModel) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: IkeruTheme.Spacing.lg) {
                topBar(vm)
                proverbHero(vm)
                statsRow(vm)
                skillRadarCard(vm)
                primaryAction(vm)
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
            Capsule().fill(.ultraThinMaterial)
        }
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
        )
    }

    // MARK: - Top Bar

    @ViewBuilder
    private func topBar(_ vm: HomeViewModel) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(timeOfDayGreeting().uppercased())
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(Color.ikeruTextTertiary)

                Text(vm.displayName.isEmpty ? "Welcome" : vm.displayName)
                    .font(.ikeruDisplaySmall)
                    .ikeruTracking(.display)
                    .foregroundStyle(Color.ikeruTextPrimary)

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
        .padding(.top, IkeruTheme.Spacing.xs)
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
            Capsule()
                .fill(Color.white.opacity(0.05))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6))
        }
    }

    // MARK: - Proverb Hero

    @ViewBuilder
    private func proverbHero(_ vm: HomeViewModel) -> some View {
        let proverb = HomeProverb.dailyProverb(level: vm.level)
        let progress = Double(vm.xpInCurrentLevel) / Double(max(1, vm.xpRequiredForLevel))

        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.lg) {
            // Rank row — brush circle + 第N段 · APPRENTICE. Chrome, not focus.
            HStack(spacing: 10) {
                EnsoRankView(level: vm.level, size: 30)
                Text(rankLabel(level: vm.level))
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                    .tracking(1.8)
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ikeruTextTertiary)
                Text(rankTitle(level: vm.level).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .tracking(2.2)
                Spacer()
            }

            // Proverb — now owns the card.
            VStack(alignment: .leading, spacing: 10) {
                Text(proverb.kanji)
                    .font(.system(size: 40, weight: .light, design: .serif))
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .tracking(4)

                Text(proverb.romaji)
                    .font(.system(size: 12))
                    .italic()
                    .foregroundStyle(Color.ikeruTextTertiary)

                Text(proverb.translation)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .lineLimit(2)
            }

            // Experience — segmented ticks.
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("EXPERIENCE")
                        .font(.ikeruMicro)
                        .ikeruTracking(.micro)
                        .foregroundStyle(Color.ikeruTextTertiary)
                    Spacer()
                    HStack(spacing: 0) {
                        Text("\(vm.xpInCurrentLevel)")
                            .foregroundStyle(Color.ikeruPrimaryAccent)
                        Text(" / \(vm.xpRequiredForLevel)")
                            .foregroundStyle(Color.ikeruTextTertiary)
                    }
                    .font(.system(size: 12, design: .monospaced))
                }

                SegmentedXPBarView(progress: progress)

                Text("\(vm.xpToNextLevel) XP to next rank")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ikeruTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(IkeruTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Mesh-gradient substrate (per ux-design-spec) topped with the
            // wabi-sabi glass overlay. The mesh adds slow, calm motion that
            // shifts palette as the player ranks up; the glass tames its
            // brightness so the proverb stays the focal element.
            ZStack {
                MeshHeroBackground(level: vm.level, cornerRadius: IkeruTheme.Radius.lg)
                IkeruGlassSurface(
                    cornerRadius: IkeruTheme.Radius.lg,
                    tint: Color.ikeruPrimaryAccent,
                    tintOpacity: 0.04,
                    highlight: 0.10,
                    strokeOpacity: 0.14
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg, style: .continuous))
        .shadow(color: Color.black.opacity(0.45), radius: 24, y: 10)
    }

    // MARK: - Skill radar card

    @ViewBuilder
    private func skillRadarCard(_ vm: HomeViewModel) -> some View {
        HStack(alignment: .center, spacing: IkeruTheme.Spacing.md) {
            SkillRadarView(skillBalance: vm.skillBalance, variant: .mini)
                .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: 8) {
                Text("BALANCE")
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(Color.ikeruTextTertiary)

                Text("Your four winds")
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ikeruTextPrimary)

                skillRow("Reading", value: vm.skillBalance.reading)
                skillRow("Listening", value: vm.skillBalance.listening)
                skillRow("Writing", value: vm.skillBalance.writing)
                skillRow("Speaking", value: vm.skillBalance.speaking)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(IkeruTheme.Spacing.md)
        .background {
            IkeruGlassSurface(
                cornerRadius: IkeruTheme.Radius.lg,
                tint: .clear,
                tintOpacity: 0.0,
                highlight: 0.10,
                strokeOpacity: 0.10
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg, style: .continuous))
    }

    @ViewBuilder
    private func skillRow(_ label: String, value: Double) -> some View {
        HStack(spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.ikeruTextSecondary)
                .frame(width: 72, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06)).frame(height: 3)
                Capsule()
                    .fill(Color.ikeruPrimaryAccent.opacity(0.85))
                    .frame(width: max(2, CGFloat(min(1, max(0, value))) * 80), height: 3)
            }
            .frame(width: 80)
            Text("\(Int(min(1, max(0, value)) * 100))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.ikeruTextTertiary)
        }
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
                    label: "New",
                    count: vm.sessionPreviewNewCount,
                    tint: .ikeruSecondaryAccent
                )
                Divider()
                    .frame(width: 0.6, height: 28)
                    .overlay(Color.white.opacity(0.10))
                breakdownCell(
                    icon: "arrow.triangle.2.circlepath",
                    label: "Review",
                    count: vm.sessionPreviewReviewCount,
                    tint: .ikeruPrimaryAccent
                )
                Divider()
                    .frame(width: 0.6, height: 28)
                    .overlay(Color.white.opacity(0.10))
                breakdownCell(
                    icon: "timer",
                    label: "Approx",
                    valueText: "\(max(1, vm.sessionPreviewMinutes))m",
                    tint: .ikeruTertiaryAccent
                )
            }
            .padding(.vertical, 10)
            .padding(.horizontal, IkeruTheme.Spacing.sm)
            .background {
                IkeruGlassSurface(
                    cornerRadius: IkeruTheme.Radius.md,
                    tint: .clear,
                    tintOpacity: 0.0,
                    highlight: 0.08,
                    strokeOpacity: 0.08
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.md, style: .continuous))
        }
    }

    @ViewBuilder
    private func breakdownCell(
        icon: String,
        label: String,
        count: Int? = nil,
        valueText: String? = nil,
        tint: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(Color.ikeruTextTertiary)
                Text(valueText ?? "\(count ?? 0)")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.ikeruTextPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    // MARK: - Stats Row
    //
    // Due Now is the action — weighted 1.4× and tinted gold with a live dot
    // when work is waiting. Learned + Lootboxes sit quieter in single-fr cells.

    @ViewBuilder
    private func statsRow(_ vm: HomeViewModel) -> some View {
        HStack(alignment: .top, spacing: IkeruTheme.Spacing.sm) {
            primaryStatCard(
                icon: "tray.full",
                value: "\(vm.dueCardCount)",
                label: "Due Now",
                caption: vm.dueCardCount > 0 ? "Ready for review" : "Nothing due",
                showsLivePulse: vm.dueCardCount > 0
            )
            .frame(maxWidth: .infinity)
            .layoutPriority(1.4)

            statCard(
                icon: "character.book.closed",
                value: "\(vm.kanjiLearnedCount)",
                label: "Learned",
                caption: "items",
                tint: .ikeruTertiaryAccent
            )
            .frame(maxWidth: .infinity)

            statCard(
                icon: "shippingbox",
                value: "\(vm.unopenedLootBoxCount)",
                label: "Loot",
                caption: vm.unopenedLootBoxCount > 0 ? "unopened" : "earn some",
                tint: vm.unopenedLootBoxCount > 0 ? .ikeruPrimaryAccent : .ikeruSecondaryAccent
            )
            .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 108)
    }

    @ViewBuilder
    private func primaryStatCard(
        icon: String,
        value: String,
        label: String,
        caption: String,
        showsLivePulse: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.ikeruPrimaryAccent.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                }
                Spacer()
                if showsLivePulse {
                    Circle()
                        .fill(Color.ikeruPrimaryAccent)
                        .frame(width: 6, height: 6)
                        .shadow(color: Color.ikeruPrimaryAccent.opacity(0.8), radius: 4)
                }
            }

            Text(value)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.ikeruTextPrimary)
                .tracking(-1)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: value)

            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(Color.ikeruPrimaryAccent.opacity(0.9))
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ikeruTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(IkeruTheme.Spacing.md)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg, style: .continuous)
                    .fill(Color.ikeruPrimaryAccent.opacity(0.06))
                RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg, style: .continuous)
                    .strokeBorder(Color.ikeruPrimaryAccent.opacity(0.22), lineWidth: 1)

                // Corner warmth — gold radial pooling in the top-right.
                RadialGradient(
                    colors: [
                        Color.ikeruPrimaryAccent.opacity(0.22),
                        Color.ikeruPrimaryAccent.opacity(0)
                    ],
                    center: .init(x: 0.9, y: 0.1),
                    startRadius: 0,
                    endRadius: 90
                )
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg, style: .continuous))
        }
        .shadow(color: Color.black.opacity(0.3), radius: 16, y: 8)
    }

    @ViewBuilder
    private func statCard(
        icon: String,
        value: String,
        label: String,
        caption: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }

            Text(value)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.ikeruTextPrimary)
                .tracking(-0.5)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: value)

            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(Color.ikeruTextTertiary)
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ikeruTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(IkeruTheme.Spacing.md)
        .background {
            IkeruGlassSurface(
                cornerRadius: IkeruTheme.Radius.lg,
                tint: .clear,
                tintOpacity: 0.0,
                highlight: 0.10,
                strokeOpacity: 0.10
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg, style: .continuous))
        .shadow(color: Color.black.opacity(0.25), radius: 12, y: 6)
    }

    // MARK: - Primary action

    @ViewBuilder
    private func primaryAction(_ vm: HomeViewModel) -> some View {
        Button {
            startSession()
        } label: {
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Begin Session")
                        .font(.system(size: 17, weight: .semibold))
                }
                Spacer()
                Text(sessionDurationEstimate(vm))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(red: 0.16, green: 0.11, blue: 0.05).opacity(0.7))
            }
            .frame(maxWidth: .infinity)
        }
        .ikeruButtonStyle(.primary)
        .padding(.top, IkeruTheme.Spacing.xs)
    }

    private func sessionDurationEstimate(_ vm: HomeViewModel) -> String {
        if vm.sessionPreviewCardCount > 0 {
            return "~\(max(1, vm.sessionPreviewMinutes)) min"
        }
        return "ready"
    }

    // MARK: - Rank labels

    private func rankLabel(level: Int) -> String {
        "第\(level)段"
    }

    private func rankTitle(level: Int) -> String {
        switch level {
        case ..<3:  return "Novice"
        case 3..<7: return "Apprentice"
        case 7..<15: return "Student"
        case 15..<25: return "Adept"
        case 25..<40: return "Master"
        default: return "Sage"
        }
    }

    // MARK: - Helpers

    private func timeOfDayGreeting() -> String {
        if let override = AppEnvironment.greetingOverride {
            return override.phrase
        }
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Good night"
        }
    }

    private func initializeViewModels() {
        guard viewModel == nil else { return }
        let container = modelContext.container

        viewModel = HomeViewModel(modelContainer: container)

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
