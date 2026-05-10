# Spec C — Progress Formulas · Implementation Progress

**Date:** 2026-05-10
**Branch:** design/wabi-refinements
**Design:** [2026-05-10-progress-formulas-design.md](./2026-05-10-progress-formulas-design.md)
**Plan:** [2026-05-10-progress-formulas-plan.md](./2026-05-10-progress-formulas-plan.md)
**Status:** **19 of 19 tasks complete** · build green · smoke-tested · ready to PR

---

## Implementation Commits (chronological)

Cluster 1 — Pure-core readiness formula

- `3fa8ec7` feat(progress): JLPTReadinessRequirements per-level table (5 levels, 7 axes)
- `88fac9f` feat(progress): JLPTReadinessReport value type (per-level + bestFit + confidence)
- `764c674` feat(progress): LearnerSnapshot per-level mastery dicts (vocab/kanji/grammar)
- `a08011a` feat(progress): JLPTReadinessFormula — weakest-link blender across 5 axes
- `5057d18` feat(rpg): LootRarity adds .uncommon tier (between .common and .rare)
- `3263452` feat(rpg): BadgeRamping — mastery-event rarity scales with learner JLPT level

Cluster 2 — Schema + backfill

- `4860284` feat(srs): CardDTO.jlptLevel optional field (nil for legacy/untagged)
- `2080a6d` feat(srs): SwiftData Card.jlptLevel column + DTO round-trip
- `7bbe067` feat(backup): round-trip CardDTO.jlptLevel through Codable payload
- `2a247a0` feat(progress): JLPTBackfillService — one-shot tagger for existing N5 seed
- `0a9cd2f` feat(progress): one-shot JLPT backfill on first launch — gate via RPGState.jlptBackfillVersion
- `0936ce8` fix(rpg): propagate LootRarity.uncommon through view-side switch statements

Cluster 3 — Pipeline wiring

- `e59257e` feat(progress): LearnerSnapshotBuilder populates per-level mastery dicts
- `55f07b7` refactor(progress): ProgressService routes JLPT estimate through readiness formula
- `bf76e5f` feat(rpg): mastery-event drops use BadgeRamping — rarity scales with learner level

Cluster 4 — Telemetry

- `c3d247f` feat(telemetry): readiness.computed event (10% sampled)
- `caade09` feat(telemetry): badge.granted.ramped event per mastery drop
- `fab974d` feat(telemetry): readiness.bestFit.changed event on level crossings

Total: **18 implementation commits.**

---

## Decisions / Deviations from Plan

**Task 5 — LootRarity extension (deviation).** The plan assumed `LootRarity` already had an `.uncommon` case. It didn't — the enum was 4-tier (`.common/.rare/.epic/.legendary`). Added `.uncommon` between `.common` and `.rare` with `sortOrder = 1`, bumped subsequent ranks (rare=2, epic=3, legendary=4). Added the matching template arm in `LootDropService.randomTemplate(for:)` with four wabi-themed templates (Bamboo Sprig, Practice Sutra, Tea Cup, Misty Morning). View-side exhaustive switches in `LootDropView`, `LootRevealView`, and `RPGProfileView` were extended with an `.uncommon` case using `IkeruTheme.Colors.Rarity.uncommon = 0x84A07C` (soft moss).

**Task 9 — JLPT backfill seed (deviation, slight).** Plan said "hardcoded sample dictionary." Subagent extracted the actual content from `n5-content.sqlite` instead — 205 N5 vocab fronts + 90 N5 kanji as `Set<String>` literals. Matches the production seed exactly so existing learners get correctly tagged on first launch.

**Task 15 — bestFit crossing detection (architectural reroute).** Plan put the upward-crossing observation inside `ProgressService.computeJLPTReadinessEstimate`. Problem: IkeruCore can't reach `RPGState` (ActiveProfileResolver lives in app layer, and adding a SwiftData dependency on the core cascade-broke 5 call sites). Resolved by moving the detection one layer up to `RPGProfileViewModel.loadSkillBalance()` which already touches both `ProgressService.loadDashboardData()` and `ActiveProfileResolver.fetchActiveRPGState`. Same behaviour, cleaner layering. The new `RPGState.lastReadinessBestFit: String?` column is the only persisted state.

**Tasks 17–19 — test/smoke/doc (consolidated).** Task 17's regression test was effectively satisfied by `ProgressServiceJLPTRebuildTests.kanaOnlyDoesNotSpike` shipped in Cluster 3 — same assertion at the projection layer, no new file needed. Task 18 smoke ran on iPhone 17 (iPhone 15 unavailable in the current Xcode toolchain). Task 19 is this document.

---

## Build / Test State

```
$ swift test --package-path IkeruCore \
    --filter "JLPTReadinessFormula|JLPTBackfill|BadgeRamping|ProgressServiceJLPTRebuild|SkillXPLedger|LootDropService"

Test run with 36 tests in 6 suites passed after 0.121 seconds.
```

All Spec C critical tests green. Unrelated stale failures (`KanaCardRepositoryTests`, `PlannerServiceTests`) predate Spec A and are tracked under follow-ups below — not regressions.

App build green via `xcodebuild -scheme Ikeru`.

---

## Smoke Test (iPhone 17 simulator, 2026-05-10)

- **Fresh install → onboarding → kana drill (hiragana あ-お).** Étude tab now reads *"Estimation JLPT N5 / 0 %"* — pre-Spec-C this same flow spiked to ~92 %. Visual confirmation captured at `/tmp/ikeru-spec-c-jlpt-fixed.png`.
- **Backfill gate.** First launch ran `JLPTBackfillService` once; `RPGState.jlptBackfillVersion` flipped 0 → 1. Subsequent launches: no re-run (verified via `os_log` stream).
- **Telemetry firing.** Captured 2 `readiness.computed bestFit=n5 confidence=0.000000 …` events across ~20 sampled dashboard loads (10% rate, consistent with `Int.random(in: 0..<100) < 10`). No `readiness.bestFit.changed` events (none expected — learner stayed at N5 throughout).
- **Four-winds row from Spec B.** Still present, still tinted, still rendering +XP correctly. No regression from Spec C wiring.

---

## Follow-ups (out of Spec C scope)

- **Seed-time tagging.** New cards from `n5-content.sqlite` import currently rely on the boot-time backfill. Move the tag into `CardSeedingService` directly so new installs never have a one-shot pass at all. Small refactor — file a separate ticket.
- **Hiragana CardType.** Kana cards are `.vocabulary` with `jlptLevel == nil`. Spec C correctly excludes them from per-level mastery counts, but it's a smell — a future `.kana` CardType (or a `pre-N5` JLPTLevel sentinel) would express intent better.
- **Stale tests.** `KanaCardRepositoryTests` and `PlannerServiceTests` fail with empty queues / 0-card mastery — they predate the `ActiveProfileResolver` rework and are out-of-date, not Spec C regressions. Triage in a separate sweep.
- **N4+ seed.** Backfill only seeds N5 today (matches the only content bundle that ships). When N4/N3 content lands, extend the `Set<String>` tables in `JLPTBackfillService` and bump `jlptBackfillVersion` to `2`.

---

## Ready to PR

Spec C ships the JLPT readiness rebuild, badge ramping, and supporting telemetry. Combined with Spec A (learning loop architecture) and Spec B (session lifecycle + XP attribution), the `design/wabi-refinements` branch is feature-complete for this design pass.
