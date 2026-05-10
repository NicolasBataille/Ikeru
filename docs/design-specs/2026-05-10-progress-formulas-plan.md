# Spec C — Progress Formulas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken JLPT readiness formula with a per-level weakest-link blend over `LearnerSnapshot`, tag cards with their JLPT level, and ramp mastery-event badge rarity by learner level.

**Architecture:** Three pure-core pieces in `IkeruCore` (`JLPTReadinessFormula` + `JLPTReadinessReport`, extended `LearnerSnapshot`, `BadgeRamping`), one schema change (`CardDTO.jlptLevel: JLPTLevel?` + SwiftData column), one one-shot backfill service to tag the existing N5 seed. `ProgressService.computeJLPTEstimate` is replaced; the legacy `JLPTEstimate` value type stays as a back-compat projection from the new report.

**Tech Stack:** Swift 6 strict concurrency, Swift Testing (`import Testing`), SwiftData, `@Observable` view models. Build via `swift test` for `IkeruCore` and `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17'` for the app.

**Branch:** `design/wabi-refinements` (continuation — same branch as Spec A and Spec B).

**Convention:** one commit per task, tests-first.

**Source design doc:** `docs/design-specs/2026-05-10-progress-formulas-design.md` — read it before starting.

---

## Task 1: `JLPTReadinessRequirements` per-level table

**Files:**
- Create: `IkeruCore/Sources/Models/Progress/JLPTReadinessRequirements.swift`
- Test: `IkeruCore/Tests/Models/Progress/JLPTReadinessRequirementsTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import IkeruCore

@Suite("JLPTReadinessRequirements")
struct JLPTReadinessRequirementsTests {

    @Test("N5 requires 100 vocab, 50 kanji, 5 grammar, hiragana, 60% listening, no recall floor")
    func n5() {
        let r = JLPTReadinessRequirements.requirements(for: .n5)
        #expect(r.vocab == 100)
        #expect(r.kanji == 50)
        #expect(r.grammar == 5)
        #expect(r.requiresHiragana == true)
        #expect(r.requiresKatakana == false)
        #expect(r.listenAccuracy == 0.60)
        #expect(r.listenRecall == nil)
    }

    @Test("N3 requires both kana, listening recall floor 30%")
    func n3() {
        let r = JLPTReadinessRequirements.requirements(for: .n3)
        #expect(r.requiresKatakana == true)
        #expect(r.listenRecall == 0.30)
    }

    @Test("N1 requires 2000 vocab, 1000 kanji, 75% listening, 70% recall")
    func n1() {
        let r = JLPTReadinessRequirements.requirements(for: .n1)
        #expect(r.vocab == 2000)
        #expect(r.kanji == 1000)
        #expect(r.listenAccuracy == 0.75)
        #expect(r.listenRecall == 0.70)
    }

    @Test("Vocab requirements are monotonic across levels")
    func vocabMonotonic() {
        let levels: [JLPTLevel] = [.n5, .n4, .n3, .n2, .n1]
        let vocabs = levels.map { JLPTReadinessRequirements.requirements(for: $0).vocab }
        for i in 1..<vocabs.count {
            #expect(vocabs[i] > vocabs[i - 1])
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path IkeruCore --filter JLPTReadinessRequirementsTests`
Expected: FAIL — `cannot find 'JLPTReadinessRequirements' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct JLPTReadinessRequirements: Sendable, Equatable {
    public let vocab: Int
    public let kanji: Int
    public let grammar: Int
    public let requiresHiragana: Bool
    public let requiresKatakana: Bool
    public let listenAccuracy: Double          // last-30 subtitled clips
    public let listenRecall: Double?           // last-30-days; nil = not gated

    public static func requirements(for level: JLPTLevel) -> JLPTReadinessRequirements {
        switch level {
        case .n5:
            return .init(vocab: 100,  kanji: 50,   grammar: 5,
                         requiresHiragana: true,  requiresKatakana: false,
                         listenAccuracy: 0.60, listenRecall: nil)
        case .n4:
            return .init(vocab: 300,  kanji: 150,  grammar: 30,
                         requiresHiragana: true,  requiresKatakana: true,
                         listenAccuracy: 0.60, listenRecall: nil)
        case .n3:
            return .init(vocab: 650,  kanji: 300,  grammar: 100,
                         requiresHiragana: true,  requiresKatakana: true,
                         listenAccuracy: 0.65, listenRecall: 0.30)
        case .n2:
            return .init(vocab: 1000, kanji: 600,  grammar: 150,
                         requiresHiragana: true,  requiresKatakana: true,
                         listenAccuracy: 0.70, listenRecall: 0.50)
        case .n1:
            return .init(vocab: 2000, kanji: 1000, grammar: 250,
                         requiresHiragana: true,  requiresKatakana: true,
                         listenAccuracy: 0.75, listenRecall: 0.70)
        }
    }
}
```

- [ ] **Step 4: Verify tests pass**

Run: `swift test --package-path IkeruCore --filter JLPTReadinessRequirementsTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```
feat(progress): JLPTReadinessRequirements per-level table (5 levels, 7 axes)
```

---

## Task 2: `JLPTReadinessReport` value type

**Files:**
- Create: `IkeruCore/Sources/Models/Progress/JLPTReadinessReport.swift`
- Test: `IkeruCore/Tests/Models/Progress/JLPTReadinessReportTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import IkeruCore

