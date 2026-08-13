import Testing
import Foundation
@testable import IkeruCore

/// Direct coverage for `CardDTO.isKana`, which was rewritten from a
/// unicode-range test to `KanaGroup` catalog membership (see the doc
/// comment on `isKana` in `Card+Mastery.swift` for why). Before this file,
/// `grep isKana IkeruCore/Tests` returned zero results for a public API used
/// at 6 call sites — this suite exists to close that gap and to pin down the
/// exact behavioural delta between the two semantics.
@Suite("CardDTO.isKana")
struct CardMasteryIsKanaTests {

    @Test("Base hiragana and katakana are kana")
    func baseKanaIsKana() {
        #expect(fixtureCard(front: "あ").isKana)
        #expect(fixtureCard(front: "ア").isKana)
    }

    @Test("Dakuten (voiced) kana are kana")
    func dakutenIsKana() {
        #expect(fixtureCard(front: "が").isKana, "hiragana が (hG group)")
        #expect(fixtureCard(front: "パ").isKana, "katakana パ (kP group)")
    }

    @Test(
        "Yōon digraphs are kana even though they are two Unicode scalars — the case that motivated the catalog-based rewrite"
    )
    func yoonDigraphIsKana() {
        // きゃ = き (U+304D) + small ゃ (U+3083): two scalars, both kana, but a
        // single logical kana unit registered in KanaGroup .hKY. A unicode-range
        // test gated on `scalars.count == 1` (the old implementation) can never
        // see this front as kana — that was the bug the catalog rewrite fixed:
        // all 66 yōon fronts would be invisible to every isKana-filtered query.
        let front = "きゃ"
        #expect(front.unicodeScalars.count == 2, "きゃ must be a 2-scalar digraph for this test to be meaningful")
        #expect(fixtureCard(front: front).isKana)

        // Katakana yōon too.
        let katakanaFront = "キャ"
        #expect(katakanaFront.unicodeScalars.count == 2)
        #expect(fixtureCard(front: katakanaFront).isKana)
    }

    @Test("Kanji is not kana")
    func kanjiIsNotKana() {
        #expect(!fixtureCard(front: "火").isKana)
    }

    @Test("Latin text is not kana")
    func latinIsNotKana() {
        #expect(!fixtureCard(front: "a").isKana)
        #expect(!fixtureCard(front: "hello").isKana)
    }

    @Test("Empty string is not kana")
    func emptyStringIsNotKana() {
        #expect(!fixtureCard(front: "").isKana)
    }

    @Test("A kana-written vocabulary word (multi-character, not a catalog entry) is not kana")
    func kanaWrittenVocabWordIsNotKana() {
        // いぬ ("dog") and ねこ ("cat") are entirely hiragana but are ordinary
        // .vocabulary CardDTOs, not registered KanaGroup fronts — catalog
        // membership (not "is every character kana") is what isKana checks.
        #expect(!fixtureCard(front: "いぬ").isKana)
        #expect(!fixtureCard(front: "ねこ").isKana)
    }

    @Test(
        "A single-scalar character inside the kana Unicode block but outside the KanaGroup catalog is NOT kana — this is the exact old-vs-new semantics delta"
    )
    func unicodeBlockMemberOutsideCatalogIsNotKana() {
        // ゐ (hiragana WI, U+3090) and ヴ (katakana VU, U+30F4) are single
        // Unicode scalars inside the hiragana/katakana blocks respectively, so
        // the OLD range-based isKana (scalars.count == 1 && block.contains(v))
        // would have returned true for both. Neither is part of the modern
        // gojūon/dakuten/yōon curriculum registered in KanaGroup, so the NEW
        // catalog-based isKana correctly returns false. This is the precise
        // case that documents the semantic change, not just a regression risk.
        let wi = "\u{3090}" // ゐ
        #expect(wi.unicodeScalars.count == 1)
        #expect((0x3040...0x309F).contains(wi.unicodeScalars.first!.value), "ゐ must be in the hiragana block for this test to be meaningful")
        #expect(!fixtureCard(front: wi).isKana)

        let vu = "\u{30F4}" // ヴ
        #expect(vu.unicodeScalars.count == 1)
        #expect((0x30A0...0x30FF).contains(vu.unicodeScalars.first!.value), "ヴ must be in the katakana block for this test to be meaningful")
        #expect(!fixtureCard(front: vu).isKana)
    }

