import SwiftUI
import IkeruCore

// MARK: - ExampleSentencesSection
//
// The reader the bundled example sentences never had.
//
// 632 sentences ship with the app, each filed under a vocabulary word and
// paired with a translation. Until now the only views that read them
// (`VocabularyExamplesView`, `VocabularyStudyView`) were instantiated by
// nothing — verified 2026-08-16, and the chain is longer than it looks:
// `VocabularyExamplesView` is built only by `KanjiStudyView`, and
// `KanjiStudyView` is itself built nowhere, because a session's `.kanjiStudy`
// exercise renders `HandwritingDrillHost` instead.
//
// Shown on the two surfaces a learner genuinely reaches:
// `VocabularyEntryDetailView` (Étude → dictionary → a word) and
// `VocabularyDetailSheet` (tapping a word in a Sakura conversation).

/// Shows a word's bundled example sentences, translation underneath.
///
/// **Purely presentational — it owns no state and fetches nothing.** That is a
/// correction, not a style preference. The first version held `@State private
/// var examples` and filled it from `.task(id: word)` attached to a
/// `Group { if !examples.isEmpty { … } }`. On first render the list is empty,
/// so the `Group` resolved to an *empty view* — and an empty view has no
/// lifecycle, so `.task` never ran. The list could therefore never fill, and
/// the section never appeared for **any** word. Measured on device 2026-08-19
/// against 水, which has six translated examples in the bundle.
///
/// The fetch now lives in the parent, which already loads its entry in a
/// `.task` on a view that always exists. Keep it that way: a self-loading view
/// that renders nothing while empty cannot load.
///
/// Renders nothing at all when `examples` is empty — not an empty section with
/// a header. Most dictionary entries come from conversation with Sakura rather
/// than from the bundle, so "no examples" is the ordinary case.
struct ExampleSentencesSection: View {

    let examples: [SentenceExample]

    /// Two, matching the judgement already encoded in
    /// `VocabularyExamplesView.examplesPerWord`. The bundle caps at 5 per word
    /// (`MAX_PER_VOCAB_WORD` in `build-corpus.py`); showing all five turns a
    /// reference card into a wall.
    static let displayedExamples = 2

    /// Loads a word's examples in the learner's language. Called by the parent
    /// view's own loader — see the type doc for why this is not a `.task` here.
    static func load(word: String) async -> [SentenceExample] {
        guard !word.isEmpty, let repository = BundledContent.makeRepository() else { return [] }
        return await repository.exampleSentences(for: word, limit: displayedExamples)
    }

    var body: some View {
        if !examples.isEmpty {
            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
                Text("Vocabulary.Examples.Title")
                    .ikeruScaledFont(11, weight: .semibold, relativeTo: .caption2)
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.ikeruTextTertiary)

                ForEach(examples) { example in
                    exampleRow(example)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func exampleRow(_ example: SentenceExample) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(example.japanese)
                .ikeruScaledFont(16, weight: .regular, relativeTo: .body)
                .foregroundStyle(Color.ikeruTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Dimmed, and directly under its own sentence — the same
            // relationship the chat uses between a line and its translation,
            // so the pairing reads the same way in both places.
            Text(example.translation)
                .ikeruScaledFont(13, weight: .regular, relativeTo: .footnote)
                .foregroundStyle(Color.ikeruTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(IkeruTheme.Spacing.sm)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm))
        // One element per example, so VoiceOver reads a sentence together with
        // its translation instead of two orphaned strings.
        .accessibilityElement(children: .combine)
    }
}
