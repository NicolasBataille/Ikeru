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

            // "kanji readings" was in this sentence until 2026-08-15, and it
            // was false — they are KANJIDIC-derived (see the note on
            // `Attribution.all`). This is the line a learner actually READS;
            // fixing only the source comment would have left the claim on
            // screen and the correction where nobody looks.
            Text("Vocabulary meanings and grammar notes are written for Ikeru. Kanji readings come from KANJIDIC, the N5 word list from Tanos, and most example sentences from the Tatoeba corpus — all credited below.")
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

            // The EDRDG licence does not merely permit a link, it asks for one:
            // "provide copies of the documentation and licence files … Where the
            // application packaging does not provide for the inclusion of such
            // files (e.g. with iPhone applications), it is sufficient to provide
            // links". We are exactly that case, so this row is a compliance
            // requirement for KANJIDIC, not decoration. It is offered for the
            // other sources too — the same courtesy costs nothing.
            if let licenceURL = item.licenceURL {
                Link(destination: licenceURL) {
                    HStack(spacing: 4) {
                        Text("Read the licence")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                }
                .padding(.top, 2)
            }
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
    /// Where the licence text itself can be read. Optional so a source without
    /// a canonical online licence page does not have to invent one — but the
    /// EDRDG licence explicitly asks for this link on apps that cannot bundle
    /// the documentation files, which is every iOS app.
    let licenceURL: URL?
    /// Typed as `LocalizedStringKey` (not `String`) so the literals below
    /// resolve against the string catalog when rendered via `Text(_:)`
    /// instead of falling into the verbatim initializer — see CLAUDE.md.
    let description: LocalizedStringKey

    /// Resources actually used by the shipped content bundle and app.
    ///
    /// The bundle is built by `scripts/generate_content_bundles.py`. Two other
    /// generators in `scripts/` are dead demo stubs; the headers claiming they
    /// import KANJIDIC/RADKFILE describe neither the shipped data nor a live
    /// pipeline, and this comment used to cite one of them as its authority.
    ///
    /// Kanji readings and meanings ARE derived from KANJIDIC, and are credited
    /// below. That was measured, not assumed, on 2026-08-15: all 63 dotted kun
    /// readings in the bundle are byte-identical to KANJIDIC's okurigana
    /// convention (`み.つ`, `みっ.つ`), and the on-readings reproduce its own
    /// ordering in 89 of 90 kanji. The bundle trims KANJIDIC's affix-marked
    /// entries (`ひと-`, `うわ-`) and keeps a subset — a curation of KANJIDIC
    /// is still derived from it. CC BY-SA 4.0 is share-alike; whether that
    /// reaches the app binary is an open question filed against the App Store
    /// task, and crediting the source is right either way.
    ///
    /// Radicals are NOT credited to RADKFILE, on the same evidence: only 36 of
    /// 90 decompositions match it, and the misses are systematic (the bundle
    /// writes 八 and 九 where RADKFILE writes its own ハ-shaped radicals).
    /// Vocabulary *glosses* remain hand-authored — all 693 of them, English and
    /// French. What is no longer Ikeru's own is the **selection**: 488 of the
    /// 693 words were picked from the Tanos JLPT N5 list (CC BY, credited
    /// below), whose site asks for a link. Only the word and its reading came
    /// from there; the deck's own English gloss column was deliberately not
    /// imported, because tanos.co.uk states no provenance for it and it is
    /// plausibly EDICT-derived — see `scripts/tanos/build-vocab-list.py`. The
    /// split is recorded per row in `vocabulary.list_source`, so "we wrote the
    /// meanings, they had the list" is a query, not a promise.
    ///
    /// Do not add a RADKFILE entry without re-running that diff — crediting a
    /// source you did not use is its own kind of false claim.
    ///
    /// Example sentences are no longer all Ikeru's: 239 of the 335 come from
    /// Tatoeba under CC BY 2.0 FR (`scripts/tatoeba/`), which requires
    /// attribution — hence the entry below. Provenance is recorded per row in
    /// the content bundle (`sentences.source`), so the two sets stay
    /// distinguishable. Tatoeba *audio* is licensed separately, per
    /// contributor, and none of it is bundled.
    @MainActor
    static let all: [Attribution] = [
        Attribution(
            id: "kanjidic",
            name: "KANJIDIC",
            author: "Electronic Dictionary Research and Development Group",
            license: "CC BY-SA 4.0",
            licenceURL: URL(string: "https://www.edrdg.org/edrdg/licence.html"),
            description: "Kanji readings and meanings in the content bundle are derived from the KANJIDIC database, maintained by the EDRDG at Monash University."
        ),
        Attribution(
            id: "kanjivg",
            name: "KanjiVG",
            author: "Ulrich Apel",
            license: "CC BY-SA 3.0",
            licenceURL: URL(string: "https://creativecommons.org/licenses/by-sa/3.0/"),
            description: "Stroke order data for kanji characters. Provides the vector paths used in stroke order animations and tracing exercises."
        ),
        Attribution(
            id: "noto-serif-jp",
            name: "Noto Serif JP",
            author: "Google Fonts",
            license: "SIL OFL 1.1",
            licenceURL: URL(string: "https://openfontlicense.org"),
            description: "Japanese serif typeface bundled with the app, used to render kanji and Japanese text on every device."
        ),
        Attribution(
            id: "tatoeba",
            name: "Tatoeba",
            author: "Tatoeba contributors — tatoeba.org",
            license: "CC BY 2.0 FR",
            licenceURL: URL(string: "https://creativecommons.org/licenses/by/2.0/fr/"),
            description: "Japanese example sentences reproduced unchanged from Tatoeba; French lightly normalized (spacing, apostrophes). Its audio is licensed separately, per contributor, unused."
        ),
        Attribution(
            id: "tanos",
            name: "Tanos JLPT lists",
            author: "Jonathan Waller — tanos.co.uk",
            license: "CC BY",
            licenceURL: URL(string: "http://www.tanos.co.uk/jlpt/sharing/"),
            description: "Which words are on the JLPT N5 list, and how they are read, come from Jonathan Waller's JLPT resources. The English and French meanings shown in Ikeru are written for Ikeru, not taken from there."
        ),
        Attribution(
            id: "voicevox",
            name: "VOICEVOX：四国めたん",
            author: "VOICEVOX / Hiroshiba",
            license: "VOICEVOX Terms (credit required)",
            licenceURL: URL(string: "https://voicevox.hiroshiba.jp/term/"),
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
