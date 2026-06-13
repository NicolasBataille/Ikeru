import SwiftUI
import SwiftData
import IkeruCore

// MARK: - Companion Tab View
//
// Tatami-direction Companion landing screen. Presents the Sakura tutor
// hero card, suggested topics, and recent conversations. Tapping the
// "BEGIN CONVERSATION" CTA (or any topic / recent row) opens the
// existing `ConversationView` chat surface as a fullScreenCover so
// the live chat experience is preserved.

struct CompanionTabView: View {

    @Environment(\.modelContext) private var modelContext
    /// The shared router injected at the app level (IkeruApp). Using the same
    /// instance as AISettingsView ensures that a refreshTierStatuses() call from
    /// Settings is visible here, and vice-versa — both surfaces stay in sync.
    @Environment(\.aiRouterService) private var aiRouterService
    @State private var viewModel: ConversationViewModel?
    @State private var showConversation = false
    @State private var hasCheckedAI = false
    @State private var aiAvailable = false

    var body: some View {
        ZStack {
            IkeruScreenBackground(variant: .auxiliary)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if hasCheckedAI && !aiAvailable {
                        noAIBanner
                    }
                    tutorCard
                    suggestedTopics
                    recentConversations
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 140)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            initializeViewModel()
            await refreshAIAvailability()
        }
        // Re-probe each time the tab becomes visible so settings changes
        // (e.g., user just deleted a provider key) are reflected immediately.
        .onAppear {
            Task { await refreshAIAvailability() }
        }
        .fullScreenCover(isPresented: $showConversation) {
            if let viewModel {
                NavigationStack {
                    ConversationView(viewModel: viewModel)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    showConversation = false
                                } label: {
                                    Image(systemName: "xmark")
                                        .foregroundStyle(Color.ikeruTextPrimary)
                                }
                            }
                        }
                }
                .preferredColorScheme(.dark)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            BilingualLabel(japanese: "対話", chrome: "Talk")
            // Sakura name is the same in EN and FR — literal string.
            Text("Sakura、 your sensei。")
                .ikeruScaledFont(28, weight: .light, design: .serif, relativeTo: .title2)
                .foregroundStyle(Color.ikeruTextPrimary)
        }
    }

    // MARK: - Tutor Card

    private var tutorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Rectangle().fill(LinearGradient(
                        colors: [
                            Color(red: 0.165, green: 0.133, blue: 0.102),
                            Color(red: 0.078, green: 0.067, blue: 0.051)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim, lineWidth: 1))
                    Text("桜")
                        .font(.system(size: 28, weight: .light, design: .serif))
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                }
                .frame(width: 64, height: 64)
                .sumiCorners(color: .ikeruPrimaryAccent, size: 8, weight: 1.2, inset: -1)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sakura")
                        .ikeruScaledFont(16, weight: .semibold, relativeTo: .body)
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Text("Patient. Specialty: keigo",
                         comment: "Sakura tutor description")
                        .ikeruScaledFont(11, relativeTo: .caption)
                        .italic()
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    MonCrest(kind: .maru, size: 10,
                             color: Color(red: 0.616, green: 0.729, blue: 0.486))
                    Text("ONLINE", comment: "Tutor status")
                        .ikeruScaledFont(10, weight: .semibold, relativeTo: .caption2)
                        .foregroundStyle(Color.ikeruTextSecondary)
                        .tracking(1.2)
                }
            }

            Button { onBeginConversation() } label: {
                HStack {
                    Spacer()
                    Text("会話を始める · ")
                        .ikeruScaledFont(13, weight: .regular, design: .serif, relativeTo: .caption)
                    Text("BEGIN CONVERSATION", comment: "Companion CTA")
                        .ikeruScaledFont(13, weight: .bold, relativeTo: .caption)
                        .tracking(1.6)
                    Spacer()
                }
                .foregroundStyle(Color.ikeruBackground)
                .padding(.vertical, 14)
                .background(aiAvailable ? Color.ikeruPrimaryAccent : Color.ikeruPrimaryAccent.opacity(0.35))
                .sumiCorners(color: Color.ikeruBackground.opacity(0.6),
                             size: 6, weight: 1.2, inset: -1)
            }
            .buttonStyle(.plain)
            .disabled(!aiAvailable)
        }
        .tatamiRoom(.glass, padding: 20)
    }

    // MARK: - Suggested Topics

    private var suggestedTopics: some View {
        VStack(alignment: .leading, spacing: 0) {
            BilingualLabel(japanese: "話題", chrome: "Suggested topics", mon: .genji)
                .padding(.bottom, 10)
            ForEach(Array(Self.demoTopics.enumerated()), id: \.offset) { index, row in
                topicRow(row, isFirst: index == 0)
            }
        }
    }

    @ViewBuilder
    private func topicRow(_ row: DemoConversationTopicRow, isFirst: Bool) -> some View {
        Button {
            onTopicTap(row.topic)
        } label: {
            topicRowLabel(row, isFirst: isFirst)
        }
        .buttonStyle(.plain)
        .disabled(!aiAvailable)
        .opacity(aiAvailable ? 1 : 0.45)
    }

    @ViewBuilder
    private func topicRowLabel(_ row: DemoConversationTopicRow, isFirst: Bool) -> some View {
        Group {
            HStack(spacing: 12) {
                MonCrest(kind: row.mon, size: 14, color: .ikeruPrimaryAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.topic.japanese)
                        .ikeruScaledFont(15, design: .serif, relativeTo: .body)
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Text(row.topic.english)
                        .ikeruScaledFont(11, relativeTo: .caption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
                Spacer()
                Text(row.topic.jlptLevel)
                    .ikeruScaledFont(11, design: .serif, relativeTo: .caption)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim, lineWidth: 1))
                Text("›")
                    .font(.system(size: 14))
                    .foregroundStyle(TatamiTokens.goldDim)
            }
            .padding(.vertical, 14).padding(.horizontal, 4)
            .overlay(alignment: .top) {
                if isFirst {
                    Rectangle().fill(TatamiTokens.goldDim.opacity(0.7)).frame(height: 1)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.ikeruPrimaryAccent.opacity(0.3)).frame(height: 1)
            }
        }
    }

    // MARK: - Recent Conversations

    private var recentConversations: some View {
        VStack(alignment: .leading, spacing: 10) {
            BilingualLabel(japanese: "履歴", chrome: "Recent conversations", mon: .kikkou)
            ForEach(Self.demoRecent, id: \.id) { conv in
                HStack {
                    Text(conv.dateJP)
                        .ikeruScaledFont(12, design: .serif, relativeTo: .caption)
                        .foregroundStyle(TatamiTokens.paperGhost)
                        .frame(minWidth: 40, alignment: .leading)
                    Text(conv.topic)
                        .ikeruScaledFont(13, relativeTo: .caption)
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Spacer()
                    Text("\(conv.minutes)分")
                        .ikeruScaledFont(11, design: .serif, relativeTo: .caption)
                        .foregroundStyle(TatamiTokens.paperGhost)
                }
                .padding(.vertical, 12).padding(.horizontal, 4)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(TatamiTokens.goldDim.opacity(0.2)).frame(height: 1)
                }
            }
        }
    }

    // MARK: - No-AI Banner

    private var noAIBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.ikeruWarning)
            VStack(alignment: .leading, spacing: 4) {
                Text("Sakura.NoAI.BannerTitle")
                    .ikeruScaledFont(14, weight: .semibold, relativeTo: .body)
                    .foregroundStyle(Color.ikeruTextPrimary)
                Text("Sakura.NoAI.BannerBody")
                    .ikeruScaledFont(12, relativeTo: .caption)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.ikeruWarning.opacity(0.08))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ikeruWarning.opacity(0.4)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.ikeruWarning.opacity(0.4)).frame(height: 1)
        }
        .sumiCorners(color: Color.ikeruWarning.opacity(0.7), size: 7, weight: 1.1)
    }

    // MARK: - Actions

    private func onBeginConversation() {
        guard viewModel != nil else { return }
        showConversation = true
    }

    private func onTopicTap(_ topic: ConversationTopic) {
        guard let vm = viewModel else { return }
        // Seed the conversation with the selected topic so the chat opens
        // directly on that subject rather than showing the welcome screen.
        vm.seedTopic = topic
        showConversation = true
    }

    private func refreshAIAvailability() async {
        guard let vm = viewModel else { return }
        await vm.onAppear()
        aiAvailable = vm.isAIAvailable
        hasCheckedAI = true
    }

    // MARK: - Initialization

    private func initializeViewModel() {
        guard viewModel == nil else { return }

        // Use the shared AIRouterService from the environment so Settings and the
        // conversation screen operate on the same provider-status state. Creating a
        // local AIRouterService() here previously caused the two surfaces to diverge:
        // Settings could show a green dot while the conversation's private instance
        // had already marked every provider as unavailable (or vice-versa).
        let router = aiRouterService ?? AIRouterService()
        let conversationService = ConversationService(aiRouter: router)

        let jlptLevel = loadJLPTLevel()
        let vocabRepo = VocabularyRepository(modelContainer: modelContext.container)
        viewModel = ConversationViewModel(
            conversationService: conversationService,
            jlptLevel: jlptLevel,
            vocabularyRepository: vocabRepo
        )
    }

    /// Load the user's JLPT level from their profile, defaulting to N5.
    private func loadJLPTLevel() -> JLPTLevel {
        let descriptor = FetchDescriptor<UserProfile>()
        let profiles = (try? modelContext.fetch(descriptor)) ?? []

        // For now, default to N5. When ProfileSettings gains a jlptLevel field,
        // this will read from the profile.
        guard profiles.first != nil else {
            return .n5
        }
        return .n5
    }
}

