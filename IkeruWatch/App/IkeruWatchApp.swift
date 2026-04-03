import SwiftUI

@main
struct IkeruWatchApp: App {

    @StateObject private var sessionManager = WatchSessionManager.shared

    init() {
        WatchSessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(sessionManager)
        }
    }
}
