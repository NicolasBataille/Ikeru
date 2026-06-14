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

    @State private var conversationViewModel: ConversationViewModel?
    @State private var showConversation = false

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
        .fullScreenCover(isPresented: $showConversation) {
            if let cvm = conversationViewModel {
                ConversationView(viewModel: cvm)
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
                       subtitle: "Hiragana & katakana")
        }
        .buttonStyle(.plain)
    }

    private var vocabularyRow: some View {
        NavigationLink {
            VocabularyDictionaryView()
        } label: {
            exploreRow(kanji: "\u{8A9E}\u{5F59}", title: "Vocabulary",
                       subtitle: "N5 dictionary & drills")
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

    /// Shared row chrome: serif kanji eyebrow, bilingual title, subtitle, chevron.
    private func exploreRow(kanji: String, title: LocalizedStringKey,
                            subtitle: LocalizedStringKey) -> some View {
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
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TatamiTokens.goldDim)
        }
        .padding(.vertical, IkeruTheme.Spacing.sm)
        .contentShape(Rectangle())
        .tatamiRoom(.standard, padding: 16)
    }

    // MARK: - Conversation

    private func presentConversation() {
        if conversationViewModel == nil {
            let router = aiRouterService ?? AIRouterService()
            let service = ConversationService(aiRouter: router)
            let vocabRepo = VocabularyRepository(modelContainer: modelContext.container)
            conversationViewModel = ConversationViewModel(
                conversationService: service,
                jlptLevel: .n5,
                vocabularyRepository: vocabRepo
            )
        }
        showConversation = true
    }
}
