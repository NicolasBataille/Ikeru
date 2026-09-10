import SwiftUI
import IkeruCore

// MARK: - ListenButton
//
// Speaker button that plays a bundled clip, falling back to on-device
// synthesis. Same visual language as `SRSCardView.kanaListenButton`, which is
// the pattern this follows rather than reinventing.

/// Plays `text` through `AudioService`.
///
/// ## Play the reading, not the written form
///
/// For a vocabulary word, pass the **reading** (`みず`), not the word (`水`).
/// Measured 2026-08-19: the bundled clips are generated from readings and
/// sentences, so `みず` has an `.m4a` while `水` has none. Passing the kanji
/// still "works" — `AudioService.playTTS` falls back to on-device synthesis —
/// but it trades a VOICEVOX clip for a synthesised one, and the synthesiser can
/// pick the wrong reading for a lone kanji, which is exactly the mistake a
/// learner would then copy.
///
/// A word with no reading (some conversation entries) falls back to the word
/// itself: a synthesised guess beats a dead button.
struct ListenButton: View {

    let text: String
    var diameter: CGFloat = 42
    var glyphSize: CGFloat = 15

    @State private var audioService = AudioService()

    var body: some View {
        Button {
            let spoken = text
            Task { await audioService.playTTS(text: spoken) }
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(Color.ikeruPrimaryAccent)
                .frame(width: diameter, height: diameter)
                .background(Color.ikeruPrimaryAccent.opacity(0.08))
                .overlay(Circle().strokeBorder(TatamiTokens.goldDim.opacity(0.5), lineWidth: 1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(Text("Listen"))
    }
}
