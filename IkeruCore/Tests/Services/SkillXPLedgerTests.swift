import Testing
@testable import IkeruCore

@Suite("SkillXPLedger")
struct SkillXPLedgerTests {

    @Test("Starts at zero")
    func startsZero() async {
        let ledger = SkillXPLedger()
        let snap = await ledger.snapshot()
        #expect(snap == .zero)
    }

    @Test("Recording 10 XP for kanaStudy puts all 10 into reading")
    func kanaAllReading() async {
        let ledger = SkillXPLedger()
        await ledger.record(xp: 10, exerciseType: .kanaStudy)
        let snap = await ledger.snapshot()
        #expect(snap.reading == 10)
        #expect(snap.writing == 0)
        #expect(snap.listening == 0)
        #expect(snap.speaking == 0)
    }

    @Test("Recording 18 XP for writingPractice splits 4 reading / 14 writing")
    func writingSplit() async {
        let ledger = SkillXPLedger()
        await ledger.record(xp: 18, exerciseType: .writingPractice)
        let snap = await ledger.snapshot()
        #expect(snap.reading == 4)
        #expect(snap.writing == 14)
        #expect(snap.listening == 0)
        #expect(snap.speaking == 0)
    }

    @Test("Recording 12 XP for listeningSubtitled splits 4 reading / 8 listening")
    func listeningSubtitledSplit() async {
        let ledger = SkillXPLedger()
        await ledger.record(xp: 12, exerciseType: .listeningSubtitled)
        let snap = await ledger.snapshot()
        #expect(snap.reading == 4)
        #expect(snap.listening == 8)
    }

    @Test("Multiple records accumulate")
    func accumulate() async {
        let ledger = SkillXPLedger()
        await ledger.record(xp: 6, exerciseType: .kanaStudy)
        await ledger.record(xp: 6, exerciseType: .kanaStudy)
        await ledger.record(xp: 8, exerciseType: .kanjiStudy)
        let snap = await ledger.snapshot()
        #expect(snap.reading == 20)
    }
}
