import SwiftUI
import SwiftData
import IkeruCore

// MARK: - VocabularyDrillModeSelector

/// Choose between Flashcard and Quiz drill modes for dictionary words.
struct VocabularyDrillModeSelector: View {

    let modelContainer: ModelContainer

    @State private var dueEntries: [VocabularyEntryDTO] = []
    @State private var allEntries: [VocabularyEntryDTO] = []
    @State private var hasLoaded = false
    @State private var goFlashcard = false
    @State private var goQuiz = false

    private var repo: VocabularyRepository {
        VocabularyRepository(modelContainer: modelContainer)
    }

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            if hasLoaded {
                VStack(alignment: .leading, spacing: IkeruTheme.Spacing.lg) {
                    header
                    modeCard(
                        title: "Flashcard",
                        subtitle: "Classic SRS review",
                        description: "See the word, recall the meaning, then grade your recall. Builds long-term retention.",
                        icon: "rectangle.on.rectangle.angled",
                        action: { goFlashcard = true }
                    )
                    modeCard(
                        title: "Quiz",
                        subtitle: "4 quick choices",
                        description: "Pick the correct meaning among 4 options. Speed bonus for fast answers.",
                        icon: "checkmark.circle.badge.questionmark",
                        action: { goQuiz = true }
                    )
                    Spacer()
                }
                .padding(IkeruTheme.Spacing.lg)
                .padding(.bottom, 88)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Vocabulary Drill")
        .task { await loadEntries() }
        .navigationDestination(isPresented: $goFlashcard) {
            VocabularyFlashcardView(viewModel: VocabularyDrillViewModel(
                queue: dueEntries,
                allEntries: allEntries,
                vocabularyRepository: repo
            ))
        }
        .navigationDestination(isPresented: $goQuiz) {
            VocabularyQuizView(viewModel: VocabularyDrillViewModel(
                queue: dueEntries,
                allEntries: allEntries,
                vocabularyRepository: repo
            ))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TRAINING MODE")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
            Text("Vocabulary Drill")
                .font(.ikeruDisplaySmall)
                .ikeruTracking(.display)
                .foregroundStyle(Color.ikeruTextPrimary)
            Text("\(dueEntries.count) words due for review")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextSecondary)
        }
    }

    @ViewBuilder
    private func modeCard(
        title: String,
        subtitle: String,
        description: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: IkeruTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.ikeruHeading2)
                        .ikeruTracking(.heading)
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Text(subtitle)
                        .font(.ikeruMicro)
                        .ikeruTracking(.micro)
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                    Text(description)
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .ikeruCard(.interactive)
        .disabled(dueEntries.isEmpty)
        .opacity(dueEntries.isEmpty ? 0.5 : 1.0)
    }

    private func loadEntries() async {
        allEntries = await repo.allEntries()
        dueEntries = await repo.dueEntries(before: Date())
        // If no due entries, offer all entries for free practice
        if dueEntries.isEmpty {
            dueEntries = allEntries
        }
        hasLoaded = true
    }
}
