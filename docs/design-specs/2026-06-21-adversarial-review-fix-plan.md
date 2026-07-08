# Adversarial Review — Root-Cause Diagnosis & Fix Plan

**Date:** 2026-06-21
**Branch:** `claude/app-screen-design-viz-kvs1a5`
**Source:** An Opus-4.8 adversarial reviewer drove the app on the simulator (42 screenshots) and filed a severity-ranked review. Four read-only diagnostic agents then traced each finding to its root cause in code. This document records **why** each critique is valid (with file:line evidence) and **the best correction**, sequenced for execution.

> Method note: every root cause below was verified against the code, not inferred from the symptom. Where the reviewer's mental model was slightly off, the corrected cause is stated.

---

## Cross-cutting insight (read first)

Three of the "separate" findings (C2 empty session, H1 Home lies, H2 count mismatch) are **one underlying defect**: the Home screen has **two competing notions of "what to do today"**:

- **Headline** "N À RÉVISER" ← `HomeViewModel.dueCardCount` = cards with `dueDate ≤ now` only (`HomeViewModel.swift:299-302`).
- **Breakdown + the actual session** ← `DefaultSessionPlanner.compose(...)`, which returns due reviews **plus** brand-new cards (`reps == 0`) via `pickNewContent()` (`DefaultSessionPlanner.swift:205-211, 258-274`).

So the two numbers diverge whenever new≠due, the "0 / tout est à jour" message can show while new cards still exist, and COMMENCER can launch a plan that is empty after filtering → the 0% summary. **Fixing the Home count model once resolves C2, H1, and H2 together.** This is the heart of the plan (Phase 2).

**Device note:** the target iPhone (14 Pro) is **not Apple-Intelligence-capable**, so `FoundationModels` is unavailable on it. Sakura chat there will hit the "no provider" path unless a Gemini key is set — which is exactly the C1 dead-end. C1 is therefore real on the user's own device, not just the simulator.

---

## CRITICAL

### C1 — "Talk with Sakura" is a black, inescapable screen
**Root cause (established):**
- `EtudeView.swift:46-50` presents `ConversationView` in a `.fullScreenCover` **with no `NavigationStack`**. `ConversationView`'s `.navigationTitle`/`.toolbar` (incl. any close affordance) are therefore inert, and the in-view `aiUnavailableSection` "Setup" `NavigationLink` (`ConversationView.swift:80-96`) is dead (nothing to push onto). A full-screen cover also blocks the edge-swipe-back. → no way out but killing the app.
- `ConversationViewModel.onAppear()` (`:96-105`) runs an async provider-availability sweep with **no loading state** the view honors; when no provider is available (on-device unavailable + no Gemini key) it lands on `aiUnavailableSection`, which over the dark background + missing nav chrome reads as black.

**Best fix:**
1. Wrap the cover content in a `NavigationStack { … }` and add an explicit close button (`xmark`) in `.topBarLeading` that sets `showConversation = false` (`EtudeView.swift:46-50`).
2. Add an `isInitializing` loading state in `ConversationView` (spinner over `IkeruScreenBackground`) covering the async `onAppear` window.
3. Keep `aiUnavailableSection` but ensure it's the visible, escapable state with a **working** "Configure AI" link (now functional inside the NavigationStack) — honest about needing a provider on non-Apple-Intelligence devices.
4. Guard: the cover already nil-checks the VM; keep that, and add an `else` so it can never present empty.

---

### C2 — COMMENCER launches an empty "0% recall" session
**Root cause (established):** no empty-queue guard. `HomeView.startSession()` (`~:470`) unconditionally calls `SessionViewModel.startSession()` (`:338-384`), which sets `sessionQueue = srsCards` (can be `[]`) and activates the session; the summary then reports 0 cards / 0% (`SessionSummaryView`). The planner can legitimately return an empty SRS plan (`DefaultSessionPlanner.finalize()` filters to `.srsReview` only, `:258-274`).

**Best fix (defense in depth):**
1. **Disable** COMMENCER when the composed session is empty — drive it off the unified count from Phase 2 (`vm.sessionPreviewCardCount == 0`), `HomeView.swift:354`.
2. **Guard** `SessionViewModel.startSession()`: `guard !srsCards.isEmpty else { return }` before `resetSessionState()`/activation (`:359`).
(Resolved structurally by Phase 2; keep the VM guard as a backstop.)

---

## HIGH

