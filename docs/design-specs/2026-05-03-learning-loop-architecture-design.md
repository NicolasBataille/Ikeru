# Spec A — Learning Loop Architecture

**Date:** 2026-05-03
**Branch:** design/wabi-refinements (continuation)
**Author:** Nico
**Status:** Approved — ready for implementation plan

---

## Problem

The current Ikeru learning loop is muddled. QA surfaced three concrete confusions and one unbounded one:

- **Concrete:** there are two "start session" affordances (Home and Study) with no clear differentiation; sessions feel too easy and too SRS-heavy for advanced learners; the JLPT readiness gauge spikes to 92 % after one kana lesson; the data model already enumerates 10 exercise types but only flashcard reviews ever appear in a session.
- **Unbounded:** the user can't articulate what each tab is *for*, which is the deeper problem — without a clear architecture, every formula (XP, readiness, badge curve) drifts.

This spec settles the architecture: what each tab does, what exercises exist, when each unlocks, how a session is composed, and what controls the user has. Spec B (lifecycle + XP attribution) and Spec C (progress formulas) build on this foundation.

## Goals

- A clear, single-sentence answer to "what is each tab for?"
- A research-grounded progression curve so exercise variety scales with learner level.
- Session composition that respects time budget, current skill balance, FSRS due cards, and unlocked content.
- A path from "advanced N3 learner needs varied content" to "the planner serves it."
- A consistent vocabulary (JLPT level, FSRS mastery) the rest of the app reuses.

## Non-Goals

- The exact session-end criteria, XP-per-exercise, and skill-attribution rules. Those are Spec B.
- The new JLPT readiness formula and badge ramping curves. Those are Spec C.
- Authoring the actual N5/N4/N3 content packs. Content production is a parallel workstream — this spec only specifies the *scaffolding* the planner expects.
- A redesign of the FSRS algorithm or the SRS card model. Those stay as-is.
- Onboarding flow changes. Existing onboarding remains; only the post-onboarding tab semantics evolve.

## Approach Overview

Two tabs, two clear roles:

| Tab | Role | Entry points |
|---|---|---|
| **Accueil (Home)** | "Today's recommendation" — one adaptive session the system composes, no configuration. | Single gold CTA: 「稽古を始める」/ "Begin practice". |
| **Étude (Study)** | "Browse + custom planner" — drill a single surface OR compose your own session with explicit filters. | A grid of unlocked exercise surfaces + a "Custom session" entry that opens the planner sheet. |

A shared `SessionPlanner` service produces a `SessionPlan` from `SessionPlannerInputs`. Home and Study just feed it different inputs:

- **Home inputs** = `(profile state, time-of-day, default duration from Settings, all unlocked exercise types)`. Composition rules apply automatically (skill-balance booster, variety tile, new-content drip).
- **Study inputs** = `(user-selected exercise types, user-selected JLPT levels, user-selected duration)`. No skill-balance feedback — user is in control.

A separate `ExerciseUnlockService` evaluates which of the 10 exercise types are available to the active profile based on research-grounded thresholds.

## Architecture

### `ExerciseType`

The data model already defines 10 cases via `ExerciseItem` (in `IkeruCore/Sources/Models/Session/ExerciseItem.swift`). Spec A introduces a parallel public enum `ExerciseType` to identify the *capability* (vs `ExerciseItem` which carries content payload):

```swift
public enum ExerciseType: String, Codable, CaseIterable, Sendable {
    case kanaStudy
    case kanjiStudy
    case vocabularyStudy
    case listeningSubtitled
    case fillInBlank
    case grammarExercise
    case sentenceConstruction
    case readingPassage
    case writingPractice
    case listeningUnsubtitled
    case speakingPractice
    case sakuraConversation
}
```

(Note: `listeningSubtitled` / `listeningUnsubtitled` collapse to a single `ExerciseItem.listeningExercise` payload at session-build time — only the *capability gate* is split.)

Each type maps to its primary `SkillType`:

| Type | Skill |
|---|---|
| kanaStudy / kanjiStudy / vocabularyStudy / fillInBlank / grammarExercise / readingPassage | reading |
| writingPractice / sentenceConstruction | writing |
| listeningSubtitled / listeningUnsubtitled | listening |
| speakingPractice / sakuraConversation | speaking |

