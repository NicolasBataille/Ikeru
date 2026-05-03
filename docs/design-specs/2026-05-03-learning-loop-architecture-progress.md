# Spec A — Learning Loop Architecture · Implementation Progress

**Date paused:** 2026-05-03
**Branch:** `design/wabi-refinements` (pushed to `origin`)
**Spec:** `docs/design-specs/2026-05-03-learning-loop-architecture-design.md` (commit `7cbe2ba`)
**Plan:** `docs/design-specs/2026-05-03-learning-loop-architecture-plan.md` (commit `b356a21`)

**Status:** **21 of 25 tasks complete** · 4 remaining · all committed and pushed.

---

## Decisions made during implementation (deviations from plan)

### 1. `ProfileSnapshot` renamed to `LearnerSnapshot`

The plan called the read-only aggregator `ProfileSnapshot`, but `BackupService.swift` already defines a public `ProfileSnapshot` for backup payloads. Adding a second top-level `ProfileSnapshot` would have been a hard compile collision.

The new type is **`LearnerSnapshot`** everywhere — same shape, same fields, same accessors. Same applies to **`LearnerSnapshotBuilder`** (was `ProfileSnapshotBuilder` in the plan).

### 2. `DefaultSessionPlanner` segments fill their budget

The plan's `pickFirstFitting` / `pickRotating` helpers each picked a *single* exercise per segment. With 15-minute sessions and per-exercise durations of 20–60 s, a single-pick implementation summed to ~360 s total — far below the spec's "40/30/20/10 of 15 min" target and below the test floor (700 s). Implementer renamed these to `fillSegment` / `fillRotating` and made them fill the per-segment time budget. **This matches the spec's design intent** ("Allocations are *time targets*, not strict caps") and the verbatim text under "Home composition skeleton".

### 3. Two production correctness bugs caught + fixed in Task 5

The code reviewer for `LearnerSnapshotBuilder` (Task 5) caught two real bugs in the plan I'd written:

- **Bug A:** the builder routed kana detection through `CardType.kanji`, but `KanaCardRepository.seedIfNeeded()` (the production seeder) emits kana cards as `CardType.vocabulary`. `hiraganaMastered` would never have flipped to `true` for any user. Fixed: detection is now `card.front`-driven via explicit base-46 sets (independent of `card.type`).
- **Bug B:** the Unicode ranges I'd specified (`0x3042...0x3093`) span 82 code points each (include voiced/dakuten and small kana). Threshold was 46. A user with 40 base + 6 dakuten would've satisfied the threshold without owning the base syllabary. Fixed: replaced ranges with explicit `Set<String>` of the 46 gojūon characters in each script.

Fix landed at `209fcf8`. Cost two extra tests (`dakutenDoesNotCountTowardKana`, `katakanaDetection`).

### 4. `Logger.learningLoop` lives in centralized `Loggers.swift`

The plan put the `Logger` extension inline at the top of `DefaultSessionPlanner.swift`. The codebase already centralizes 11 logger categories under `IkeruCore/Sources/Utilities/Loggers.swift`. The implementer added `learningLoop` there for consistency — no separate inline extension. Cleaner.

### 5. `@AppStorage` requires `@ObservationIgnored` in `@Observable` class

`SessionViewModel` is `@Observable`. Adding `@AppStorage("ikeru.session.defaultDurationMinutes") private var defaultDurationMinutes: Int = 15` required the `@ObservationIgnored` annotation because `@AppStorage` doesn't compose with the `@Observable` macro's synthesized observation. Functional behaviour is preserved (the `UserDefaults` backing reflects setting changes immediately).

### 6. SessionViewModel test fixtures updated to use `MockSessionPlanner`

The pre-existing `SessionViewModelTests.swift` (20 tests) encoded the OLD `PlannerService.composeSession()` contract: "every due card → queue". The new planner enforces 40/30/20/10 segment budgets, so tests that seeded 3 cards and expected `sessionQueue.count == 3` now see a smaller queue. Resolution: introduced a fileprivate `MockSessionPlanner` and a `plannerWithSeededCards` helper so tests inject a deterministic plan via the new `sessionPlanner:` parameter on `SessionViewModel.init`. All 20 tests + 6 integration tests pass green.

### 7. `kanaStudy` synthesise is a known TODO

