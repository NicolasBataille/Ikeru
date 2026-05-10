# Spec B — Session Lifecycle & XP Attribution

**Date:** 2026-05-04
**Branch:** design/wabi-refinements (continuation of Spec A)
**Author:** Nico
**Status:** Implemented — 2026-05-10, smoke-tested, ready to PR (see `2026-05-04-session-lifecycle-xp-progress.md`)

---

## Problem

Spec A settled the *architecture* — what each tab is for, what exercises exist, how a session is composed. The *lifecycle* of that session and the *economy* underneath it are still half-built:

- **Session-end is queue-driven only.** A session ends when its planned queue is fully reviewed, or when the user abandons. The new `defaultDurationMinutes` setting (5/15/30/45) is purely a *planning* hint passed to `SessionPlanner.compose`. If the planner over-estimates a card's duration the user gets cut short; if it under-estimates, the user is held past their target. There is no real time-budget cut-off.
- **XP is flat per grade.** `RPGConstants.xpForGrade` returns 6 for `.easy / .good / .hard` and 3 for `.again`, regardless of exercise type. A 30-second kana flashcard awards the same XP as a 5-minute reading passage at N3. With Spec A introducing 12 exercise types of widely varying weight, the flat curve becomes the lie of the system.
- **Skill XP doesn't exist as a session signal.** `skillBalance` (the four-winds card on Rang) is computed *read-side* by `ProgressService.computeSkillBalance` from every card's `MasteryLevel`. A finished session never visibly moves the four winds in real time — only the next FSRS rating shift does. The user can't see what a session *gave them*.
- **Multi-skill exercises have no attribution model.** A `listeningSubtitled` exercise is audio + text. A `sakuraConversation` is listening + speaking. There is no rule for how XP from a dual-skill exercise should split between winds.

Spec C handles the JLPT readiness formula and badge ramping curves. Those are downstream of the session-XP signal Spec B produces here.

## Goals

- Sessions end when the user *expects* them to — queue exhaustion **or** time-budget exhaustion, whichever comes first, with a "finish current item" grace.
- XP scales with exercise complexity (kana flashcard ≠ reading passage) and difficulty (N5 ≠ N3).
- Each session produces a visible, per-skill XP contribution surfaced on the session summary.
- Multi-skill exercises (listeningSubtitled, sakuraConversation, sentenceConstruction, writingPractice, speakingPractice) split XP across the relevant winds with documented ratios.
- Backwards-compatible: pure-flashcard sessions (kana / kanji / vocab) award the same total XP as today, so the existing curve isn't perturbed.

## Non-Goals

- The new JLPT readiness formula. Spec C.
- Badge ramping curves. Spec C.
- Quality-bonus XP for writing / speaking / reading-comprehension grading. The grading services for those don't exist yet — Spec B credits *engagement* (an exercise was completed), not *correctness on free-form output*. Quality bonuses can layer in later.
- A redesign of `SessionBonusService` (daily / streak XP). Those keep their current semantics — they live alongside the new per-exercise XP, not instead of it.
- A redesign of FSRS, `LeechDetectionService`, or `LootBoxService`. They consume the same `reviewedCount` they always have.
- Rebuilding `skillBalance` to be accumulated rather than mastery-derived. The four-winds card on Rang stays mastery-derived; Spec B adds a *parallel* per-session contribution signal.

## Approach Overview

Three new concerns, three small additions:

| Concern | New piece |
|---|---|
| Session-end policy | `SessionEndPolicy` value type + `SessionEndAction` enum, evaluated by `SessionViewModel` after every grade |
| XP per exercise | `ExerciseXPRule` table with per-type base + JLPT multiplier |
| Skill XP attribution | `SkillAttribution` table + `SkillXPLedger` actor scoped to the session, surfaced on `SessionSummaryView` |

All three live in `IkeruCore`. `SessionViewModel` consumes them at the existing grading callsite (around `ViewModels/SessionViewModel.swift:487`). No new screens. The session summary gets one new row.

## Architecture

### `SessionEndPolicy`

A pure value type evaluated after every grade and at the start of every new exercise:

