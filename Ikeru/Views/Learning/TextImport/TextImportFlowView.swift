import SwiftUI
import SwiftData
import IkeruCore

// MARK: - TextImportFlowView

/// Hosts the whole « apporte ton propre texte » journey behind one screen:
/// capture, assisted reading, selection, and the offer to practise.
///
/// One view model, one stage value — so no two screens can disagree about where
/// the learner is. The stages are pushed rather than swapped so the system back
/// gesture means what it looks like it means.
///
/// The success criterion the vision sets is a stopwatch: a sentence met
/// anywhere is readable here, its unknown words chosen, and a mini-session
/// offered, in under a minute. Every extra tap on this path is spent against
/// that budget, which is why capture leads straight into reading and why
/// nothing here asks the learner to name their import.
struct TextImportFlowView: View {

    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: TextImportViewModel?
    @State private var showJournal = false
    @State private var practising = false

    var body: some View {
        ZStack {
            IkeruScreenBackground()
            if let viewModel {
                content(viewModel)
            } else {
                unavailable
            }
        }
        .navigationTitle("Your own text")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showJournal = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("Reading journal")
            }
        }
        .navigationDestination(isPresented: $showJournal) {
            TextImportJournalView(modelContainer: modelContext.container)
        }
        .task { makeViewModelIfNeeded() }
    }

    // MARK: - Stages

    @ViewBuilder
    private func content(_ viewModel: TextImportViewModel) -> some View {
        switch viewModel.stage {
        case .capture:
            TextImportCaptureView(viewModel: viewModel)
        case .reading:
            TextImportReadingStage(viewModel: viewModel)
        case .selection:
            WordSelectionView(viewModel: viewModel)
        case .saved(let kept):
            savedStage(viewModel, wordsKept: kept)
        }
    }

    /// The end of the journey: what was kept, and an **offer** to practise.
    ///
    /// « Proposer (jamais imposer) » is the vision's own wording, so the
    /// mini-session is a button next to a way out, not a screen the learner has
    /// to escape. Keeping nothing is a legitimate outcome — a text can be read
    /// without being mined — and the copy says so instead of treating zero as a
    /// failure.
    private func savedStage(_ viewModel: TextImportViewModel, wordsKept: Int) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: wordsKept > 0 ? "checkmark.seal" : "book.closed")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(TatamiTokens.goldDim)

            if wordsKept > 0 {
                Text("TextImport.Saved.WordsKept \(viewModel.savedEntryIDs.count)")
                    .multilineTextAlignment(.center)
            } else {
                Text("TextImport.Saved.NoWord")
                    .multilineTextAlignment(.center)
            }

            if wordsKept > 0 {
                Button("Practise what you just read") { practising = true }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("textImport.practise")
            }
            Button("Import another text") { viewModel.reset() }
                .buttonStyle(.plain)
                .foregroundStyle(Color.ikeruTextSecondary)
            Spacer()
        }
        .padding(.horizontal, 32)
        .navigationDestination(isPresented: $practising) {
            practiceSession(viewModel)
        }
    }

    /// The mini-session reuses the vocabulary quiz rather than inventing a
    /// drill: the words are ordinary vocabulary entries the moment they are
    /// saved, and a second, near-identical drill would be a second thing to
    /// maintain for no learner-visible gain.
    @ViewBuilder
    private func practiceSession(_ viewModel: TextImportViewModel) -> some View {
        let repository = VocabularyRepository(modelContainer: modelContext.container)
        AsyncEntriesView(repository: repository, ids: viewModel.savedEntryIDs) { queue, all in
            VocabularyQuizView(viewModel: VocabularyDrillViewModel(
                queue: queue, allEntries: all, vocabularyRepository: repository))
        }
    }

    // MARK: - Unavailable

    /// The dictionary is a bundled resource, so its absence means a broken
    /// build rather than a runtime condition — but saying so beats a screen
    /// that silently finds no word in any text.
    private var unavailable: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.text.page")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.ikeruTextSecondary)
            Text("TextImport.Flow.DictionaryUnavailable")
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.ikeruTextSecondary)
        }
        .padding(.horizontal, 32)
    }

    private func makeViewModelIfNeeded() {
        guard viewModel == nil, let dictionary = BundledContent.makeDictionary() else { return }
        viewModel = TextImportViewModel(
            analyzer: JapaneseTextAnalyzer(dictionary: dictionary),
            dictionary: dictionary,
            vocabulary: VocabularyRepository(modelContainer: modelContext.container),
            imports: TextImportRepository(modelContainer: modelContext.container)
        )
    }
}

// MARK: - TextImportReadingStage

/// Reading, plus the single way forward. Split out so `AssistedReadingView`
/// stays a pure renderer of an `AnalyzedText` and can be previewed and reused
/// (a future « lire ce que Sakura a écrit » wants exactly that view, and
/// nothing of this chrome).
private struct TextImportReadingStage: View {

    @Bindable var viewModel: TextImportViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let analysis = viewModel.analysis {
                AssistedReadingView(analysis: analysis, knownForms: viewModel.knownForms)
            }
            footer
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let coverage = viewModel.coverage {
                Text("TextImport.Selection.Coverage \(Int((coverage * 100).rounded()))")
                    .font(.subheadline)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
            Button("Choose words to learn") { viewModel.moveToSelection() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("textImport.toSelection")
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
}

// MARK: - AsyncEntriesView

/// Loads vocabulary entries by identifier, then hands them to `content`.
///
/// A tiny shim, and it exists for a reason worth remembering: a view that
/// renders nothing while empty has no lifecycle, so its `.task` never fires and
/// it can never load itself. That exact bug shipped in #114 and made the
/// example-sentences section permanently blank. Here the placeholder is always
/// rendered, so loading always starts.
private struct AsyncEntriesView<Content: View>: View {

    let repository: VocabularyRepository
    let ids: [UUID]
    @ViewBuilder let content: ([VocabularyEntryDTO], [VocabularyEntryDTO]) -> Content

    @State private var loaded: ([VocabularyEntryDTO], [VocabularyEntryDTO])?

    var body: some View {
        Group {
            if let loaded {
                content(loaded.0, loaded.1)
            } else {
                ProgressView()
            }
        }
        .task {
            let all = await repository.allEntries()
            let wanted = Set(ids)
            loaded = (all.filter { wanted.contains($0.id) }, all)
        }
    }
}