@Suite("JLPTReadinessReport")
struct JLPTReadinessReportTests {

    @Test("Stores per-level + bestFit + confidence")
    func fields() {
        let report = JLPTReadinessReport(
            perLevel: [.n5: 0.95, .n4: 0.4, .n3: 0.0, .n2: 0.0, .n1: 0.0],
            bestFit: .n5,
            bestFitConfidence: 0.95
        )
        #expect(report.perLevel[.n5] == 0.95)
        #expect(report.bestFit == .n5)
        #expect(report.bestFitConfidence == 0.95)
    }

    @Test("bestFitThreshold is 0.85")
    func threshold() {
        #expect(JLPTReadinessReport.bestFitThreshold == 0.85)
    }
}
```

- [ ] **Step 2: Verify failure, implement, verify pass**

```swift
import Foundation

public struct JLPTReadinessReport: Sendable, Equatable {
    public let perLevel: [JLPTLevel: Double]
    public let bestFit: JLPTLevel
    public let bestFitConfidence: Double

    public static let bestFitThreshold: Double = 0.85

    public init(perLevel: [JLPTLevel: Double], bestFit: JLPTLevel, bestFitConfidence: Double) {
        self.perLevel = perLevel
        self.bestFit = bestFit
        self.bestFitConfidence = bestFitConfidence
    }
}
```

- [ ] **Step 3: Commit**

```
feat(progress): JLPTReadinessReport value type (per-level + bestFit + confidence)
```

---

## Task 3: Extend `LearnerSnapshot` with per-level mastery dicts

**Files:**
- Modify: `IkeruCore/Sources/Services/ExerciseUnlock/LearnerSnapshot.swift`
- Test: `IkeruCore/Tests/Services/ExerciseUnlock/LearnerSnapshotPerLevelTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import IkeruCore

@Suite("LearnerSnapshot per-level mastery dicts")
struct LearnerSnapshotPerLevelTests {

    @Test("Defaults to empty dicts when not provided")
    func emptyByDefault() {
        let snap = LearnerSnapshot.empty
        #expect(snap.vocabularyMasteredAtOrBelow.isEmpty)
        #expect(snap.kanjiMasteredAtOrBelow.isEmpty)
        #expect(snap.grammarPointsMasteredAtOrBelow.isEmpty)
    }

    @Test("Stores per-level counts")
    func storesCounts() {
        let snap = LearnerSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 100,
            kanjiMasteredFamiliarPlus: 50,
            hiraganaMastered: true,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 5,
            listeningAccuracyLast30: 0.6,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            dueCardCount: 0,
            hasNewContentQueued: false,
            lastSessionAt: nil,
            vocabularyMasteredAtOrBelow: [.n5: 100, .n4: 100, .n3: 100, .n2: 100, .n1: 100],
            kanjiMasteredAtOrBelow: [.n5: 50],
            grammarPointsMasteredAtOrBelow: [.n5: 5]
        )
        #expect(snap.vocabularyMasteredAtOrBelow[.n5] == 100)
        #expect(snap.kanjiMasteredAtOrBelow[.n5] == 50)
        #expect(snap.grammarPointsMasteredAtOrBelow[.n5] == 5)
    }
}
```

- [ ] **Step 2: Verify failure, implement extension**

Add the three dictionary fields with default `[:]` values, update `init` and `.empty`:

```swift
public let vocabularyMasteredAtOrBelow: [JLPTLevel: Int]
public let kanjiMasteredAtOrBelow: [JLPTLevel: Int]
public let grammarPointsMasteredAtOrBelow: [JLPTLevel: Int]
```

Init takes them with default `[:]`. `.empty` keeps `[:]`.

- [ ] **Step 3: Commit**

```
feat(progress): LearnerSnapshot per-level mastery dicts (vocab/kanji/grammar)
```

---

## Task 4: `JLPTReadinessFormula.compute`

**Files:**
- Create: `IkeruCore/Sources/Services/Progress/JLPTReadinessFormula.swift`
- Test: `IkeruCore/Tests/Services/Progress/JLPTReadinessFormulaTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import IkeruCore

@Suite("JLPTReadinessFormula.compute")
struct JLPTReadinessFormulaTests {

