import Testing
import Foundation
@testable import IkeruCore

@Suite("KanaGroup")
struct KanaGroupTests {

    @Test("Hiragana vowel group has 5 characters")
    func hiraganaVowels() {
        #expect(KanaGroup.hVowels.characters.count == 5)
        #expect(KanaGroup.hVowels.script == .hiragana)
        #expect(KanaGroup.hVowels.section == .base)
    }

    @Test("Katakana vowel group has 5 characters")
    func katakanaVowels() {
        #expect(KanaGroup.kVowels.characters.count == 5)
        #expect(KanaGroup.kVowels.script == .katakana)
    }

    @Test("Y group has 3 characters in both scripts")
    func yGroup() {
        #expect(KanaGroup.hY.characters.count == 3)
        #expect(KanaGroup.kY.characters.count == 3)
    }

    @Test("WN group has 3 characters in both scripts")
    func wnGroup() {
        #expect(KanaGroup.hWN.characters.count == 3)
        #expect(KanaGroup.kWN.characters.count == 3)
    }

    @Test("All 92 base kana are present exactly once")
    func allBaseKanaCovered() {
        let chars = KanaGroup.allBaseCharacters
        #expect(chars.count == 92)
        let unique = Set(chars.map(\.character))
        #expect(unique.count == 92)
    }

    @Test("Each base kana character round-trips to its group")
    func roundTrip() {
        for kana in KanaGroup.allBaseCharacters {
            #expect(kana.group.characters.contains(kana))
        }
    }

    @Test("Hiragana groups have hiragana script")
    func hiraganaScriptDerivation() {
        let hiraganaGroups: [KanaGroup] = [.hVowels, .hK, .hS, .hT, .hN, .hH, .hM, .hY, .hR, .hWN]
        for group in hiraganaGroups {
            #expect(group.script == .hiragana)
        }
    }

    @Test("Dakuten groups have dakuten section")
    func dakutenSection() {
        #expect(KanaGroup.hG.section == .dakuten)
        #expect(KanaGroup.kP.section == .dakuten)
    }

    @Test("Yōon groups have combined section")
    func combinedSection() {
        #expect(KanaGroup.hKY.section == .combined)
        #expect(KanaGroup.kPY.section == .combined)
    }
}
