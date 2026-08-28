import SwiftUI
import SwiftData
import IkeruCore

// MARK: - VocabularyDictionaryView

/// Personal vocabulary dictionary showing all saved words with mastery badges,
/// encounter counts, and access to vocabulary drills.
struct VocabularyDictionaryView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: VocabularyDictionaryViewModel?
    @State private var selectedEntry: VocabularyEntryDTO?
    @State private var showAddWord = false

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            if let vm = viewModel, vm.hasLoaded {
                if vm.entries.isEmpty {
                    emptyState
                } else {
                    dictionaryContent(vm)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Vocabulary")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddWord = true } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                }
                .accessibilityLabel("Vocabulary.Add")
            }
        }
        .task {
            initializeViewModel()
            await viewModel?.loadData()
        }
        .onAppear {
            if viewModel != nil {
                Task { await viewModel?.loadData() }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            VocabularyEntryDetailView(
                entryId: entry.id,
                modelContainer: modelContext.container
            ) {
                Task { await viewModel?.loadData() }
            }
        }
        .sheet(isPresented: $showAddWord) {
            VocabularyWordFormView(modelContainer: modelContext.container) {
                Task { await viewModel?.loadData() }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            Image(systemName: "book.closed")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Color.ikeruTextTertiary)

            VStack(spacing: IkeruTheme.Spacing.sm) {
                Text("No words yet")
                    .font(.ikeruHeading2)
                    .foregroundStyle(Color.ikeruTextPrimary)

                // Honest copy: words flow in from Sakura chat, but that needs an
                // AI provider — so we always offer a manual path too, otherwise
                // an offline learner is dead-ended with no way to add a word.
                Text("Vocabulary.Empty.Body")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, IkeruTheme.Spacing.xl)
            }

            Button { showAddWord = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Vocabulary.Add")
                        .font(.ikeruCaption)
                }
                .foregroundStyle(Color.ikeruPrimaryAccent)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Rectangle().fill(Color.ikeruPrimaryAccent.opacity(0.10)))
                .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.5), lineWidth: 1))
                .sumiCorners(color: TatamiTokens.goldDim, size: 6, weight: 1.0)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func dictionaryContent(_ vm: VocabularyDictionaryViewModel) -> some View {
        ScrollView {
            VStack(spacing: IkeruTheme.Spacing.md) {
                headerSection(vm)
                searchBar(vm)
                filterChips(vm)

                if vm.dueCount > 0 {
                    drillBanner(vm)
                }

                wordList(vm)

                Spacer(minLength: 200)
            }
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .padding(.top, IkeruTheme.Spacing.md)
        }
    }

    // MARK: - Header

    private func headerSection(_ vm: VocabularyDictionaryViewModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("MY DICTIONARY")
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Color.ikeruTextTertiary)
                Text("\(vm.totalCount) words")
                    .font(.ikeruHeading2)
                    .foregroundStyle(Color.ikeruTextPrimary)
            }
            Spacer()
            sortMenu(vm)
        }
    }

    // MARK: - Sort

    private func sortMenu(_ vm: VocabularyDictionaryViewModel) -> some View {
        Menu {
            ForEach(VocabSortOrder.allCases) { order in
                Button {
                    vm.sortOrder = order
                } label: {
                    HStack {
                        Text(order.label)
                        if vm.sortOrder == order {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11))
                Text(vm.sortOrder.label)
                    .font(.ikeruCaption)
            }
            .foregroundStyle(Color.ikeruPrimaryAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Rectangle()
                    .fill(Color.ikeruPrimaryAccent.opacity(0.10))
                    .overlay { Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.4), lineWidth: 0.5) }
            }
            .sumiCorners(color: TatamiTokens.goldDim, size: 6, weight: 1.1)
        }
    }

    // MARK: - Search

    private func searchBar(_ vm: VocabularyDictionaryViewModel) -> some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.ikeruTextTertiary)
            TextField("Search words...", text: Binding(
                get: { vm.searchText },
                set: { vm.searchText = $0 }
            ))
            .font(.ikeruBody)
            .foregroundStyle(Color.ikeruTextPrimary)
            .autocorrectionDisabled()

            if !vm.searchText.isEmpty {
                Button {
                    vm.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.ikeruTextTertiary)
                }
            }
        }
        .padding(IkeruTheme.Spacing.sm)
        .background {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .overlay { Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.3), lineWidth: 0.5) }
        }
        .sumiCorners(color: TatamiTokens.goldDim, size: 6, weight: 1.0)
    }

    // MARK: - Filter Chips

    private func filterChips(_ vm: VocabularyDictionaryViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: IkeruTheme.Spacing.xs) {
                ForEach(VocabMasteryFilter.allCases) { filter in
                    filterChip(filter, vm: vm)
                }
            }
        }
    }

    private func filterChip(_ filter: VocabMasteryFilter, vm: VocabularyDictionaryViewModel) -> some View {
        let isSelected = vm.masteryFilter == filter
        return Button {
            vm.masteryFilter = filter
        } label: {
            Text(filter.label)
                .font(.ikeruCaption)
                .foregroundStyle(isSelected ? Color.ikeruBackground : Color.ikeruTextPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Rectangle()
                        .fill(isSelected ? Color.ikeruPrimaryAccent : Color.white.opacity(0.08))
                        .overlay {
                            Rectangle().strokeBorder(
                                isSelected ? Color.ikeruPrimaryAccent : TatamiTokens.goldDim.opacity(0.4),
                                lineWidth: 0.5
                            )
                        }
                }
                .sumiCorners(color: isSelected ? Color.ikeruPrimaryAccent : TatamiTokens.goldDim, size: 6, weight: 1.1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Drill Banner

    private func drillBanner(_ vm: VocabularyDictionaryViewModel) -> some View {
        NavigationLink {
            VocabularyDrillModeSelector(modelContainer: modelContext.container)
        } label: {
            HStack(spacing: IkeruTheme.Spacing.md) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                    .frame(width: 38, height: 38)
                    .background {
                        Rectangle()
                            .fill(Color.ikeruPrimaryAccent.opacity(0.12))
                            .overlay { Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.4), lineWidth: 0.5) }
                    }
                    .sumiCorners(color: TatamiTokens.goldDim, size: 6, weight: 1.0)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drill Due Words")
                        .font(.ikeruHeading3)
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Text("\(vm.dueCount) words ready for review")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextTertiary)
            }
            .tatamiRoom(.standard)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Word List

    @ViewBuilder
    private func wordList(_ vm: VocabularyDictionaryViewModel) -> some View {
        LazyVStack(spacing: IkeruTheme.Spacing.sm) {
            ForEach(vm.filteredEntries) { entry in
                wordRow(entry)
            }
        }
    }

    private func wordRow(_ entry: VocabularyEntryDTO) -> some View {
        Button {
            selectedEntry = entry
        } label: {
            HStack(spacing: IkeruTheme.Spacing.md) {
                // Mastery badge
                Text(entry.mastery.emoji)
                    .font(.system(size: 20))
                    .frame(width: 32)

                // Word info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: IkeruTheme.Spacing.xs) {
                        Text(entry.word)
                            .font(.ikeruHeading3)
                            .foregroundStyle(Color.ikeruTextPrimary)
                        Text(entry.reading)
                            .font(.ikeruCaption)
                            .foregroundStyle(Color.ikeruPrimaryAccent)
                    }
                    Text(entry.meaning)
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Stats
                VStack(alignment: .trailing, spacing: 2) {
                    if let level = entry.jlptLevel {
                        Text(level.displayLabel)
                            .ikeruScaledFont(10, weight: .semibold, relativeTo: .caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(Color.ikeruPrimaryAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background {
                                Rectangle()
                                    .fill(Color.ikeruPrimaryAccent.opacity(0.12))
                                    .overlay { Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.4), lineWidth: 0.5) }
                            }
                            .sumiCorners(color: TatamiTokens.goldDim, size: 4, weight: 0.9)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                            .font(.system(size: 9))
                        Text("\(entry.encounterCount)")
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(Color.ikeruTextTertiary)
                }
            }
            .padding(IkeruTheme.Spacing.md)
            .background {
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .overlay { Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.18), lineWidth: 0.5) }
            }
            .sumiCorners(color: TatamiTokens.goldDim, size: 6, weight: 1.0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func initializeViewModel() {
        guard viewModel == nil else { return }
        viewModel = VocabularyDictionaryViewModel(modelContainer: modelContext.container)
    }
}

// MARK: - VocabularyWordFormView

/// Saisie manuelle d'un mot — création ET correction (OBS2-007/013).
///
/// `editing` non nil bascule la feuille en mode correction : mêmes champs,
/// mêmes règles de validation, `updateEntry` au lieu d'`addEntry`. Un seul
/// formulaire pour les deux, parce que deux formulaires divergent toujours —
/// et c'est justement l'absence de chemin de correction qui laissait vivre des
/// entrées inétudiables.
struct VocabularyWordFormView: View {

    let modelContainer: ModelContainer
    var editing: VocabularyEntryDTO? = nil
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var word = ""
    @State private var reading = ""
    @State private var meaning = ""
    @State private var isSaving = false
    @State private var didPrefill = false

    private var trimmedWord: String { word.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedReading: String { reading.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedMeaning: String { meaning.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Vrai quand le mot contient au moins un kanji. Un mot tout en kana EST sa
    /// propre lecture — lui réclamer une lecture séparée serait du bruit.
    private var needsExplicitReading: Bool {
        trimmedWord.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)   // idéogrammes unifiés
                || (0x3400...0x4DBF).contains(scalar.value)  // extension A
        }
    }

    /// Ce qui manque encore, ou `nil` si l'entrée est étudiable (OBS2-007/013).
    ///
    /// Seul le MOT était requis. On pouvait donc enregistrer une entrée sans
    /// sens et sans lecture — une carte que le SRS sert ensuite et que personne
    /// ne peut réviser : le quiz de vocabulaire n'a aucune bonne réponse à
    /// afficher et dégénère en deux cases dont une vide. Et rien ne permet de
    /// la réparer après coup.
    ///
    /// La règle est minimale et pédagogique : il faut de quoi POSER la question
    /// (le mot), de quoi y RÉPONDRE (le sens), et de quoi la LIRE (la lecture,
    /// seulement si le mot porte un kanji).
    private var missingRequirement: LocalizedStringKey? {
        if trimmedWord.isEmpty { return "Vocabulary.Validation.WordRequired" }
        if trimmedMeaning.isEmpty { return "Vocabulary.Validation.MeaningRequired" }
        if needsExplicitReading, trimmedReading.isEmpty {
            return "Vocabulary.Validation.ReadingRequired"
        }
        return nil
    }

    private var canSave: Bool {
        missingRequirement == nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                IkeruScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: IkeruTheme.Spacing.lg) {
                        field("Vocabulary.Field.Word", jp: "\u{8A00}\u{8449}", text: $word)
                        field("Vocabulary.Field.Reading", jp: "\u{8AAD}\u{307F}", text: $reading)
                        field("Vocabulary.Field.Meaning", jp: "\u{610F}\u{5473}", text: $meaning)

                        // Dire CE QUI manque, plutôt que de laisser un bouton
                        // « Enregistrer » grisé sans explication : un contrôle
                        // inerte et muet est une impasse.
                        if let missingRequirement {
                            Text(missingRequirement)
                                .font(.ikeruCaption)
                                .foregroundStyle(Color.ikeruTextTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(IkeruTheme.Spacing.lg)
                }
            }
            .navigationTitle(editing == nil ? "Vocabulary.Add" : "Vocabulary.Edit")
            .navigationBarTitleDisplayMode(.inline)
            // `.task`, pas `.onAppear` avec un garde muet : le préremplissage
            // ne doit se faire qu'une fois, sinon une réévaluation du corps
            // écraserait ce que l'utilisateur vient de taper.
            .task {
                guard !didPrefill, let editing else { return }
                didPrefill = true
                word = editing.word
                reading = editing.reading
                meaning = editing.meaning
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func field(_ label: LocalizedStringKey, jp: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(jp)
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                Text(label)
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
            TextField("", text: text)
                .font(.ikeruBody)
                .foregroundStyle(Color.ikeruTextPrimary)
                .padding(IkeruTheme.Spacing.sm)
                .background(Rectangle().fill(Color.ikeruSurface))
                .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.5), lineWidth: 1))
                .sumiCorners(color: TatamiTokens.goldDim, size: 5, weight: 0.9)
                .autocorrectionDisabled()
        }
    }

    private func save() {
        // Même garde que `canSave` : le bouton peut être désactivé, `save()`
        // reste appelable depuis un autre chemin.
        guard missingRequirement == nil else { return }
        isSaving = true
        let finalWord = trimmedWord
        let finalReading = trimmedReading
        let finalMeaning = trimmedMeaning
        Task {
            let repo = VocabularyRepository(modelContainer: modelContainer)
            if let editing {
                await repo.updateEntry(
                    id: editing.id,
                    word: finalWord,
                    reading: finalReading,
                    meaning: finalMeaning
                )
            } else {
                _ = await repo.addEntry(
                    word: finalWord,
                    reading: finalReading,
                    meaning: finalMeaning,
                    jlptLevel: nil
                )
            }
            onSaved()
            dismiss()
        }
    }
}
