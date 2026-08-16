import SwiftUI
import IkeruCore

// MARK: - KanaDrillModeSelector

/// Intermediate screen between the pool selector and the actual drill view.
/// Lets the user choose between the deep-learning Flashcard mode and the
/// rapid 4-choice Quiz mode.
struct KanaDrillModeSelector: View {

    @Environment(\.modelContext) private var modelContext
    let mode: KanaDrillMode
    let groups: Set<KanaGroup>
    /// Restricts every card refresh to these fronts within `groups`. Used by
    /// the confusion-pair drills (chantier #24b): repository queries are
    /// group-scoped, so seeding/fetching pulls in the whole group, and this
    /// filter is what keeps `refreshCards()` from re-widening the queue back
    /// out to the full group on every appear. `nil` (default) preserves the
    /// existing behaviour for the three main drill buttons.
    let characterFilter: Set<String>?
    /// Overrides `mode.displayName` in the header and is threaded through to
    /// the Flashcard/Quiz view models. `nil` (default) preserves the
    /// existing mode-name display.
    let sessionLabel: LocalizedStringKey?

    /// Live queue for this mode. Seeded from the snapshot captured when the
    /// drill was launched, then refreshed on every appear (including pop-back
    /// from a finished drill) so the "N cards ready" count and the queue handed
    /// to the drill reflect the current SRS state — not a frozen snapshot that
    /// keeps re-offering cards the user already graded.
    @State private var cards: [CardDTO]

    @State private var goFlashcard = false
    @State private var goQuiz = false
    /// Refreshed on each drill launch so SwiftUI rebuilds the destination
    /// view with a brand-new `@State`. Without this, re-entering the drill
    /// reuses the previously-shuffled queue — which is what made the user
    /// see the same hiragana order every time.
    @State private var runId: UUID = UUID()

    init(
        mode: KanaDrillMode,
        groups: Set<KanaGroup>,
        cards: [CardDTO],
        characterFilter: Set<String>? = nil,
        sessionLabel: LocalizedStringKey? = nil
    ) {
        self.mode = mode
        self.groups = groups
        self.characterFilter = characterFilter
        self.sessionLabel = sessionLabel
        _cards = State(initialValue: cards)
    }

    private var cardRepository: CardRepository {
        CardRepository(modelContainer: modelContext.container)
    }

    private var vocabularyRepository: VocabularyRepository {
        VocabularyRepository(modelContainer: modelContext.container)
    }

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.lg) {
                header
                modeCard(
                    title: "Flashcard",
                    subtitle: "Classic SRS review",
                    description: "Tap to reveal the answer, then grade your recall. Ideal for long-term retention.",
                    icon: "rectangle.on.rectangle.angled",
                    accessibilityID: "kanaDrillMode.flashcard",
                    action: {
                        runId = UUID()
                        goFlashcard = true
                    }
                )
                modeCard(
                    title: "Quiz",
                    subtitle: "4 quick choices",
                    description: "Recognise the romaji among 4 options. Bonus for quick correct answers.",
                    icon: "checkmark.circle.badge.questionmark",
                    accessibilityID: "kanaDrillMode.quiz",
                    action: {
                        runId = UUID()
                        goQuiz = true
                    }
                )
                Spacer()
            }
            .padding(IkeruTheme.Spacing.lg)
            .padding(.bottom, 88) // Floating tab bar clearance
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Mode")
        .onAppear {
            // Runs on first appear and on every pop-back from a finished drill,
            // so the count and queue reflect the live SRS state rather than the
            // snapshot captured when the drill was launched.
            Task { await refreshCards() }
        }
        .navigationDestination(isPresented: $goFlashcard) {
            KanaFlashcardView(viewModel: KanaDrillViewModel(
                mode: mode,
                queue: cards,
                cardRepository: cardRepository,
                vocabularyRepository: vocabularyRepository,
                sessionLabel: sessionLabel
            ))
            .id(runId)
        }
        .navigationDestination(isPresented: $goQuiz) {
            KanaQuizView(viewModel: KanaDrillViewModel(
                mode: mode,
                queue: cards,
                cardRepository: cardRepository,
                vocabularyRepository: vocabularyRepository,
                sessionLabel: sessionLabel
            ))
            .id(runId)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TRAINING MODE")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
            Text(sessionLabel ?? LocalizedStringKey(mode.displayName))
                .font(.ikeruDisplaySmall)
                .ikeruTracking(.display)
                .foregroundStyle(Color.ikeruTextPrimary)
            Text("\(cards.count) cards ready")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextSecondary)
        }
    }

    private func refreshCards() async {
        let kanaRepo = KanaCardRepository(cardRepository: cardRepository)
        var result: [CardDTO]
        switch mode {
        case .dueReview:
            result = await kanaRepo.dueCardsForGroups(groups, now: Date())
        case .freePractice:
            result = await kanaRepo.cardsForGroups(groups)
        case .weakReinforcement:
            result = await kanaRepo.weakCardsForGroups(groups)
        }
        if let characterFilter {
            result = result.filter { characterFilter.contains($0.front) }
        }
        cards = result
    }

    @ViewBuilder
    private func modeCard(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        description: LocalizedStringKey,
        icon: String,
        accessibilityID: String,
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
        .tatamiRoom(.standard)
        .disabled(cards.isEmpty)
        .opacity(cards.isEmpty ? 0.5 : 1.0)
        // GAP-01 two-client merge test: this "Mode" screen sits between
        // `KanaPoolSelectorView`'s drill buttons and the actual
        // `KanaQuizView`/`KanaFlashcardView` — measured, not assumed to be
        // a direct navigation.
        .accessibilityIdentifier(accessibilityID)
    }
}