### `ExerciseUnlockService`

Pure service. Decides whether a given exercise type is unlocked for a profile:

```swift
public enum ExerciseUnlockState: Sendable, Equatable {
    case unlocked
    case locked(reason: ExerciseLockReason)
}

public enum ExerciseLockReason: Sendable, Equatable {
    case vocabularyMastered(required: Int, current: Int)
    case kanjiMastered(required: Int, current: Int)
    case kanaMastered(syllabary: KanaScript)
    case grammarPointsMastered(required: Int, current: Int)
    case listeningAccuracyOver(required: Double, current: Double, window: Int)
    case listeningRecallOver(required: Double, current: Double, days: Int)
    case jlptLevelReached(required: JLPTLevel, current: JLPTLevel)
}

public protocol ExerciseUnlockService: Sendable {
    func state(for type: ExerciseType, profile: ProfileSnapshot) -> ExerciseUnlockState
    func unlockedTypes(profile: ProfileSnapshot) -> Set<ExerciseType>
    /// Detects newly unlocked types since `previous` and returns the set
    /// (used to fire one-time 「新しい稽古」 badges).
    func newlyUnlocked(profile: ProfileSnapshot, previous: Set<ExerciseType>) -> Set<ExerciseType>
}
```

`ProfileSnapshot` aggregates the inputs the service needs (mastered card counts by type, kana/kanji breakdown, listening accuracy rolling window, JLPT estimate). Computed once per session-planning request, not on every call.

### Unlock thresholds (research-grounded)

**Day 1 — always unlocked:**
- `kanaStudy`
- `kanjiStudy` (one card at a time, picks from the N5 list)
- `vocabularyStudy` (picks from N5 vocab)
- `listeningSubtitled` (receptive-first per SLA research)

**Earned via threshold:**

| Type | Threshold | Rationale |
|---|---|---|
| `fillInBlank` | 50 vocab @ familiar+ | Minimum lexical building blocks |
| `grammarExercise` | All 46 hiragana mastered | Particles & inflections need kana literacy |
| `sentenceConstruction` | 5 N5 grammar points familiar+ | Need parts to assemble |
| `readingPassage` | 100 vocab + 50 kanji @ familiar+ | ~95 % coverage of Tadoku L0 graded readers |
| `writingPractice` | Both kana scripts mastered + 50 vocab | Output needs scaffolding (Swain) |
| `listeningUnsubtitled` | ≥ 60 % accuracy on last 30 subtitled exercises | Sustained receptive proficiency |
| `speakingPractice` | ≥ 60 % listening recall over last 30 days | Output prerequisite (Swain) |
| `sakuraConversation` | JLPT estimate ≥ N4 (≥ 300 vocab + 30 N5 grammar familiar+) | Real conversation needs grammar foundation |

"@ familiar+" = `MasteryLevel.familiar` or higher in the existing scale (familiar / mastered / anchored). Excludes `.new` and `.learning`.

The 60 %/30-window thresholds avoid one-time fluke unlocks and require sustained competence.

### Each unlock fires once

`ExerciseUnlockService.newlyUnlocked(...)` returns deltas. The session orchestrator, after each completed session, calls it with `(currentSnapshot, previouslyKnownUnlocks)` and grants a one-time 「新しい稽古」 badge per newly unlocked type. The set of "previously known unlocks" lives on `RPGState` as `acknowledgedUnlocks: Set<ExerciseType>`.

### `SessionPlanner` service

Replaces / consolidates the existing `PlannerService` and `AdaptivePlannerService`. Single entry:

```swift
public protocol SessionPlanner: Sendable {
    func compose(inputs: SessionPlannerInputs) async -> SessionPlan
}

public struct SessionPlannerInputs: Sendable {
    public enum Source: Sendable, Equatable {
        case homeRecommendation
        case studyCustom(types: Set<ExerciseType>, jlptLevels: Set<JLPTLevel>)
    }
    public let source: Source
    public let durationMinutes: Int
    public let profile: ProfileSnapshot
    public let unlockedTypes: Set<ExerciseType>
}
```

