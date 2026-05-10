# Spec B — Session Lifecycle & XP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Spec B — give sessions a real time-budget end, replace flat-grade XP with per-exercise-type XP × JLPT-level multiplier, and surface per-session skill contribution on the summary screen.

**Architecture:** Three new pure-core pieces in `IkeruCore` (`SessionEndPolicy`, `ExerciseXP`, `SkillAttribution` + `SkillXPLedger`), wired into `SessionViewModel` at the existing grading callsite. One new row on `SessionSummaryView`. No data migration; no new persistence.

**Tech Stack:** Swift 6 strict concurrency, Swift Testing (`import Testing`), `@Observable` view models, SwiftUI for the summary row. Build via `swift test` for `IkeruCore` and `xcodebuild -scheme Ikeru` for the app.

**Branch:** `design/wabi-refinements` (continuation — same branch as Spec A).

**Convention:** one commit per task, tests-first. Match existing IkeruCore `Sources/Models/Session/` and `Sources/Services/` layout. Match existing `Ikeru/ViewModels/` and `Ikeru/Views/Session/` patterns.

**Source design doc:** `docs/design-specs/2026-05-04-session-lifecycle-xp-design.md` — read it before starting if you didn't write it.

---

## Task 1: `SessionEndState` value type

**Files:**
- Create: `IkeruCore/Sources/Models/Session/SessionEndState.swift`
- Test: `IkeruCore/Tests/Models/Session/SessionEndStateTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import IkeruCore

@Test("SessionEndState stores all fields")
func sessionEndStateInit() {
    let state = SessionEndState(elapsedSeconds: 120, completedCount: 3, activeItemInFlight: true)
    #expect(state.elapsedSeconds == 120)
    #expect(state.completedCount == 3)
    #expect(state.activeItemInFlight == true)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd IkeruCore && swift test --filter SessionEndStateTests`
Expected: FAIL with `cannot find 'SessionEndState' in scope`.

- [ ] **Step 3: Implement minimal type**

```swift
import Foundation

/// Snapshot of the data SessionEndPolicy needs to decide whether to end
/// the active session. Pure value type — no behavior.
public struct SessionEndState: Sendable, Equatable {
    public let elapsedSeconds: Int
    public let completedCount: Int
    public let activeItemInFlight: Bool

    public init(elapsedSeconds: Int, completedCount: Int, activeItemInFlight: Bool) {
        self.elapsedSeconds = elapsedSeconds
        self.completedCount = completedCount
        self.activeItemInFlight = activeItemInFlight
    }
}
```

- [ ] **Step 4: Verify test passes**

Run: `cd IkeruCore && swift test --filter SessionEndStateTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```
feat(session): SessionEndState value type for end-policy evaluation
```

---

## Task 2: `SessionEndAction` enum + `SessionEndPolicy.evaluate`

**Files:**
- Create: `IkeruCore/Sources/Models/Session/SessionEndPolicy.swift`
- Test: `IkeruCore/Tests/Models/Session/SessionEndPolicyTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import IkeruCore

@Suite("SessionEndPolicy.evaluate")
struct SessionEndPolicyTests {

    private let policy = SessionEndPolicy(durationBudgetMinutes: 15, queueLength: 10, graceWindowSeconds: 60)

    @Test("Continues when budget and queue both have headroom")
    func continueWithHeadroom() {
        let s = SessionEndState(elapsedSeconds: 60, completedCount: 2, activeItemInFlight: false)
        #expect(policy.evaluate(state: s) == .continueSession)
    }

    @Test("Completes after current when queue exhausts mid-exercise")
    func queueExhaustedMidExercise() {
        let s = SessionEndState(elapsedSeconds: 60, completedCount: 10, activeItemInFlight: true)
        #expect(policy.evaluate(state: s) == .completeAfterCurrent)
    }

    @Test("Completes now when queue exhausts and no item in flight")
    func queueExhaustedIdle() {
        let s = SessionEndState(elapsedSeconds: 60, completedCount: 10, activeItemInFlight: false)
        #expect(policy.evaluate(state: s) == .completeNow)
    }

    @Test("Completes after current when budget fires mid-exercise")
    func budgetFiresMidExercise() {
        let s = SessionEndState(elapsedSeconds: 15 * 60, completedCount: 4, activeItemInFlight: true)
        #expect(policy.evaluate(state: s) == .completeAfterCurrent)
    }

    @Test("Completes now when budget fires and no item in flight")
    func budgetFiresIdle() {
        let s = SessionEndState(elapsedSeconds: 15 * 60, completedCount: 4, activeItemInFlight: false)
        #expect(policy.evaluate(state: s) == .completeNow)
    }