### H1 + H2 — Home count is inconsistent and dishonest for new users
**Root cause:** the two-sources problem (see Cross-cutting). Headline = due-only; breakdown/session = planner (incl. new). Quiet state fires on `dueCardCount == 0` (`HomeView.swift:171-173`) while COMMENCER still composes new cards. **Kana progress ("X/92") is never on Home** — it exists only in `ExploreView` via `KanaProgress`.

**Best fix (one coherent Home model):**
1. Make the planner-composed session the **single source of truth**: `HomeViewModel` exposes `todayCount`, `newCount`, `reviewCount` all derived from one `compose()` result.
2. Headline = `todayCount`, with an **honest label** that reflects the mix (e.g. all-new → "À APPRENDRE", all-review → "À RÉVISER", mixed → a neutral "AUJOURD'HUI" with the new/review split beneath). Breakdown derives from the same result, so they can't disagree.
3. Quiet "tout est à jour" state only when `todayCount == 0`; COMMENCER disabled/hidden in that case.
4. **Surface kana progress on Home**: add a calm "かな X/92" line (the beginner's compass), reusing `KanaProgress.from(cards:)`.

### H3 — Red 急 ("urgent") badge violates the calm/anti-pressure core
**Root cause:** `HomeView.swift:332-334` renders `HankoStamp(kanji: "急")` filled `TatamiTokens.vermilion` whenever `dueCardCount > 0`. Red is the only saturated non-gold colour in the chrome; "急" = hurry/urgent — the opposite of the stated vision.
**Best fix:** remove the urgency stamp (the count numeral already communicates there's something to do). If a glyph is wanted, use a calm gold/ink mon with non-pressuring semantics — but default to removal.

### H4 — Dead "Tracés"/"Exemple" buttons on kana cards
**Root cause:** `SRSCardView.swift:246-248` creates `HintChip(icon:label:)` for Strokes/Example **with no `action` closure** (defaults to nil → tap is a no-op). Kana is seeded as `CardType.kanji` but has no stroke-order data and no example sentences.
**Best fix (now):** gate the Strokes/Example chips to **real kanji** (Unicode CJK range check on `card.front`, excluding kana blocks) so they don't render for kana. (Wiring them to a stroke-order viewer / example sheet is a separate feature — deferred.) Keep the "Écouter" chip if its action works (verify).

---

## MEDIUM

### M1 — English bleeding into the French UI
All verified as either hardcoded `String` (bypasses the catalogue) or a missing FR value:
- **Proverbs** — `HomeView.swift:499-528` (`HomeProverb.pool`): each `translation` is a hardcoded English `String`. → give each proverb a localizable translation (key per proverb) + add FR; surfaces on Home + summary.
- **AI provider subtitle** — `AISettingsView.swift:42`: hardcoded "Google AI Studio · Free tier · Recommended first provider". → `LocalizedStringKey` + FR (and see L3).
- **"beginner-friendly"** — left untranslated **inside the FR string** `Settings.InterfaceTatami.HelpOn` (`Localizable.xcstrings`). → translate ("mode adapté aux débutants" / "mode débutant").
- **Settings labels** — `SettingsView.swift:569` ("Data & Storage"), `:587` ("Cache & pre-warm"), `:605` ("Developer tools"): hardcoded `String`. → `LocalizedStringKey` + FR (dev-tools is behind `IKERU_DEV_TOOLS`, lower urgency).

### M2 — Tab labels inconsistent across modes (semantic mismatch)
**Root cause:** middle tab content is `HomeView`, but its label is "Accueil"/"Home" in beginner mode (`IkeruTabBar+Beginner.swift:51`, `Tab.Home`) and "稽古" (keiko = practice/training) in tatami mode (`IkeruTabBar.swift:107`) — different concepts.
**Best fix:** pick one concept per tab and use it in both modes. Recommend aligning to the documented IA "**Practice / Pratique / 練習**" (the tab IS where you start practice): beginner FR "Accueil"→"Pratique", JP "稽古"→"練習" (or keep 稽古 consistently). **Decision needed** (see below).

### M3 — "0% RAPPEL" on a 0-card summary
**Root cause:** `SessionSummaryView` renders the recall column unconditionally; `recallPercentage` returns 0 when `reviewedCount == 0` (`:216-220`, displayed `:80`).
**Best fix:** gate the RECALL column on `viewModel.reviewedCount > 0` (clean CARDS | TIME layout when empty). Mostly moot once C2 prevents empty sessions, but keep as a guard.

### M4 — "Vocabulaire" row opens a "Dictionnaire" screen
**Root cause:** `EtudeView.swift:82` row title "Vocabulary" vs `VocabularyDictionaryView.swift:28` `.navigationTitle("Dictionary")`.
**Best fix:** one term. Recommend **"Vocabulary"/"Vocabulaire"** everywhere (matches the 語彙 eyebrow + the entry row) → change the screen title. **Minor decision.**

### M5 — Always-running stopwatch + "~Xs" estimate on every card
**Root cause:** `SessionProgressBar.swift:43-72` renders elapsed time + remaining estimate; the budget logic (`ContinuousClock`, one-minute warning, end policy) lives separately in `SessionViewModel.swift:974-988, 1024-1031, 94-103` and does **not** depend on the visible labels.
**Best fix:** hide the visible time labels (keep the progress bar + all budget logic intact). The one-minute warning + auto-end still fire. **Design decision** (timer removal aligns with "no pressure"; confirm).

---

## LOW (polish)

- **L1 — Black flash mid-transition.** The opacity crossfades (tab switch in `MainTabView`, onboarding coordinator) momentarily show black. Fix: shorten the crossfade and/or guarantee a persistent `IkeruScreenBackground` floor beneath the transition so it never bottoms out to black.
- **L2 — Onboarding slides 1–2 have no forward affordance** (page dots only). Fix: add a subtle "glisse →"/chevron hint (or a Next button) on `OnboardingTourView` non-final slides.
- **L3 — "Recommandé" ambiguity.** Remove "Recommended first provider" from the Gemini subtitle (`AISettingsView.swift:42`); the section header already says it.
- **L4 — Furigana row shows a chevron but is a toggle.** `SettingsView.swift:326-335` uses `settingRow` → `rowChrome` (always renders `›`). Fix: a dedicated chevron-less toggle row (it already shows On/Off), consistent with the reminder toggles.
- **L5 — Tour/swipe tutorial re-fire for an "advanced" seeded profile.** Mostly a test-seed artifact (real advanced users still go through onboarding once). Optional: gate to genuinely-new profiles. Low priority.
- **L6 — AI setup fallback.** On non-Apple-Intelligence devices (e.g., iPhone 14 Pro) `AISetupView` correctly shows the Gemini path; make that fallback obvious and consistent with the fixed unavailable state in C1.

---

## Decisions needed (recommendations in bold)

1. **M2 tab naming:** align the middle tab to one concept — **recommend "Practice / Pratique / 練習"** (matches the IA + the practice CTA). Alternative: keep a "home" concept in both.
2. **M5 stopwatch:** **recommend hiding** the visible timer (aligns with the no-pressure vision); budget logic stays.
3. **H3 badge:** **recommend removing** the red 急 stamp outright.
4. **H4 stroke/example:** **recommend hiding for kana now**, wire up stroke-order/examples as a later feature.
5. **M4 naming:** **recommend "Vocabulaire"** everywhere.
6. **Home headline label (H1):** confirm the honest label scheme (À APPRENDRE / À RÉVISER / AUJOURD'HUI + split).

---

## Execution plan (sequenced; build + filtered tests + simulator verify + commit per phase)

**Phase 1 — Stop the bleeding (CRITICAL).**
- C1: NavigationStack + close button + loading state + escapable honest unavailable state.
- C2: empty-session guard (VM backstop) — full resolution lands with Phase 2.
- *Verify:* open Sakura with no provider → escapable; tapping COMMENCER with nothing due → no empty 0% session.

**Phase 2 — Honest Home (HIGH, the core).**
- Unify the count model (single planner-composed source), honest headline label + split, quiet-state/CTA gating (resolves H1, H2, C2), surface かな X/92, remove the red 急 badge (H3).
- *Verify:* fresh user, seeded user, all-caught-up user all read truthfully; numbers agree.

**Phase 3 — Card & session honesty (HIGH/MEDIUM).**
- H4 (gate stroke/example to kanji), M3 (recall column guard), M5 (hide stopwatch).

**Phase 4 — i18n + naming + polish (MEDIUM/LOW).**
- M1 localization sweep (+ proverbs FR), M2 tab labels, M4 vocab naming, L3 Recommandé, L4 Furigana toggle, L2 slide affordance, L1 fade floor, L6 AI fallback clarity, (L5 optional).

**Validation throughout:** iOS build green, Core green-subset tests, and live simulator pass per phase; final signed install on the device. No `dev`/`master`, no TestFlight (per current standing instruction); commits on `claude/app-screen-design-viz-kvs1a5`.

## Out of scope / deferred
- Wiring real stroke-order + example-sentence content (H4 beyond hiding).
- The dormant RPG `@Model` removal (tracked separately in `2026-06-14-beginner-first-ux-rework.md`).
- Seeding an N5 vocabulary content pack (the dictionary stays encounter-driven).
