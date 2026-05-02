import SwiftUI
import SwiftData
import IkeruCore

// MARK: - RPGProfileView

/// RPG tab root view showing the learner's progression profile:
/// level, XP bar, unlocked attributes, and loot inventory.
struct RPGProfileView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: RPGProfileViewModel?
    @State private var selectedLootBox: LootBox?

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            if let vm = viewModel, vm.hasLoaded {
                ScrollView {
                    VStack(spacing: IkeruTheme.Spacing.xl) {
                        topBar(vm)
                        heroSection(vm)
                        achievementsSection(vm)
                        nextRankSection(vm)
                        lootBoxSection(vm)
                        attributesSection(vm)
                        inventorySection(vm)

                        Spacer(minLength: 200)
                    }
                    .padding(.horizontal, IkeruTheme.Spacing.md)
                    .padding(.top, IkeruTheme.Spacing.lg)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $selectedLootBox) { box in
            LootBoxOpenView(lootBox: box) {
                selectedLootBox = nil
                Task { await viewModel?.loadData() }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = RPGProfileViewModel(modelContainer: modelContext.container)
            }
            await viewModel?.loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ikeruActiveProfileDidChange)) { _ in
            Task { await viewModel?.loadData() }
        }
    }

    // MARK: - Top Bar

    @ViewBuilder
    private func topBar(_ vm: RPGProfileViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("YOUR JOURNEY")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
            Text("RPG Profile")
                .font(.ikeruDisplaySmall)
                .ikeruTracking(.display)
                .foregroundStyle(Color.ikeruTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Hero Section
    //
    // Tatami direction: hero rank crest is now the torii frame (`RPGRankCrest`)
    // wrapping the rank kanji. Use only at sizes ≥ 80; smaller rank glyphs
    // (e.g. inside Home pills) keep `EnsoRankView`.

    @ViewBuilder
    private func heroSection(_ vm: RPGProfileViewModel) -> some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            rankCrest(vm)

            // Equipped cosmetics belong in the hero room — keep them under
            // the torii so the user sees what they're wearing alongside rank.
            if vm.equippedTitle != nil || !vm.equippedBadges.isEmpty {
                equippedRow(vm)
            }

            XPBarView(totalXP: vm.xp, level: vm.level, variant: .full)

            HStack(spacing: IkeruTheme.Spacing.sm) {
                tatamiStatChip(
                    glyph: "\u{53C8}",            // 又  — repetitions
                    value: vm.totalReviews,
                    label: "Reviews",
                    tint: Color.ikeruPrimaryAccent
                )
                tatamiStatChip(
                    glyph: "\u{8CA1}",            // 財  — treasures / inventory
                    value: vm.inventory.count,
                    label: "Items",
                    tint: Color.ikeruSecondaryAccent
                )
                tatamiStatChip(
                    glyph: "\u{529B}",            // 力  — power / attribute
                    value: vm.unlockedAttributes.count,
                    label: "Attributes",
                    tint: Color.ikeruTertiaryAccent
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Tatami-direction stat chip: serif kanji glyph + serif numeral +
    /// caps EN/FR label, framed by sumi corners. Replaces `IkeruStatPill`
    /// (which was glass-tinted) for the Profile header row.
    private func tatamiStatChip(
        glyph: String,
        value: Int,
        label: LocalizedStringKey,
        tint: Color
    ) -> some View {
        HStack(spacing: 8) {
            Text(glyph)
                .font(.system(size: 16, weight: .light, design: .serif))
                .foregroundStyle(tint)
            SerifNumeral(value, size: 16, color: Color.ikeruTextPrimary)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(TatamiTokens.paperGhost)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08))
        .sumiCorners(color: tint, size: 6, weight: 1.0, inset: -1)
    }

    // MARK: - Rank Crest (Torii)

    @ViewBuilder
    private func rankCrest(_ vm: RPGProfileViewModel) -> some View {
        let progress = vm.progressInLevel
        HStack(alignment: .center, spacing: 22) {
            RPGRankCrest(level: vm.level, size: 96)
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 4) {
                Text("第\(rankKanji(vm.level))段")
                    .font(.system(size: 22, weight: .light, design: .serif))
                    .foregroundStyle(Color.ikeruTextPrimary)
                Text(rankTitle(level: vm.level).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                    .tracking(2)
                HStack(spacing: 0) {
                    SerifNumeral(progress.current, size: 12, color: TatamiTokens.paperGhost)
                    Text(" / ")
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(TatamiTokens.paperGhost)
                    SerifNumeral(progress.required, size: 12, color: TatamiTokens.paperGhost)
                    Text(" XP")
                        .font(.system(size: 12))
                        .foregroundStyle(TatamiTokens.paperGhost)
                }
                .padding(.top, 6)
                ZStack(alignment: .leading) {
                    Rectangle().fill(TatamiTokens.goldDim.opacity(0.2)).frame(height: 1)
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.ikeruPrimaryAccent)
                            .frame(width: geo.size.width * vm.progressFraction, height: 1)
                    }
                    .frame(height: 1)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .tatamiRoom(.glass, padding: 22)
    }

    @ViewBuilder
    private func equippedRow(_ vm: RPGProfileViewModel) -> some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            if let title = vm.equippedTitle {
                Text(title.name.uppercased())
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(rarityColor(title.rarity))
            }
            if !vm.equippedBadges.isEmpty {
                badgeCluster(vm.equippedBadges)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Achievements Section
    //
    // The view-model does not surface achievements yet, so this renders a
    // static demo row with the 5 kanji from the Tatami plan
    // (初, 七, 百, 千, 極). When `RPGProfileViewModel` gains an
    // `achievements: [Achievement]` collection (.id, .kanji, .label, .earned),
    // wire it up here. Mirrors the streak placeholder pattern from T4.

    @ViewBuilder
    private func achievementsSection(_ vm: RPGProfileViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            BilingualLabel(japanese: "勲章", chrome: "Achievements", mon: .asanoha)
            HStack(alignment: .top, spacing: 14) {
                ForEach(demoAchievements(for: vm), id: \.id) { ach in
                    achievementCell(ach)
                }
            }
        }
        .tatamiRoom(.standard, padding: 16)
    }

    @ViewBuilder
    private func achievementCell(_ ach: DemoAchievement) -> some View {
        VStack(spacing: 6) {
            if ach.earned {
                HankoStamp(kanji: ach.kanji, size: 42)
            } else {
                Text(ach.kanji)
                    .font(.system(size: 22, weight: .light, design: .serif))
                    .foregroundStyle(TatamiTokens.paperGhost)
                    .frame(width: 42, height: 42)
                    .overlay(
                        Rectangle()
                            .strokeBorder(
                                TatamiTokens.paperGhost,
                                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                            )
                    )
                    .opacity(0.55)
            }
            Text(ach.label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(TatamiTokens.paperGhost)
                .tracking(1)
                .frame(maxWidth: 56)
                .multilineTextAlignment(.center)
        }
    }

    /// Lightweight value type used by the static demo row above. Once the
    /// view-model exposes real achievements, replace this with the model
    /// type and delete `demoAchievements(for:)`.
    private struct DemoAchievement: Identifiable {
        let id: String
        let kanji: String
        let label: String
        let earned: Bool
    }

    private func demoAchievements(for vm: RPGProfileViewModel) -> [DemoAchievement] {
        // Earn thresholds are quietly tied to the few signals the view-model
        // does surface (level, total reviews) so the row at least responds
        // to actual progress while we wait for real wiring.
        [
            DemoAchievement(id: "first",   kanji: "初", label: "First step",  earned: vm.totalReviews > 0),
            DemoAchievement(id: "seven",   kanji: "七", label: "7-day arc",   earned: vm.level >= 2),
            DemoAchievement(id: "hundred", kanji: "百", label: "100 cards",   earned: vm.totalReviews >= 100),
            DemoAchievement(id: "thousand",kanji: "千", label: "1000 cards",  earned: vm.totalReviews >= 1000),
            DemoAchievement(id: "kiwami",  kanji: "極", label: "Mastery",     earned: vm.level >= 10)
        ]
    }

    // MARK: - Next Rank Section

    @ViewBuilder
    private func nextRankSection(_ vm: RPGProfileViewModel) -> some View {
        let progress = vm.progressInLevel
        let xpToNext = max(0, progress.required - progress.current)
        VStack(alignment: .leading, spacing: 10) {
            BilingualLabel(japanese: "次の段", chrome: "Next rank", mon: .genji)
            HStack(spacing: 16) {
                RPGRankCrest(level: vm.level + 1, size: 56, dashed: true)
                    .frame(width: 56, height: 56)
                    .opacity(0.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text("第\(rankKanji(vm.level + 1))段 · \(rankTitle(level: vm.level + 1))")
                        .font(.system(size: 16, design: .serif))
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Text("\(xpToNext) XP to advance",
                         comment: "RPG next rank caption — format string `%lld XP to advance`")
                        .font(.system(size: 11))
                        .foregroundStyle(TatamiTokens.paperGhost)
                }
                Spacer(minLength: 0)
                SerifNumeral("\(xpToNext) XP →", size: 11, color: .ikeruPrimaryAccent)
            }
        }
        .tatamiRoom(.standard, padding: 16)
    }

    // MARK: - Rank kanji helper

    /// Daiji-style numerals for the dan rank label. Falls back to the ASCII
    /// numeral past the prepared range — same convention as `RPGRankCrest`.
    private func rankKanji(_ n: Int) -> String {
        let lookup = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        return lookup.indices.contains(n) ? lookup[n] : "\(n)"
    }

    // MARK: - Loot Box Section

    @ViewBuilder
    private func lootBoxSection(_ vm: RPGProfileViewModel) -> some View {
        if !vm.unopenedLootBoxes.isEmpty {
            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
                IkeruSectionHeader(title: "Lootboxes", eyebrow: "Awaiting")

                VStack(spacing: 0) {
                    ForEach(Array(vm.unopenedLootBoxes.enumerated()), id: \.element.id) { index, box in
                        Button {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                selectedLootBox = box
                            }
                        } label: {
                            HStack(spacing: IkeruTheme.Spacing.md) {
                                Image(systemName: "shippingbox.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(Color(hex: IkeruTheme.Colors.Rarity.epic))
                                    .frame(width: 36)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(box.challengeType.displayName)
                                        .font(.ikeruBody)
                                        .foregroundStyle(Color.ikeruTextPrimary)

                                    Text("Score \(box.requiredScore) to open")
                                        .font(.ikeruCaption)
                                        .foregroundStyle(Color.ikeruTextSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.ikeruTextTertiary)
                            }
                            .padding(.vertical, IkeruTheme.Spacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < vm.unopenedLootBoxes.count - 1 {
                            IkeruDivider()
                        }
                    }
                }
            }
            .ikeruCard(.elevated)
        }
    }

    // MARK: - Attributes Section

    @ViewBuilder
    private func attributesSection(_ vm: RPGProfileViewModel) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            BilingualLabel(japanese: "\u{529B}", chrome: "Attributes", mon: .kikkou)

            VStack(spacing: 0) {
                let unlocked = vm.unlockedAttributes
                let locked = vm.lockedAttributes
                let all: [(RPGAttribute, Bool)] =
                    unlocked.map { ($0, false) } + locked.map { ($0, true) }

                ForEach(Array(all.enumerated()), id: \.element.0.id) { index, pair in
                    attributeRow(pair.0, isLocked: pair.1)
                    if index < all.count - 1 {
                        Rectangle()
                            .fill(TatamiTokens.goldDim.opacity(0.18))
                            .frame(height: 1)
                    }
                }
            }
        }
        .tatamiRoom(.standard, padding: IkeruTheme.Spacing.md)
    }

    private func attributeRow(_ attr: RPGAttribute, isLocked: Bool) -> some View {
        HStack(spacing: IkeruTheme.Spacing.md) {
            ZStack {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.ikeruTextTertiary)
                } else {
                    Text(Self.attributeKanji(attr.id))
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                }
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(isLocked ? "???" : attr.name)
                    .font(.ikeruBody)
                    .foregroundStyle(isLocked ? Color.ikeruTextTertiary : Color.ikeruTextPrimary)

                if isLocked {
                    Text("Unlocks at Lv. \(attr.unlockLevel)")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextTertiary)
                } else {
                    Text(attr.description)
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
            }

            Spacer()

            if !isLocked {
                attributeValueBar(value: attr.value)
            }
        }
        .padding(.vertical, IkeruTheme.Spacing.sm)
        .opacity(isLocked ? 0.55 : 1.0)
    }

    private func attributeValueBar(value: Int) -> some View {
        HStack(spacing: IkeruTheme.Spacing.xs) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 60, height: 6)
                Capsule()
                    .fill(LinearGradient.ikeruGold)
                    .frame(width: 60 * (Double(value) / 100.0), height: 6)
            }

            Text("\(value)")
                .font(.ikeruStats)
                .foregroundStyle(Color.ikeruTextSecondary)
                .frame(width: 28, alignment: .trailing)
        }
    }

    // MARK: - Inventory Section

    @ViewBuilder
    private func inventorySection(_ vm: RPGProfileViewModel) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            BilingualLabel(japanese: "\u{8CA1}", chrome: "Inventory", mon: .maru)

            if vm.inventory.isEmpty {
                Text("Complete sessions to earn loot.")
                    .font(.ikeruBody)
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, IkeruTheme.Spacing.lg)
            } else {
                VStack(alignment: .leading, spacing: IkeruTheme.Spacing.lg) {
                    ForEach(vm.inventoryByRarity, id: \.rarity) { group in
                        rarityGroupSection(rarity: group.rarity, items: group.items)
                    }
                }
            }
        }
        .tatamiRoom(.standard, padding: IkeruTheme.Spacing.md)
    }

    private func rarityGroupSection(rarity: LootRarity, items: [LootItem]) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            Text(rarity.displayName.uppercased())
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(rarityColor(rarity))

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 76), spacing: IkeruTheme.Spacing.sm)],
                spacing: IkeruTheme.Spacing.sm
            ) {
                ForEach(items) { item in
                    inventoryItemCell(item)
                }
            }
        }
    }

    private func inventoryItemCell(_ item: LootItem) -> some View {
        let isEquipped = viewModel?.isEquipped(item) ?? false
        let equippable = EquipmentService.isEquippable(item)

        return Button {
            guard equippable, let vm = viewModel else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                vm.toggleEquip(item)
            }
        } label: {
            VStack(spacing: IkeruTheme.Spacing.xs) {
                Image(systemName: item.iconName)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(rarityColor(item.rarity))

                Text(item.name)
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 76, height: 80)
            .padding(IkeruTheme.Spacing.xs)
            .background(
                rarityColor(item.rarity)
                    .opacity(isEquipped ? 0.18 : 0.08)
            )
            .sumiCorners(
                color: rarityColor(item.rarity),
                size: 8,
                weight: isEquipped ? 1.4 : 1.0,
                inset: -1
            )
            .overlay(alignment: .topTrailing) {
                if isEquipped {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(rarityColor(item.rarity))
                        .padding(6)
                }
            }
            .overlay {
                if isEquipped {
                    RoundedRectangle(cornerRadius: IkeruTheme.Radius.md, style: .continuous)
                        .strokeBorder(rarityColor(item.rarity).opacity(0.7), lineWidth: 1.2)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!equippable)
        .opacity(equippable ? 1.0 : 0.75)
    }

    // MARK: - Badge Cluster

    @ViewBuilder
    private func badgeCluster(_ badges: [LootItem]) -> some View {
        HStack(spacing: 6) {
            ForEach(badges) { badge in
                Image(systemName: badge.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(rarityColor(badge.rarity))
                    .frame(width: 22, height: 22)
                    .background {
                        Circle().fill(rarityColor(badge.rarity).opacity(0.14))
                    }
                    .overlay {
                        Circle().strokeBorder(rarityColor(badge.rarity).opacity(0.35), lineWidth: 0.8)
                    }
            }
        }
    }

    // MARK: - Rank title helper (mirrors HomeView)

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

    // MARK: - Attribute kanji mapping
    //
    // Traditional Japanese single-character labels for each skill attribute —
    // Reading → 読, Writing → 書, Listening → 聞, Speaking → 話. A brushable
    // kanji glyph is far more on-brand than an SF Symbol.

    private static func attributeKanji(_ id: String) -> String {
        switch id {
        case "reading":    return "読"
        case "writing":    return "書"
        case "listening":  return "聞"
        case "speaking":   return "話"
        case "grammar":    return "文"
        case "vocabulary": return "語"
        case "culture":    return "和"
        case "intuition":  return "悟"
        default:           return "字"
        }
    }

    // MARK: - Helpers

    private func rarityColor(_ rarity: LootRarity) -> Color {
        switch rarity {
        case .common: Color(hex: IkeruTheme.Colors.Rarity.common)
        case .rare: Color(hex: IkeruTheme.Colors.Rarity.rare)
        case .epic: Color(hex: IkeruTheme.Colors.Rarity.epic)
        case .legendary: Color(hex: IkeruTheme.Colors.Rarity.legendary)
        }
    }
}

// MARK: - Preview

#Preview("RPGProfileView") {
    NavigationStack {
        RPGProfileView()
    }
    .preferredColorScheme(.dark)
}
