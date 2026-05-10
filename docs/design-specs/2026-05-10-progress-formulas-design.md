# Spec C — Progress Formulas

**Date:** 2026-05-10
**Branch:** design/wabi-refinements (continuation of Spec A and Spec B)
**Author:** Nico
**Status:** Implemented — 2026-05-10, smoke-tested, ready to PR. See [progress doc](./2026-05-10-progress-formulas-progress.md).

---

## Problem

Spec A settled the architecture; Spec B settled session lifecycle and per-skill XP attribution. The *progression formulas* on top — JLPT readiness and badge rarity — are still mathematically wrong.

- **JLPT readiness spikes after kana drills.** `ProgressService.computeJLPTEstimate` counts every card with `fsrsState.reps > 0` and divides by a flat per-level threshold. A learner who reviews 92 kana cards once gets `92/100 = 92 % N5 readiness` despite never having seen a single N5 vocab item or kanji. The gauge is a lie. Spec A flagged this directly: *"the JLPT readiness gauge spikes to 92 % after one kana lesson"*.
- **Mastery is mis-defined.** `reps > 0` includes cards graded `.again` (the FSRS state where the learner *failed* the card). The current readiness counts a single review of a card the learner doesn't know.
- **Per-N-level cards aren't distinguished.** Cards have no JLPT level field. Vocab from N5 and vocab from N3 contribute identically to the same readiness counter — there's no "you're ready for N3" signal that requires actually mastering N3 content.
- **Listening / writing / speaking aren't part of readiness at all.** Real JLPT readiness is reading + listening (Spec A's four-winds language captured this). The current formula ignores the other three winds entirely. A learner with 100 % vocab recognition and 0 % listening accuracy would read as "N5 ready" — clearly wrong.
- **Badge rarity is flat.** `MasteryEvent.rarity` returns a fixed tier per event regardless of where the learner is. Burning a 180-day card at N5 awards the same `.epic` badge as burning a 180-day card at N1. Progression rewards don't ramp.

## Goals

- A readiness formula that tracks the *weakest skill at a given JLPT level*, not the strongest.
- Per-N-level readiness that requires N-level-tagged content mastery, not raw card counts.
- A multi-skill blend that gates higher-level readiness on the four winds (reading, listening, writing, speaking) — same vocabulary as Spec A and Spec B's summary row.
- A badge ramping curve so the same mastery event feels heavier the deeper the learner gets.
- Pure-core, deterministic formulas — no external state. Test once with fixtures, ship.

## Non-Goals

- Authoring N4/N3/N2/N1 content packs. Content production is a parallel workstream — Spec C tags the existing N5 seed and treats untagged content as "ungated".
- New badge artwork or icon set. Spec C only changes the *rarity* of the badge that fires; the visual cosmetic (`iconName`, `name`) stays as-is.
- A redesign of FSRS, the SRS card model, or `MasteryLevel` thresholds. Those stay as-is.
- A new "JLPT practice test" feature (a real mock JLPT inside the app). That's its own surface; Spec C only powers the *estimate*.
- Settings UI to override or hide the readiness display. Show the truth.
- Per-skill rest days or per-skill streaks. Spec A already deferred those.

## Approach Overview

Three new pure pieces in `IkeruCore` plus one schema change:

| Concern | New piece |
|---|---|
| Per-N-level readiness math | `JLPTReadinessFormula.compute(snapshot:) -> JLPTReadinessReport`, pure function over `LearnerSnapshot` |
| Output shape | `JLPTReadinessReport` value type with `[JLPTLevel: Double]` per-level + `bestFit: JLPTLevel` + `bestFitConfidence: Double` |
| Card-level tagging | `jlptLevel: JLPTLevel?` field on `CardDTO` and the SwiftData model; existing N5 seed tagged at migration; `nil` excluded from per-level counts |
| Badge ramping | `BadgeRamping.rarity(for: event, learnerLevel:) -> LootRarity`, consumed by `LootDropService.generateMasteryDrop` (call site updated to pass the learner level) |

`ProgressService.computeJLPTEstimate` is replaced. The legacy `JLPTEstimate` value type stays public but is now a *projection* of `JLPTReadinessReport` — `level` = report.bestFit; `masteryFraction` = `report.perLevel[bestFit] ?? 0`. Existing UI consumers don't need to change.

## Architecture

### `JLPTReadinessReport`

