import SwiftUI
import SwiftData
import IkeruCore

/// Detail sheet shown when tapping a VocabChip in chat. Displays word info
/// and allows adding to the personal dictionary.
struct VocabularyDetailSheet: View {

    let hint: VocabularyHint
    let contextSnippet: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.toastManager) private var toastManager
    @Environment(\.dismiss) private var dismiss
    @State private var existingEntry: VocabularyEntryDTO?
    @State private var encounters: [VocabularyEncounterDTO] = []
    @State private var hasLoaded = false
    @State private var contextExpanded = false

    /// Whether this word is explicitly in the user's dictionary.
    private var isInDictionary: Bool {
        existingEntry?.isInDictionary ?? false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ikeruBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: IkeruTheme.Spacing.xl) {
                        wordHeader
                        meaningSection
                        contextSection
                        if let entry = existingEntry, entry.isInDictionary {
                            masterySection(entry)
                        }
                        if !encounters.isEmpty {
                            encounterSection
                        }
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, IkeruTheme.Spacing.lg)
                    .padding(.top, IkeruTheme.Spacing.lg)
                }

                // Sticky bottom button
                VStack {
                    Spacer()
                    actionSection
                        .padding(.horizontal, IkeruTheme.Spacing.lg)
                        .padding(.bottom, IkeruTheme.Spacing.lg)
                        .background(
                            LinearGradient(
                                colors: [Color.ikeruBackground.opacity(0), Color.ikeruBackground],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 80)
                            .allowsHitTesting(false),
                            alignment: .top
                        )
                }
            }
            .navigationTitle("Vocabulary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                }
            }
            .task {
                await loadEntry()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Word Header

    private var wordHeader: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Text(hint.word)
                .font(.system(size: 64, weight: .regular, design: .serif))
                .foregroundStyle(Color.ikeruTextPrimary)

            Text(hint.reading)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundStyle(Color.ikeruPrimaryAccent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, IkeruTheme.Spacing.lg)
    }

    // MARK: - Meaning

    private var meaningSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            sectionLabel("MEANING")
            Text(hint.meaning)
                .font(.ikeruBody)
                .foregroundStyle(Color.ikeruTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ikeruCard(.standard)
    }

    // MARK: - Context (expandable)

    private var contextSection: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                contextExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
                HStack {
                    sectionLabel("CONTEXT")
                    Spacer()
                    Image(systemName: contextExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.ikeruTextTertiary)
                }
                Text(contextSnippet)
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .lineLimit(contextExpanded ? nil : 3)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .ikeruCard(.standard)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mastery

    @ViewBuilder
    private func masterySection(_ entry: VocabularyEntryDTO) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            sectionLabel("MASTERY")
            HStack(spacing: IkeruTheme.Spacing.lg) {
                statTile(
                    value: entry.mastery.emoji,
                    label: entry.mastery.label
                )
                statTile(
                    value: "\(entry.encounterCount)",
                    label: "Encounters"
                )
                statTile(
                    value: "\(entry.interval)j",
                    label: "Interval"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ikeruCard(.standard)
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.ikeruStatsLarge)
                .foregroundStyle(Color.ikeruPrimaryAccent)
            Text(label.uppercased())
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Encounters

    @ViewBuilder
    private var encounterSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            sectionLabel("RECENT ENCOUNTERS")
            ForEach(encounters.prefix(5)) { encounter in
                HStack(spacing: IkeruTheme.Spacing.sm) {
                    Image(systemName: encounter.source.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(encounter.source.label)
                            .font(.ikeruCaption)
                            .foregroundStyle(Color.ikeruTextPrimary)
                        Text(encounter.contextSnippet)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.ikeruTextTertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(encounter.timestamp, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.ikeruTextTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ikeruCard(.standard)
    }

    // MARK: - Action (sticky bottom)

    @ViewBuilder
    private var actionSection: some View {
        if isInDictionary {
            HStack(spacing: IkeruTheme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                Text("In your Dictionary")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, IkeruTheme.Spacing.md)
        } else {
            Button {
                Task { await addToDictionary() }
            } label: {
                HStack(spacing: IkeruTheme.Spacing.sm) {
                    Image(systemName: "plus")
                    Text("Add to Dictionary")
                }
                .frame(maxWidth: .infinity)
            }
            .ikeruButtonStyle(.primary)
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.ikeruMicro)
            .ikeruTracking(.micro)
            .foregroundStyle(Color.ikeruTextTertiary)
    }

    private func loadEntry() async {
        let repo = VocabularyRepository(modelContainer: modelContext.container)
        if let entry = await repo.entry(byWord: hint.word) {
            existingEntry = entry
            encounters = await repo.encounters(for: entry.id)
        }
        hasLoaded = true
    }

    private func addToDictionary() async {
        let repo = VocabularyRepository(modelContainer: modelContext.container)
        let entry = await repo.addEntry(
            word: hint.word,
            reading: hint.reading,
            meaning: hint.meaning
        )
        existingEntry = await repo.entry(by: entry.id)
        if let id = existingEntry?.id {
            encounters = await repo.encounters(for: id)
        }
        toastManager.showInfo("\(hint.word) added to dictionary")
        dismiss()
    }
}
