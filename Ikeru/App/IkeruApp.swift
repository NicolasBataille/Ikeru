import SwiftUI
import SwiftData
import IkeruCore
import os

@main
struct IkeruApp: App {

    @State private var toastManager = ToastManager()

    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                UserProfile.self,
                Card.self,
                ReviewLog.self,
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
            MainTabView()
                .preferredColorScheme(.dark)
                .environment(\.toastManager, toastManager)
                .toastOverlay()
                .task {
                    await seedDefaultProfileIfNeeded()
                }
        }
        .modelContainer(modelContainer)
    }

    /// Creates a default UserProfile on first launch if none exists.
    @MainActor
    private func seedDefaultProfileIfNeeded() async {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<UserProfile>()
        let existingProfiles = (try? context.fetch(descriptor)) ?? []

        if existingProfiles.isEmpty {
            let defaultProfile = UserProfile(displayName: "Learner")
            context.insert(defaultProfile)
            try? context.save()
            Logger.srs.info("Created default user profile")
        }
    }
}