    @Test("Queue exhaustion beats budget when both fire simultaneously")
    func queueWinsTie() {
        let s = SessionEndState(elapsedSeconds: 15 * 60, completedCount: 10, activeItemInFlight: false)
        #expect(policy.evaluate(state: s) == .completeNow)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd IkeruCore && swift test --filter SessionEndPolicyTests`
Expected: FAIL with `cannot find 'SessionEndPolicy' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Decision returned by SessionEndPolicy.evaluate.
public enum SessionEndAction: Sendable, Equatable {
    /// Keep the session running.
    case continueSession
    /// Suppress the next exercise; let the in-flight one finish.
    case completeAfterCurrent
    /// End immediately — no item in flight.
    case completeNow
}

/// Pure value type — decides when an active session ends.
/// Evaluated post-grade and at the start of every new exercise.
public struct SessionEndPolicy: Sendable, Equatable {
    public let durationBudgetMinutes: Int
    public let queueLength: Int
    public let graceWindowSeconds: Int

    public init(durationBudgetMinutes: Int, queueLength: Int, graceWindowSeconds: Int = 60) {
        self.durationBudgetMinutes = durationBudgetMinutes
        self.queueLength = queueLength
        self.graceWindowSeconds = graceWindowSeconds
    }

    public func evaluate(state: SessionEndState) -> SessionEndAction {
        let queueExhausted = state.completedCount >= queueLength
        let budgetExhausted = state.elapsedSeconds >= durationBudgetMinutes * 60

        if queueExhausted || budgetExhausted {
            return state.activeItemInFlight ? .completeAfterCurrent : .completeNow
        }
        return .continueSession
    }
}
```

- [ ] **Step 4: Verify tests pass**

Run: `cd IkeruCore && swift test --filter SessionEndPolicyTests`
Expected: PASS (6/6).

- [ ] **Step 5: Commit**

```
feat(session): SessionEndPolicy — queue OR budget exhaustion with finish-current grace
```

---

## Task 3: `ExerciseXPRule` enum

**Files:**
- Create: `IkeruCore/Sources/Models/RPG/ExerciseXP.swift` (initial sketch — extended in Tasks 4-6)
- Test: `IkeruCore/Tests/Models/RPG/ExerciseXPRuleTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import IkeruCore

@Suite("ExerciseXPRule")
struct ExerciseXPRuleTests {

    @Test("perGrade carries grade + bonus")
    func perGradeShape() {
        let rule = ExerciseXPRule.perGrade(grade: .good, bonus: 2)
        guard case .perGrade(let g, let bonus) = rule else { Issue.record("not perGrade"); return }
        #expect(g == .good)
        #expect(bonus == 2)
    }

    @Test("perCompletion carries base")
    func perCompletionShape() {
        let rule = ExerciseXPRule.perCompletion(base: 25)
        guard case .perCompletion(let base) = rule else { Issue.record("not perCompletion"); return }
        #expect(base == 25)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd IkeruCore && swift test --filter ExerciseXPRuleTests`
Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Rule describing how XP is awarded for a single exercise completion.
public enum ExerciseXPRule: Sendable, Equatable {
    /// Flashcard-style — XP delegates to RPGConstants.xpForGrade(_:) plus a
    /// per-type bonus. Keeps kana/kanji/vocab sessions matching today's totals.
    case perGrade(grade: Grade, bonus: Int)
    /// Long-form — flat per-completion bounty (reading passage, listening clip, etc.).
    case perCompletion(base: Int)
}
```

- [ ] **Step 4: Verify tests pass**

Run: `cd IkeruCore && swift test --filter ExerciseXPRuleTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```
feat(rpg): ExerciseXPRule enum — flashcard vs long-form XP shape
```

---

## Task 4: `ExerciseXP.rule(for:grade:)` per-type table

**Files:**
- Modify: `IkeruCore/Sources/Models/RPG/ExerciseXP.swift`
- Test: `IkeruCore/Tests/Models/RPG/ExerciseXPTableTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import IkeruCore

@Suite("ExerciseXP.rule per-type table")
struct ExerciseXPTableTests {

    @Test("kanaStudy is perGrade with no bonus")
    func kanaIsFlat() {
        let rule = ExerciseXP.rule(for: .kanaStudy, grade: .good)
        #expect(rule == .perGrade(grade: .good, bonus: 0))
    }

    @Test("kanjiStudy is perGrade with +2 bonus")
    func kanjiBonus() {
        let rule = ExerciseXP.rule(for: .kanjiStudy, grade: .good)
        #expect(rule == .perGrade(grade: .good, bonus: 2))
    }

    @Test("readingPassage is perCompletion 25")
    func readingPassage() {
        let rule = ExerciseXP.rule(for: .readingPassage, grade: nil)
        #expect(rule == .perCompletion(base: 25))
    }

    @Test("sakuraConversation is perCompletion 20")
    func sakura() {
        #expect(ExerciseXP.rule(for: .sakuraConversation, grade: nil) == .perCompletion(base: 20))
    }

    @Test("All 12 ExerciseType cases have a rule")
    func everyTypeCovered() {
        for type in ExerciseType.allCases {
            _ = ExerciseXP.rule(for: type, grade: .good)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd IkeruCore && swift test --filter ExerciseXPTableTests`
Expected: FAIL — `rule(for:grade:)` undefined.

- [ ] **Step 3: Implement (append to ExerciseXP.swift)**

```swift
public enum ExerciseXP {

    /// Per-type rule table. `grade` is required for `perGrade` types; pass any
    /// value for long-form types (it's ignored).
    public static func rule(for type: ExerciseType, grade: Grade?) -> ExerciseXPRule {
        switch type {
        case .kanaStudy:
            return .perGrade(grade: grade ?? .good, bonus: 0)
        case .kanjiStudy:
            return .perGrade(grade: grade ?? .good, bonus: 2)
        case .vocabularyStudy:
            return .perGrade(grade: grade ?? .good, bonus: 0)
        case .fillInBlank:
            return .perGrade(grade: grade ?? .good, bonus: 1)
        case .grammarExercise:
            return .perCompletion(base: 8)
        case .sentenceConstruction:
            return .perCompletion(base: 12)
        case .readingPassage:
            return .perCompletion(base: 25)
        case .writingPractice:
            return .perCompletion(base: 18)
        case .listeningSubtitled:
            return .perCompletion(base: 10)
        case .listeningUnsubtitled:
            return .perCompletion(base: 14)
        case .speakingPractice:
            return .perCompletion(base: 16)
        case .sakuraConversation:
            return .perCompletion(base: 20)
        }
    }
}
```

- [ ] **Step 4: Verify tests pass**

Run: `cd IkeruCore && swift test --filter ExerciseXPTableTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```
feat(rpg): ExerciseXP.rule per-type XP table (12 cases)
```

---

## Task 5: `ExerciseXP.multiplier(for:)` JLPT scale

**Files:**
- Modify: `IkeruCore/Sources/Models/RPG/ExerciseXP.swift`
- Test: `IkeruCore/Tests/Models/RPG/ExerciseXPMultiplierTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import IkeruCore

@Suite("ExerciseXP.multiplier")
struct ExerciseXPMultiplierTests {
    @Test("N5 = 1.0")
    func n5() { #expect(ExerciseXP.multiplier(for: .n5) == 1.0) }

    @Test("N4 = 1.15")
    func n4() { #expect(ExerciseXP.multiplier(for: .n4) == 1.15) }

    @Test("N3 = 1.30")
    func n3() { #expect(ExerciseXP.multiplier(for: .n3) == 1.30) }

    @Test("N2 = 1.50")
    func n2() { #expect(ExerciseXP.multiplier(for: .n2) == 1.50) }

    @Test("N1 = 1.75")
    func n1() { #expect(ExerciseXP.multiplier(for: .n1) == 1.75) }

    @Test("Multipliers strictly increase with level")
    func monotonic() {
        let levels: [JLPTLevel] = [.n5, .n4, .n3, .n2, .n1]
        let mults = levels.map(ExerciseXP.multiplier(for:))
        for i in 1..<mults.count {
            #expect(mults[i] > mults[i - 1])
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd IkeruCore && swift test --filter ExerciseXPMultiplierTests`
Expected: FAIL.

- [ ] **Step 3: Implement (append to `ExerciseXP`)**

```swift
extension ExerciseXP {
    public static func multiplier(for level: JLPTLevel) -> Double {
        switch level {
        case .n5: return 1.00
        case .n4: return 1.15
        case .n3: return 1.30
        case .n2: return 1.50
        case .n1: return 1.75
        }
    }
}
```

- [ ] **Step 4: Verify tests pass**

Run: `cd IkeruCore && swift test --filter ExerciseXPMultiplierTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```
feat(rpg): ExerciseXP.multiplier — JLPT level scale (N5 1.0 → N1 1.75)
```

---

## Task 6: `ExerciseXP.award(type:level:grade:)`

**Files:**
- Modify: `IkeruCore/Sources/Models/RPG/ExerciseXP.swift`
- Test: `IkeruCore/Tests/Models/RPG/ExerciseXPAwardTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import IkeruCore

@Suite("ExerciseXP.award")
struct ExerciseXPAwardTests {

    @Test("Kana .good at N5 = 6 (matches RPGConstants.xpForGrade)")
    func kanaN5Good() {
        #expect(ExerciseXP.award(type: .kanaStudy, level: .n5, grade: .good) == 6)
    }

    @Test("Kana .again at N5 = 3")
    func kanaN5Again() {
        #expect(ExerciseXP.award(type: .kanaStudy, level: .n5, grade: .again) == 3)
    }

    @Test("Kanji .good at N5 = 8 (6 base + 2 bonus)")
    func kanjiN5Good() {
        #expect(ExerciseXP.award(type: .kanjiStudy, level: .n5, grade: .good) == 8)
    }

    @Test("Reading passage at N5 = 25")
    func readingN5() {
        #expect(ExerciseXP.award(type: .readingPassage, level: .n5, grade: nil) == 25)
    }

    @Test("Reading passage at N3 = 33 (round(25 × 1.30))")
    func readingN3() {
        #expect(ExerciseXP.award(type: .readingPassage, level: .n3, grade: nil) == 33)
    }

    @Test("Sentence construction at N3 = 16 (round(12 × 1.30))")
    func sentenceN3() {
        #expect(ExerciseXP.award(type: .sentenceConstruction, level: .n3, grade: nil) == 16)
    }

    @Test("Sakura at N1 = 35 (round(20 × 1.75))")
    func sakuraN1() {
        #expect(ExerciseXP.award(type: .sakuraConversation, level: .n1, grade: nil) == 35)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd IkeruCore && swift test --filter ExerciseXPAwardTests`
Expected: FAIL.

- [ ] **Step 3: Implement (append to `ExerciseXP`)**

```swift
extension ExerciseXP {
    /// Final XP for an exercise completion. `grade` is required for
    /// flashcard-style types; pass `nil` for long-form types.
    public static func award(type: ExerciseType, level: JLPTLevel, grade: Grade?) -> Int {
        let base: Int
        switch rule(for: type, grade: grade) {
        case .perGrade(let g, let bonus):
            base = RPGConstants.xpForGrade(g) + bonus
        case .perCompletion(let b):
            base = b
        }
        return Int((Double(base) * multiplier(for: level)).rounded())
    }
}
```

- [ ] **Step 4: Verify tests pass**

Run: `cd IkeruCore && swift test --filter ExerciseXPAwardTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```
feat(rpg): ExerciseXP.award — base × multiplier with flashcard delegation
```

---

## Task 7: `SkillSplit` value type with sum-to-1.0 invariant

**Files:**
- Create: `IkeruCore/Sources/Models/Session/SkillAttribution.swift` (sketch — extended in Task 8)
- Test: `IkeruCore/Tests/Models/Session/SkillSplitTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import IkeruCore

@Suite("SkillSplit")
struct SkillSplitTests {

    @Test("Stores all four weights")
    func fields() {
        let split = SkillSplit(reading: 0.3, writing: 0.0, listening: 0.7, speaking: 0.0)
        #expect(split.reading == 0.3)
        #expect(split.writing == 0.0)
        #expect(split.listening == 0.7)
        #expect(split.speaking == 0.0)
    }

    @Test("sum() reports total")
    func sum() {
        let split = SkillSplit(reading: 0.3, writing: 0.4, listening: 0.2, speaking: 0.1)
        #expect(abs(split.sum() - 1.0) < 1e-9)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd IkeruCore && swift test --filter SkillSplitTests`
Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Per-exercise-type weighting that distributes earned XP across the four winds.
/// Invariant: reading + writing + listening + speaking == 1.0 (within 1e-9).
public struct SkillSplit: Sendable, Equatable {
    public let reading: Double
    public let writing: Double
    public let listening: Double
    public let speaking: Double

    public init(reading: Double, writing: Double, listening: Double, speaking: Double) {
        self.reading = reading
        self.writing = writing
        self.listening = listening
        self.speaking = speaking
    }

    public func sum() -> Double { reading + writing + listening + speaking }
}
```

- [ ] **Step 4: Verify tests pass**

Run: `cd IkeruCore && swift test --filter SkillSplitTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```
feat(session): SkillSplit — per-exercise-type weighting across four winds
```

---

## Task 8: `SkillAttribution.split(for:)` per-type table

**Files:**
- Modify: `IkeruCore/Sources/Models/Session/SkillAttribution.swift`
- Test: `IkeruCore/Tests/Models/Session/SkillAttributionTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import IkeruCore

@Suite("SkillAttribution.split")
struct SkillAttributionTests {

    @Test("kanaStudy is 100% reading")
    func kana() {
        let s = SkillAttribution.split(for: .kanaStudy)
        #expect(s.reading == 1.0)
        #expect(s.writing == 0.0)
        #expect(s.listening == 0.0)
        #expect(s.speaking == 0.0)
    }

    @Test("listeningSubtitled is 30/70 reading/listening")
    func listeningSubtitled() {
        let s = SkillAttribution.split(for: .listeningSubtitled)
        #expect(s.reading == 0.3)
        #expect(s.listening == 0.7)
    }

    @Test("writingPractice is 20/80 reading/writing")
    func writing() {
        let s = SkillAttribution.split(for: .writingPractice)
        #expect(s.reading == 0.2)
        #expect(s.writing == 0.8)
    }

    @Test("sakuraConversation is 50/50 listening/speaking")
    func sakura() {
        let s = SkillAttribution.split(for: .sakuraConversation)
        #expect(s.listening == 0.5)
        #expect(s.speaking == 0.5)
    }

    @Test("speakingPractice is 30/70 listening/speaking")
    func speaking() {
        let s = SkillAttribution.split(for: .speakingPractice)
        #expect(s.listening == 0.3)
        #expect(s.speaking == 0.7)
    }

    @Test("Every ExerciseType has a split that sums to 1.0")
    func everyTypeSumsToOne() {
        for type in ExerciseType.allCases {
            let s = SkillAttribution.split(for: type)
            #expect(abs(s.sum() - 1.0) < 1e-9, "\(type) split sums to \(s.sum())")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd IkeruCore && swift test --filter SkillAttributionTests`
Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
public enum SkillAttribution {
    public static func split(for type: ExerciseType) -> SkillSplit {
        switch type {
        case .kanaStudy, .kanjiStudy, .vocabularyStudy, .fillInBlank,
             .grammarExercise, .readingPassage:
            return SkillSplit(reading: 1.0, writing: 0.0, listening: 0.0, speaking: 0.0)
        case .sentenceConstruction:
            return SkillSplit(reading: 0.6, writing: 0.4, listening: 0.0, speaking: 0.0)
        case .writingPractice:
            return SkillSplit(reading: 0.2, writing: 0.8, listening: 0.0, speaking: 0.0)
        case .listeningSubtitled:
            return SkillSplit(reading: 0.3, writing: 0.0, listening: 0.7, speaking: 0.0)
        case .listeningUnsubtitled:
            return SkillSplit(reading: 0.0, writing: 0.0, listening: 1.0, speaking: 0.0)
        case .speakingPractice:
            return SkillSplit(reading: 0.0, writing: 0.0, listening: 0.3, speaking: 0.7)
        case .sakuraConversation:
            return SkillSplit(reading: 0.0, writing: 0.0, listening: 0.5, speaking: 0.5)
        }
    }
}
```

- [ ] **Step 4: Verify tests pass**

Run: `cd IkeruCore && swift test --filter SkillAttributionTests`
Expected: PASS (6/6).

- [ ] **Step 5: Commit**

```
feat(session): SkillAttribution per-type split table (12 cases, all sum to 1.0)
```

---

## Task 9: `SessionSkillContribution` value type

**Files:**
- Create: `IkeruCore/Sources/Models/Session/SessionSkillContribution.swift`
- Test: `IkeruCore/Tests/Models/Session/SessionSkillContributionTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import IkeruCore

@Suite("SessionSkillContribution")
struct SessionSkillContributionTests {

    @Test("zero starts at all-zero")
    func zero() {
        let z = SessionSkillContribution.zero
        #expect(z.reading == 0)
        #expect(z.writing == 0)
        #expect(z.listening == 0)
        #expect(z.speaking == 0)
    }

    @Test("total returns sum across four winds")
    func total() {
        let c = SessionSkillContribution(reading: 10, writing: 5, listening: 3, speaking: 2)
        #expect(c.total == 20)
    }

    @Test("Codable round-trip")
    func codable() throws {
        let original = SessionSkillContribution(reading: 1, writing: 2, listening: 3, speaking: 4)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SessionSkillContribution.self, from: data)
        #expect(decoded == original)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd IkeruCore && swift test --filter SessionSkillContributionTests`
Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// XP earned per skill in a single session. Not persisted as cumulative state —
/// reset to .zero on every new session, surfaced on SessionSummaryView.
public struct SessionSkillContribution: Sendable, Codable, Equatable {
    public var reading: Int
    public var writing: Int
    public var listening: Int
    public var speaking: Int

    public init(reading: Int, writing: Int, listening: Int, speaking: Int) {
        self.reading = reading
        self.writing = writing
        self.listening = listening
        self.speaking = speaking
    }

    public static let zero = SessionSkillContribution(reading: 0, writing: 0, listening: 0, speaking: 0)

    public var total: Int { reading + writing + listening + speaking }
}
```

- [ ] **Step 4: Verify tests pass**

Run: `cd IkeruCore && swift test --filter SessionSkillContributionTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```
feat(session): SessionSkillContribution value type (per-session four-winds XP)
```

---

## Task 10: `SkillXPLedger` actor

**Files:**
- Create: `IkeruCore/Sources/Services/SkillXPLedger.swift`
- Test: `IkeruCore/Tests/Services/SkillXPLedgerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
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
        #expect(snap.reading == 4)   // round(18 × 0.2) = 4
        #expect(snap.writing == 14)  // round(18 × 0.8) = 14
        #expect(snap.listening == 0)
        #expect(snap.speaking == 0)
    }

    @Test("Recording 12 XP for listeningSubtitled splits 4 reading / 8 listening")
    func listeningSubtitledSplit() async {
        let ledger = SkillXPLedger()
        await ledger.record(xp: 12, exerciseType: .listeningSubtitled)
        let snap = await ledger.snapshot()
        #expect(snap.reading == 4)   // round(12 × 0.3) = 4
        #expect(snap.listening == 8) // round(12 × 0.7) = 8
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd IkeruCore && swift test --filter SkillXPLedgerTests`
Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Per-session ledger that accumulates XP into the four winds using
/// SkillAttribution.split. Lives only for the duration of one session.
public actor SkillXPLedger {

    private var contribution: SessionSkillContribution = .zero

    public init() {}

    public func record(xp: Int, exerciseType: ExerciseType) {
        let split = SkillAttribution.split(for: exerciseType)
        let xpDouble = Double(xp)
        contribution.reading   += Int((xpDouble * split.reading).rounded())
        contribution.writing   += Int((xpDouble * split.writing).rounded())
        contribution.listening += Int((xpDouble * split.listening).rounded())
        contribution.speaking  += Int((xpDouble * split.speaking).rounded())
    }

    public func snapshot() -> SessionSkillContribution { contribution }
}
```

- [ ] **Step 4: Verify tests pass**

Run: `cd IkeruCore && swift test --filter SkillXPLedgerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```
feat(session): SkillXPLedger actor — per-session four-winds XP attribution
```

---

## Task 11: Wire `SessionEndPolicy` into `SessionViewModel`

**Files:**
- Modify: `Ikeru/ViewModels/SessionViewModel.swift`
- Test: `IkeruTests/SessionEndPolicyIntegrationTests.swift` (new)

- [ ] **Step 1: Read the existing session-completion path**

Read `Ikeru/ViewModels/SessionViewModel.swift` around the session-completion call (currently triggered when `reviewedCount >= sessionExercises.count` — search for `presentNextExercise` and the completion handler near line 581). Note where elapsed time is updated and where the next-exercise call is made.

- [ ] **Step 2: Write the failing integration test**

```swift
import Testing
import IkeruCore
@testable import Ikeru

@Suite("SessionEndPolicy integration")
struct SessionEndPolicyIntegrationTests {

    @Test("Time-budget exhaustion ends the session after current item finishes")
    func budgetEndsAfterCurrent() async {
        // Arrange: 30-item queue, 5-min budget — budget should fire while
        // queue still has work remaining.
        let vm = SessionViewModel.test_makeWithFixedQueue(items: 20, durationMinutes: 5)
        await vm.test_advance(elapsedSeconds: 5 * 60, gradeCurrent: .good)
        #expect(vm.test_isCompleting == true)
        #expect(vm.reviewedCount < 20) // didn't drain the queue
    }
}
```

(Add `test_makeWithFixedQueue`, `test_advance`, `test_isCompleting` as `#if DEBUG` test seams on `SessionViewModel`.)

- [ ] **Step 3: Run test to verify it fails**

Run: `xcodebuild test -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IkeruTests/SessionEndPolicyIntegrationTests 2>&1 | tail -30`
Expected: FAIL.

- [ ] **Step 4: Implement**

In `SessionViewModel`:

1. Add stored `private let endPolicy: SessionEndPolicy` initialized from `(durationMinutes, sessionExercises.count)` when the session starts.
2. Add `private var isCompletingAfterCurrent = false`.
3. Build a helper:

```swift
private func evaluateEndPolicy(activeItemInFlight: Bool) -> SessionEndAction {
    let state = SessionEndState(
        elapsedSeconds: Int(elapsedTime),
        completedCount: reviewedCount,
        activeItemInFlight: activeItemInFlight
    )
    return endPolicy.evaluate(state: state)
}
```

4. After every grade (post-`reviewedCount += 1`), call `evaluateEndPolicy(activeItemInFlight: true)` and:
   - `.continueSession` → present next exercise
   - `.completeAfterCurrent` → set `isCompletingAfterCurrent = true`; the next `presentNextExercise` short-circuits to summary
   - `.completeNow` → call existing `completeSession()` directly

5. At the start of `presentNextExercise()`, if `isCompletingAfterCurrent` is set OR `evaluateEndPolicy(activeItemInFlight: false) != .continueSession`, route to `completeSession()`.

6. Add `#if DEBUG` test seams: `test_makeWithFixedQueue(items:durationMinutes:)`, `test_advance(elapsedSeconds:gradeCurrent:)`, `test_isCompleting`.

- [ ] **Step 5: Verify test passes**

Run: `xcodebuild test -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IkeruTests/SessionEndPolicyIntegrationTests 2>&1 | tail -30`
Expected: PASS.

- [ ] **Step 6: Commit**

```
feat(session): wire SessionEndPolicy — time-budget OR queue exhaustion ends the run
```

---

## Task 12: "1 minute remaining" toast

**Files:**
- Modify: `Ikeru/ViewModels/SessionViewModel.swift`
- Modify: `Ikeru/Views/Session/ActiveSessionView.swift`
- Modify: `Ikeru/Localization/Localizable.xcstrings`

- [ ] **Step 1: Add observable signal on the view model**

```swift
public private(set) var oneMinuteRemainingFired = false
```

In the elapsed-time tick (where `elapsedTime += 1` happens):

```swift
let budgetSeconds = endPolicy.durationBudgetMinutes * 60
if !oneMinuteRemainingFired && elapsedTime >= Double(budgetSeconds - 60) {
    oneMinuteRemainingFired = true
}
```

- [ ] **Step 2: Add toast in `ActiveSessionView`**

Add `@State private var showOneMinuteToast = false` and an overlay:

```swift
.overlay(alignment: .top) {
    if showOneMinuteToast {
        Text("Session.OneMinuteRemaining", comment: "Toast shown 60s before time budget ends the session")
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .tatamiRoom(.glass, padding: 0)
            .padding(.top, 8)
            .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
.onChange(of: viewModel.oneMinuteRemainingFired) { _, fired in
    guard fired else { return }
    withAnimation { showOneMinuteToast = true }
    Task {
        try? await Task.sleep(for: .seconds(3))
        withAnimation { showOneMinuteToast = false }
    }
}
```

- [ ] **Step 3: Add localized strings**

In `Ikeru/Localization/Localizable.xcstrings`, add `Session.OneMinuteRemaining`:
- EN: "1 minute remaining"
- FR: "Une minute restante"

- [ ] **Step 4: Smoke test on simulator**

Run a 5-min session, confirm the toast appears at the 4:00 mark and disappears 3 s later.

- [ ] **Step 5: Commit**

```
feat(session): one-minute-remaining toast before budget cut-off
```

---

## Task 13: Wire `ExerciseXP.award` into `SessionViewModel`

**Files:**
- Modify: `Ikeru/ViewModels/SessionViewModel.swift`
- Test: `IkeruTests/SessionXPRegressionTests.swift` (new)

- [ ] **Step 1: Identify the current XP-award path**

Today (around `Ikeru/ViewModels/SessionViewModel.swift:487`):
```swift
let result = RPGService.awardXP(grade: grade, ...)
```

`RPGService.awardXP` calls `RPGConstants.xpForGrade(grade)`. Replace this with `ExerciseXP.award(type:level:grade:)` and feed the result into `xpEarned += awarded`.

- [ ] **Step 2: Write the regression test (kana-only N5 fixture)**

```swift
import Testing
import IkeruCore
@testable import Ikeru

@Suite("Session XP backwards-compat (kana-only)")
struct SessionXPRegressionTests {

    @Test("15 kanaStudy .good grades at N5 award 90 XP (matches today)")
    func kanaN5Regression() async {
        let vm = SessionViewModel.test_makeKanaSession(itemCount: 15, level: .n5)
        await vm.test_gradeAll(.good)
        #expect(vm.xpEarned == 90) // 15 × 6
    }

    @Test("Mixed reading + kana session at N5 awards expected total")
    func mixedRegression() async {
        let vm = SessionViewModel.test_makeMixedSession(
            kana: 5,
            readingPassages: 1,
            level: .n5
        )
        await vm.test_gradeAllKanaThenComplete(.good)
        #expect(vm.xpEarned == 5 * 6 + 25) // 30 (kana) + 25 (reading) = 55
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `xcodebuild test -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IkeruTests/SessionXPRegressionTests 2>&1 | tail -30`
Expected: FAIL — non-flashcard XP not yet wired.

- [ ] **Step 4: Implement**

Replace the XP line in `SessionViewModel.grade(_:)`:

```swift
let exerciseType = currentExercise.exerciseType    // resolve from current exercise
let level = currentExercise.jlptLevel              // resolve from current card / passage
let xpAwarded = ExerciseXP.award(type: exerciseType, level: level, grade: grade)
xpEarned += xpAwarded
```

For long-form exercises that don't have a `Grade`, callers pass `grade: nil`.

Keep `RPGService.awardXP` for its side-effects (loot drops etc.) but replace the flat-XP delegation inside it with `ExerciseXP.award(...)`.

- [ ] **Step 5: Verify tests pass**

Run: `xcodebuild test -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IkeruTests/SessionXPRegressionTests 2>&1 | tail -30`
Expected: PASS.

- [ ] **Step 6: Run the full IkeruTests suite to confirm no regressions**

Run: `xcodebuild test -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -10`
Expected: All previously-passing tests still pass.

- [ ] **Step 7: Commit**

```
feat(session): replace flat-grade XP with ExerciseXP.award (per-type × level)
```

---

## Task 14: Wire `SkillXPLedger` into `SessionViewModel`

**Files:**
- Modify: `Ikeru/ViewModels/SessionViewModel.swift`

- [ ] **Step 1: Add ledger property + accessor**

```swift
private let ledger = SkillXPLedger()
public private(set) var skillContribution: SessionSkillContribution = .zero
```

- [ ] **Step 2: Record after every award**

In `grade(_:)`, after `xpEarned += xpAwarded`:

```swift
Task {
    await ledger.record(xp: xpAwarded, exerciseType: exerciseType)
    let snap = await ledger.snapshot()
    await MainActor.run {
        self.skillContribution = snap
    }
}
```

- [ ] **Step 3: Smoke test**

Run a session containing 1 kanaStudy + 1 writingPractice + 1 listeningSubtitled. Print `vm.skillContribution` at session end. Verify all four winds have the expected non-zero values.

- [ ] **Step 4: Commit**

```
feat(session): SkillXPLedger wired — skillContribution snapshot per session
```

---

## Task 15: `SessionSummaryView` four-winds contribution row

**Files:**
- Modify: `Ikeru/Views/Session/SessionSummaryView.swift`

- [ ] **Step 1: Add the row helper**

Insert a new private view between `heroStatRow` and `xpGainRail`:

```swift
private var fourWindsRow: some View {
    HStack(spacing: 10) {
        windCell(label: "Summary.Reading", japanese: "読",
                 mon: .asanoha, value: viewModel.skillContribution.reading)
        windCell(label: "Summary.Writing", japanese: "書",
                 mon: .genji, value: viewModel.skillContribution.writing)
        windCell(label: "Summary.Listening", japanese: "聴",
                 mon: .kikkou, value: viewModel.skillContribution.listening)
        windCell(label: "Summary.Speaking", japanese: "話",
                 mon: .maru, value: viewModel.skillContribution.speaking)
    }
}

@ViewBuilder
private func windCell(label: LocalizedStringKey, japanese: String,
                       mon: MonKind, value: Int) -> some View {
    VStack(spacing: 6) {
        HStack(spacing: 4) {
            MonCrest(kind: mon, size: 11,
                     color: value > 0 ? Color.ikeruPrimaryAccent : TatamiTokens.paperGhost)
            Text(japanese)
                .font(.system(size: 11, design: .serif))
                .foregroundStyle(value > 0 ? Color.ikeruTextPrimary : TatamiTokens.paperGhost)
        }
        Text("+\(value)")
            .font(.system(size: 22, weight: .light, design: .serif))
            .foregroundStyle(value > 0 ? Color.ikeruPrimaryAccent : TatamiTokens.paperGhost)
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(Color.ikeruTextSecondary)
    }
    .frame(maxWidth: .infinity)
    .tatamiRoom(.standard, padding: 12)
}
```

Wire into the body:

```swift
VStack(spacing: 18) {
    triumphHeader
    heroStatRow
    fourWindsRow      // ← new
    xpGainRail
    splitCells
    actions
}
```

- [ ] **Step 2: Add localized strings**

In `Ikeru/Localization/Localizable.xcstrings`, add four keys:
- `Summary.Reading` — EN "READING" / FR "LECTURE"
- `Summary.Writing` — EN "WRITING" / FR "ÉCRITURE"
- `Summary.Listening` — EN "LISTENING" / FR "ÉCOUTE"
- `Summary.Speaking` — EN "SPEAKING" / FR "PAROLE"

- [ ] **Step 3: Smoke test**

Build, run a mixed session, verify the four-winds row shows on summary with correct values.

- [ ] **Step 4: Commit**

```
feat(summary): four-winds contribution row — read/write/listen/speak per session
```

---

## Task 16: `session.ended.budget` / `session.ended.queue` telemetry

**Files:**
- Modify: `Ikeru/ViewModels/SessionViewModel.swift`

- [ ] **Step 1: Identify existing telemetry conventions**

Search for the existing log lines in `SessionViewModel`. Add a `Logger` instance if absent:

```swift
private let logger = Logger(subsystem: "com.ikeru", category: "session")
```

- [ ] **Step 2: Log the end action**

In `completeSession()`, branch on which action triggered the end:

```swift
if reviewedCount >= sessionExercises.count {
    logger.log("session.ended.queue durationMinutes=\(self.endPolicy.durationBudgetMinutes) elapsedSeconds=\(Int(self.elapsedTime)) completedCount=\(self.reviewedCount) queueLength=\(self.sessionExercises.count)")
} else {
    logger.log("session.ended.budget durationMinutes=\(self.endPolicy.durationBudgetMinutes) elapsedSeconds=\(Int(self.elapsedTime)) completedCount=\(self.reviewedCount) queueLength=\(self.sessionExercises.count)")
}
```

- [ ] **Step 3: Smoke test**

Run a 5-min session twice — once draining the queue, once letting the budget fire. Verify the right log line appears via `xcrun simctl spawn booted log stream --predicate 'category == "session"'`.

- [ ] **Step 4: Commit**

```
feat(telemetry): session.ended.budget / .queue events
```

---

## Task 17: `xp.attributed` event (sampled at 10 %)

**Files:**
- Modify: `Ikeru/ViewModels/SessionViewModel.swift`

- [ ] **Step 1: Add sampled logger**

In `grade(_:)`, after the XP award and ledger record:

```swift
if Int.random(in: 0..<100) < 10 {
    logger.log("xp.attributed type=\(exerciseType.rawValue) level=\(level.rawValue) finalXP=\(xpAwarded)")
}
```

- [ ] **Step 2: Smoke test**

Run a 30-card session; verify roughly 3 `xp.attributed` log lines appear.

- [ ] **Step 3: Commit**

```
feat(telemetry): xp.attributed event (10% sampled)
```

---

## Task 18: `summary.contribution.viewed` event

**Files:**
- Modify: `Ikeru/Views/Session/SessionSummaryView.swift`

- [ ] **Step 1: Log on appear**

```swift
.onAppear {
    let c = viewModel.skillContribution
    Logger(subsystem: "com.ikeru", category: "session").log(
        "summary.contribution.viewed reading=\(c.reading) writing=\(c.writing) listening=\(c.listening) speaking=\(c.speaking)"
    )
}
```

- [ ] **Step 2: Commit**

```
feat(telemetry): summary.contribution.viewed event
```

---

## Task 19: Backwards-compat regression — full kana-only fixture

**Files:**
- Modify: `IkeruCore/Tests/Models/RPG/ExerciseXPAwardTests.swift` (extends Task 6's tests)

- [ ] **Step 1: Add fixtures for every flashcard type**

```swift
@Test("Vocabulary at N5 .good awards 6 (no bonus, no scaling)")
func vocabN5() {
    #expect(ExerciseXP.award(type: .vocabularyStudy, level: .n5, grade: .good) == 6)
}

@Test("FillInBlank at N5 .good awards 7 (6 + 1 bonus)")
func fillN5() {
    #expect(ExerciseXP.award(type: .fillInBlank, level: .n5, grade: .good) == 7)
}

@Test("Vocabulary at N3 .good awards 8 (round(6 × 1.30))")
func vocabN3() {
    #expect(ExerciseXP.award(type: .vocabularyStudy, level: .n3, grade: .good) == 8)
}
```

- [ ] **Step 2: Verify**

Run: `cd IkeruCore && swift test --filter ExerciseXPAwardTests`
Expected: PASS.

- [ ] **Step 3: Commit**

```
test(rpg): expand ExerciseXP.award fixture coverage (vocab, fill-in-blank, N3 scaling)
```

---

## Task 20: Smoke test on simulator

**Files:**
- Create: `docs/design-specs/2026-05-04-session-lifecycle-xp-progress.md`

- [ ] **Step 1: Boot simulator + install app**

```bash
xcrun simctl boot 'iPhone 15' || true
xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 15' build
xcrun simctl install booted /path/to/Ikeru.app
xcrun simctl launch booted com.ikeru.Ikeru
```

- [ ] **Step 2: Run a 5-min session — let the budget fire**

Walk through 1 kana drill + 1 vocabulary drill until elapsed reaches 5 min. Verify:
- "1 minute remaining" toast at 4:00.
- Session does not start a new exercise after 5:00; current item finishes.
- Summary shows the four-winds row with correct values.
- Logs show `session.ended.budget`.

- [ ] **Step 3: Run a queue-exhausting session — verify queue path**

Set queue to 5 items, default duration 30 min. Drain the queue. Verify:
- Session ends immediately on last grade.
- Summary shows the four-winds row.
- Logs show `session.ended.queue`.

- [ ] **Step 4: Document results in progress doc**

Write a short progress doc parallel to Spec A's `2026-05-03-learning-loop-architecture-progress.md`. Capture: tasks 1-20 status, smoke-test screenshots, log excerpts.

- [ ] **Step 5: Commit**

```
docs(spec-b): smoke-test results — 20/20 tasks complete
```

---

## Task 21: Final review & PR-readiness

- [ ] **Step 1: Confirm all acceptance criteria from design doc**

Walk every checkbox in `docs/design-specs/2026-05-04-session-lifecycle-xp-design.md` § Acceptance Criteria. Mark each.

- [ ] **Step 2: Run the full test suite**

```bash
cd IkeruCore && swift test
xcodebuild test -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -10
```

Expected: green.

- [ ] **Step 3: Update design-doc status**

In `docs/design-specs/2026-05-04-session-lifecycle-xp-design.md`, change `Status: Draft — awaiting approval before plan` → `Status: Implemented — 2026-05-XX, smoke-tested, ready to PR`.

- [ ] **Step 4: Commit**

```
docs(spec-b): mark design as implemented
```

---

## Self-Review

**Spec coverage check:**
- ✅ Session-end policy → Tasks 1, 2, 11
- ✅ Time-budget end + finish-current grace → Task 11
- ✅ "1 minute remaining" toast → Task 12
- ✅ Per-type XP table → Task 4
- ✅ JLPT multiplier → Task 5
- ✅ XP award helper → Tasks 6, 13
- ✅ Skill split table → Tasks 7, 8
- ✅ SkillXPLedger → Tasks 10, 14
- ✅ Summary four-winds row → Task 15
- ✅ Telemetry events → Tasks 16, 17, 18
- ✅ Backwards-compat regression → Tasks 13, 19
- ✅ Smoke test → Task 20
- ✅ Acceptance-criteria walk-through → Task 21

**Type consistency check:** `SessionEndPolicy`, `SessionEndState`, `SessionEndAction`, `ExerciseXPRule`, `ExerciseXP`, `SkillSplit`, `SkillAttribution`, `SessionSkillContribution`, `SkillXPLedger` — names match across all task descriptions.

**No placeholders.** Every task has either real code or specific path + behavior. The smoke test (Task 20) is the only "fill in actual values from the run" step, which is intrinsic to smoke-testing.

**Granularity:** Most tasks are 5-15 minutes. Task 11 (SessionEndPolicy integration) is the largest — read it first to confirm fit with the existing SessionViewModel structure.

---

## Execution Handoff

Two execution options:

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task, two-stage review between tasks, fast iteration.

**2. Inline / Manual Execution** — execute tasks in this session task-by-task, with checkpoints for review.

Tell me which.