    private func snap(
        hiraganaMastered: Bool = false,
        katakanaMastered: Bool = false,
        listenAccuracy: Double = 0,
        listenRecall: Double = 0,
        vocabAtOrBelow: [JLPTLevel: Int] = [:],
        kanjiAtOrBelow: [JLPTLevel: Int] = [:],
        grammarAtOrBelow: [JLPTLevel: Int] = [:]
    ) -> LearnerSnapshot {
        LearnerSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: hiraganaMastered,
            katakanaMastered: katakanaMastered,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: listenAccuracy,
            listeningRecallLast30Days: listenRecall,
            skillBalances: [:],
            dueCardCount: 0,
            hasNewContentQueued: false,
            lastSessionAt: nil,
            vocabularyMasteredAtOrBelow: vocabAtOrBelow,
            kanjiMasteredAtOrBelow: kanjiAtOrBelow,
            grammarPointsMasteredAtOrBelow: grammarAtOrBelow
        )
    }

    @Test("Fresh profile (no kana, no cards) reads bestFit=N5, confidence=0")
    func freshProfile() {
        let report = JLPTReadinessFormula.compute(snapshot: snap())
        #expect(report.bestFit == .n5)
        #expect(report.bestFitConfidence == 0.0)
    }

    @Test("Hiragana-only profile (Spec A bug regression) reads ≤ 5% N5 confidence")
    func kanaOnlyDoesNotSpike() {
        let report = JLPTReadinessFormula.compute(snapshot: snap(hiraganaMastered: true))
        #expect(report.bestFit == .n5)
        #expect(report.bestFitConfidence <= 0.05)
    }

    @Test("Full N5 prereqs read bestFit=N5, confidence ≥ 0.85")
    func fullN5() {
        let report = JLPTReadinessFormula.compute(snapshot: snap(
            hiraganaMastered: true,
            listenAccuracy: 0.60,
            vocabAtOrBelow: [.n5: 100, .n4: 100, .n3: 100, .n2: 100, .n1: 100],
            kanjiAtOrBelow:  [.n5: 50,  .n4: 50,  .n3: 50,  .n2: 50,  .n1: 50],
            grammarAtOrBelow: [.n5: 5, .n4: 5, .n3: 5, .n2: 5, .n1: 5]
        ))
        #expect(report.bestFit == .n5)
        #expect(report.bestFitConfidence >= 0.85)
    }

    @Test("N5 prereqs but 0% listening: bestFit=N5, confidence < 0.85")
    func zeroListeningDragsDown() {
        let report = JLPTReadinessFormula.compute(snapshot: snap(
            hiraganaMastered: true,
            listenAccuracy: 0.0,
            vocabAtOrBelow: [.n5: 100], kanjiAtOrBelow: [.n5: 50], grammarAtOrBelow: [.n5: 5]
        ))
        #expect(report.bestFit == .n5)
        #expect(report.bestFitConfidence < 0.85)
    }

    @Test("All N3 axes met EXCEPT recall (25% vs 30%) → bestFit ≤ N4")
    func n3WeakRecall() {
        let report = JLPTReadinessFormula.compute(snapshot: snap(
            hiraganaMastered: true,
            katakanaMastered: true,
            listenAccuracy: 0.65,
            listenRecall: 0.25,
            vocabAtOrBelow:  [.n3: 650, .n2: 650, .n1: 650, .n4: 650, .n5: 650],
            kanjiAtOrBelow:  [.n3: 300, .n2: 300, .n1: 300, .n4: 300, .n5: 300],
            grammarAtOrBelow:[.n3: 100, .n2: 100, .n1: 100, .n4: 100, .n5: 100]
        ))
        #expect(report.bestFit < .n3)
    }

    @Test("Missing hiragana hard-gates to 0 readiness")
    func hardKanaGate() {
        let report = JLPTReadinessFormula.compute(snapshot: snap(
            hiraganaMastered: false,
            listenAccuracy: 1.0,
            vocabAtOrBelow:  [.n5: 1000], kanjiAtOrBelow: [.n5: 1000], grammarAtOrBelow: [.n5: 1000]
        ))
        #expect((report.perLevel[.n5] ?? 0) == 0)
    }
}
```

- [ ] **Step 2: Verify failure, implement**

```swift
import Foundation

public enum JLPTReadinessFormula {

    public static func compute(snapshot: LearnerSnapshot) -> JLPTReadinessReport {
        let perLevel = JLPTLevel.allCases.reduce(into: [JLPTLevel: Double]()) { acc, level in
            acc[level] = readinessForLevel(level, snapshot: snapshot)
        }
        let bestFit = JLPTLevel.allCases.reversed()
            .first { (perLevel[$0] ?? 0) >= JLPTReadinessReport.bestFitThreshold }
            ?? .n5
        return JLPTReadinessReport(
            perLevel: perLevel,
            bestFit: bestFit,
            bestFitConfidence: perLevel[bestFit] ?? 0
        )
    }

    private static func readinessForLevel(
        _ level: JLPTLevel,
        snapshot: LearnerSnapshot
    ) -> Double {
        let req = JLPTReadinessRequirements.requirements(for: level)

        if req.requiresHiragana && !snapshot.hiraganaMastered { return 0 }
        if req.requiresKatakana && !snapshot.katakanaMastered { return 0 }

        let vocab   = ratio(snapshot.vocabularyMasteredAtOrBelow[level] ?? 0,        req.vocab)
        let kanji   = ratio(snapshot.kanjiMasteredAtOrBelow[level] ?? 0,             req.kanji)
        let grammar = ratio(snapshot.grammarPointsMasteredAtOrBelow[level] ?? 0,     req.grammar)
        let listen  = ratioDouble(snapshot.listeningAccuracyLast30, req.listenAccuracy)
        let recall  = req.listenRecall.map {
            ratioDouble(snapshot.listeningRecallLast30Days, $0)
        } ?? 1.0

        return [vocab, kanji, grammar, listen, recall].min() ?? 0
    }

    private static func ratio(_ value: Int, _ required: Int) -> Double {
        guard required > 0 else { return 1.0 }
        return min(1.0, Double(value) / Double(required))
    }

