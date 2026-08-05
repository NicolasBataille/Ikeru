# Ikeru — Re-scoped Remediation Plan (vs `dev`)

> Re-scope of the 2026-07-08 remediation plan after the beginner-first redesign (PR #22) landed on
> `dev`. Audited against `dev @ e99b33e` (`claude/review-salvage-on-dev`). Scope: Phases 4, 6, 7, 8.
> Companion to `2026-07-08-remediation-plan.md` — item IDs are unchanged so the two cross-reference.

## 1. Headline — how much is actually left

Of the **32 items** across Phases 4/6/8 plus Phase 7, the redesign fully closed **3** (4.2, 6.1, 8.5),
partially closed **6** (4.7, 6.3, 6.7, 6.8, 7.4, 8.8), and left **23 open** — so **29 of 32 are still
live work**. Crucially, the redesign spent its budget on the *highest-visibility honesty* items and
almost nothing on structure: it deleted the keyword-matching "companion chat" stub that was presented
as AI (6.1, ~1,111 LOC removed) and shipped real KanjiVG stroke data for all 90 kanji (4.2), and it
chipped at offline audio (bundled VOICEVOX now preferred over TTS on the reachable surfaces). But the
pedagogy core is untouched: the seven real drill views (Listening/Shadowing/SentenceConstruction/
Handwriting/VocabularyStudy/FillInBlank/Reading) are still unreachable islands referenced only in their
own `#Preview` blocks while live sessions render a "Complete"-button placeholder (4.1); exercises never
grade FSRS (4.4); `LearnerSnapshot` grammar/listening/skill inputs are still hard-zeroed (4.3); content
is unchanged at N5-only ~206 vocab / 31 grammar / 96 sentences / 90 kanji (4.5). The engineering
foundation is likewise untouched and in two places *worse*: there is still no SwiftData migration plan
over a now-**10-model** live schema (8.2 — the redesign added `@Model` types without one), CI still runs
a ~12 % filtered test subset because `swift test` SIGSEGVs (8.1, reproduced live), and `SessionViewModel`
grew 1,111 → 1,248 lines (8.4). All of Phase 7 (widgets, watch, backup, export) is essentially
untouched — 7 open, 2 partial, 0 done. **Bottom line: the app tells fewer lies than it did, but it
still does not do what its session UI, its FSRS engine, or its widgets/watch claim to do.**

## 2. Open & partial items

Sorted **value desc, then effort asc** (high-value / low-effort first). `P4` = Pedagogy, `P6` = AI
honesty & robustness, `P7` = Platform features, `P8` = Engineering health. `~` = partial.

| id | title | phase | value | effort | dependencies |
|----|-------|-------|-------|--------|--------------|
| 8.2 | No SwiftData `VersionedSchema`/`SchemaMigrationPlan` over a live 10-model schema | P8 Eng | **high** | M | Gates every future `@Model` change (7.6 schemaV2, vocab-dictionary). Land before next migration-incompatible model ships to TestFlight. |
| 4.1 | Non-SRS exercises render placeholders; 7 real drill views are islands | P4 Ped | **high** | XL | Needs content payloads + real IDs from `ContentRepository` (planner emits bare UUIDs). Unblocks 4.4; listening wiring overlaps 4.7/6.3. |
| 4.5 | Content volume: 206 vocab / 31 grammar / 96 sentences / 90 kanji, N5-only | P4 Ped | **high** | XL | Native-review pass required before release; N4 depends on N5 expansion. Runs as a parallel content workstream. |
| 7.7 | Export promises `reviews.json` but never writes it; ShareLinks a bare dir | P7 Plat | medium | S | None. Write review logs + zip the dir (or ship one archive) before `ShareLink`. |
| 4.4 | Output exercises never feed FSRS (no grade mapping) | P4 Ped | medium | M | Blocked by 4.1 (VMs must be reachable + tied to specific cards first). |
| 4.7~ | Listening exercises proper still islands; no "synthetic voice" TTS label | P4 Ped | medium | M | Overlaps 4.1 (listening views) + 6.3 (rig). Bundled-clip coverage limited to strings with a generated clip. |
| 6.2 | Router never consults tier health; no 429 cooldown; ignores `Retry-After` | P6 AI | medium | M | Transport must surface `Retry-After`; cooldown map + skip logic in `buildFallbackChain`. |
| 6.4 | Marker parsing brittle (`[CORRECTION]`/`[VOCAB]` per-line string split) | P6 AI | medium | M | Shares `ConversationService` parsing + prompt contract with 6.5 — land together. |
| 6.5 | Flattened single-message history (no real multi-turn arrays) | P6 AI | medium | M | Reshape `AIPrompt` into a messages array through every provider + codec. Pairs with 6.4. |
| 6.7~ | Mnemonic/correction hallucination cached; no furigana-vs-bundle validation | P6 AI | medium | M | Needs a bundle reading-lookup for known kanji. Regenerate button already shipped. |
| 7.1 | Widgets have no app-group data channel (hardcoded timelines) | P7 Plat | medium | M | Add group to `IkeruWidget.entitlements` + a shared writer. Shares channel with 7.2. |
| 7.4~ | Watch state sync bidirectional but never sent at launch/session-end; UI ignores synced values | P7 Plat | medium | M | Add launch + session-end send sites; bind `WatchHomeView` to `WatchSessionManager.shared`. |
| 7.5 | Watch XP bypasses `RPGRewardService`; pitch drill awards passive XP | P7 Plat | medium | M | Route `WatchSessionResult` through `RPGRewardService`; redesign pitch drill into an active-answer quiz. |
| 8.3 | O(all-cards) in-memory filtering in hot paths; `UserDefaults` read inside the ModelActor | P8 Eng | medium | M | Functionally fine today (scale/perf). Inject profile ID + rewrite as `#Predicate`/`FetchDescriptor`. |
| 4.3 | `LearnerSnapshot` grammar/listening/skillBalances inputs hard-zeroed | P4 Ped | medium | L | Grammar needs grammar-type cards; listening needs 4.4 result persistence; skillBalances already computed in `ProgressService`, just not threaded in. |
| 7.3 | Watch complication homeless (no widget-ext target) + hardcoded | P7 Plat | medium | L | Needs a new watchOS widget-extension target + watch app-group entitlement. Ties into 7.4. |
| 7.6 | Backup restore drops FSRS state; destructive; 1 MB inline record; feature dormant | P7 Plat | medium | L | Must land before iCloud is enabled. schemaV2 migration (gated by 8.2) + CKAsset + safety export are independent sub-tasks. |
| 8.1 | CI runs a filtered green subset; legacy suites crash under full `swift test` | P8 Eng | medium | L | Not just the SIGSEGV: `PlannerServiceTests` fail behaviorally (queue.count→0) because the redesign changed planner semantics — reconcile stale tests, not just the crash. |
| 8.7 | No UI-test target despite complete fixture infra | P8 Eng | medium | L | Leverages `TestFixtures.seedIfRequested` + dynamic-simulator CI. Valuable because the redesign reworked onboarding/IA. |
| 6.8~ | BYO-key: no inline "add a free key (2 min)" paste-in-place CTA in chat | P6 AI | low | S | Chat routes out to Settings today; leans on existing `AISettingsView`/`AISetupView` free-key flow. |
| 7.8~ | Handwriting scribble-passing `ShapeMatchingProvider` fallback is dead code but remains; no honest self-grade path | P7 Plat | low | S | Low priority while writing is a session placeholder (4.1). Remove/replace if handwriting is re-wired. |
| 7.9 | `isSilentMode` tests `outputVolume == 0`, not the mute switch; consumed live | P7 Plat | low | S | Delete the volume-based skip path (TTS in `.playback` ignores the switch regardless). |
| 8.8~ | Timestamp build numbers; `MARKETING_VERSION` uniformly 1.0.0 with no bump discipline | P8 Eng | low | S | `workflow_dispatch` deploy path already added. Swap to `github.run_number` + a version-bump guard. |
| 4.6 | Leech-quiz distractors are hardcoded filler; service not wired to any live surface | P4 Ped | low | M | Needs `ContentRepository` injection into a static service. Low value until the intervention surface is wired. |
| 6.3~ | Rig/VOICEVOX TTS never played back; prewarm budget-burn now gated but flag defaults ON | P6 AI | low | M | Rig playback is power-user-only + largely superseded by bundled offline audio. Flip prewarm flag default OFF. |
| 6.6 | GitHub Models on legacy Azure endpoint; no remote provider/model manifest | P6 AI | low | M | Endpoint swap is trivial (S); the remote GitHub-Pages JSON manifest with baked-in fallback is the larger, independent piece. |
| 7.2 | StandBy widget: 10 s timeline over 12 hardcoded kanji | P7 Plat | low | M | Depends on 7.1 (needs the app-group channel to read due/leech cards). |
| 8.6 | SwiftLint non-strict (~200 legacy warnings tolerated) | P8 Eng | low | M | Independent. `swiftlint analyze --baseline` to capture legacy, then `--strict` on the diff. |
| 8.4 | `SessionViewModel` god object (1,111 → 1,248 lines) | P8 Eng | low | L | Pure maintainability refactor, no functional bug. Best done after 8.3 (same finalization/persistence code). |

## 3. Recommended execution order — next 1–2 work units

**Work Unit 1 — de-risk the foundation before building on it (8.2 → 8.1).**
Do these first because everything else in the plan lands *on top of* them, and both are compounding
liabilities today.

1. **8.2 — SwiftData `VersionedSchema` + `SchemaMigrationPlan` (M, high).** This is the single
   highest-value open engineering item and a hard gate. The live schema is now **10 `@Model` types**,
   three of them (`VocabularyEntry`/`VocabularyEncounter`, `CompanionChatMessage`, `DailyTerm`) added
   by the redesign *without* a migration plan — so the risk is strictly larger than when the original
   plan was written, and it grows with every TestFlight build that persists the new shape. It also
   gates 7.6 (backup schemaV2) and the planned vocab-dictionary work. Land it before the next
   lightweight-migration-incompatible `@Model` change ships.
2. **8.1 — un-filter the test suite (L, medium).** CI runs a ~12 % subset because full `swift test`
   SIGSEGVs (reproduced live: "unexpected signal code 5" / index-out-of-range in `KanaCardRepository`/
   `PlannerService`). Critically, `PlannerServiceTests` also fail *behaviorally* (queue.count→0) —
   evidence the redesign already changed planner semantics, so the legacy suites are **stale, not just
   crashing**. Reconcile them now: you need a green full suite as a regression net *before* Work Unit 2
   re-wires the session/exercise path through that same planner, otherwise those regressions stay
   invisible.

**Work Unit 2 — the flagship user-value fix (4.1, pulling in 4.4 and 4.7).**

3. **4.1 — wire the island drill views into live sessions (XL, high).** This is the biggest
   "the app does what it says" fix: today `ExerciseTransitionContainer` routes every non-SRS exercise
   to a placeholder that auto-grades `.good`, while seven fully-built drill views sit unreachable. The
   fix threads real content IDs from `ContentRepository` through `DefaultSessionPlanner` (which emits
   bare UUIDs today) into the container. Doing this *unblocks 4.4* (once VMs are reachable and tied to
   specific cards, map their outcomes to FSRS grades) and *pulls in 4.7* (the listening exercise views
   are part of the same island set). Sequence 4.1 → 4.4 → 4.7 as one cluster; 4.3's listening/skill
   signals become feedable only after 4.4 persists real results.

**Why not lead with something else:** Phase 6 robustness (6.2/6.4/6.5) is real but the *honesty*
headline (6.1) already landed, so it is lower urgency than pedagogy. Phase 7 (widgets/watch/backup) is
mostly medium/low value and much is gated behind disabled features (iCloud off, watch complication has
no hosting target) — defer past Work Unit 2. **4.5 (content expansion)** is high-value but is a
*content* workstream needing native review, not engineering-blocked — run it in parallel to Work Units
1–2 rather than serializing it. The two cheap medium-value wins **7.7** (write `reviews.json` + zip the
export) and the **6.4 + 6.5** pair (structured multi-turn chat contract) are good fillers once the two
work units above are in flight.

## 4. Already DONE or MOOT — do not redo

**Fully landed by the redesign (verified in the audit — leave them):**

- **4.2 — Stroke-order SVG.** All 90 kanji now carry real KanjiVG path data (len 226–1853, avg 778)
  with in-app CC BY-SA attribution (`AttributionView`), parseable by `StrokeDataService`. Data fix
  complete; only downstream *visibility* in a session is gated by 4.1.
- **6.1 — Companion chat honesty.** The keyword-matching stub presented as AI was deleted (commit
  73f6264, ~1,111 LOC). The surviving `ConversationView` routes fully through
  `ConversationService → AIRouterService.generate` with an honest "no AI configured" offline state +
  setup CTA. No scripted-as-AI path remains.
- **8.5 — Code-review CI trigger.** `code-review.yml` now fires on PRs to `dev` and `master`; the
  opt-in `ENABLE_CODE_REVIEW` gate is documented. Only residual is the owner setting the repo var +
  secret to activate it (an ops action, not code).

**MOOT:** none. Every audited item is either done, partial, or open — the redesign did not render any
open item unnecessary. In particular the Phase 7 platform items were *not* touched by the re-home, so
none of them became obsolete.

**Watch for these partial-item traps (don't re-do the done half):**

- 6.7 regenerate button **shipped** — only furigana-vs-bundle validation remains.
- 7.4 bidirectional sync plumbing **exists** — only the send-sites + UI binding remain.
- 6.3 prewarm budget-burn **already gated** (flag + rig-configured guard) — only rig *playback* +
  flipping the flag default remain, and playback is largely superseded by bundled audio.
- 8.8 `workflow_dispatch` deploy path **already added** — only build-number/version polish remains.