```swift
public struct SessionEndPolicy: Sendable, Equatable {
    public let durationBudgetMinutes: Int
    public let queueLength: Int
    public let graceWindowSeconds: Int   // default 60 — see "queue exhaustion + grace" below
}

public struct SessionEndState: Sendable, Equatable {
    public let elapsedSeconds: Int
    public let completedCount: Int
    public let activeItemInFlight: Bool   // true while the user is mid-exercise
}

public enum SessionEndAction: Sendable, Equatable {
    case continueSession
    case completeAfterCurrent   // suppress the next exercise; let the in-flight one finish
    case completeNow            // queue empty AND no item in flight
}

public extension SessionEndPolicy {
    func evaluate(state: SessionEndState) -> SessionEndAction {
        let queueExhausted = state.completedCount >= queueLength
        let budgetExhausted = state.elapsedSeconds >= durationBudgetMinutes * 60

        if queueExhausted {
            return state.activeItemInFlight ? .completeAfterCurrent : .completeNow
        }
        if budgetExhausted {
            return state.activeItemInFlight ? .completeAfterCurrent : .completeNow
        }
        return .continueSession
    }
}
```

**`SessionViewModel` integration:** at the start of every `presentNextExercise`, evaluate the policy with `activeItemInFlight = false`. If the answer is `.completeNow` or `.completeAfterCurrent`, fall straight through to the summary screen. After every grade, evaluate with `activeItemInFlight = true`. If the answer is `.completeAfterCurrent`, set a flag so the *next* `presentNextExercise` short-circuits to summary.

**Telemetry:** the action that fires is recorded as `session.ended.budget` or `session.ended.queue`. `session.ended.abandon` already exists.

### `ExerciseXPRule`

Per-exercise-type XP, evaluated when the exercise *completes* (graded for flashcards, submitted for long-form). Final XP = `round(base × multiplier(level))`.

```swift
public enum ExerciseXPRule {
    /// Flashcard-style — XP delegates to the existing `RPGConstants.xpForGrade(_:)`
    /// curve so kana/kanji/vocab sessions match today's totals.
    case perGrade(grade: Grade, bonus: Int)
    /// Long-form — flat per-completion bounty.
    case perCompletion(base: Int)
}

public enum ExerciseXP {
    public static func rule(for type: ExerciseType, grade: Grade?) -> ExerciseXPRule { … }
    public static func multiplier(for level: JLPTLevel) -> Double { … }
    public static func award(type: ExerciseType, level: JLPTLevel, grade: Grade?) -> Int {
        let base: Int = {
            switch rule(for: type, grade: grade) {
            case .perGrade(let g, let bonus): return RPGConstants.xpForGrade(g) + bonus
            case .perCompletion(let base):    return base
            }
        }()
        return Int((Double(base) * multiplier(for: level)).rounded())
    }
}
```

#### Per-type table

| Type | Rule | Notes |
|---|---|---|
| `kanaStudy` | `.perGrade(g, bonus: 0)` | Same as today (6 / 3 XP). |
| `kanjiStudy` | `.perGrade(g, bonus: 2)` | +2 vs kana — radicals + reading + meaning is more cognitive load than a single kana. |
| `vocabularyStudy` | `.perGrade(g, bonus: 0)` | Same as today. |
| `fillInBlank` | `.perGrade(g, bonus: 1)` | Slight bump: requires retrieval *in context*, not just recognition. |
| `grammarExercise` | `.perCompletion(base: 8)` | Per item (one rule + one application). |
| `sentenceConstruction` | `.perCompletion(base: 12)` | Per sentence built from word-bank. |
| `readingPassage` | `.perCompletion(base: 25)` | Per passage. Calibrated against ~3 minutes of reading effort. |
| `writingPractice` | `.perCompletion(base: 18)` | Per prompt answered (output is high-effort). |
| `listeningSubtitled` | `.perCompletion(base: 10)` | Per clip. |
| `listeningUnsubtitled` | `.perCompletion(base: 14)` | Per clip — harder than subtitled, +40 %. |
| `speakingPractice` | `.perCompletion(base: 16)` | Per turn (prompt → user speaks → system feedback). |
| `sakuraConversation` | `.perCompletion(base: 20)` | Per multi-turn segment (≈3 exchanges). |

#### JLPT multiplier

| Level | Multiplier |
|---|---|
| N5 | 1.00 |
| N4 | 1.15 |
| N3 | 1.30 |
| N2 | 1.50 |
| N1 | 1.75 |

The multiplier captures both genuine difficulty and the longer effort horizon at higher levels. Calibrated so a 15-min session lands in the **80–150 XP** range across the board (vs. 60–90 today).

### `SkillAttribution`

A per-type split table mapping each `ExerciseType` to a `[SkillType: Double]` whose values sum to 1.0:

```swift
public struct SkillSplit: Sendable, Equatable {
    public let reading: Double
    public let writing: Double
    public let listening: Double
    public let speaking: Double
    // Invariant: reading + writing + listening + speaking == 1.0 (within 1e-9).
}

public enum SkillAttribution {
    public static func split(for type: ExerciseType) -> SkillSplit { … }
}
```

| Type | Reading | Writing | Listening | Speaking |
|---|---|---|---|---|
| `kanaStudy` | 1.0 | – | – | – |
| `kanjiStudy` | 1.0 | – | – | – |
| `vocabularyStudy` | 1.0 | – | – | – |
| `fillInBlank` | 1.0 | – | – | – |
| `grammarExercise` | 1.0 | – | – | – |
| `readingPassage` | 1.0 | – | – | – |
| `sentenceConstruction` | 0.6 | 0.4 | – | – |
| `writingPractice` | 0.2 | 0.8 | – | – |
| `listeningSubtitled` | 0.3 | – | 0.7 | – |
| `listeningUnsubtitled` | – | – | 1.0 | – |
| `speakingPractice` | – | – | 0.3 | 0.7 |
| `sakuraConversation` | – | – | 0.5 | 0.5 |

**Rationale for the split values:**
- `listeningSubtitled` 70/30 listening/reading mirrors the dual-channel processing literature (Vanderplank, captioning gives ~70 % audio cue salience when subs are present).
- `writingPractice` 80/20 writing/reading: the user reads the prompt, then writes — bulk of effort is output.
- `sentenceConstruction` 60/40 reading/writing: it's a writing exercise, but the word-bank reading load is non-trivial.
- `sakuraConversation` 50/50 listening/speaking: a balanced conversation hits both equally on average; per-turn variance evens out across a session.
- `speakingPractice` 30/70 listening/speaking: there's always a model utterance to listen to before the user speaks.

These are tuneable constants — they live in one file so playtest adjustments are one-line changes.

### `SkillXPLedger`

A short-lived actor scoped to the active session:

```swift
public struct SessionSkillContribution: Sendable, Codable, Equatable {
    public var reading: Int
    public var writing: Int
    public var listening: Int
    public var speaking: Int
    public static let zero = SessionSkillContribution(reading: 0, writing: 0, listening: 0, speaking: 0)
}

public actor SkillXPLedger {
    private(set) var contribution: SessionSkillContribution = .zero

    public func record(xp: Int, exerciseType: ExerciseType) {
        let split = SkillAttribution.split(for: exerciseType)
        contribution.reading   += Int((Double(xp) * split.reading).rounded())
        contribution.writing   += Int((Double(xp) * split.writing).rounded())
        contribution.listening += Int((Double(xp) * split.listening).rounded())
        contribution.speaking  += Int((Double(xp) * split.speaking).rounded())
    }

    public func snapshot() -> SessionSkillContribution { contribution }
}
```

`SessionViewModel` owns one ledger per session. After every successful grade / exercise completion, it calls `record(xp:exerciseType:)`. On session end, it reads `snapshot()` and passes it to `SessionSummaryView` for display. The contribution is **not persisted** as cumulative state — it's a per-session derivation. The cumulative four-winds card on Rang stays mastery-derived (unchanged).

### Session summary surface

`SessionSummaryView` gains a four-winds contribution row beneath the existing hero stat row:

```
   読 ・ READING       書 ・ WRITING
   +45                 +12

   聴 ・ LISTENING     話 ・ SPEAKING
   +18                 +5
```

Styling matches the existing `tatamiRoom(.standard)` cells with `MonCrest` icons. Skills with zero contribution render dimmer (paperGhost color) so the user can read the session's *shape* at a glance.

### Backwards compatibility

`RPGConstants.xpForGrade(_:)` stays public and unchanged. Flashcard-style exercise types (`kanaStudy`, `kanjiStudy`, `vocabularyStudy`, `fillInBlank`) delegate to it via `ExerciseXPRule.perGrade`. A pure-kana session at N5 awards exactly the same total XP as today (modulo the +0 bonus). Existing `RPGService.awardXP` callsites still work; the new `ExerciseXP.award(type:level:grade:)` is a *replacement* helper that `SessionViewModel` adopts in one pass.

## Acceptance Criteria

