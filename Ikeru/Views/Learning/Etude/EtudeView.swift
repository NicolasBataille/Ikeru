import SwiftUI
import IkeruCore
import SwiftData
import os

// MARK: - ExploreView
//
// The "Explore" tab (学習). Replaces the old Étude practice-ground grid (11
// tiles, 9 of which led to placeholder exercises) with a short, honest list of
// the surfaces that actually work today: the kana drill, the N5 vocabulary
// dictionary, and the Sakura AI conversation partner. No grid, no locked tiles,
// no JLPT hero that reads 0% on day one.
//
// (File is still named EtudeView.swift for pbxproj continuity; the struct is
// ExploreView. A pure file rename can follow later.)

struct ExploreView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.aiRouterService) private var aiRouterService
    @Environment(\.profileViewModel) private var profileViewModel

    /// Presenting this (non-nil) drives the chat cover via `.fullScreenCover(item:)`.
    @State private var conversationViewModel: ConversationViewModel?

    // Calm progress signals (replace the old gamified XP chrome): how much
    // kana is learned, and how many words you've collected. Nil until loaded.
    @State private var kanaProgress: KanaProgress?
    @State private var vocabSavedCount: Int?
    @State private var grammarCount: Int?
    @State private var importCount: Int?
    /// Un texte est arrivé par l'extension de partage et attend.
    @State private var hasSharedText = false

    // « Composer une séance » — the opt-in door (see `ComposeSessionSheet`).
    // The session view model is built the way `HomeView` builds its own, and
    // the cover follows the same `isActive` contract.
    @State private var composeViewModel: ComposeSessionViewModel?
    @State private var sessionViewModel: SessionViewModel?
    /// The session cover, presented with `item:` — see `composedSession`'s
    /// `.fullScreenCover` below for why `isPresented:` + `if let` is not an
    /// option here (measured: an empty black cover).
    @State private var composedSession: ComposedSessionPresentation?
    /// Set by `startComposedSession` when a session actually started; the
    /// cover is presented from the sheet's `onDismiss`, never while the
    /// sheet is still up — two modals at once, SwiftUI shows neither.
    @State private var sessionPendingAfterCompose = false

    var body: some View {
        ZStack {
            IkeruScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    composeRow
                    kanaRow
                    vocabularyRow
                    grammarRow
                    textImportRow
                    sakuraRow
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 140)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadProgress() }
        // The dictionary and the imports are per-profile since IkeruSchemaV6,
        // and this tab stays mounted across a profile switch: without a
        // reload, the counts below would keep showing the PREVIOUS profile's
        // words — OBS2-022's leak, in its transient form. Same signal
        // `HomeView` already reloads on.
        .onReceive(NotificationCenter.default.publisher(for: .ikeruActiveProfileDidChange)) { _ in
            Task { await loadProgress() }
        }
        // `item:`, not `isPresented:` + `if let` — that pair raced and
        // presented an EMPTY sheet (measured on simulator 2026-09-10, the same
        // trap the conversation cover below had already hit). Assigning the
        // view model IS the presentation, so the content is never handed nil.
        .sheet(item: $composeViewModel, onDismiss: {
            if sessionPendingAfterCompose, let svm = sessionViewModel {
                sessionPendingAfterCompose = false
                composedSession = ComposedSessionPresentation(viewModel: svm)
            }
        }) { cvm in
            ComposeSessionSheet(viewModel: cvm) {
                await startComposedSession()
            }
        }
        // `item:` here too. `isPresented:` + `if let svm = sessionViewModel`
        // presented an EMPTY black cover on simulator (2026-09-10) even
        // though the session had started (its Live Activity was up) — the
        // content closure saw nil. Same trap, same cure as the sheet above.
        .fullScreenCover(item: $composedSession) { presentation in
            ActiveSessionView(viewModel: presentation.viewModel)
                .onChange(of: presentation.viewModel.isActive) { _, isActive in
                    if !isActive {
                        composedSession = nil
                        Task { await loadProgress() }
                    }
                }
        }
        .fullScreenCover(item: $conversationViewModel) { cvm in
            ZStack(alignment: .topLeading) {
                // `item:` guarantees `cvm` is non-nil here (the old isPresented +
                // optional `if let` raced and presented an empty black screen).
                // NavigationStack so the in-view "Configure AI" link works.
                NavigationStack {
                    ConversationView(viewModel: cvm)
                }

                // Explicit close button — an overlay that does NOT depend on the
                // navigation bar rendering, so there is always a visible way out.
                Button {
                    conversationViewModel = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.ikeruTextPrimary)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(
                            Circle().strokeBorder(TatamiTokens.goldDim.opacity(0.5), lineWidth: 1)
                        )
                }
                .accessibilityLabel("Close")
                .padding(.leading, 16)
                .padding(.top, 10)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            BilingualLabel(japanese: "\u{5B66}\u{7FD2}", chrome: "Explore")
            Text("Choose what to practice")
                .ikeruScaledFont(24, weight: .light, design: .serif, relativeTo: .title)
                .foregroundStyle(Color.ikeruTextPrimary)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Rows

    /// The opt-in door. Every other row is a surface; this one is a session
    /// the learner assembles — the counterpart of the home session, which
    /// chooses for them.
    private var composeRow: some View {
        Button {
            presentCompose()
        } label: {
            exploreRow(kanji: "\u{81EA}\u{7531}", title: "Compose a session",
                       subtitle: "Choose your exercises and duration")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("explore.composeRow")
    }

    private var kanaRow: some View {
        NavigationLink {
            KanaPoolSelectorView()
        } label: {
            exploreRow(kanji: "\u{304B}\u{306A}", title: "Kana",
                       subtitle: "Hiragana & katakana",
                       stat: kanaProgress.map { "\($0.total)/\(KanaProgress.grandTotal)" })
        }
        .buttonStyle(.plain)
        // GAP-01 two-client merge test: the only reachable path from Explore
        // into `KanaPoolSelectorView`, where a specific kana group can be
        // selected and drilled deterministically (see `KanaGroupCard`'s and
        // `KanaPoolSelectorView.drillButton`'s identifiers, added for the
        // same effort).
        .accessibilityIdentifier("explore.kanaRow")
    }

    private var vocabularyRow: some View {
        NavigationLink {
            VocabularyDictionaryView()
        } label: {
            exploreRow(kanji: "\u{8A9E}\u{5F59}", title: "Vocabulary",
                       subtitle: "Your saved words",
                       stat: vocabSavedCount.flatMap { $0 > 0 ? "\($0)" : nil })
        }
        .buttonStyle(.plain)
    }

    /// Grammaire — la surface qui manquait. Les 51 points existaient dans le
    /// bundle sans qu'aucune vue ne les affiche (verifie 2026-08-19).
    private var grammarRow: some View {
        NavigationLink {
            GrammarListView()
        } label: {
            exploreRow(kanji: "\u{6587}\u{6CD5}", title: "Grammar",
                       subtitle: "Sentence patterns",
                       stat: grammarCount.flatMap { $0 > 0 ? "\($0)" : nil })
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("explore.grammarRow")
    }

    /// « Apporte ton propre texte » — la porte par laquelle le japonais
    /// rencontré dehors entre dans l'app. Placée juste avant Sakura : les deux
    /// lignes du bas sont celles où l'apprenant amène quelque chose à lui,
    /// plutôt que de consommer du contenu curaté.
    private var textImportRow: some View {
        NavigationLink {
            TextImportFlowView()
        } label: {
            // Le sous-titre change quand un texte partagé attend : c'est la
            // seule trace visible du partage, puisqu'une extension ne peut pas
            // ouvrir l'app elle-même (voir `SharedTextInbox`).
            exploreRow(kanji: "\u{8AAD}\u{89E3}", title: "Your own text",
                       subtitle: hasSharedText
                           ? "A shared text is waiting"
                           : "Paste or photograph Japanese",
                       stat: importCount.flatMap { $0 > 0 ? "\($0)" : nil })
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("explore.textImportRow")
    }

    private var sakuraRow: some View {
        Button {
            presentConversation()
        } label: {
            exploreRow(kanji: "\u{5BFE}\u{8A71}", title: "Talk with Sakura",
                       subtitle: "AI conversation partner")
        }
        .buttonStyle(.plain)
    }

    /// Shared row chrome: serif kanji eyebrow, bilingual title, subtitle,
    /// an optional progress stat (e.g. "46/92"), and a chevron.
    private func exploreRow(kanji: String, title: LocalizedStringKey,
                            subtitle: LocalizedStringKey,
                            stat: String? = nil) -> some View {
        HStack(spacing: IkeruTheme.Spacing.md) {
            Text(kanji)
                .font(.system(size: 24, weight: .light, design: .serif))
                .foregroundStyle(Color.ikeruPrimaryAccent)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .ikeruScaledFont(16, weight: .regular, relativeTo: .body)
                    .foregroundStyle(Color.ikeruTextPrimary)
                Text(subtitle)
                    .ikeruScaledFont(12, relativeTo: .caption2)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
            Spacer()
            if let stat {
                Text(stat)
                    .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.ikeruPrimaryAccent)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TatamiTokens.goldDim)
        }
        .padding(.vertical, IkeruTheme.Spacing.sm)
        .contentShape(Rectangle())
        .tatamiRoom(.standard, padding: 16)
    }

    // MARK: - Progress

    /// Loads calm progress counts from the card + vocabulary stores. Kana
    /// mastery powers "X/92"; the vocabulary collection size powers the saved-
    /// words stat. Both stay nil (no stat shown) until the first load lands.
    private func loadProgress() async {
        let container = modelContext.container
        let cards = await CardRepository(modelContainer: container).allCards()
        let vocab = await VocabularyRepository(modelContainer: container).allEntries()
        kanaProgress = KanaProgress.from(cards: cards)
        vocabSavedCount = vocab.count
        // Compte lu depuis le bundle, pas code en dur : si le contenu s'enrichit
        // la ligne suit, et s'il manque la ligne s'affiche sans chiffre.
        grammarCount = await Self.makeContentRepository()?
            .grammarPointsByLevel(.n5).count
        importCount = await TextImportRepository(modelContainer: container).all().count
        hasSharedText = SharedTextInbox().hasPending
    }

    // MARK: - Compose

    private func presentCompose() {
        let container = modelContext.container
        let repo = CardRepository(modelContainer: container)
        if sessionViewModel == nil {
            sessionViewModel = SessionViewModel(
                plannerService: PlannerService(cardRepository: repo),
                cardRepository: repo,
                modelContainer: container,
                contentRepository: Self.makeContentRepository()
            )
        }
        // Rebuilt on every open: the offer list must reflect the snapshot of
        // NOW (a drill unlocked by the last session shows up unlocked).
        composeViewModel = ComposeSessionViewModel(
            cardRepository: repo,
            modelContainer: container,
            contentRepository: Self.makeContentRepository()
        )
    }

    /// `true` only if a session actually started — see
    /// `SessionViewModel.startStudyCustomSession`. The sheet stays open
    /// otherwise and says why.
    private func startComposedSession() async -> Bool {
        guard let composeViewModel, let svm = sessionViewModel else { return false }
        let started = await composeViewModel.start(on: svm)
        if started {
            // The sheet dismisses itself on `true`; the cover follows from
            // its `onDismiss` (see the `.sheet` above).
            sessionPendingAfterCompose = true
        }
        return started
    }

    // MARK: - Conversation

    private func presentConversation() {
        // Build the view model and assign it — with `.fullScreenCover(item:)`
        // that assignment IS what presents the cover, so the content can never
        // be handed a nil model.
        let router = aiRouterService ?? AIRouterService()
        let service = ConversationService(aiRouter: router)
        let vocabRepo = VocabularyRepository(modelContainer: modelContext.container)
        conversationViewModel = ConversationViewModel(
            conversationService: service,
            jlptLevel: .n5,
            vocabularyRepository: vocabRepo,
            contentRepository: Self.makeContentRepository(),
            // Le prénom demandé au premier écran de l'onboarding, enfin
            // transmis à Sakura (OBS2-028). Vide si aucun profil n'est
            // résolu — le prompt est alors inchangé.
            learnerName: profileViewModel?.displayName ?? ""
        )
    }

    /// Resolves the bundled `n5-content.sqlite` and builds a read-only
    /// `ContentRepository` so Sakura can validate the furigana she suggests
    /// against curated readings (remediation 6.7). Fail-safe: a missing
    /// resource logs and returns nil, and reading-validation simply no-ops.
    private static func makeContentRepository() -> ContentRepository? {
        BundledContent.makeRepository()
    }
}

/// Identity for the composed-session cover. The `SessionViewModel` is
/// long-lived (rebuilt only on the first open), so the identity belongs to
/// the presentation, not to the model.
private struct ComposedSessionPresentation: Identifiable {
    let id = UUID()
    let viewModel: SessionViewModel
}