For `Source.homeRecommendation`, composition follows the **Home composition skeleton** below. For `Source.studyCustom(...)`, composition skips skill-balance feedback and respects only the user-selected types + JLPT levels.

### Home composition skeleton

For a 15-minute session (linearly scaled for 5 / 30 / 45 min):

| Segment | Allocation | Content |
|---|---|---|
| **Review wave** | 40 % | FSRS-due SRS cards. If fewer than 5 are due, fill from the **lapse pool** (cards flagged by the existing `LeechDetectionService` — i.e., leeches and recently-lapsed cards). |
| **Skill-balance booster** | 30 % | One unlocked exercise targeting the current lowest-balance `SkillType` |
| **Variety tile** | 20 % | One unlocked exercise from a different skill, rotates daily (deterministic from `(profileID, day-of-year)`) |
| **New content drip** | 10 % | One new kanji or vocab introduction (drawn from the next-up N-level item) |

Allocations are *time targets*, not strict caps — the planner picks whole exercises whose estimated duration sums close to the target. A 15-min session is roughly: 6 min reviews / 4-5 min skill booster / 3 min variety / 1-2 min new content.

### Level-tied variety pool

The "skill-balance booster" and "variety tile" segments draw from level-appropriate sub-pools:

| JLPT estimate | Variety pool |
|---|---|
| **N5** | listening-subtitled, fill-in-blank |
| **N4** | + grammar-exercise, sentence-construction |
| **N3** | + reading-passage, writing-practice, listening-unsubtitled |
| **N2 / N1** | + speaking-practice, sakura-conversation, immersive-listening |

The pool intersects with `unlockedTypes` — if the learner is rated N3 but hasn't unlocked `speakingPractice`, it stays out of the pool.

### Rest day

Home shows the rest-day state when **all** of these hold:

- `dueCardCount < 5`
- skill imbalance ≤ 15 % (defined as `(maxSkill - minSkill) / maxSkill` across the four winds; e.g. {reading 80, listening 70, writing 65, speaking 68} → `(80-65)/80 = 18.75%` would NOT trigger; under 15 % does)
- no new-content queue items (no untouched N-level vocab/kanji ready to drip)
- user has completed a session in the last 24 h

When triggered:

```
今日は休
Rest day
```

…instead of the CTA. Study still works on demand. After 24 h with no session, the rest-day state expires and the CTA returns regardless of due count.

### Session duration as a Setting

`SessionDuration` (existing enum: micro / short / standard / focused) gets a sibling user preference:

```
@AppStorage("ikeru.session.defaultDurationMinutes") var defaultDuration = 15
```

Settings → Pratique → "Durée par défaut" with options 5 / 15 / 30 / 45 min. Default 15 min for new accounts.

Home's CTA always uses this value. Study's planner uses it as the initial value of its duration picker, but the user can override per-session.

### Study tab restructure

`ProgressDashboardView` (current Étude content) becomes a 2-section screen:

**Section 1 — Browse** (renamed "稽古場 / Practice ground")

A grid of tiles, one per unlocked `ExerciseType`. Locked types appear dimmed with a 「鍵」/「locked」 stamp and a tooltip stating the unlock requirement (read from `ExerciseLockReason`). Tap an unlocked tile → drills only that type for the user's default duration. Tap a locked tile → shows the unlock requirement and progress.

**Section 2 — Custom planner** (new "編成 / Compose")

A row that opens a sheet with three inputs:

1. **Exercise types** — multi-select from unlocked types only (chips)
2. **JLPT levels** — multi-select N5 → N1 (chips)
3. **Duration** — same picker as Settings (5 / 15 / 30 / 45 min)

A "Compose" button at the bottom calls `SessionPlanner.compose(.studyCustom(...))` and pushes into the active-session UI. The user's last-used selection is remembered (per profile) for one-tap re-runs.

The existing JLPT-estimate hero stays at the top of Étude as a context summary; the four-winds skill-balance card moves to the user's RPG profile (`Rang` tab) where it belongs.

### Sakura conversation gating note

`sakuraConversation` doesn't appear as a Browse tile — it lives behind the existing Chat tab. The unlock service still tracks its state because Home's variety tile may surface a Sakura suggestion at N4+. The Chat tab remains accessible from day one, but with the existing no-AI / pre-N4 explanation messaging when the user isn't yet on the conversation tier.