    private static func ratioDouble(_ value: Double, _ required: Double) -> Double {
        guard required > 0 else { return 1.0 }
        return min(1.0, value / required)
    }
}
```

- [ ] **Step 3: Commit**

```
feat(progress): JLPTReadinessFormula — weakest-link blender across 5 axes
```

---

## Task 5: `BadgeRamping.rarity` table

**Files:**
- Create: `IkeruCore/Sources/Services/Progress/BadgeRamping.swift`
- Test: `IkeruCore/Tests/Services/Progress/BadgeRampingTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import IkeruCore

@Suite("BadgeRamping.rarity")
struct BadgeRampingTests {

    @Test("Burned at N5 = rare; Burned at N2 = legendary")
    func burnedRamps() {
        #expect(BadgeRamping.rarity(for: .burned, learnerLevel: .n5) == .rare)
        #expect(BadgeRamping.rarity(for: .burned, learnerLevel: .n2) == .legendary)
    }

    @Test("Graduation N5..N3 = common, N2..N1 = uncommon")
    func graduationRamps() {
        #expect(BadgeRamping.rarity(for: .graduation, learnerLevel: .n5) == .common)
        #expect(BadgeRamping.rarity(for: .graduation, learnerLevel: .n4) == .common)
        #expect(BadgeRamping.rarity(for: .graduation, learnerLevel: .n3) == .common)
        #expect(BadgeRamping.rarity(for: .graduation, learnerLevel: .n2) == .uncommon)
        #expect(BadgeRamping.rarity(for: .graduation, learnerLevel: .n1) == .uncommon)
    }

    @Test("LongIntervalRecall N5=uncommon, N3=rare, N1=epic")
    func longIntervalRamps() {
        #expect(BadgeRamping.rarity(for: .longIntervalRecall, learnerLevel: .n5) == .uncommon)
        #expect(BadgeRamping.rarity(for: .longIntervalRecall, learnerLevel: .n3) == .rare)
        #expect(BadgeRamping.rarity(for: .longIntervalRecall, learnerLevel: .n1) == .epic)
    }

    @Test("LeechRecovered N5..N4=rare, N3..N2=epic, N1=legendary")
    func leechRamps() {
        #expect(BadgeRamping.rarity(for: .leechRecovered, learnerLevel: .n5) == .rare)
        #expect(BadgeRamping.rarity(for: .leechRecovered, learnerLevel: .n4) == .rare)
        #expect(BadgeRamping.rarity(for: .leechRecovered, learnerLevel: .n3) == .epic)
        #expect(BadgeRamping.rarity(for: .leechRecovered, learnerLevel: .n1) == .legendary)
    }
}
```

- [ ] **Step 2: Verify failure, implement**

```swift
import Foundation

public enum BadgeRamping {
    public static func rarity(
        for event: MasteryEvent,
        learnerLevel: JLPTLevel
    ) -> LootRarity {
        switch (event, learnerLevel) {
        case (.graduation, .n5), (.graduation, .n4), (.graduation, .n3):     return .common
        case (.graduation, .n2), (.graduation, .n1):                          return .uncommon

        case (.longIntervalRecall, .n5):                                      return .uncommon
        case (.longIntervalRecall, .n4), (.longIntervalRecall, .n3):          return .rare
        case (.longIntervalRecall, .n2), (.longIntervalRecall, .n1):          return .epic

        case (.burned, .n5):                                                  return .rare
        case (.burned, .n4), (.burned, .n3):                                  return .epic
        case (.burned, .n2), (.burned, .n1):                                  return .legendary

        case (.leechRecovered, .n5), (.leechRecovered, .n4):                  return .rare
        case (.leechRecovered, .n3), (.leechRecovered, .n2):                  return .epic
        case (.leechRecovered, .n1):                                          return .legendary
        }
    }
}
```

- [ ] **Step 3: Commit**

```
feat(rpg): BadgeRamping — mastery-event rarity scales with learner JLPT level
```

---

## Task 6: Add `jlptLevel` to `CardDTO`

**Files:**
- Modify: `IkeruCore/Sources/Repositories/CardRepository.swift` (CardDTO struct lives there)
- Test: `IkeruCore/Tests/Repositories/CardDTOJLPTLevelTests.swift`

- [ ] **Step 1: Read existing CardDTO**

Open `CardRepository.swift` and locate the `public struct CardDTO`. Note all init params.

- [ ] **Step 2: Write the failing tests**

Construct a CardDTO with all existing required init params plus the new `jlptLevel: nil` and `.n5` cases. Adapt to the actual init signature.

- [ ] **Step 3: Implement**

Add `public let jlptLevel: JLPTLevel?` to `CardDTO`. Update `init` to take `jlptLevel: JLPTLevel? = nil` (default keeps every existing call site source-compatible).

- [ ] **Step 4: Verify all existing CardDTO callers still build**

Run: `swift build --package-path IkeruCore` and `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```
feat(srs): CardDTO.jlptLevel optional field (nil for legacy/untagged)
```

---

## Task 7: Add `jlptLevel` column to SwiftData Card model

**Files:**
- Modify: the SwiftData `Card` model (search for `@Model.*Card` or `class Card` near `CardRepository`)

- [ ] **Step 1: Locate the SwiftData Card model**

Run: `rg -n "@Model" /Users/batum/Projects/Ikeru/IkeruCore/Sources --type swift | grep -i card`