    private func fixtureCard(front: String, back: String = "x", type: CardType = .vocabulary) -> CardDTO {
        CardDTO(
            id: UUID(),
            front: front,
            back: back,
            type: type,
            fsrsState: FSRSState(
                difficulty: 5,
                stability: 1,
                reps: 0,
                lapses: 0,
                lastReview: nil
            ),
            easeFactor: 2.5,
            interval: 1,
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            lapseCount: 0,
            leechFlag: false
        )
    }
}

/// Direct coverage for `CardDTO.purgeableKanaGroup`, the stricter
/// purge-eligibility check `KanaCardRepository.purgeUnstartedCards` uses
/// instead of the looser `kanaGroup` (front-catalog-only). See the doc
/// comment on `purgeableKanaGroup` in `Card+Mastery.swift` for the full
/// rationale: neither `front`-catalog membership alone, nor `CardType`
/// alone, can tell a real kana card apart from a same-shaped vocabulary
/// card, because every known kana-seeding site tags its cards
/// `.vocabulary` — the exact type a personal-vocabulary card would use.
/// Only an exact `back == romaji` match closes that gap.
@Suite("CardDTO.purgeableKanaGroup")
struct CardMasteryPurgeableKanaGroupTests {

    private func fixtureCard(front: String, back: String, type: CardType = .vocabulary) -> CardDTO {
        CardDTO(
            id: UUID(),
            front: front,
            back: back,
            type: type,
            fsrsState: FSRSState(
                difficulty: 5,
                stability: 1,
                reps: 0,
                lapses: 0,
                lastReview: nil
            ),
            easeFactor: 2.5,
            interval: 1,
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            lapseCount: 0,
            leechFlag: false
        )
    }

    @Test("A real kana card — .vocabulary type, back == catalog romaji — resolves to its group")
    func realKanaCardResolves() {
        let card = fixtureCard(front: "え", back: "e")
        #expect(card.purgeableKanaGroup == .hVowels)
    }

    @Test(
        "A .vocabulary card whose front is a kana-shaped real word (え/\"image\") but whose back is a meaning, not romaji, does NOT resolve — this is the exact collision KanaCardRepository.purgeUnstartedCards must not delete"
    )
    func kanaShapedVocabWordDoesNotResolve() {
        // え is a real Japanese word ("picture/image"). A future
        // personal-vocabulary card for it would be `.vocabulary`-typed with
        // front "え" — identical to the real kana card on both `front` and
        // `type` — but its `back` would carry the meaning, not the romaji
        // "e". `kanaGroup` (front-catalog-only) resolves this to `.hVowels`
        // and would make it purge-eligible; `purgeableKanaGroup` must not.
        let card = fixtureCard(front: "え", back: "image")
        #expect(card.kanaGroup == .hVowels, "sanity: the looser front-only check DOES resolve this front")
        #expect(card.purgeableKanaGroup == nil)
    }

    @Test("A card with the correct front and back but a non-.vocabulary type does not resolve")
    func nonVocabularyTypeDoesNotResolve() {
        let card = fixtureCard(front: "え", back: "e", type: .kanji)
        #expect(card.purgeableKanaGroup == nil)
    }

    @Test("A card whose front is not in the kana catalog never resolves, regardless of back or type")
    func nonKanaFrontDoesNotResolve() {
        #expect(fixtureCard(front: "犬", back: "dog").purgeableKanaGroup == nil)
    }

    @Test("Back must match romaji exactly — a near-miss (wrong case, extra whitespace) does not resolve")
    func backMustMatchExactly() {
        #expect(fixtureCard(front: "え", back: "E").purgeableKanaGroup == nil)
        #expect(fixtureCard(front: "え", back: " e").purgeableKanaGroup == nil)
        #expect(fixtureCard(front: "え", back: "e ").purgeableKanaGroup == nil)
    }
}
