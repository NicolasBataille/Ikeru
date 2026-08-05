# Beginner-First UX Rework — Plan & Handoff

**Date:** 2026-06-14
**Branch:** `claude/ux-deep-rework` (off `claude/app-screen-design-viz-kvs1a5`)
**Drivers:** product owner feedback — the app feels "too full" / too complicated; it tried to serve new *and* experienced learners simultaneously and the mix was bad. New directive: **beginner-first by default; expertise as progressive depth, never a parallel mode.**

## Evidence (full code inventory + design panel)

The app is, in reality, a **beginner N5 SRS-flashcard + kana app** wearing the costume of a big expert app:

- **Only N5 content ships.** N4–N1 code paths exist but no content.
- **Only SRS review + kana drill work end-to-end.** 9 of 12 "exercise types" are in-session placeholders (auto-grade "good"). Full exercise chains (kana, vocab, kanji, reading, listening, speaking, writing) exist but are **unwired orphans**.
- **~3,600–4,650 LOC of gamification** (XP, dan levels, lootboxes + timed mini-game challenges, random loot drops during review, an 8-attribute RPG sheet never read, inventory/cosmetics, streak bonuses never shown, level-up/loot-reveal theatre). **None of it gates learning.** It contradicts the stated anti-gamification posture and occupies a whole tab.
- **~6,000 LOC AI subsystem**, offline by default, exposed as a primary tab **plus** a redundant floating-avatar chat (keyword stub).
- **5 tabs** (3 in a swipe pager, 2 tap-only — inconsistent). Dead `NavigationCoordinator`. ~2,200 LOC of unreachable views. 8-step onboarding tour introducing all 5 tabs.

## The plan

### Vision
> A calm, honest Japanese starter: open the app, it tells you the one thing to do right now, you do it, you close it feeling more capable than when you opened it.

### Information architecture — 3 tabs, tap-only, no swipe pager
- **練習 Practice** (default) — simplified Home: date, greeting, due-count numeral, BEGIN PRACTICE CTA, session breakdown, quiet state, proverb. **Removed:** level pill, XP rail, display-mode suggestion card, equipped title. **Added:** a "Start with kana" card shown only when no SRS cards exist and kana isn't done.
- **学習 Explore** (replaces Étude grid) — a short vertical list, not a grid: Kana · Vocabulary · Talk with Sakura (honest offline state) · Compose session. A small "N words known / 46·92 kana" mastery line. No JLPT hero on day one.
- **設定 Settings** — streamlined; dead rows removed; density becomes one honest "Furigana" toggle; FSRS jargon page gone; rig behind `IKERU_DEV_TOOLS`.
- **Gone from tab bar:** Companion tab, RPG/Rang tab, floating avatar.

### Motivation (replaces gamification) — two honest numbers + one quiet moment
1. **Cards mastered** ("47 words known") — a fact about memory, no bar/animation.
2. **Kana completion** ("46 / 92 かな").
3. **One-time kana-complete beat** (完 · "You can now read Japanese"), fires once, no repeat.
No streaks, no XP toast, no level-up overlay, no loot drops. SessionSummary keeps the calm triumph header + 3 stats + split cells; drops the XP rail + four-winds row.

### Experienced-as-a-layer (not a mode)
One onboarding question — "Starting from scratch" vs "I know some" → a single `knowsSome` flag that shifts *emphasis* (kana as "Start here" vs "Reference"; furigana default on/off; Compose visible) — **same screens, no second UI**. Progressive disclosure via silent state changes (JLPT readiness line after 50 reviews), never "you unlocked X."

### Exercises
- **Wire now:** kana drill (the day-one path), vocabulary dictionary + drill, kanji study as reference from vocab detail. **Honest v1 set.**
- **Hide until real (keep code):** reading, listening, writing — no N5 content/audio/stroke data.
- **Cut views (keep dormant Core services):** speaking (pitch/shadowing), sentence construction, and the 9 placeholder session cases.

### AI
Demote to a single Explore row presenting `ConversationView` (the complete surface); cut `CompanionTabView`, `CompanionAvatarView`, `CompanionChatSheet` (the duplicate). Lazy-init (no cold-start warm of 6k LOC for a beginner with no provider).

### Cut list — ~10,000 LOC across views/VMs/Core; FSRS + repositories + dormant audio/pitch/handwriting services untouched.

