import SwiftUI
import IkeruCore

// MARK: - WatchHomeView

/// Root view for the Watch app showing available nano-sessions.
struct WatchHomeView: View {

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    KanaQuizView()
                } label: {
                    Label("Kana Quiz", systemImage: "character.ja")
                }

                NavigationLink {
                    HapticPitchDrillView()
                } label: {
                    Label("Pitch Accent", systemImage: "waveform")
                }
            }
            .navigationTitle("Ikeru")
        }
    }
}

#Preview {
    WatchHomeView()
}
