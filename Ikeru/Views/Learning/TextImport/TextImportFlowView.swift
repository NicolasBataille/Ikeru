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
    @Environment(\.aiRouterService) private var aiRouterService

    @State private var viewModel: TextImportViewModel?
    @State private var showJournal = false
    @State private var practising = false
    /// Non-nil présente la conversation — même motif que `ExploreView` :
    /// `.fullScreenCover(item:)` garantit un modèle non nil au contenu, là où
    /// `isPresented:` + `if let` avait produit un écran noir.
    @State private var conversationViewModel: ConversationViewModel?

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
        .task {
            makeViewModelIfNeeded()
            adoptSharedTextIfAny()
        }
        .fullScreenCover(item: $conversationViewModel) { model in
            NavigationStack {
                ConversationView(viewModel: model)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { conversationViewModel = nil }
                        }
                    }
            }
        }
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
            // « Parlons de ce que tu as lu » : le texte devient matière de
            // conversation tant que le contexte est chaud. Proposé au même
            // titre que la mini-séance, jamais imposé.
            if let analysis = viewModel.analysis, !analysis.source.isEmpty {
                Button("Talk about this text with Sakura") {
                    presentConversation(about: analysis.source)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.ikeruPrimaryAccent)
                .accessibilityIdentifier("textImport.talkAboutIt")
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

    /// Reprend le texte déposé par l'extension de partage, s'il y en a un.
    ///
    /// Il atterrit dans le champ de capture comme un collage : éditable,
    /// corrigeable, effaçable. `take()` vide la boîte, donc rouvrir l'écran ne
    /// repropose pas éternellement le même texte — et ne remplace jamais un
    /// brouillon déjà commencé, ce qui serait une perte de saisie.
    private func adoptSharedTextIfAny() {
        guard let viewModel, viewModel.draft.isEmpty, viewModel.stage == .capture,
              let shared = SharedTextInbox().take() else { return }
        viewModel.begin(with: shared, source: .paste)
    }

    /// Ouvre Sakura sur le texte qui vient d'être lu.
    ///
    /// La graine n'est pas le texte entier : envoyer un paragraphe comme
    /// premier message de l'apprenant sonnerait faux et coûterait des jetons
    /// pour rien. C'est **la première phrase**, présentée comme une lecture
    /// (« j'ai lu … »), ce qui donne à Sakura la matière et le registre d'un
    /// seul coup.
    private func presentConversation(about text: String) {
        let router = aiRouterService ?? AIRouterService()
        let service = ConversationService(aiRouter: router)
        let viewModel = ConversationViewModel(
            conversationService: service,
            jlptLevel: .n5,
            vocabularyRepository: VocabularyRepository(modelContainer: modelContext.container),
            contentRepository: BundledContent.makeRepository()
        )
        viewModel.seedTopic = ConversationTopic(
            japanese: "「\(Self.opening(from: text))」を読みました。",
            english: "Talking about the text you just read",
            jlptLevel: "N5"
        )
        conversationViewModel = viewModel
    }

    /// La première phrase du texte, plafonnée. Le plafond est une sécurité, pas
    /// un style : un texte sans ponctuation finale (un tweet, une pancarte)
    /// n'a qu'une phrase, et elle peut être longue.
    static func opening(from text: String, limit: Int = 60) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let breaks: Set<Character> = ["。", "！", "？", "\n"]
        let first = trimmed.prefix { !breaks.contains($0) }
        return first.count > limit ? String(first.prefix(limit)) + "…" : String(first)
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

    /// Le texte de l'apprenant EST scrollable.
    ///
    /// Sans ce `ScrollView`, un texte plus haut que l'écran était coupé net et
    /// rien ne permettait d'en lire la suite : la capture et la sélection ont
    /// chacune le leur, cette étape-ci ne l'avait pas. Un texte tronqué à
    /// l'affichage est un texte réécrit du point de vue de qui le lit.
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                if let analysis = viewModel.analysis {
                    AssistedReadingView(analysis: analysis, knownForms: viewModel.knownForms)
                        .padding(.horizontal, IkeruTheme.Spacing.md)
                        .padding(.top, IkeruTheme.Spacing.md)
                        .padding(.bottom, IkeruTheme.Spacing.lg)
                }
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