```swift
public struct JLPTReadinessReport: Sendable, Equatable {
    /// Per-level readiness ratio in [0, 1]. 1.0 means every prerequisite for that
    /// level is met at the threshold; 0.0 means the learner has nothing yet.
    public let perLevel: [JLPTLevel: Double]

    /// The highest level whose readiness ≥ `bestFitThreshold`. Falls back to N5
    /// when nothing crosses the threshold.
    public let bestFit: JLPTLevel

    /// Readiness ratio of `bestFit` (0…1). Drives the headline gauge.
    public let bestFitConfidence: Double

    public static let bestFitThreshold: Double = 0.85
}
```

The legacy `JLPTEstimate` projects from this:
- `level` = `report.bestFit.displayLabel` (e.g., `"N5"`)
- `masteryFraction` = `report.bestFitConfidence`
- `masteredCount` / `totalRequired` = derived from the bestFit's vocabulary requirement (kept for backwards display compatibility — UI shows "X / Y mastered" against the *vocabulary* axis since that's the most legible single number).

### `JLPTReadinessFormula`

A pure function. Takes the learner snapshot, returns the report:

```swift
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
}
```

`readinessForLevel(_:snapshot:)` is the weak-link blender — see below.

#### Per-level requirements

Each level defines the minimum signals across the four-skill axes. Values are tuned to JLPT public study guides (Tanaka & MNN, Tobira, Kanzen Master).

| Level | Vocab @ familiar+ | Kanji @ familiar+ | Grammar @ familiar+ | Kana | Listening accuracy (last 30 subtitled) | Listening recall (last 30 days) |
|---|---|---|---|---|---|---|
| N5 | 100 | 50 | 5 | hiragana mastered | 60 % | — |
| N4 | 300 | 150 | 30 | both kana mastered | 60 % | — |
| N3 | 650 | 300 | 100 | both kana mastered | 65 % | 30 % |
| N2 | 1000 | 600 | 150 | both kana mastered | 70 % | 50 % |
| N1 | 2000 | 1000 | 250 | both kana mastered | 75 % | 70 % |

Thresholds for vocab/kanji/grammar are *cumulative* — to be N3-ready you need 650 vocab in your N3-or-below mastered pool. The pool is `card.jlptLevel ≤ targetLevel && masteryLevel >= .familiar`.

#### Weak-link blender

```swift
private static func readinessForLevel(_ level: JLPTLevel, snapshot: LearnerSnapshot) -> Double {
    let req = requirements(for: level)

    // Hard prerequisites — kana literacy must be present, period.
    guard req.requiresHiragana ? snapshot.hiraganaMastered : true,
          req.requiresKatakana ? snapshot.katakanaMastered : true else { return 0 }

    // Per-axis ratios capped at 1.0 — overshooting one axis doesn't compensate for another.
    let vocab    = ratio(snapshot.vocabularyMasteredAtOrBelow[level] ?? 0, req.vocab)
    let kanji    = ratio(snapshot.kanjiMasteredAtOrBelow[level] ?? 0,      req.kanji)
    let grammar  = ratio(snapshot.grammarPointsMasteredAtOrBelow[level] ?? 0, req.grammar)
    let listen   = ratioDouble(snapshot.listeningAccuracyLast30,           req.listenAccuracy)
    let recall   = req.listenRecall.map {
        ratioDouble(snapshot.listeningRecallLast30Days, $0)
    } ?? 1.0   // Spec defers recall threshold for N5/N4 — treat as satisfied.

    // Weakest-link: readiness = min over all required axes. A learner cannot
    // claim N3 readiness with N5 listening accuracy; the gauge tracks the
    // skill they need to work on most.
    return [vocab, kanji, grammar, listen, recall].min() ?? 0
}
```

The `min` is the heart of the formula. It punishes imbalance, which matches how the JLPT actually works — the test gates on every section, you can't over-perform on vocab to compensate for failing listening.

### `CardDTO.jlptLevel`

Add an optional field:

```swift
public struct CardDTO: Sendable, Identifiable {
    // ...existing fields...
    public let jlptLevel: JLPTLevel?      // nil for legacy / un-tagged cards
}
```

