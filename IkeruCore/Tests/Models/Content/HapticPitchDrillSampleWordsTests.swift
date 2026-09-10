import Testing
@testable import IkeruCore

// MARK: - HapticPitchDrillSampleWordsTests

/// Regression guard for `HapticPitchViewModel.sampleWords` in
/// `IkeruWatch/Views/HapticPitchDrillView.swift`.
///
/// That table organizes sample words into sections commented by pitch-accent pattern
/// (平板/頭高/中高/尾高). It is easy for a word to end up filed under the wrong section
/// during editing — the classification logic itself (`PitchAccentPattern.classifyType`) is
/// correct, but nothing previously checked that each entry's `(moraCount, accentPosition)`
/// actually produces the pattern its comment claims.
///
/// This is a deliberately duplicated copy of the sample word table, not a shared import:
/// the watchOS app target (`IkeruWatch`) has no unit test target wired up, and `IkeruCore`
/// cannot depend on Watch-app-target types — the dependency only flows the other way
/// (`IkeruWatch` imports `IkeruCore`). Keep this table in sync with
/// `HapticPitchViewModel.sampleWords` whenever that table changes.
///
/// This pattern generalizes: any content table organized into semantic sections should have
/// a test verifying each entry actually belongs to the section it's filed under.
@Suite("HapticPitchDrillView sample words are filed under their true pattern")
struct HapticPitchDrillSampleWordsTests {

    private struct SampleWordEntry: Sendable {
        let word: String
        let moraCount: Int
        let accentPosition: Int
        let declaredSection: PitchAccentType
    }

    /// Mirror of `HapticPitchViewModel.sampleWords`. Verified against NHK/OJAD accent
    /// dictionaries: さくら[0], ともだち[0], ねこ[1], カメラ[1], たまご[2], せんせい[3],
    /// あたま[3], おとうと[4], いぬ[2], おとこ[3].
    private static let sampleWords: [SampleWordEntry] = [
        // 平板 (heiban) — flat
        SampleWordEntry(word: "さくら", moraCount: 3, accentPosition: 0, declaredSection: .heiban),
        SampleWordEntry(word: "ともだち", moraCount: 4, accentPosition: 0, declaredSection: .heiban),
        // 頭高 (atamadaka) — accent on first mora
        SampleWordEntry(word: "ねこ", moraCount: 2, accentPosition: 1, declaredSection: .atamadaka),
        SampleWordEntry(word: "カメラ", moraCount: 3, accentPosition: 1, declaredSection: .atamadaka),
        // 中高 (nakadaka) — accent on an interior mora
        SampleWordEntry(word: "たまご", moraCount: 3, accentPosition: 2, declaredSection: .nakadaka),
        SampleWordEntry(word: "せんせい", moraCount: 4, accentPosition: 3, declaredSection: .nakadaka),
        // 尾高 (odaka) — accent on the final mora
        SampleWordEntry(word: "あたま", moraCount: 3, accentPosition: 3, declaredSection: .odaka),
        SampleWordEntry(word: "おとうと", moraCount: 4, accentPosition: 4, declaredSection: .odaka),
        SampleWordEntry(word: "いぬ", moraCount: 2, accentPosition: 2, declaredSection: .odaka),
        SampleWordEntry(word: "おとこ", moraCount: 3, accentPosition: 3, declaredSection: .odaka)
    ]

    @Test(
        "Each sample word's (moraCount, accentPosition) classifies into its declared section",
        arguments: sampleWords
    )
    private func wordMatchesDeclaredSection(entry: SampleWordEntry) {
        let actual = PitchAccentPattern.classifyType(
            moraCount: entry.moraCount,
            accentPosition: entry.accentPosition
        )
        #expect(
            actual == entry.declaredSection,
            "\(entry.word) classifies as \(actual) but is filed under \(entry.declaredSection)"
        )
    }

    @Test("Every pattern type has at least two sample words")
    func everySectionHasAtLeastTwoExamples() {
        let counts = Dictionary(grouping: Self.sampleWords, by: \.declaredSection)
            .mapValues(\.count)
        for type in PitchAccentType.allCases {
            #expect((counts[type] ?? 0) >= 2, "\(type) has fewer than 2 sample words")
        }
    }
}