## Acceptance Criteria

- [ ] `ExerciseType` enum with all 12 cases (10 base + listeningUnsubtitled split + sakuraConversation) lives in `IkeruCore`.
- [ ] `ExerciseUnlockService` returns `unlocked` for the 4 day-1 types on a fresh profile.
- [ ] On a fresh N5 profile with 100 vocab + 50 kanji at familiar+, `readingPassage` returns `unlocked`; before that, it returns `locked(.vocabularyMastered(...))` or `locked(.kanjiMastered(...))` whichever fails first.
- [ ] After a session that crosses an unlock threshold, `newlyUnlocked(...)` returns the new type and a 「新しい稽古」 badge is granted exactly once.
- [ ] Home CTA always launches a session whose duration sums close to the user's `defaultDurationMinutes` setting (±10 %).
- [ ] Home composition skeleton applies: a 15-min session contains roughly 40/30/20/10 split across the four segments.
- [ ] Level-tied variety pool: an N5-rated learner never sees `speakingPractice` in Home (even if unlocked); an N3-rated learner with `readingPassage` unlocked may see it as variety tile.
- [ ] Study Browse grid shows all 12 types, dimmed for locked, tappable for unlocked.
- [ ] Study Custom planner sheet composes a session matching the user's filters; remembers last-used filters per profile.
- [ ] Rest-day state surfaces when all four conditions hold; expires after 24 h of no session.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Content packs (graded readers, listening prompts, sentence-construction templates) don't yet exist for all 12 types | Unlock state can return "ready but no content" — the planner gracefully skips types with empty content pools and logs a `contentDrought` event so we know to author content. The user-visible behavior: Home falls back to skill-balance booster from the next-best pool. |
| Level estimate (current `computeJLPTEstimate`) is broken (Spec C) | Spec A's planner reads the JLPT estimate produced by Spec C. During interim while only Spec A ships, the planner uses the existing buggy estimate — variety pool may be wrong but won't crash. Layer Spec C before scaling content. |
| User feels the rest-day state as "lazy app" | Rest-day expires after 24 h. Plus the user can still tap Étude → Browse to drill on demand. Make rest-day copy aspirational, not apologetic ("一日休 · honor the rest"). |
| Custom planner produces an empty session if user picks types with no content | Compose-button is disabled until at least one type with available content is selected. |
| Existing `PlannerService` callsites break during refactor | `SessionPlanner` keeps the existing `compose() -> SessionPlan` signature shape; old callers are updated in one pass. Existing Adaptive-planner tests (currently failing per `2026-05-02-tatami-fix-plan.md`) get rewritten against the new service. |

## Migration

- Existing profiles with 0 unlocks tracked in `RPGState.acknowledgedUnlocks` get the day-1 four types added on first read after this lands. No badges fired retroactively.
- Existing profiles whose current state already crosses one or more earned thresholds: the unlock service will surface those as "newly unlocked" on the first session-planning call after the update; one badge per type is granted. This is intentional — we want users to feel their existing progress recognized.
- `SessionDuration` enum stays as-is; the new `defaultDurationMinutes` setting maps to it via the existing `from(minutes:)` static.

## Telemetry

- `unlock.granted` — `(type, reason, timestamp)` per badge fired
- `session.composed` — `(source, durationMinutes, segmentBreakdown, variantsServed)` per session created
- `session.skipped.contentDrought` — `(type, reason)` when a type is gated out for missing content
- `restDay.shown` / `restDay.expired` — to validate the 24 h timeout works

## Out of Scope (revisit later)

- Spec B handles: session-end criteria, XP per exercise, skill XP attribution rules.
- Spec C handles: JLPT readiness formula rebuild, badge ramping curve.
- Onboarding curriculum sequencing (e.g., "first day teaches all 5 vowel kana before introducing K-line"). The planner today picks "next-up" by FSRS new-card priority; a curated onboarding sequence is its own spec.
- A separate "free practice" mode that ignores SRS scheduling. Not requested.
- Per-skill rest days (e.g., rest from speaking only). Single global rest-day flag for now.

## Open Questions

None — all locked during brainstorm.