- [ ] **Step 2: Add the column**

```swift
@Attribute var jlptLevel: String?  // raw JLPTLevel.rawValue; SwiftData prefers stable raw types
```

Add a computed bridge if helpful:

```swift
var jlptLevelEnum: JLPTLevel? {
    get { jlptLevel.flatMap(JLPTLevel.init(rawValue:)) }
    set { jlptLevel = newValue?.rawValue }
}
```

- [ ] **Step 3: Update `CardRepository.toDTO` / `fromDTO`**

Round-trip the new field through the Model ↔ DTO mapping. Untagged rows decode as `nil`.

- [ ] **Step 4: Build + run all card-touching tests**

Run: `swift test --package-path IkeruCore` — pre-existing failures stay red (Spec B accepted that), but no NEW failures should appear.

- [ ] **Step 5: Commit**

```
feat(srs): SwiftData Card.jlptLevel column + DTO round-trip
```

---

## Task 8: `BackupService` round-trips `jlptLevel`

**Files:**
- Modify: `IkeruCore/Sources/Services/BackupService.swift`
- Test: `IkeruCore/Tests/Services/BackupServiceJLPTLevelTests.swift`

- [ ] **Step 1: Write the failing test**

Construct a backup payload containing one tagged + one untagged card, encode with `JSONEncoder`, decode with `JSONDecoder`, verify both fields survive. Adapt the assertions to the actual `BackupPayload` shape — the principle is: the new optional field encodes when present and absent fields decode as `nil`.

- [ ] **Step 2: Update encode / decode**

Add `jlptLevel: JLPTLevel?` to whatever `Codable` struct represents a card in the backup payload. `JLPTLevel` already conforms to `Codable`.

- [ ] **Step 3: Verify older backups still load**

Manually craft a JSON payload without the `jlptLevel` field and confirm decode succeeds (the field is `Optional`, so `JSONDecoder` returns `nil` when absent).

- [ ] **Step 4: Commit**

```
feat(backup): round-trip CardDTO.jlptLevel through Codable payload
```

---

## Task 9: `JLPTBackfillService` — one-shot tagger for the N5 seed

**Files:**
- Create: `IkeruCore/Sources/Services/Progress/JLPTBackfillService.swift`
- Test: `IkeruCore/Tests/Services/Progress/JLPTBackfillServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import IkeruCore

@Suite("JLPTBackfillService")
struct JLPTBackfillServiceTests {

    @Test("Vocabulary card matching N5 seed gets tagged .n5")
    func n5VocabTagged() {
        // Construct a vocabulary CardDTO whose `front` is in the N5 seed dict.
        // result.first?.jlptLevel should be .n5
    }

    @Test("Kana card stays nil (kana is pre-N5, tracked separately)")
    func kanaStaysNil() {
        // Construct a vocab card with front "あ" — should NOT be tagged.
    }

    @Test("Card not in seed dictionary stays nil")
    func unknownStaysNil() {
        // Construct a vocab card with a front string not in the seed dict.
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation

public enum JLPTBackfillService {

    /// Returns a copy of `cards` with `jlptLevel` populated where the front
    /// matches a known N5 seed entry. Pure — no side effects.
    public static func tag(cards: [CardDTO]) -> [CardDTO] {
        cards.map { card in
            guard card.jlptLevel == nil else { return card }
            guard !N5SeedDictionary.contains(front: card.front, type: card.type) else {
                return card.with(jlptLevel: .n5)
            }
            return card
        }
    }
}

extension CardDTO {
    func with(jlptLevel: JLPTLevel?) -> CardDTO {
        CardDTO(
            id: id, front: front, back: back, type: type, fsrsState: fsrsState,
            easeFactor: easeFactor, interval: interval, dueDate: dueDate,
            lapseCount: lapseCount, leechFlag: leechFlag, jlptLevel: jlptLevel
        )
    }
}
```

`N5SeedDictionary` is a private file-scope set of strings — populate from the existing seed JSON or from a hardcoded list of the ~150 N5 vocab + 50 N5 kanji items the app currently ships.

- [ ] **Step 3: Verify**

Run: `swift test --package-path IkeruCore --filter JLPTBackfillServiceTests`

- [ ] **Step 4: Commit**

```
feat(progress): JLPTBackfillService — one-shot tagger for existing N5 seed
```

---

## Task 10: `RPGState.jlptBackfillVersion` + IkeruApp boot wire-in

**Files:**
- Modify: `IkeruCore/Sources/Models/RPG/RPGState.swift`
- Modify: `Ikeru/App/IkeruApp.swift` (similar pattern to existing `acknowledgedUnlocks` backfill from Spec A)

- [ ] **Step 1: Add the gating column on `RPGState`**

```swift
public var jlptBackfillVersion: Int = 0
```

- [ ] **Step 2: Add a one-shot Task in `IkeruApp` boot**

Pattern matches the existing `UnlockBackfillService` wire-in:

```swift
Task {
    let cards = await cardRepository.allCards()
    let state = ActiveProfileResolver.fetchActiveRPGState(in: context)
    if let state, state.jlptBackfillVersion == 0 {
        let tagged = JLPTBackfillService.tag(cards: cards)
        for card in tagged where card.jlptLevel != nil {
            await cardRepository.upsert(card)
            Logger.rpg.info("card.tagged.backfill cardId=\(card.id, privacy: .public) level=\(card.jlptLevel!.rawValue)")
        }
        state.jlptBackfillVersion = 1
        try? context.save()
    }
}
```

