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
        }
    }

    // MARK: - Attribution Card

    private func attributionCard(_ item: Attribution) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            HStack {
                Text(item.name)
                    .font(.ikeruHeading3)
                    .foregroundStyle(.white)

                Spacer()

                Text(item.license)
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                    .padding(.horizontal, IkeruTheme.Spacing.sm)
                    .padding(.vertical, 2)
                    .background(Color.ikeruPrimaryAccent.opacity(0.10))
                    .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim, lineWidth: 0.8))
                    .sumiCorners(color: TatamiTokens.goldDim, size: 4, weight: 0.9)
            }

            Text(item.author)
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
    let description: String

    static let all: [Attribution] = [
        Attribution(
            id: "kanjivg",
            name: "KanjiVG",
            author: "Ulrich Apel",
            license: "CC BY-SA 3.0",
            description: "Stroke order data for kanji characters. Provides the vector paths used in stroke order animations and tracing exercises."
        ),
        Attribution(
            id: "tatoeba",
            name: "Tatoeba",
            author: "Tatoeba Contributors",
            license: "CC BY 2.0",
            description: "Example sentences used in grammar exercises and sentence construction practice. A collaborative database of multilingual sentences."
        ),
        Attribution(
            id: "kanjidic",
            name: "KANJIDIC / RADKFILE",
            author: "Electronic Dictionary Research and Development Group (EDRDG), Jim Breen",
            license: "CC BY-SA 4.0",
            description: "Kanji readings, meanings, and radical decomposition data. Powers the kanji knowledge graph and radical-based learning."
        ),
        Attribution(
            id: "jmdict",
            name: "JMdict",
            author: "Electronic Dictionary Research and Development Group (EDRDG), Jim Breen",
            license: "CC BY-SA 4.0",
            description: "Japanese-English dictionary data used for vocabulary entries and definitions."
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
