import SwiftUI
import SwiftData
import IkeruCore

/// Full detail view for a vocabulary entry, shown from the dictionary list.
/// Displays mastery stats, encounter history, and allows deletion.
struct VocabularyEntryDetailView: View {

    let entryId: UUID
    let modelContainer: ModelContainer

    @Environment(\.dismiss) private var dismiss
    @State private var entry: VocabularyEntryDTO?
    @State private var encounters: [VocabularyEncounterDTO] = []
    @State private var hasLoaded = false
    @State private var showDeleteConfirm = false

    private var repo: VocabularyRepository {
        VocabularyRepository(modelContainer: modelContainer)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ikeruBackground.ignoresSafeArea()

                if let entry, hasLoaded {
                    ScrollView {
                        VStack(spacing: IkeruTheme.Spacing.xl) {
                            wordHeader(entry)
                            masteryCard(entry)
                            encounterTimeline
                            deleteSection
                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, IkeruTheme.Spacing.lg)
                        .padding(.top, IkeruTheme.Spacing.lg)
                    }
                }
            }
            .navigationTitle("Word Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                }
            }
            .task { await loadData() }
            .alert("Remove from dictionary?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    Task {
                        await repo.deleteEntry(by: entryId)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove the word and all its encounter history.")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Word Header

    private func wordHeader(_ entry: VocabularyEntryDTO) -> some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Text(entry.word)
                .font(.system(size: 64, weight: .regular, design: .serif))
                .foregroundStyle(Color.ikeruTextPrimary)

            Text(entry.reading)
                .ikeruScaledFont(24, weight: .medium, design: .rounded, relativeTo: .title2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color.ikeruPrimaryAccent)

            Text(entry.meaning)
                .font(.ikeruBody)
                .foregroundStyle(Color.ikeruTextSecondary)

            if let level = entry.jlptLevel {
                Text(level.displayLabel)
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background {
                        Rectangle()
                            .fill(Color.ikeruPrimaryAccent.opacity(0.12))
                            .overlay { Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.4), lineWidth: 0.5) }
                    }
                    .sumiCorners(color: TatamiTokens.goldDim, size: 5, weight: 1.0)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, IkeruTheme.Spacing.lg)
    }

    // MARK: - Mastery Card

    private func masteryCard(_ entry: VocabularyEntryDTO) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            Text("MASTERY")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color.ikeruTextTertiary)

            HStack(spacing: 0) {
                statTile(value: entry.mastery.emoji, label: entry.mastery.label)
                statTile(value: "\(entry.encounterCount)", label: "Encounters")
                statTile(value: "\(entry.interval)j", label: "Interval")
                statTile(value: "\(entry.lapseCount)", label: "Lapses")
            }

            HStack(spacing: IkeruTheme.Spacing.sm) {
                Label("Added", systemImage: "calendar")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextTertiary)
                Spacer()
                Text(entry.createdAt, style: .date)
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }

            if entry.fsrsState.reps > 0 {
                HStack(spacing: IkeruTheme.Spacing.sm) {
                    Label("Next review", systemImage: "clock")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextTertiary)
                    Spacer()
                    Text(entry.dueDate, style: .relative)
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
            }
        }
        .tatamiRoom(.standard)
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.ikeruStatsLarge)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color.ikeruPrimaryAccent)
            Text(label.uppercased())
                .ikeruScaledFont(10, relativeTo: .caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color.ikeruTextTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Encounter Timeline

    @ViewBuilder
    private var encounterTimeline: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            Text("ENCOUNTER HISTORY")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color.ikeruTextTertiary)

            if encounters.isEmpty {
                Text("No encounters logged yet.")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, IkeruTheme.Spacing.md)
            } else {
                ForEach(encounters) { encounter in
                    HStack(alignment: .top, spacing: IkeruTheme.Spacing.sm) {
                        Image(systemName: encounter.source.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ikeruPrimaryAccent)
                            .frame(width: 24, height: 24)
                            .background {
                                Rectangle()
                                    .fill(Color.ikeruPrimaryAccent.opacity(0.10))
                                    .overlay { Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.3), lineWidth: 0.5) }
                            }
                            .sumiCorners(color: TatamiTokens.goldDim, size: 4, weight: 0.9)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(encounter.source.label)
                                    .font(.ikeruCaption)
                                    .foregroundStyle(Color.ikeruTextPrimary)
                                Spacer()
                                Text(encounter.timestamp, style: .relative)
                                    .ikeruScaledFont(10, relativeTo: .caption2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .foregroundStyle(Color.ikeruTextTertiary)
                            }
                            Text(encounter.contextSnippet)
                                .ikeruScaledFont(11, relativeTo: .caption2)
                                .foregroundStyle(Color.ikeruTextTertiary)
                                .lineLimit(2)
                        }
                    }

                    if encounter.id != encounters.last?.id {
                        Rectangle()
                            .fill(TatamiTokens.goldDim.opacity(0.18))
                            .frame(width: 1, height: 12)
                            .padding(.leading, 12)
                    }
                }
            }
        }
        .tatamiRoom(.standard)
    }

    // MARK: - Delete

    private var deleteSection: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Remove from Dictionary")
            }
            .frame(maxWidth: .infinity)
            .font(.ikeruCaption)
        }
        .ikeruButtonStyle(.secondary)
    }

    // MARK: - Data Loading

    private func loadData() async {
        entry = await repo.entry(by: entryId)
        encounters = await repo.encounters(for: entryId)
        hasLoaded = true
    }
}