(Adapt to actual `cardRepository.upsert` / `update` method name.)

- [ ] **Step 3: Smoke-verify on simulator**

Boot, launch app, confirm the log shows N+M `card.tagged.backfill` lines once and never again on subsequent launches.

- [ ] **Step 4: Commit**

```
feat(progress): one-shot JLPT backfill on first launch — gate via RPGState.jlptBackfillVersion
```

---

## Task 11: Update `LearnerSnapshotBuilder` to populate per-level dicts

**Files:**
- Modify: `IkeruCore/Sources/Services/ExerciseUnlock/LearnerSnapshotBuilder.swift`
- Test: `IkeruCore/Tests/Services/ExerciseUnlock/LearnerSnapshotBuilderPerLevelTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import IkeruCore

@Suite("LearnerSnapshotBuilder per-level counts")
struct LearnerSnapshotBuilderPerLevelTests {

    @Test("Vocab card tagged N3 counts toward N3, N2, N1 (cumulative pool)")
    func n3VocabCountsCumulatively() {
        // Build one familiar+ vocab card tagged .n3, run builder, check dicts.
    }

    @Test("Untagged familiar+ card does NOT count toward any level")
    func untaggedExcluded() {
        // Build one familiar+ vocab card with jlptLevel = nil, run builder.
        // All vocabularyMasteredAtOrBelow values must be 0.
    }
}
```

- [ ] **Step 2: Implement**

In the builder's `build(...)`, add three dictionary computations:

```swift
let vocabAtOrBelow = JLPTLevel.allCases.reduce(into: [JLPTLevel: Int]()) { acc, level in
    acc[level] = cards.filter {
        $0.type == .vocabulary &&
        masteryLevel(of: $0) >= .familiar &&
        $0.jlptLevel != nil &&
        ($0.jlptLevel ?? .n1) <= level
    }.count
}
// Same for kanji + grammar.
```

Pass them into the `LearnerSnapshot` constructor.

- [ ] **Step 3: Verify**

Run: `swift test --package-path IkeruCore --filter LearnerSnapshotBuilderPerLevelTests`

- [ ] **Step 4: Commit**

```
feat(progress): LearnerSnapshotBuilder populates per-level mastery dicts
```

---

## Task 12: Replace `ProgressService.computeJLPTEstimate` with the new pipeline

**Files:**
- Modify: `IkeruCore/Sources/Services/ProgressService.swift`
- Test: `IkeruCore/Tests/Services/ProgressServiceJLPTRebuildTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import IkeruCore

@Suite("ProgressService JLPT estimate rebuild")
struct ProgressServiceJLPTRebuildTests {

    @Test("Hiragana-only profile returns estimate.level == 'N5' with very low fraction")
    func kanaOnlyDoesNotSpike() async {
        // Construct a ProgressService with a card pool of only kana cards
        // (jlptLevel == nil because they're pre-N5).
        // Run loadDashboardData(); inspect data.jlptEstimate.
        // #expect(data.jlptEstimate.level == "N5")
        // #expect(data.jlptEstimate.masteryFraction <= 0.05)
    }

    @Test("Full N5-ready profile reports N5 with masteryFraction ≥ 0.85")
    func fullN5() async {
        // 100 N5 vocab + 50 N5 kanji + 5 N5 grammar familiar+, hiragana mastered.
    }
}
```

- [ ] **Step 2: Implement**

In `ProgressService.loadDashboardData`:

1. Replace `computeJLPTEstimate(allCards:)` call with `JLPTReadinessFormula.compute(snapshot: ...)` — the snapshot is built via `LearnerSnapshotBuilder`.
2. Project the legacy `JLPTEstimate` from the new report:

```swift
let report = JLPTReadinessFormula.compute(snapshot: snapshot)
let bestFitReq = JLPTReadinessRequirements.requirements(for: report.bestFit)
let masteredVocab = snapshot.vocabularyMasteredAtOrBelow[report.bestFit] ?? 0
let estimate = JLPTEstimate(
    level: report.bestFit.displayName,
    masteryFraction: report.bestFitConfidence,
    masteredCount: masteredVocab,
    totalRequired: bestFitReq.vocab
)
```

3. Delete the private `computeJLPTEstimate(allCards:)` function.

- [ ] **Step 3: Verify**

Run the new tests + the existing ProgressServiceTests. Pre-existing failures stay red; nothing new.

- [ ] **Step 4: Commit**

```
refactor(progress): ProgressService routes JLPT estimate through readiness formula
```

---

## Task 13: Wire `BadgeRamping` into `LootDropService.generateMasteryDrop`

