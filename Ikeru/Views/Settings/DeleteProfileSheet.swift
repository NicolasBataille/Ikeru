import SwiftUI
import SwiftData
import IkeruCore

/// Styled confirmation sheet for deleting a profile. Replaces the generic
/// system confirmationDialog with something that matches Ikeru's wabi-sabi
/// glass aesthetic and — critically — shows the learner exactly what they
/// are about to lose (cards, level, items, days active).
struct DeleteProfileSheet: View {

    let profile: UserProfile
    let onConfirm: () -> Void
    let onCancel: () -> Void

    /// Summary loaded from the model container on appear.
    @State private var summary: Summary?
    @Environment(\.modelContext) private var modelContext

    struct Summary: Equatable {
        let cardCount: Int
        let level: Int
        let xp: Int
        let lootCount: Int
        let daysActive: Int
    }

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            ScrollView {
                VStack(spacing: IkeruTheme.Spacing.xl) {
                    header
                    warningCard
                    if let summary {
                        summaryCard(summary)
                    } else {
                        loadingCard
                    }
                    finalWordCard
                    actionButtons
                    Spacer(minLength: IkeruTheme.Spacing.xl)
                }
                .padding(.horizontal, IkeruTheme.Spacing.lg)
                .padding(.top, IkeruTheme.Spacing.xl)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await loadSummary() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DANGER ZONE")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruDanger)
            Text("Delete Profile")
                .font(.ikeruDisplaySmall)
                .ikeruTracking(.display)
                .foregroundStyle(Color.ikeruTextPrimary)
            Text(profile.displayName)
                .font(.ikeruHeading3)
                .foregroundStyle(Color.ikeruTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var warningCard: some View {
        HStack(alignment: .top, spacing: IkeruTheme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.ikeruDanger)
                .frame(width: 32)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("This cannot be undone")
                    .font(.ikeruBody)
                    .foregroundStyle(Color.ikeruTextPrimary)
                Text("All learning progress for this profile will be permanently erased.")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(IkeruTheme.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg, style: .continuous)
                .fill(Color.ikeruDanger.opacity(0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg, style: .continuous)
                .strokeBorder(Color.ikeruDanger.opacity(0.35), lineWidth: 0.8)
        }
    }

    private var loadingCard: some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            ProgressView()
                .tint(Color.ikeruTextSecondary)
            Text("Loading profile data…")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, IkeruTheme.Spacing.lg)
        .ikeruCard(.standard)
    }

    private func summaryCard(_ s: Summary) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            IkeruSectionHeader(title: "You will lose", eyebrow: "What disappears")

            VStack(spacing: 0) {
                summaryRow(
                    icon: "rectangle.stack.fill",
                    tint: Color.ikeruPrimaryAccent,
                    label: "Learning cards",
                    value: "\(s.cardCount)"
                )
                IkeruDivider()
                summaryRow(
                    icon: "shield.lefthalf.filled",
                    tint: Color(hex: IkeruTheme.Colors.Rarity.legendary),
                    label: "RPG level \(s.level)",
                    value: "\(s.xp) XP"
                )
                IkeruDivider()
                summaryRow(
                    icon: "bag.fill",
                    tint: Color.ikeruSecondaryAccent,
                    label: "Loot items",
                    value: "\(s.lootCount)"
                )
                IkeruDivider()
                summaryRow(
                    icon: "calendar",
                    tint: Color.ikeruTertiaryAccent,
                    label: "Days active",
                    value: "\(s.daysActive)"
                )
            }
        }
        .ikeruCard(.standard)
    }

    private func summaryRow(icon: String, tint: Color, label: String, value: String) -> some View {
        HStack(spacing: IkeruTheme.Spacing.md) {
            ZStack {
                Circle().fill(tint.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }

            Text(label)
                .font(.ikeruBody)
                .foregroundStyle(Color.ikeruTextPrimary)

            Spacer()

            Text(value)
                .font(.ikeruStats)
                .foregroundStyle(Color.ikeruTextSecondary)
        }
        .padding(.vertical, IkeruTheme.Spacing.sm)
    }

    private var finalWordCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("REMINDER")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
            Text("Export your data before deleting if you want to keep a backup.")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionButtons: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            HoldToConfirmButton(
                title: "Hold to delete \(profile.displayName)",
                icon: "trash.fill",
                duration: 1.6,
                onConfirm: onConfirm
            )

            Button("Cancel") {
                onCancel()
            }
            .ikeruButtonStyle(.ghost)

            Text("Press and hold to confirm")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
                .padding(.top, 2)
        }
    }

    // MARK: - Loading

    @MainActor
    private func loadSummary() async {
        let cards = profile.cards ?? []
        let rpg = profile.rpgState
        let created = profile.createdAt
        let days = max(0, Calendar.current.dateComponents([.day], from: created, to: Date()).day ?? 0)
        summary = Summary(
            cardCount: cards.count,
            level: rpg?.level ?? 1,
            xp: rpg?.xp ?? 0,
            lootCount: rpg?.lootInventory.count ?? 0,
            daysActive: days
        )
    }
}
