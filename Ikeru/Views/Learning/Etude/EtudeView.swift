import SwiftUI
import IkeruCore
import SwiftData

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

    /// Presenting this (non-nil) drives the chat cover via `.fullScreenCover(item:)`.
    @State private var conversationViewModel: ConversationViewModel?

    // Calm progress signals (replace the old gamified XP chrome): how much
    // kana is learned, and how many words you've collected. Nil until loaded.
    @State private var kanaProgress: KanaProgress?
    @State private var vocabSavedCount: Int?

    var body: some View {
        ZStack {
            IkeruScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    kanaRow
                    vocabularyRow
                    sakuraRow
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 140)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadProgress() }
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

    private var kanaRow: some View {
        NavigationLink {
            KanaPoolSelectorView()
        } label: {
            exploreRow(kanji: "\u{304B}\u{306A}", title: "Kana",
                       subtitle: "Hiragana & katakana",
                       stat: kanaProgress.map { "\($0.total)/\(KanaProgress.grandTotal)" })
        }
        .buttonStyle(.plain)
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
            vocabularyRepository: vocabRepo
        )
    }
}