// MARK: - Demo Data
//
// Placeholders for the suggested-topics and recent-conversations rails.
// `ConversationViewModel` does not yet expose these affordances, so the
// rows render against a static demo set — same pattern used by Streak
// (T4), Achievements (T7), and Decks (T8). Replace with real VM data
// when the conversation routing / history APIs land.

// ConversationTopic is defined in ConversationViewModel.swift.
// DemoConversationTopicRow wraps it with the UI-only mon crest kind.
private struct DemoConversationTopicRow: Hashable {
    let topic: ConversationTopic
    let mon: MonKind
}

private struct DemoRecentConversation: Hashable {
    let id: String
    let dateJP: String
    let topic: String
    let minutes: Int
}

extension CompanionTabView {
    fileprivate static let demoTopics: [DemoConversationTopicRow] = [
        .init(topic: .init(japanese: "自己紹介", english: "Self-introduction", jlptLevel: "N5"),
              mon: .maru),
        .init(topic: .init(japanese: "道を尋ねる", english: "Asking for directions", jlptLevel: "N4"),
              mon: .asanoha),
        .init(topic: .init(japanese: "敬語の練習", english: "Keigo practice", jlptLevel: "N3"),
              mon: .genji),
        .init(topic: .init(japanese: "仕事の話", english: "Work conversation", jlptLevel: "N3"),
              mon: .kikkou)
    ]

    fileprivate static let demoRecent: [DemoRecentConversation] = [
        .init(id: "r1", dateJP: "昨日",
              topic: "Self-introduction", minutes: 12),
        .init(id: "r2", dateJP: "一昨日",
              topic: "Asking for directions", minutes: 8),
        .init(id: "r3", dateJP: "三日前",
              topic: "Keigo practice", minutes: 15)
    ]
}

// MARK: - Preview

#Preview("Companion Tab") {
    NavigationStack {
        CompanionTabView()
    }
    .preferredColorScheme(.dark)
}
