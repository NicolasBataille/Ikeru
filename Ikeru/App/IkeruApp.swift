import SwiftUI

@main
struct IkeruApp: App {

    @State private var toastManager = ToastManager()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.dark)
                .environment(\.toastManager, toastManager)
                .toastOverlay()
        }
    }
}