`ExerciseItem` has no `.kanaStudy(String)` payload — only `.kanjiStudy(String)`. So when the planner synthesises an `ExerciseType.kanaStudy`, it produces an `ExerciseItem.kanjiStudy(...)`. Net effect: kana drills are reported as 60 s (kanji study duration) instead of 25 s. The plan's `finalize()` will slightly overestimate plan duration in plans containing kana drills. Inline TODO comment at the synthesise switch flags this as a model-level follow-up: add `case kanaStudy(String)` to `ExerciseItem`. Not blocking — sessions still run correctly.

### 8. Etude tab restructure required pbxproj surgery

`git mv ProgressDashboardViewModel.swift → EtudeViewModel.swift` and `git rm ProgressDashboardView.swift` left the Xcode project file with stale references. Implementer rewrote four pbxproj entries (build-file, file-ref, group child, sources phase) for the rename + four for the deletion. Without that, the build would fail with "missing source file" before linking. Don't forget to use `scripts/add-to-xcodeproj.rb` for new files — but renames/deletes need manual pbxproj cleanup.

---

## Done — 21 tasks (commits pushed to `origin/design/wabi-refinements`)

Stack from bottom to top of `b356a21..0466ad6`:

| # | Task | Commit(s) | Notes |
|---|---|---|---|
| 1 | `ExerciseType` enum + skill mapping | `3e825aa` | 12 cases, 3 tests |
| 2 | `ExerciseUnlockState` + `ExerciseLockReason` enums | `4b416e9`, `9b6b80d` | + doc-comment fix for `LearnerSnapshot` rename |
| 3 | `LearnerSnapshot` value type | `622fb8c` | renamed from `ProfileSnapshot` |
| 4 | `ExerciseUnlockService` (12 rules) | `d7c6bd7`, `b2841b1` | + 3 ordering/boundary tests added in review |
| 5 | `LearnerSnapshotBuilder` | `307bfb1`, `209fcf8` | + 2 production-bug fixes (kana detection) |
| 6 | `RPGState.acknowledgedUnlocks` field | `ae05dee` | JSON-encoded `Set<ExerciseType>` |
| 7 | Settings duration picker | `a77fd7f`, `32d5d18` | + missing `@AppStorage` backing fix |
| 8 | `SessionPlannerInputs` DTO | `33720c9` | `Source` enum + 4 fields |
| 9 | `VarietyPoolResolver` | `40b52c8` | 4 tests, level-tied pool |
| 10 | `RestDayDetector` | `6404926` | 6 tests, 4-condition gate |
| 11 | `SessionPlanner` protocol | `8b49fd0` | trivial |
| 12 | `DefaultSessionPlanner` (Home + Study) | `e9a129b`, `3884150` | + doc/log/TODO follow-ups from review |
| 13 | `SessionViewModel` migration | `457536e`, `05bbb9c` | + 16 test fixtures rewritten with `MockSessionPlanner` |
| 14 | 「新しい稽古」 badge granting | `45c436b` | wired into `endSession()` via `processNewlyUnlocked()` |
| 15 | `HomeViewModel.restDayActive` | `0f5628a` | published property + `refreshRestDay()` |
| 16 | HomeView rest-day rendering | `15121e9` | conditional in proverb-hero CTA |
| 17 | `ExerciseTileTokens` | `bdd051e` | glyph + label per `ExerciseType` |
| 18 | `ExerciseTypeTile` | `808bcc2` | locked/unlocked tile, lock-hint copy |
| 19 | `EtudeBrowseGrid` | `9fa7fed` | 2-column grid, Sakura excluded |
| 20 | `CustomPlannerSheet` | `520b4cd` | FlowLayout chips + segmented duration |
| 21 | `EtudeView` (replaces ProgressDashboardView) | `0466ad6` | rename VM + new view + tab routing |

**Build status:** green (`** BUILD SUCCEEDED **` after every commit).
**Test status:** all relevant suites pass — `SessionViewModelTests` 20/20, `SessionIntegrationTests` 6/6, `LearnerSnapshotBuilderTests` 7/7, `ExerciseUnlockServiceTests` 12/12, `VarietyPoolResolverTests` 4/4, `RestDayDetectorTests` 6/6, `DefaultSessionPlannerTests` 4/4, `RPGStateAcknowledgedUnlocksTests` 3/3, `LearnerSnapshotTests` 3/3, `ExerciseTypeTests` 3/3.

---

## Left to do — 4 tasks

### Task 22 — Move four-winds skill balance to Rang (RPG) tab

