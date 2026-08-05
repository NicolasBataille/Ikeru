import SwiftUI
import IkeruCore

// MARK: - AttributionView

/// Lists open-source resources and their licenses.
struct AttributionView: View {

    var body: some View {
        ZStack {
            Color.ikeruBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: IkeruTheme.Spacing.lg) {
                    headerSection

                    ForEach(Attribution.all) { attribution in
                        attributionCard(attribution)
                    }
                }
                .padding(IkeruTheme.Spacing.md)
            }
        }
        .navigationTitle("Attribution")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            Text("Ikeru is made possible by these open-source resources.")
                .font(.ikeruBody)
                .foregroundStyle(.ikeruTextSecondary)

            Text("Vocabulary, kanji readings, grammar notes, and example sentences are original content written for Ikeru.")
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)
        }
    }

    // MARK: - Attribution Card

    private func attributionCard(_ item: Attribution) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            HStack {
                Text(verbatim: item.name)
                    .font(.ikeruHeading3)
                    .foregroundStyle(.white)

                Spacer()

                Text(verbatim: item.license)
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                    .padding(.horizontal, IkeruTheme.Spacing.sm)
                    .padding(.vertical, 2)
                    .background(Color.ikeruPrimaryAccent.opacity(0.10))
                    .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim, lineWidth: 0.8))
                    .sumiCorners(color: TatamiTokens.goldDim, size: 4, weight: 0.9)
            }

            Text(verbatim: item.author)
                .font(.ikeruStats)
                .foregroundStyle(.ikeruTextSecondary)

            Text(item.description)
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)
        }
        .tatamiRoom(.standard)
    }
}

// MARK: - Attribution Data

struct Attribution: Identifiable {
    let id: String
    let name: String
    let author: String
    let license: String
    /// Typed as `LocalizedStringKey` (not `String`) so the literals below
    /// resolve against the string catalog when rendered via `Text(_:)`
    /// instead of falling into the verbatim initializer — see CLAUDE.md.
    let description: LocalizedStringKey

    /// Resources actually used by the shipped content bundle and app.
    ///
    /// Kept intentionally short: kanji readings/meanings/radicals,
    /// vocabulary, and example sentences are hand-authored for Ikeru
    /// (see `scripts/generate-content-bundle.swift`) rather than imported
    /// from JMdict, KANJIDIC/RADKFILE, or the Tatoeba corpus, so those are
    /// not credited here.
    @MainActor
    static let all: [Attribution] = [
        Attribution(
            id: "kanjivg",
            name: "KanjiVG",
            author: "Ulrich Apel",
            license: "CC BY-SA 3.0",
            description: "Stroke order data for kanji characters. Provides the vector paths used in stroke order animations and tracing exercises."
        ),
        Attribution(
            id: "noto-serif-jp",
            name: "Noto Serif JP",
            author: "Google Fonts",
            license: "SIL OFL 1.1",
            description: "Japanese serif typeface bundled with the app, used to render kanji and Japanese text on every device."
        ),
        Attribution(
            id: "voicevox",
            name: "VOICEVOX：四国めたん",
            author: "VOICEVOX / Hiroshiba",
            license: "VOICEVOX Terms (credit required)",
            description: "Pronunciation audio for kana, vocabulary, and example sentences is pre-generated with the free VOICEVOX speech engine (voice: 四国めたん) and bundled for offline playback — no setup required."
        ),
    ]
}

// MARK: - Preview

#Preview("AttributionView") {
    NavigationStack {
        AttributionView()
    }
    .preferredColorScheme(.dark)
}