`nil` cards are excluded from `vocabularyMasteredAtOrBelow` / `kanjiMasteredAtOrBelow` / `grammarPointsMasteredAtOrBelow` counts at any level (they don't contribute to readiness; they still progress through FSRS). Once tagged, they fold into the right per-level pool.

`LearnerSnapshot` extends with per-level mastery dictionaries:

```swift
public struct LearnerSnapshot: Sendable, Equatable {
    // ...existing fields kept for backwards compatibility...
    public let vocabularyMasteredAtOrBelow: [JLPTLevel: Int]
    public let kanjiMasteredAtOrBelow: [JLPTLevel: Int]
    public let grammarPointsMasteredAtOrBelow: [JLPTLevel: Int]
}
```

The existing scalar fields like `vocabularyMasteredFamiliarPlus` continue to mean "across all tagged levels" — unchanged. The new dictionaries support per-level reasoning. `LearnerSnapshotBuilder` populates them by walking the card pool once per level, applying `card.jlptLevel != nil && card.jlptLevel <= level && masteryLevel >= .familiar`.

### `BadgeRamping`

Pure function. Takes the event and the learner's current level (read from `LearnerSnapshot.jlptLevel`), returns the rarity to use when generating the drop.

```swift
public enum BadgeRamping {
    public static func rarity(
        for event: MasteryEvent,
        learnerLevel: JLPTLevel
    ) -> LootRarity { /* see table */ }
}
```

#### Rarity table

| Event | N5 | N4 | N3 | N2 | N1 |
|---|---|---|---|---|---|
| `graduation` (first review of a new card) | common | common | common | uncommon | uncommon |
| `longIntervalRecall` (≥ 30 d interval) | uncommon | rare | rare | epic | epic |
| `burned` (≥ 180 d interval) | rare | epic | epic | legendary | legendary |
| `leechRecovered` (broke a leech) | rare | rare | epic | epic | legendary |

Reasoning: `graduation` is high-volume early on, so it stays low-rarity until N2 when it actually means tackling rarer content. `longIntervalRecall` and `burned` represent stable retention; their value compounds as the underlying content gets harder. `leechRecovered` is always meaningful (you broke a card you struggled with) — it just gets nuttier when the card is N1.

`LootDropService.generateMasteryDrop(for:)` adds a `learnerLevel:` parameter and routes through `BadgeRamping.rarity` instead of reading `event.rarity` directly.

### Update path through `ProgressService`

`ProgressService.computeJLPTEstimate(allCards:)` is replaced by:

```swift
public func computeReadinessReport(
    snapshot: LearnerSnapshot
) -> JLPTReadinessReport {
    JLPTReadinessFormula.compute(snapshot: snapshot)
}
```

`loadDashboardData()` builds a snapshot via `LearnerSnapshotBuilder` (already used by Spec A's planner) and projects the legacy `JLPTEstimate` from the new report. UI consumers (`EtudeView`, `ProgressDashboardView` if still around, etc.) keep reading `JLPTEstimate` and don't need to change.

## Acceptance Criteria

- [ ] A fresh profile with 0 mastered cards and `hiraganaMastered = false` reads `bestFit = .n5`, `bestFitConfidence = 0.0`, all `perLevel` ≈ 0.
- [ ] A profile with hiragana mastered + 100 vocab @ familiar+ + 50 kanji @ familiar+ + 5 grammar + 60 % listening accuracy reads `bestFit = .n5`, `bestFitConfidence ≥ 0.85`.
- [ ] A profile with the N5 prereqs above PLUS only 0 % listening accuracy reads `bestFit = .n5` *but* `bestFitConfidence < 0.85` — listening drags it down.
- [ ] A profile that satisfies every N3 axis EXCEPT listening recall (e.g. 25 % vs threshold 30 %) reads `bestFit ≤ .n4`, never `.n3` — the weakest link gates the level.
- [ ] Re-driving the smoke from Spec A ("the JLPT readiness gauge spikes to 92 % after one kana lesson"): doing a single hiragana drill, with no vocab or kanji mastered, returns `bestFitConfidence ≤ 0.05` (not 0.92).
- [ ] An untagged card (`jlptLevel == nil`) does NOT count toward any per-level mastery total even if `MasteryLevel >= .familiar`.
- [ ] `LootDropService.generateMasteryDrop(for: .burned, learnerLevel: .n5)` returns a `.rare` LootItem; same call with `learnerLevel: .n2` returns `.legendary`.
- [ ] `BadgeRamping.rarity(for: .graduation, learnerLevel:)` returns `.common` for N5–N3 and `.uncommon` for N2–N1.
- [ ] The legacy `JLPTEstimate` projection still produces `level: "N5"` / `masteredCount: 100` / `totalRequired: 100` for a clean N5-ready profile (UI back-compat).

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Adding `jlptLevel` to `CardDTO` is a SwiftData migration and a backup-format change | The field is `Optional`, default `nil`, no NOT NULL constraint. Backup format already round-trips `Codable` — `nil` decodes cleanly. Migration: tag existing seed cards as `.n5` (vocabulary + kanji), leave kana cards `nil`. |
| Existing untagged cards become invisible to readiness | That's intentional. The legacy formula was wrong because it ignored level. Untagged cards still progress through FSRS — they just don't move the readiness needle until tagged. Tag the seed; future content packs ship with tags. |
| Per-level requirement numbers feel arbitrary | All numbers live in one struct (`Requirements`) inside `JLPTReadinessFormula`. Calibration is one-line constants. Acceptance criteria pin invariants (weakest-link, kana prereq), not exact numbers. |
| Weak-link `min` makes the gauge feel stuck | That's the spec's intent — the gauge should match how the JLPT works. UI can surface the *limiting axis* (e.g., "Listening is your weakest link") so the user knows what to drill. Spec C only produces the report; the UI presentation is up to the consumer. |
| Badge rarity inflation breaks the loot economy | The ramping multiplier is bounded — same event family, just one tier higher per ~2 levels. Drop rates per session are gated by `LootDropService.shouldDropLoot` (Spec A unchanged), so volume doesn't change. Only *which loot table* gets sampled. |
| Listening signals (`listeningAccuracyLast30`, `listeningRecallLast30Days`) are zero on fresh profiles | The `requiresHiragana` / `requiresKatakana` hard gates catch the very-fresh case. For mid-game profiles with no listening yet, the listening axis ratio is 0.0, which correctly drags readiness down — that's the correct signal. |
| `LearnerSnapshotBuilder` becomes more expensive (per-level counts) | Cards are filtered once per level, O(N × 5). With N ≤ a few thousand, that's a few thousand comparisons — sub-millisecond. The builder is already not in the per-frame UI path; it runs at session-planning request time. |

## Migration

- Add `jlptLevel: JLPTLevel?` column to the SwiftData `Card` model. Default `nil` for existing rows.
- Run a one-time tag pass at first launch after this lands: every card whose `front` matches the N5 seed dictionary gets `jlptLevel = .n5`. Implementation lives in a new `JLPTBackfillService` keyed off `RPGState.jlptBackfillVersion` (start at 0, set to 1 after the pass).
- `BackupService` round-trips the new field as `Optional<JLPTLevel>`. Older backups (no `jlptLevel`) decode as `nil` — the backfill pass re-tags them on first use.
- The legacy `JLPTEstimate` value type stays public. UI code reading `.level` / `.masteryFraction` / `.masteredCount` / `.totalRequired` continues to work via the projection from `JLPTReadinessReport`.
- `LootDropService.generateMasteryDrop(for:)` keeps its existing signature for source compatibility but is deprecated; new call sites pass `learnerLevel`. Existing call site in `SessionViewModel` is updated in one commit.

## Telemetry

- `readiness.computed` — `(perLevel[N5..N1], bestFit, bestFitConfidence)` per dashboard load. 10 % sample.
- `readiness.bestFit.changed` — fired once when the user crosses a `bestFit` boundary up (e.g., N5 → N4). Drives a celebratory toast (UI work in a follow-up — Spec C only emits the event).
- `badge.granted.ramped` — `(event, learnerLevel, finalRarity)` per mastery drop. Confirms the ramping table fires correctly in production.
- `card.tagged.backfill` — `(cardId, jlptLevel)` for each card the one-time backfill pass tags. Volume-bounded by the seed size; safe to log unsampled.

## Out of Scope (revisit later)

- Authoring N4/N3/N2/N1 content packs.
- Per-skill rest days. Spec A already deferred this.
- Replacing FSRS with a different SRS algorithm.
- A real mock-test feature inside the app.
- A "JLPT exam booking" reminder system.
- UI surfaces for the per-level readiness breakdown beyond the existing single-gauge headline. Spec C produces `perLevel` for future UI iteration; this spec doesn't redesign the dashboard.

## Open Questions

None — locked during scoping.