**Files to touch:**
- `Ikeru/Views/RPG/RPGProfileView.swift` — add a `skillBalanceCard(_:)` view that mirrors the layout previously in `ProgressDashboardView` (small radar mini + 4 skill rows).
- `Ikeru/ViewModels/RPGProfileViewModel.swift` — add `private(set) var skillBalance: SkillBalance?` and a `loadSkillBalance()` async method that reads via `PlannerService.computeSkillBalances()`.

**Why:** Task 21 stripped `skillBalance` from the renamed `EtudeViewModel`. Currently the four-winds card is *gone from the UI entirely* — it should live on the Rang (RPG) tab, where the four-winds attribute system already lives.

**Pattern in plan:** plan's Task 22. Existing `SkillRadarView` and `SkillBalance` types are reused.

**Estimated size:** 1 commit, ~50 lines of new code in two files. Inline-doable.

**Acceptance:** Rang tab renders the radar + skill rows; Étude tab does not.

### Task 23 — `UnlockBackfillService` + first-launch backfill in `IkeruApp`

**Files to create:**
- `IkeruCore/Sources/Services/ExerciseUnlock/UnlockBackfillService.swift` (3 lines of logic + tests)
- `IkeruCore/Tests/Services/ExerciseUnlock/UnlockBackfillServiceTests.swift` (3 tests: day-1 backfill, earned-types backfill, idempotency)

**Files to modify:**
- `Ikeru/IkeruApp.swift` — at the root view's `.task`, if `state.acknowledgedUnlocks.isEmpty`, build a `LearnerSnapshot` and union the result of `unlockedTypes(profile:)` into `state.acknowledgedUnlocks`. This prevents existing-profile users from getting a flood of "new practice unlocked" badges on first launch after this lands (because every type they already meet the threshold for would otherwise fire as "newly unlocked" the first time `processNewlyUnlocked` runs).

**Pattern in plan:** plan's Task 23 has the full code blocks.

**Estimated size:** 1 commit, ~50 lines core + ~20 lines app wire-in. Inline-doable.

**Acceptance:** fresh-install profile gets the 4 day-1 types in `acknowledgedUnlocks` immediately; existing profiles get all currently-met thresholds in there too on first launch after this ships, so they don't all fire as "newly unlocked" simultaneously.

### Task 24 — Deprecate old `composeAdaptiveSession` + delete obsolete tests

**File to modify:** `IkeruCore/Sources/Services/PlannerService.swift` — add `@available(*, deprecated, message: "Use DefaultSessionPlanner.compose(inputs:) instead.")` to `composeAdaptiveSession(config:)`. Keep `composeSession()` and `computeSkillBalances()` undeprecated — they're still used elsewhere.

**Files to delete:**
- `IkeruCore/Tests/Services/AdaptivePlannerTests.swift`
- `IkeruCore/Tests/Services/AdaptivePlannerIntegrationTests.swift`

These tested the API that's been replaced. New behaviour is covered by `DefaultSessionPlannerTests` (Task 12).

**Estimated size:** 1 commit, ~3 lines added + 2 files deleted. Inline-doable.

**Acceptance:** `swift test --package-path IkeruCore` passes without `Adaptive Planner` suites; build still succeeds (deprecation warnings on `composeAdaptiveSession` are acceptable).

### Task 25 — Manual end-to-end smoke test

**No files** — verification on the simulator. Per the plan's Task 25 checklist:

| # | Surface | Expected |
|---|---|---|
| 1 | Settings → Pratique | "Durée par défaut" row exists, picker offers 5/15/30/45 (currently labelled `Settings.SessionDuration`) |
| 2 | Home / Accueil | One CTA only; tap → starts a session whose duration target matches the Settings value |
| 3 | Home / Accueil after first session, no due cards, balanced state, < 24h | "今日は休 / Rest day" surface shows |
| 4 | Étude tab | JLPT hero + 11-tile grid (no Sakura tile) + "編成 / Compose" row |
| 5 | Étude → tap a locked tile | Shows lock-reason hint (e.g., "0 / 50 vocab to unlock"); tap is disabled |
| 6 | Étude → Compose | Sheet opens; Compose disabled until ≥1 type and ≥1 level selected |
| 7 | Étude → Compose → submit | `lastComposedPlan` set; current behaviour is "log + remember" — actually launching the active-session UI from the composed plan is a future wiring task |
| 8 | Rang tab | Four-winds skill-balance card visible (after Task 22) |
| 9 | Chat tab (no AI provider) | Existing pre-N4 message preserved (was Layer 1 work, unchanged here) |
| 10 | After a session that crosses an unlock threshold | "Nouvelle pratique débloquée" badge appears in inventory exactly once per type |