**Files:**
- Modify: `IkeruCore/Sources/Services/LootDropService.swift`
- Modify: `Ikeru/ViewModels/SessionViewModel.swift` (the call site)
- Test: `IkeruCore/Tests/Services/LootDropMasteryRampingTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import IkeruCore

@Suite("LootDropService.generateMasteryDrop ramping")
struct LootDropMasteryRampingTests {

    @Test("Burned at N5 is rare; same event at N2 is legendary")
    func burnedRamping() {
        let n5Drop = LootDropService.generateMasteryDrop(for: .burned, learnerLevel: .n5)
        let n2Drop = LootDropService.generateMasteryDrop(for: .burned, learnerLevel: .n2)
        #expect(n5Drop.rarity == .rare)
        #expect(n2Drop.rarity == .legendary)
    }

    @Test("Iconography stays consistent across levels (only rarity changes)")
    func iconUnchanged() {
        let n5 = LootDropService.generateMasteryDrop(for: .graduation, learnerLevel: .n5)
        let n1 = LootDropService.generateMasteryDrop(for: .graduation, learnerLevel: .n1)
        #expect(n5.iconName == n1.iconName)
        #expect(n5.name == n1.name)
    }
}
```

- [ ] **Step 2: Add the new overload to `LootDropService`**

```swift
public static func generateMasteryDrop(
    for event: MasteryEvent,
    learnerLevel: JLPTLevel
) -> LootItem {
    let template = masteryTemplate(for: event)
    return LootItem(
        category: template.category,
        rarity: BadgeRamping.rarity(for: event, learnerLevel: learnerLevel),
        name: template.name,
        iconName: template.iconName
    )
}
```

Keep the existing `generateMasteryDrop(for:)` as a deprecated wrapper that delegates with `learnerLevel: .n5` to preserve source compatibility for any internal callers.

- [ ] **Step 3: Update the SessionViewModel call site**

In `gradeAndAdvance`, where `generateMasteryDrop(for: event)` is called, pass `learnerLevel: sessionJLPTLevel` (the field added in Spec B).

- [ ] **Step 4: Verify**

```bash
swift test --package-path IkeruCore --filter LootDropMasteryRampingTests
xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build | grep -E "BUILD SUCCEEDED|BUILD FAILED"
```

- [ ] **Step 5: Commit**

```
feat(rpg): mastery-event drops use BadgeRamping — rarity scales with learner level
```

---

## Task 14: `readiness.computed` telemetry (10% sampled)

**Files:**
- Modify: `IkeruCore/Sources/Services/ProgressService.swift`

- [ ] **Step 1: Add sampled log in `loadDashboardData`**

After the readiness report is computed:

```swift
if Int.random(in: 0..<100) < 10 {
    Logger.rpg.info(
        "readiness.computed bestFit=\(report.bestFit.rawValue) confidence=\(report.bestFitConfidence) n5=\(report.perLevel[.n5] ?? 0) n4=\(report.perLevel[.n4] ?? 0) n3=\(report.perLevel[.n3] ?? 0) n2=\(report.perLevel[.n2] ?? 0) n1=\(report.perLevel[.n1] ?? 0)"
    )
}
```

- [ ] **Step 2: Commit**

```
feat(telemetry): readiness.computed event (10% sampled)
```

---

## Task 15: `readiness.bestFit.changed` event

**Files:**
- Modify: `IkeruCore/Sources/Models/RPG/RPGState.swift` (persist last bestFit)
- Modify: `IkeruCore/Sources/Services/ProgressService.swift`

- [ ] **Step 1: Persist last bestFit on `RPGState`**

```swift
public var lastReadinessBestFit: String?
```

- [ ] **Step 2: Detect upward crossing in `loadDashboardData`**

```swift
if let last = state.lastReadinessBestFit.flatMap(JLPTLevel.init(rawValue:)) {
    if report.bestFit > last {
        Logger.rpg.info("readiness.bestFit.changed from=\(last.rawValue) to=\(report.bestFit.rawValue)")
    }
}
state.lastReadinessBestFit = report.bestFit.rawValue
```

(`JLPTLevel` is `Comparable` per the existing model.)

- [ ] **Step 3: Commit**

```
feat(telemetry): readiness.bestFit.changed event on level crossings
```

---

## Task 16: `badge.granted.ramped` event

**Files:**
- Modify: `IkeruCore/Sources/Services/LootDropService.swift`

- [ ] **Step 1: Log inside `generateMasteryDrop(for:learnerLevel:)`**

```swift
public static func generateMasteryDrop(
    for event: MasteryEvent,
    learnerLevel: JLPTLevel
) -> LootItem {
    let rarity = BadgeRamping.rarity(for: event, learnerLevel: learnerLevel)
    let template = masteryTemplate(for: event)
    Logger.rpg.info(
        "badge.granted.ramped event=\(event.rawValue) level=\(learnerLevel.rawValue) rarity=\(rarity.rawValue)"
    )
    return LootItem(
        category: template.category, rarity: rarity,
        name: template.name, iconName: template.iconName
    )
}
```

- [ ] **Step 2: Commit**

```
feat(telemetry): badge.granted.ramped event per mastery drop
```

---

## Task 17: Backwards-compat regression — legacy `JLPTEstimate` projection

**Files:**
- Test: `IkeruCore/Tests/Services/JLPTEstimateProjectionTests.swift`

- [ ] **Step 1: Verify the legacy shape still satisfies UI expectations**

