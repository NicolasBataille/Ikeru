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
            Color.ikeruBackground
                .ignoresSafeArea()

            if let vm = viewModel, vm.hasLoaded {
                ScrollView {
                    VStack(spacing: IkeruTheme.Spacing.lg) {
                        heroSection(vm)
                        lootBoxSection(vm)
                        attributesSection(vm)
                        inventorySection(vm)
                    }
                    .padding(.horizontal, IkeruTheme.Spacing.md)
                    .padding(.top, IkeruTheme.Spacing.xl)
                    .padding(.bottom, IkeruTheme.Spacing.xxl)
                }
            }
        }
        .navigationTitle("RPG Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
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

    // MARK: - Hero Section

    @ViewBuilder
    private func heroSection(_ vm: RPGProfileViewModel) -> some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            // Level badge
            Image(systemName: "shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color(hex: IkeruTheme.Colors.Rarity.legendary))

            Text("Level \(vm.level)")
                .font(.system(size: IkeruTheme.Typography.Size.heading1, weight: .bold))
                .foregroundStyle(.white)

            // XP Bar
            XPBarView(totalXP: vm.xp, level: vm.level, variant: .full)
                .padding(.horizontal, IkeruTheme.Spacing.sm)

            // Stats row
            HStack(spacing: IkeruTheme.Spacing.xl) {
                statBadge(label: "Reviews", value: "\(vm.totalReviews)")
                statBadge(label: "Items", value: "\(vm.inventory.count)")
                statBadge(label: "Attributes", value: "\(vm.unlockedAttributes.count)")
            }
        }
        .frame(maxWidth: .infinity)
        .ikeruCard(.elevated)
    }

    private func statBadge(label: String, value: String) -> some View {
        VStack(spacing: IkeruTheme.Spacing.xs) {
            Text(value)
                .font(.ikeruHeading3)
                .foregroundStyle(Color.ikeruPrimaryAccent)
            Text(label)
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)
        }
    }

    // MARK: - Loot Box Section

    @ViewBuilder
    private func lootBoxSection(_ vm: RPGProfileViewModel) -> some View {
        if !vm.unopenedLootBoxes.isEmpty {
            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
                sectionHeader(title: "Lootboxes", icon: "shippingbox.fill")

                ForEach(vm.unopenedLootBoxes) { box in
                    Button {
                        selectedLootBox = box
                    } label: {
                        HStack(spacing: IkeruTheme.Spacing.sm) {
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Color(hex: IkeruTheme.Colors.Rarity.epic))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(box.challengeType.displayName)
                                    .font(.ikeruBody)
                                    .foregroundStyle(.white)

                                Text("Score \(box.requiredScore) to open")
                                    .font(.ikeruCaption)
                                    .foregroundStyle(.ikeruTextSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundStyle(.ikeruTextSecondary)
                        }
                        .padding(.vertical, IkeruTheme.Spacing.xs)
                    }
                }
            }
            .ikeruCard(.elevated)
        }
    }

    // MARK: - Attributes Section

    @ViewBuilder
    private func attributesSection(_ vm: RPGProfileViewModel) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            sectionHeader(title: "Attributes", icon: "chart.bar.fill")

            // Unlocked attributes
            ForEach(vm.unlockedAttributes) { attr in
                attributeRow(attr, isLocked: false)
            }

            // Locked attributes (teaser)
            ForEach(vm.lockedAttributes) { attr in
                attributeRow(attr, isLocked: true)
            }
        }
        .ikeruCard(.standard)
    }

    private func attributeRow(_ attr: RPGAttribute, isLocked: Bool) -> some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            Image(systemName: isLocked ? "lock.fill" : attr.iconName)
                .font(.ikeruBody)
                .foregroundStyle(isLocked ? .ikeruTextSecondary : Color.ikeruPrimaryAccent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(isLocked ? "???" : attr.name)
                    .font(.ikeruBody)
                    .foregroundStyle(isLocked ? .ikeruTextSecondary : .white)

                if isLocked {
                    Text("Unlocks at Lv. \(attr.unlockLevel)")
                        .font(.ikeruCaption)
                        .foregroundStyle(.ikeruTextSecondary)
                } else {
                    Text(attr.description)
                        .font(.ikeruCaption)
                        .foregroundStyle(.ikeruTextSecondary)
                }
            }

            Spacer()

            if !isLocked {
                // Attribute value bar
                attributeValueBar(value: attr.value)
            }
        }
        .padding(.vertical, IkeruTheme.Spacing.xs)
        .opacity(isLocked ? 0.5 : 1.0)
    }

    private func attributeValueBar(value: Int) -> some View {
        HStack(spacing: IkeruTheme.Spacing.xs) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.ikeruSurface)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.ikeruPrimaryAccent)
                        .frame(
                            width: geometry.size.width * (Double(value) / 100.0),
                            height: 6
                        )
                }
            }
            .frame(width: 60, height: 6)

            Text("\(value)")
                .font(.ikeruStats)
                .foregroundStyle(.ikeruTextSecondary)
                .frame(width: 28, alignment: .trailing)
        }
    }

    // MARK: - Inventory Section

    @ViewBuilder
    private func inventorySection(_ vm: RPGProfileViewModel) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            sectionHeader(title: "Inventory", icon: "bag.fill")

            if vm.inventory.isEmpty {
                Text("Complete sessions to earn loot!")
                    .font(.ikeruBody)
                    .foregroundStyle(.ikeruTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, IkeruTheme.Spacing.lg)
            } else {
                ForEach(vm.inventoryByRarity, id: \.rarity) { group in
                    rarityGroupSection(rarity: group.rarity, items: group.items)
                }
            }
        }
        .ikeruCard(.standard)
    }

    private func rarityGroupSection(rarity: LootRarity, items: [LootItem]) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
            Text(rarity.displayName)
                .font(.ikeruCaption)
                .foregroundStyle(rarityColor(rarity))
                .textCase(.uppercase)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 72))],
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
                .font(.system(size: 24))
                .foregroundStyle(rarityColor(item.rarity))

            Text(item.name)
                .font(.ikeruCaption)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 72, height: 72)
        .background(
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
                .fill(Color.ikeruSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
                .stroke(rarityColor(item.rarity).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Color.ikeruPrimaryAccent)
            Text(title)
                .font(.ikeruHeading3)
                .foregroundStyle(.white)
            Spacer()
        }
    }

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