**Likely follow-ups discovered during smoke test:**
- Étude → Compose → Submit currently sets `lastComposedPlan` on the VM but does NOT navigate to `ActiveSessionView`. Wiring that handoff is a known gap. Spec lines around 240 say "A 'Compose' button at the bottom calls `SessionPlanner.compose(.studyCustom(...))` and pushes into the active-session UI." The "pushes into the active-session UI" part is not implemented yet.
- Étude → tap unlocked tile (`startSingleSurface`) currently only logs; it doesn't route into a single-type drill. Plan deferred this with `Logger.planner.info` per the spec's "When a topic-routing API lands…" pattern.

---

## Known issues / deferred follow-ups

These were noted in code review or implementation but deliberately not fixed inline:

### Cosmetic (inherited / pre-existing pattern)
- `import Foundation` is unused in `ExerciseType.swift`, `ExerciseUnlockState.swift`, etc. — sibling files (`SkillType.swift`) have the same unused import; touching it would create inconsistency.
- `isUnlocked: Bool` in `ExerciseUnlockState` uses `if case .unlocked = self` instead of the more idiomatic `self == .unlocked`. Both compile and behave identically.
- Test bound `<= 240` in `ExerciseTypeTests.durations` is generous (current max is 180); could be tightened or parameterized.
- `for type in ExerciseType.allCases` in `ExerciseTypeTests.durations` shadows the Swift keyword `type` — renaming to `exerciseType` would be cleaner.

### Architectural (worth a tracking issue)
- **`ExerciseItem` has no `.kanaStudy(String)` case.** `DefaultSessionPlanner.synthesise` falls back to `.kanjiStudy(...)` for both `.kanaStudy` and `.kanjiStudy` exercise types, causing the kana-drill duration to be reported as 60 s instead of 25 s. Inline TODO comment in the synthesise switch documents this.
- **`LearnerSnapshot.skillImbalance` and `SkillBalance.imbalanceScore(current:)` use different formulas** (range-ratio vs sum-of-deviations from target). Same domain, different definitions — easy to confuse. Worth a shared formula or a clarifying doc comment.
- **`LearnerSnapshot.listeningAccuracyLast30` vs `listeningRecallLast30Days`** — naming asymmetry. One has `Days`, the other doesn't. Both are 30-day windows.
- **`SessionPlannerInputs.availableCards` contract is implicit** — the planner assumes pre-filtered (due cards + new content); a doc comment on the field would make this explicit.
- **`composeStudy`'s `levels` parameter is currently a no-op**. Logged a warning when non-empty, but content packs don't yet have JLPT-level tagging so the filter has nothing to bite on. Spec mentioned this.
- **Étude → Compose handoff to active session is missing** (see Task 25 note above).
- **Étude → single-surface tap is a stub** (logs, doesn't navigate).

### Test gaps
- `dayOfYear` injection point in `DefaultSessionPlanner` exists but is not exercised in tests.
- `pickNewContent` positive path (cards with `reps: 0`) is untested.

### Minor
- Pre-existing dirty path `IkeruCore/Tests/Services/LootDropServiceTests.swift` was modified outside this session and never committed; not part of this work, left untouched.

---

## How to resume

1. Pull the branch:
   ```bash
   git fetch origin && git checkout design/wabi-refinements && git pull
   ```
2. Verify state:
   ```bash
   git log --oneline | head -25  # should show 0466ad6 at the top
   xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build
   ```
3. Re-read this file + the plan + the spec.
4. Tasks 22–24 are small (each ~1 commit, mostly mechanical) — could be batched in a single subagent dispatch, or done inline.
5. Task 25 is manual — run on the simulator; capture a checklist of which acceptance items pass and which surface the deferred follow-ups noted above.

The branch is currently a fork from `master`. When all 25 are green and Spec B / Spec C work hasn't started, Spec A is ready to PR.

---

## Stats

- **Commits added this work:** 28 (21 task commits + 5 review-driven follow-ups + 1 progress doc + 1 spec + 1 plan)
- **Lines changed (rough):** ~3,500 added / ~200 deleted across `IkeruCore/Sources/`, `Ikeru/`, tests, localization, project file
- **Tests added:** 51 (Swift Testing) — plus 20 SessionViewModel tests rewritten
- **New IkeruCore service files:** 9
- **New SwiftUI views:** 5