## Phased execution (build green at each step)
- **Phase 0** — safe dead code: `NavigationCoordinator`, dead Settings rows. *(Partially done: CardReview/SessionConfig/SegmentedXPBar already removed, ~983 LOC.)*
- **Phase 1** — cut gamification theatre: unwire RPG/Companion tabs → stub SessionViewModel RPG calls → remove overlays (session) + chrome (home) + summary cleanup → delete RPG view + Core files. (~5,000 LOC)
- **Phase 2** — IA collapse: remove swipe pager, build `ExploreView`, 3-tab `IkeruTabBar`, delete Étude grid + Companion surfaces, lazy AI init.
- **Phase 3** — beginner-first onboarding (placement question) + density layer; delete the 8-step tour system + anchors.
- **Phase 4** — wire kana + vocab + kanji-as-reference; clean the session router (remove 9 placeholder cases); delete speaking/sentence views; add mastery counts.

### Key risks
SessionViewModel RPG entanglement (stub before delete), Watch `xp` field (hardcode 0), Vocabulary dictionary empty for new users (show all N5 with a "Studied" filter), the documented kana black-screen bug (navigate straight to `KanaPoolSelectorView`, never via the session router), do **not** rename `DisplayMode` enum cases (only the Settings label).

---

## Progress — 2026-06-14 (session 2)

Delivered (committed on `claude/ux-deep-rework`, build green, Core tests green):
- **Explore mastery counts** — new pure, tested `KanaProgress` (Core) drives a quiet "X/92" on the Kana row and a saved-words count on Vocabulary. Replaces gamified XP chrome with two honest numbers (Motivation model, above).
- **Honest Vocabulary row** — reframed to "Your saved words". *Finding:* there is **no seeded N5 vocab pack** — the dictionary is collected via Sakura chat, so the old "N5 dictionary & drills" subtitle over-promised. (Plan's "show all N5 with a Studied filter" is not possible until an N5 vocab content pack exists — a separate content task, gated by the zero-paid-API constraint.)
- **Settings slimming** — removed the decorative FSRS "Memory algorithm" stub sub-page (read-only, no controls).
- **Beginner-first onboarding placement** — after name entry, one question ("Have you studied Japanese before?") sets `DisplayMode` (`.beginner` default vs `.tatami` immersion). *Correction to plan:* `DisplayMode` **already is** the density layer (and already defaults `.beginner` for new profiles), and a dedicated **Furigana** toggle already exists — so the plan's "density becomes one honest Furigana toggle" was a mis-read. We did **not** rename the "Tatami interface" toggle (its copy is already clear); the placement question is the experienced-as-a-layer opt-in. A `.displayModeDidChange` notification makes the choice apply without relaunch.
- **i18n** — FR added for all new Explore + placement strings (and prior-session Explore strings that were never localized).

### Deferred (with reason): dormant RPG **deletion** — Phase 1 "delete RPG Core files"
The inventory characterized `RPGState` as dormant. On inspection it is **load-bearing**, not purely dead:
- `acknowledgedUnlocks` → 「新しい稽古」 unlock dedup (`ExerciseUnlockService`)
- `jlptBackfillVersion` → one-shot boot JLPT backfill
- `lastReadinessBestFit` → JLPT readiness telemetry
- `lastSessionDate` / `totalSessionsCompleted` / `currentDailyStreak` → rest-day card + backup/export
- It is a **`@Relationship(deleteRule: .cascade)`** child of `UserProfile`, registered in the app `Schema` → deleting it is a real SwiftData migration on live TestFlight data.
- In `SessionViewModel.finalizeSession`, the dead XP/loot/bonus computation is **interwoven** with the live session-history writes (and the streak value comes from `SessionBonusService.evaluate`, itself slated for deletion). ~14 test files assert on `xpEarned`.

Conclusion: this is **not** a safe invisible delete — it is a dedicated migration touching the core study loop, the JLPT/unlock systems, and the SwiftData schema, for **zero visible benefit**. The dormant XP/loot fields are harmless (computed, never displayed). **Recommendation:** do it as its own carefully-tested PR — (1) extract a lean `SessionRecord`/`ProgressState` `@Model` for `lastSessionDate`/`totalSessionsCompleted`/streaks/`acknowledgedUnlocks`/`jlptBackfillVersion`/`lastReadinessBestFit`; (2) lightweight-migrate; (3) rewire the ~10 call sites; (4) delete loot/attribute models + the 5 services + `EquippedCosmeticsBridge` + the dead `SessionViewModel` machinery; (5) update the ~14 tests — verifying against a pre-existing store. Not bundled here to avoid risking visible systems for invisible hygiene.
