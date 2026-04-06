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

    @ViewBuilder
    private func heroSection(_ vm: RPGProfileViewModel) -> some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LEVEL")
                        .font(.ikeruMicro)
                        .ikeruTracking(.micro)
                        .foregroundStyle(Color.ikeruTextTertiary)
                    Text("\(vm.level)")
                        .font(.ikeruDisplayLarge)
                        .ikeruTracking(.display)
                        .foregroundStyle(Color.ikeruTextPrimary)
                }
                Spacer()
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(LinearGradient.ikeruGold)
            }

            XPBarView(totalXP: vm.xp, level: vm.level, variant: .full)

            HStack(spacing: IkeruTheme.Spacing.sm) {
                IkeruStatPill(
                    icon: "rectangle.stack",
                    value: "\(vm.totalReviews)",
                    label: "reviews"
                )
                IkeruStatPill(
                    icon: "bag",
                    value: "\(vm.inventory.count)",
                    label: "items",
                    tint: Color.ikeruSecondaryAccent
                )
                IkeruStatPill(
                    icon: "sparkles",
                    value: "\(vm.unlockedAttributes.count)",
                    label: "attrs",
                    tint: Color.ikeruTertiaryAccent
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .ikeruCard(.hero)
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
            IkeruSectionHeader(title: "Attributes", eyebrow: "Skill profile")

            VStack(spacing: 0) {
                let unlocked = vm.unlockedAttributes
                let locked = vm.lockedAttributes
                let all: [(RPGAttribute, Bool)] =
                    unlocked.map { ($0, false) } + locked.map { ($0, true) }

                ForEach(Array(all.enumerated()), id: \.element.0.id) { index, pair in
                    attributeRow(pair.0, isLocked: pair.1)
                    if index < all.count - 1 {
                        IkeruDivider()
                    }
                }
            }
        }
        .ikeruCard(.standard)
    }

    private func attributeRow(_ attr: RPGAttribute, isLocked: Bool) -> some View {
        HStack(spacing: IkeruTheme.Spacing.md) {
            Image(systemName: isLocked ? "lock.fill" : attr.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isLocked ? Color.ikeruTextTertiary : Color.ikeruPrimaryAccent)
                .frame(width: 28)

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
            IkeruSectionHeader(title: "Inventory", eyebrow: "Treasures")

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
        .ikeruCard(.standard)
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
        .ikeruGlass(
            cornerRadius: IkeruTheme.Radius.md,
            tint: rarityColor(item.rarity),
            tintOpacity: 0.10
        )
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