- [ ] A 15-min session ends within ±90 s of the 15-min mark even if the queue isn't drained.
- [ ] When the time budget fires mid-exercise, the active card / passage / clip finishes; the *next* exercise doesn't start.
- [ ] When the queue is exhausted before the budget, the session ends immediately with no idle wait.
- [ ] A pure-kana N5 session at 15 cards awards the same total XP as today (regression-tested against a fixture).
- [ ] An N3 `sentenceConstruction` awards `round(12 × 1.30) = 16` XP per sentence.
- [ ] After a session containing one `writingPractice` item awarding 18 XP at N5, `SessionSkillContribution` reads `(reading: 4, writing: 14, listening: 0, speaking: 0)` (within rounding).
- [ ] After a session containing one `listeningSubtitled` item awarding 10 XP at N4 (= 12 XP final), the contribution reads `(reading: 4, writing: 0, listening: 8, speaking: 0)`.
- [ ] `SessionSummaryView` renders the four-winds contribution row with non-zero values bold and zero values dimmed.
- [ ] Abandon flow continues to credit only the XP earned before abandon (no change).
- [ ] `SessionBonusService` daily + streak bonuses fire on the same triggers as today.
- [ ] No regression in `LootBoxService` drop probability (still keyed off `reviewedCount`).

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Time-budget cut-off feels punishing if it triggers mid-card | The `completeAfterCurrent` rule guarantees the user finishes whatever's on screen. A "1 min remaining" toast at `elapsed = duration − 60s` tells the user the budget is closing — no surprise. |
| The XP table feels arbitrary / will need tuning | All numbers live in one file (`ExerciseXP.swift`). Calibration delta is a one-line change. The acceptance criteria pin the *invariants* (kana ≤ reading, N3 multiplier = 1.3 ×) — actual numbers can shift between playtests. |
| Skill split percentages are a research claim that's hard to verify | They're starting points, documented inline with citations. Easy to re-tune. |
| Existing tests assume flat XP | Two tests need rewriting: `SessionViewModelTests` XP assertions and `SessionBonusServiceTests` if it relies on per-grade-XP equality. The flashcard delegation keeps numerical regressions on those test fixtures to zero. |
| Skill balance ratio doesn't move when contributions land | That's intentional — balance is mastery-derived, contributions are per-session. The session summary shows contributions; the four-winds card on Rang continues to show balance. Document the distinction in the contribution row's tooltip. |
| Multi-skill split values produce non-integer XP that rounds inconsistently across runs | Round once at the end of `record(xp:exerciseType:)`, not per-skill — accumulation drifts < 1 XP per item, which is below user-visible threshold. |
| `SessionEndPolicy` makes timed sessions feel like a "race" | Calibration: time budget is *generous* by design — `defaultDurationMinutes` is the planner's *target* output time, so the budget cut-off only fires when the planner under-estimates. In normal flow, queue exhaustion fires first. |

## Migration

- `RPGState.totalXP` continues to accumulate as before. No DB migration.
- `SessionSkillContribution` is *not* persisted as cumulative state — it's a per-session value passed into `SessionSummaryView` and dropped when the session ends.
- `RPGConstants.xpForGrade` stays public; flashcard types delegate to it.
- Existing `xpEarned` field on `SessionViewModel` continues to be the running session total. Internally it's now the sum of `ExerciseXP.award(...)` results instead of `RPGConstants.xpForGrade(grade)` — a behavioral change for non-flashcard exercises only.

## Telemetry

- `session.ended.budget` — `(durationBudgetMinutes, elapsedSeconds, completedCount, queueLength)` fired when the time budget closed the session
- `session.ended.queue` — same payload, when queue exhaustion fired
- `session.ended.abandon` — already exists, unchanged
- `xp.attributed` — `(exerciseType, level, base, multiplier, finalXP, splitReading, splitWriting, splitListening, splitSpeaking)` per item — high-volume; sample at 10 % in production
- `summary.contribution.viewed` — `(SessionSkillContribution)` once per session-summary appearance — confirms users actually see the new row

## Out of Scope (revisit later)

- Spec C handles: JLPT readiness formula rebuild, badge ramping curve.
- Quality-bonus XP (correctness multipliers on writing / speaking / reading-comp). Depends on grading services that don't yet exist.
- Per-skill rest days (Spec A already noted this is a single global rest-day flag for now).
- A "make-up" session for skills that fell behind their balance target. The mastery-derived four-winds card already nudges behavior via the planner's skill-balance booster segment (Spec A).
- Persisting `SessionSkillContribution` as cumulative per-skill XP. If we later decide the four winds should be accumulated, that's its own spec — for now, mastery-derived stays the single source of truth.

## Open Questions

None pending — locked during scoping.
