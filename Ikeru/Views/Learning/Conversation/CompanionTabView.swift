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
            Color.ikeruBackground.ignoresSafeArea()

            VStack(spacing: IkeruTheme.Spacing.md) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.ikeruPrimaryAccent)

                Text("Companion")
                    .font(.ikeruHeading1)
                    .foregroundStyle(.white)
            }
        }
        .navigationTitle("Companion")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Initialization

    private func initializeViewModel() {
        guard viewModel == nil else { return }

        let jlptLevel = loadJLPTLevel()
        let aiRouter = AIRouterService()
        let conversationService = ConversationService(aiRouter: aiRouter)

        viewModel = ConversationViewModel(
            conversationService: conversationService,
            jlptLevel: jlptLevel
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
