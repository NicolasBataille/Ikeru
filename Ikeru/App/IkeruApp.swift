import SwiftUI
import SwiftData
import IkeruCore
import os

@main
struct IkeruApp: App {

    @State private var toastManager = ToastManager()
    @State private var profileViewModel: ProfileViewModel?
    @State private var showOnboarding = false
    @State private var hasCheckedProfile = false
    @State private var aiRouterService = AIRouterService()

    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                UserProfile.self,
                Card.self,
                ReviewLog.self,
                RPGState.self,
                MnemonicCache.self,
                CompanionChatMessage.self,
            ])
            let config = ModelConfiguration(
                "Ikeru",
                schema: schema
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [config]
            )
        } catch {
            Logger.srs.critical("Failed to create ModelContainer: \(error)")
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            mainContent
                .preferredColorScheme(.dark)
                .environment(\.toastManager, toastManager)
                .environment(\.profileViewModel, profileViewModel)
                .environment(\.aiRouterService, aiRouterService)
                .toastOverlay()
                .task {
                    initializeProfileViewModel()
                }
        }
        .modelContainer(modelContainer)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if hasCheckedProfile {
            MainTabView()
                .fullScreenCover(isPresented: $showOnboarding) {
                    NameEntryView()
                        .environment(\.profileViewModel, profileViewModel)
                        .onDisappear {
                            // Reload profile after onboarding dismisses
                            profileViewModel?.loadProfile()
                        }
                }
        } else {
            // Brief loading state while checking profile
            ZStack {
                Color.ikeruBackground
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Profile Initialization

    @MainActor
    private func initializeProfileViewModel() {
        let viewModel = ProfileViewModel(modelContext: modelContainer.mainContext)
        profileViewModel = viewModel

        if viewModel.hasProfile {
            Logger.ui.info("Existing profile found — skipping onboarding")
            showOnboarding = false
        } else {
            Logger.ui.info("No profile found — showing onboarding")
            showOnboarding = true
        }

        hasCheckedProfile = true
    }
}