```swift
import Testing
@testable import IkeruCore

@Suite("Legacy JLPTEstimate projection")
struct JLPTEstimateProjectionTests {

    @Test("Clean N5-ready profile projects level='N5', mastered=100, totalRequired=100")
    func n5ProjectionShape() async {
        // Construct a snapshot that produces report.bestFit == .n5, confidence == 1.0
        // Run ProgressService.loadDashboardData (or the projection helper directly).
        // #expect(estimate.level == "N5")
        // #expect(estimate.masteredCount == 100)
        // #expect(estimate.totalRequired == 100)
    }

    @Test("Hiragana-only profile projects masteryFraction ≤ 0.05")
    func kanaSpikeFix() async {
        // Re-prove the Spec A bug fix at the projection layer.
    }
}
```

- [ ] **Step 2: Commit**

```
test(progress): legacy JLPTEstimate projection regression — kana-spike fix + N5 shape
```

---

## Task 18: Smoke test on simulator + progress doc

**Files:**
- Create: `docs/design-specs/2026-05-10-progress-formulas-progress.md`

- [ ] **Step 1: Boot, build, install, launch**

```bash
xcrun simctl boot 'iPhone 17' || true
xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' \
    -derivedDataPath /tmp/ikeru-build-specc build | grep -E "BUILD SUCCEEDED|BUILD FAILED"
xcrun simctl install booted /tmp/ikeru-build-specc/Build/Products/Debug-iphonesimulator/Ikeru.app
xcrun simctl launch booted com.ikeru.app
```

- [ ] **Step 2: Verify backfill log fires once**

```bash
xcrun simctl spawn booted log show --predicate 'subsystem == "com.ikeru"' --info --last 2m \
    | grep -E "card\.tagged\.backfill|readiness\.computed|readiness\.bestFit\.changed|badge\.granted\.ramped"
```

Expected on first launch: N+M `card.tagged.backfill` entries (one per N5-seed card). On second launch: zero (gated by `jlptBackfillVersion`).

- [ ] **Step 3: Run a quick session to verify a graduation badge fires at the new ramped rarity**

Drill 1 fresh card via Étude → Compose. After `.good` grade, look for `badge.granted.ramped event=graduation level=n5 rarity=common` in the log.

- [ ] **Step 4: Verify the JLPT gauge no longer spikes**

Open the dashboard / Étude tab on a fresh profile; confirm the JLPT readiness display shows a small fraction (≤ 5 %) rather than the previous ~92 %.

- [ ] **Step 5: Write the progress doc** mirroring Spec A and Spec B's:

- Commit log
- Decisions made during implementation (deviations from plan)
- Build & test state
- Smoke-test results
- Pre-existing failures explicitly out-of-scope
- Follow-ups for a separate PR

- [ ] **Step 6: Commit**

```
docs(spec-c): smoke-tested 18/18 — JLPT readiness rebuild + badge ramping ready to PR
```

---

## Task 19: Final review & PR-readiness

- [ ] **Step 1: Walk every acceptance criterion from `docs/design-specs/2026-05-10-progress-formulas-design.md` § Acceptance Criteria.**

Mark each. None should be unchecked.

- [ ] **Step 2: Run the full test suite**

```bash
swift test --package-path IkeruCore
xcodebuild test -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -10
```

Expected: all *new* Spec C tests green; pre-existing failures unchanged from Spec B's progress doc.

- [ ] **Step 3: Flip design-doc status**

In `docs/design-specs/2026-05-10-progress-formulas-design.md`, change `Status: Draft — awaiting approval before plan` → `Status: Implemented — 2026-05-XX, smoke-tested, ready to PR`.

- [ ] **Step 4: Commit**

```
docs(spec-c): mark design as implemented
```

---

## Self-Review

**Spec coverage check:**
- ✅ Per-level requirements table → Task 1
- ✅ Readiness report value type → Task 2
- ✅ Snapshot per-level dicts → Tasks 3, 11
- ✅ Weakest-link blender → Task 4
- ✅ Badge ramping table → Task 5
- ✅ CardDTO schema change → Task 6
- ✅ SwiftData migration → Task 7
- ✅ Backup round-trip → Task 8
- ✅ One-shot backfill → Tasks 9, 10
- ✅ ProgressService rewire → Task 12
- ✅ LootDropService ramping wire-in → Task 13
- ✅ Telemetry events → Tasks 14, 15, 16
- ✅ Legacy projection regression → Task 17
- ✅ Smoke test → Task 18
- ✅ Acceptance walk-through → Task 19

**Type consistency check:** `JLPTReadinessRequirements`, `JLPTReadinessReport`, `JLPTReadinessFormula`, `BadgeRamping`, `JLPTBackfillService`, `LearnerSnapshot.vocabularyMasteredAtOrBelow` — names match across all task descriptions.

**No placeholders.** Every task has either real code or a specific path + behavior. Tasks 8 (backup round-trip) and 9 (seed dictionary) explicitly note that the implementer adapts to the actual repo shape — both are local lookups, not architectural decisions.

**Granularity:** Most tasks are 10–25 minutes. Tasks 7 (SwiftData migration) and 9 (seed dictionary population) are the largest — read them first to confirm fit with existing data layer.

---

## Execution Handoff

Two execution options:

**1. Subagent-Driven (recommended)** — fresh subagent per task, two-stage review between tasks, fast iteration.

**2. Inline / Manual Execution** — execute tasks in this session task-by-task, with checkpoints for review.

Tell me which.
