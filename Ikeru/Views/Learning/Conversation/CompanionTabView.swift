import SwiftUI
import SwiftData
import IkeruCore

// MARK: - Companion Tab View

/// Entry point for the Companion tab. Initializes the conversation
/// ViewModel with the user's JLPT level and AI router.
struct CompanionTabView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ConversationViewModel?

    var body: some View {
        Group {
            if let viewModel {
                ConversationView(viewModel: viewModel)
            } else {
                loadingPlaceholder
            }
        }
        .task {
            initializeViewModel()
        }
    }

    // MARK: - Loading Placeholder

    private var loadingPlaceholder: some View {
        ZStack {
            IkeruScreenBackground()

            VStack(spacing: IkeruTheme.Spacing.lg) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(LinearGradient.ikeruGold)

                VStack(spacing: 6) {
                    Text("YOUR PARTNER")
                        .font(.ikeruMicro)
                        .ikeruTracking(.micro)
                        .foregroundStyle(Color.ikeruTextTertiary)

                    Text("Companion")
                        .font(.ikeruDisplaySmall)
                        .ikeruTracking(.display)
                        .foregroundStyle(Color.ikeruTextPrimary)

                    Text("Preparing your conversation…")
                        .font(.ikeruBody)
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
            }
            .padding(IkeruTheme.Spacing.xl)
            .ikeruCard(.companion)
            .padding(.horizontal, IkeruTheme.Spacing.lg)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Initialization

    private func initializeViewModel() {
        guard viewModel == nil else { return }

        let jlptLevel = loadJLPTLevel()
        let aiRouter = AIRouterService()
        let conversationService = ConversationService(aiRouter: aiRouter)

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

// MARK: - Preview

#Preview("Companion Tab") {
    NavigationStack {
        CompanionTabView()
    }
    .preferredColorScheme(.dark)
}
