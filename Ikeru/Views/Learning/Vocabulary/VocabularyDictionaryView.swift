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
            )
        }
        .sheet(isPresented: $showAddWord) {
            AddVocabularyWordView(modelContainer: modelContext.container) {
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

// MARK: - AddVocabularyWordView

/// Minimal manual word-entry sheet. Surfaces the existing
/// `VocabularyRepository.addEntry` so a learner can build their dictionary
/// without depending on the (AI-gated) Sakura chat.
private struct AddVocabularyWordView: View {

    let modelContainer: ModelContainer
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var word = ""
    @State private var reading = ""
    @State private var meaning = ""
    @State private var isSaving = false

    private var canSave: Bool {
        !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
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
                    }
                    .padding(IkeruTheme.Spacing.lg)
                }
            }
            .navigationTitle("Vocabulary.Add")
            .navigationBarTitleDisplayMode(.inline)
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
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return }
        isSaving = true
        let r = reading.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            _ = await VocabularyRepository(modelContainer: modelContainer)
                .addEntry(word: w, reading: r, meaning: m, jlptLevel: nil)
            onSaved()
            dismiss()
        }
    }
}
