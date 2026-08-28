import SwiftUI
import SwiftData
import IkeruCore

// MARK: - TextImportJournalView

/// Le journal de lecture : tous les textes que l'apprenant a fait entrer dans
/// l'app, du plus récent au plus ancien.
///
/// ## La confirmation dit ce que le code fait, pas ce qui rassure
///
/// `TextImportRepository.delete(_:)` ne supprime un mot que si **cet import
/// était sa seule provenance** : un mot rencontré aussi dans une conversation
/// Sakura ou dans une session reste au dictionnaire, il perd seulement la
/// rencontre liée à ce texte. La boîte de confirmation énonce exactement cette
/// règle. Le nombre de mots réellement retirés n'est connu qu'**après** la
/// suppression — c'est le dépôt qui le calcule — donc on ne le promet pas
/// avant.
struct TextImportJournalView: View {

    let modelContainer: ModelContainer

    @State private var repository: TextImportRepository?
    @State private var imports: [TextImportDTO] = []
    @State private var hasLoaded = false
    @State private var pendingDeletion: TextImportDTO?

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            if hasLoaded {
                if imports.isEmpty {
                    emptyState
                } else {
                    importList
                }
            }
        }
        .navigationTitle("TextImport.Journal.Title")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if repository == nil {
                repository = TextImportRepository(modelContainer: modelContainer)
            }
            await load()
        }
        .confirmationDialog(
            "TextImport.Journal.DeleteTitle",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = pendingDeletion {
                    delete(target)
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("TextImport.Journal.DeleteExplanation")
        }
    }

    // MARK: - List

    /// Un vrai `List` : `.swipeActions` n'attache rien du tout en dehors d'une
    /// ligne de `List` — le repo s'est déjà fait avoir sur l'écran des profils,
    /// où le modificateur était silencieusement inerte dans un `VStack`.
    private var importList: some View {
        List {
            monthSummary
            ForEach(imports) { item in
                row(item)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: IkeruTheme.Spacing.md,
                                              bottom: 4, trailing: IkeruTheme.Spacing.md))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDeletion = item
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
    }

    private func row(_ item: TextImportDTO) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
            Text(item.title)
                .font(.ikeruHeading3)
                .foregroundStyle(Color.ikeruTextPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: IkeruTheme.Spacing.sm) {
                Label {
                    Text(LocalizedStringKey(item.source.labelKey))
                } icon: {
                    Image(systemName: item.source.icon)
                }
                .font(.ikeruMicro)
                .foregroundStyle(Color.ikeruTextTertiary)

                Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.ikeruMicro)
                    .foregroundStyle(Color.ikeruTextTertiary)
            }

            HStack(spacing: IkeruTheme.Spacing.sm) {
                metric("TextImport.Journal.Words \(item.wordCount)")
                if let coverage = item.coverage {
                    // « à l'import », et pas « connus » tout court (OBS2-062).
                    // `TextImport.coverage` est une valeur STOCKÉE au moment de
                    // l'analyse, pas une requête : elle est structurellement
                    // incapable de changer, quoi que l'apprenant apprenne
                    // ensuite. Sur une fonctionnalité dont la promesse est
                    // « apporte ton texte et apprends-le », afficher ce nombre
                    // comme une couverture actuelle décrit une progression qui
                    // n'aura jamais lieu. Le rendre vivant demande de
                    // ré-analyser le texte à l'affichage — chantier séparé ;
                    // en attendant, l'étiquette dit ce que le nombre est.
                    metric("TextImport.Journal.Coverage \(Int((coverage * 100).rounded()))")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(IkeruTheme.Spacing.md)
        .background {
            Rectangle()
                .fill(Color.white.opacity(0.04))
                .overlay { Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.18), lineWidth: 0.5) }
        }
        .sumiCorners(color: TatamiTokens.goldDim, size: 6, weight: 1.0)
    }

    private func metric(_ label: LocalizedStringKey) -> some View {
        Text(label)
            .ikeruScaledFont(11, weight: .medium, relativeTo: .caption2)
            .foregroundStyle(Color.ikeruPrimaryAccent)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background {
                Rectangle()
                    .fill(Color.ikeruPrimaryAccent.opacity(0.10))
                    .overlay { Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.35), lineWidth: 0.5) }
            }
            .sumiCorners(color: TatamiTokens.goldDim, size: 4, weight: 0.9)
    }

    // MARK: - Empty state

    /// « Aucun élément » n'apprend rien à personne. Un écran vide est le seul
    /// endroit où la feature peut encore s'expliquer.
    /// Ce que le mois en cours donne, en une ligne.
    ///
    /// Rien du tout tant qu'aucun texte n'a été lu ce mois-ci : un journal qui
    /// affiche « 0 texte, 0 mot » le premier du mois transforme un compteur
    /// remis à zéro en reproche.
    @ViewBuilder
    private var monthSummary: some View {
        let summary = TextImportSummary.make(
            from: imports,
            since: TextImportSummary.startOfMonth(containing: Date()))
        if !summary.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("TextImport.Journal.ThisMonth")
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(Color.ikeruTextTertiary)
                if let coverage = summary.averageCoverage {
                    Text("TextImport.Journal.Summary \(summary.textCount) \(summary.wordCount) \(Int((coverage * 100).rounded()))")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                } else {
                    // Pas de moyenne à annoncer : on ne la remplace pas par un
                    // zéro, on n'en parle pas.
                    Text("TextImport.Journal.SummaryNoCoverage \(summary.textCount) \(summary.wordCount)")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .padding(.vertical, IkeruTheme.Spacing.sm)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
        }
    }

    private var emptyState: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Color.ikeruTextTertiary)

            Text("TextImport.Journal.Empty")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, IkeruTheme.Spacing.xl)
        }
    }

    // MARK: - Data

    private func load() async {
        guard let repository else { return }
        imports = await repository.all()
        hasLoaded = true
    }

    private func delete(_ item: TextImportDTO) {
        guard let repository else { return }
        Task {
            await repository.delete(id: item.id)
            await load()
        }
    }
}
