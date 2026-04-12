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
        .navigationTitle("Dictionary")
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

                Text("Tap vocabulary chips in Sakura chat to add words to your dictionary.")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, IkeruTheme.Spacing.xl)
            }
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
            .background(Color.ikeruPrimaryAccent.opacity(0.10))
            .clipShape(Capsule())
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
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.md))
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
                .background(isSelected ? Color.ikeruPrimaryAccent : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Drill Banner

    private func drillBanner(_ vm: VocabularyDictionaryViewModel) -> some View {
        NavigationLink {
            VocabularyDrillModeSelector(modelContainer: modelContext.container)
        } label: {
            HStack(spacing: IkeruTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.ikeruSecondaryAccent.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.ikeruSecondaryAccent)
                }
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
            .ikeruCard(.interactive)
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
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.ikeruPrimaryAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.ikeruPrimaryAccent.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                            .font(.system(size: 9))
                        Text("\(entry.encounterCount)")
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .foregroundStyle(Color.ikeruTextTertiary)
                }
            }
            .padding(IkeruTheme.Spacing.md)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func initializeViewModel() {
        guard viewModel == nil else { return }
        viewModel = VocabularyDictionaryViewModel(modelContainer: modelContext.container)
    }
}
