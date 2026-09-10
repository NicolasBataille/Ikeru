import SwiftUI
import SwiftData
import IkeruCore

/// Styled confirmation sheet for deleting a profile. Replaces the generic
/// system confirmationDialog with something that matches Ikeru's wabi-sabi
/// glass aesthetic and — critically — shows the learner exactly what they
/// are about to lose (cards, level, days active, words, imported texts).
struct DeleteProfileSheet: View {

    let profile: UserProfile
    let onConfirm: () -> Void
    let onCancel: () -> Void

    /// `profile.displayName` captured as a plain value the moment this sheet is built —
    /// the header and the hold-to-confirm button title read this, never `profile` directly.
    /// `onConfirm` deletes the underlying SwiftData model, and SwiftUI can still replay
    /// `body` on this already-built view during the sheet's dismiss animation (or, in
    /// principle, if some other path deletes this profile while the sheet is still up).
    /// Reading a `String` captured up front can't crash or go blank the way a live
    /// `profile.displayName` read against a deleted/faulted model could.
    let displayName: String

    /// Summary loaded from the model container on appear.
    @State private var summary: Summary?
    @Environment(\.modelContext) private var modelContext

    init(profile: UserProfile, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.profile = profile
        self.displayName = profile.displayName
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    struct Summary: Equatable {
        let cardCount: Int
        let level: Int
        let xp: Int
        let daysActive: Int
        /// Dictionary words and imported texts — owned by the profile since
        /// `IkeruSchemaV6`, and erased with it (OBS2-051).
        let wordCount: Int
        let importCount: Int
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
            Text(displayName)
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
                // Nomme ce qui est RÉELLEMENT effacé, au lieu de « toute la
                // progression » (OBS2-051). La cascade est
                // `ProfileDeletion.tombstoneGraph` : cartes, journaux de
                // révision, état RPG, journaux d'exercice, dictionnaire
                // personnel, textes importés, et le profil. Les deux derniers
                // en font partie depuis `IkeruSchemaV6` (P1-1) — la carte
                // « Ce qui reste » qui les excusait est partie avec la
                // migration, dans le même commit.
                Text("This profile's cards, review history, level, active days, personal dictionary and imported texts will be permanently erased.")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(IkeruTheme.Spacing.md)
        .background(Color.ikeruDanger.opacity(0.10))
        .overlay(Rectangle().strokeBorder(Color.ikeruDanger.opacity(0.45), lineWidth: 0.8))
        .sumiCorners(color: Color.ikeruDanger.opacity(0.6), size: 6, weight: 1.0)
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
        .tatamiRoom(.standard)
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
                    icon: "calendar",
                    tint: Color.ikeruTertiaryAccent,
                    label: "Days active",
                    value: "\(s.daysActive)"
                )
                IkeruDivider()
                summaryRow(
                    icon: "character.book.closed",
                    tint: Color.ikeruSecondaryAccent,
                    label: "Dictionary words",
                    value: "\(s.wordCount)"
                )
                IkeruDivider()
                summaryRow(
                    icon: "doc.text",
                    tint: Color.ikeruSecondaryAccent,
                    label: "Imported texts",
                    value: "\(s.importCount)"
                )
            }
        }
        .tatamiRoom(.standard)
    }

    /// `label` en `LocalizedStringKey` (OBS2-050) ; `value` reste un `String`,
    /// c'est un nombre formaté, pas du texte à traduire.
    private func summaryRow(icon: String, tint: Color, label: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: IkeruTheme.Spacing.md) {
            ZStack {
                Rectangle().fill(tint.opacity(0.12))
                    .frame(width: 28, height: 28)
                    .overlay(Rectangle().strokeBorder(tint.opacity(0.35), lineWidth: 0.8))
                    .sumiCorners(color: TatamiTokens.goldDim, size: 4, weight: 0.9)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
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

    /// Vrai seulement si le profil qu'on s'apprête à supprimer est celui
    /// actuellement utilisé. La corbeille de Réglages ouvre cette feuille pour
    /// N'IMPORTE QUEL profil, alors que `DataExportManager` est cadré sur le
    /// profil ACTIF de bout en bout — y compris `allCards()`, dont le nom
    /// suggère le contraire mais qui appelle `activeProfileCards()`.
    private var isActiveProfile: Bool {
        ActiveProfileResolver.activeProfileID() == profile.id
    }

    /// Le conseil « exporte avant de supprimer » n'est juste que pour le profil
    /// actif (OBS2-051). Le suivre en supprimant un AUTRE profil produit une
    /// archive des données de quelqu'un d'autre, et ne sauvegarde rien de ce
    /// qui va être détruit — un conseil qui échoue silencieusement est pire que
    /// pas de conseil sur un écran irréversible.
    private var finalWordCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("REMINDER")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
            if isActiveProfile {
                Text("Export your data before deleting if you want to keep a backup.")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextSecondary)
            } else {
                Text("Exporting only covers the profile you are currently using. To keep a backup of this one, switch to it first, then come back.")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionButtons: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            HoldToConfirmButton(
                title: "Hold to delete \(displayName)",
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
        // Relationship traversal — no `#Predicate` reaches it, so filter here
        // or already-deleted cards inflate the "N cards" the sheet warns about.
        let cards = (profile.cards ?? []).filter { $0.deletedAt == nil }
        let rpg = profile.rpgState
        let created = profile.createdAt
        let days = max(0, Calendar.current.dateComponents([.day], from: created, to: Date()).day ?? 0)
        // Scalar-scoped (no relationship to walk), so fetched — same as
        // `ProfileDeletion.tombstoneGraph` does. Counting only dictionary
        // words: pre-tracked (encounter-only) entries are not something the
        // learner ever saw as theirs.
        let profileID = profile.id
        let wordCount = (try? modelContext.fetchCount(FetchDescriptor<VocabularyEntry>(
            predicate: #Predicate { $0.profileID == profileID && $0.isInDictionary == true && $0.deletedAt == nil }
        ))) ?? 0
        let importCount = (try? modelContext.fetchCount(FetchDescriptor<TextImport>(
            predicate: #Predicate { $0.profileID == profileID && $0.deletedAt == nil }
        ))) ?? 0
        summary = Summary(
            cardCount: cards.count,
            level: rpg?.level ?? 1,
            xp: rpg?.xp ?? 0,
            daysActive: days,
            wordCount: wordCount,
            importCount: importCount
        )
    }
}
