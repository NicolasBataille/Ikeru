# Tatami Redesign — Post-QA Fix Plan

**Status:** draft, ready to execute
**Branch:** `design/wabi-refinements`
**Spec it fixes against:** `docs/design-specs/2026-04-29-tatami-direction.md` and its plan `2026-04-29-tatami-direction-plan.md` (Tasks 1–11)
**Companion finding logs:** `/tmp/ikeru-walkthrough-findings.md`, `/tmp/ikeru-tests.log`
**Auditors:** plan-compliance, theme-penetration, localization, asset, build-and-test, MobAI live-walkthrough subagents (2026-05-02)

---

## TL;DR

The Tatami redesign landed on disk: 11 primitives, 5 marble PNGs, EN/FR string catalog, AppLocale wiring, all 11 plan Tasks PASS. But the running app on iPhone 17 simulator shows a **ship-blocking horizontal overflow** that clips two of five tabs out of view, makes Settings unreachable, and clips two of four FSRS grade buttons. On top of that, the marble texture isn't reading visually, the tab bar still shows EN labels under the kanji (spec violation), and HomeViewModel was modified in violation of the "view-only" contract (8 unit tests fail).

This plan fixes everything in priority order: **first the layout root cause** (because nothing else can be QA'd until the screen lays out correctly), **then the spec violations on the running app**, **then the static-audit regressions**, **then polish**.

---

## Priority key

| Tier | Meaning |
|---|---|
| **P0** | Ship blocker. Fix before any further QA. |
| **P1** | Spec violation visible to users. Fix before merging the design branch. |
| **P2** | Direction drift / design polish. Fix in this branch. |
| **P3** | Code regression from static audits. Fix before merging. |
| **P4** | Nice-to-have. Park as follow-up tickets if needed. |

---

## P0 — Ship-blocking layout

### Fix 1 · Clamp `MarbleBackground` and root containers to screen bounds

**Symptom (W-1, W-2):** ScrollView content lays out at x≈-188, w≈778 on a 402-pt screen. Tab bar HStack is ~735 pt wide. Home (稽古) and Settings (設定) tabs are clipped off-screen. Sumi corner L-marks not visible because they're off-screen-left. Two of four FSRS grade buttons off-screen.

**Root cause:**
- `MarbleBackground.swift:27-30` uses `Image(...).resizable().scaledToFill().ignoresSafeArea()` with **no explicit frame**. With `scaledToFill`, the image's intrinsic size (`marble-N` PNGs are 750×1624 base, but at @3x they decode at 2250×4872) leaks up the layout pass. `.ignoresSafeArea()` extends to safe area but does not clamp width.
- Parent ZStack in `MainTabView.body` (`MainTabView.swift:56`) uses `ZStack(alignment: .bottom)` with no `.frame(maxWidth: .infinity)` — so when the marble blows out, the ZStack sizes to the largest child.
- The `tabContent` ZStack (`MainTabView.swift:107-121`) and `IkeruTabBar` HStack inherit the inflated container width.

**Files to change:**
- `Ikeru/Views/Shared/Theme/Tatami/MarbleBackground.swift`
- `Ikeru/Views/Shared/Theme/IkeruGlass.swift` (inside `IkeruScreenBackground`)
- `Ikeru/Views/MainTabView.swift` (root ZStack)

**Patch — MarbleBackground.swift:**
```swift
public var body: some View {
    GeometryReader { proxy in
        Image(variant.rawValue)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
}
```
Why `GeometryReader` over `frame(maxWidth: .infinity, maxHeight: .infinity).clipped()`: the latter still lets `scaledToFill` propose its intrinsic size to the parent in some iOS 26 layout passes. `GeometryReader` gives us the proposed size deterministically, so the marble can fill it without growing past it.

**Patch — IkeruScreenBackground (`IkeruGlass.swift:189-195`):**
```swift
public var body: some View {
    ZStack {
        Color.ikeruBackground
        MarbleBackground(variant: variant)
            .opacity(0.95)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ignoresSafeArea()
}
```

**Patch — MainTabView root ZStack (`MainTabView.swift:55-71`):** wrap the ZStack with `.frame(maxWidth: .infinity, maxHeight: .infinity)` so the marble background and tab content cannot exceed the screen.

**Verification:**
- Re-run MobAI walkthrough; Home + Settings tabs must be reachable, all 5 tab cells visible, FSRS buttons all 4 visible and tappable.
- Inspect `snapshot` results: ScrollView width must equal device width (402 on iPhone 17).

---

### Fix 2 · Verify tab bar fits 5 cells inside screen width

**Symptom (W-2 secondary):** Even after Fix 1 clamps the parent, 5 tab cells × ~76 pt minimum content might still not fit a 380-pt usable tab-bar line if cells stay at their current padding.

**Files to change:** `Ikeru/Views/Shared/Theme/IkeruTabBar.swift`

**Action:**
1. Run the walkthrough after Fix 1. If all 5 cells are visible and not clipping content, this fix is no-op.
2. If still tight, reduce horizontal padding on `IkeruTabBar.body` (`IkeruTabBar.swift:37`) from `.padding(.horizontal, 22)` to `.padding(.horizontal, 12)`.

---

## P1 — Spec violations on the running app

### Fix 3 · Make tab bar truly kanji-only (drop EN labels)

**Symptom (W-3):** Each tab cell renders kanji + caps EN/FR label below (ÉTUDE / PARLER / PROFIL). Spec says **kanji-only** with mon active marker.

**File:** `Ikeru/Views/Shared/Theme/IkeruTabBar.swift`

**Action:** Delete lines 68–74 (the second `Text(englishLabel)` block and its modifiers). Also delete the `englishLabel` computed property (lines 92–100). The mon crest above (line 59) remains the only visual cue beyond the kanji glyph itself, which matches the spec ("Active marker: a gold MonCrest above the kanji label").

**Knock-on benefit:** removing the second line shrinks each tab cell vertically by ~16 pt and gives more horizontal room — likely makes Fix 2 unnecessary.

**Verification:**
- Walkthrough confirms tab cells show only the kanji + active mon crest.
- All 5 tabs reachable and visually balanced.

---

### Fix 4 · Use the spec'd kanji glyph for "Again" in FSRS grade buttons

**Symptom (W-4 secondary):** `GradeButtonsView.swift:44` uses `\u{53C8}` (又, "also") for the Again grade. The spec called for **再** (`\u{518D}`, "again"). 又 ≠ 再 even though both are valid kanji; spec compliance matters here because the four FSRS glyphs are meant to be a memorable Tatami signature.

**File:** `Ikeru/Views/Learning/CardReview/GradeButtonsView.swift`

**Action:** change line 44 from `kanji: "\u{53C8}"` → `kanji: "\u{518D}"`. Update the inline comment from `// 又` to `// 再`.

**Note:** the EN labels (Again / Hard / Good / Easy) under each kanji are correct per the implementation — they're a sub-label, not a replacement for the kanji header. The walkthrough subagent flagged this as "English labels", but the kanji headers are present at 18 pt serif above the EN word at 11 pt bold. Once Fix 1 stops clipping the row, all four buttons will be visible and the kanji will be unambiguous.

---

### Fix 5 · Onboarding walkthrough copy must wrap to multiple lines

**Symptom (O-1):** First-launch walkthrough text overflows screen width on a single line.

**Files:** `Ikeru/Views/Onboarding/OnboardingTourView.swift` (suspect lines 173, 178)

**Investigation needed:** the `description` Text (line 183) already has `.fixedSize(horizontal: false, vertical: true)` and `.multilineTextAlignment(.center)`, so it should wrap. The likely culprits:
- **Line 178** `Text(page.subtitle)` has **no** wrap guarantees — falls back to default which truncates if the parent doesn't propose enough width. Most likely victim of the W-1 root overflow (parent width is wrong, so the subtitle ends up "single line that doesn't fit").
- **Line 173** `Text(page.title)` similar.

**Action:**
1. After Fix 1, retest. If onboarding text wraps correctly, this is no-op (root cause was W-1).
2. If still cropped, add `.multilineTextAlignment(.center)`, `.fixedSize(horizontal: false, vertical: true)`, and a `.padding(.horizontal, IkeruTheme.Spacing.md)` to both `subtitle` and `title` blocks.

---

## P2 — Direction drift / design polish

### Fix 6 · Marble texture must read on screen

**Symptom (W-5 + user observation):** Marble background appears near-flat dark; the paper/marble texture isn't visible like the spec called for.

**Diagnosis:**
- `IkeruGlass.swift:189-195` already layers `MarbleBackground` at 0.95 opacity over `Color.ikeruBackground` — so the marble *should* dominate the visual.
- No `DimmingOverlay` exists in the codebase (grep returned nothing). The "DimmingOverlay" the walkthrough subagent saw in the snapshot is a SwiftUI / NavigationStack internal node, not an Ikeru view.
- Therefore the texture deficit is one of: (a) the marble PNGs themselves are too dark, (b) `Color.ikeruBackground` underneath is bleeding through because the marble is rendering at a smaller size than it should after Fix 1, or (c) something else (like the per-screen `IkeruScreenBackground` second instance) is layering a second tinted surface that washes it out.

**Action:**
1. After Fix 1, take fresh screenshots and inspect the marble visibility. If it now reads — done.
2. If still flat, **lighten the marble PNGs**. Options:
   - Re-export `marble-{1..5}.png` with brightness +20%, contrast +10% in an image editor.
   - Or add a subtle `.colorMultiply(Color(white: 1.2))` modifier on the Image inside `MarbleBackground.body`.
3. Audit each tab's root view (`HomeView`, `ProgressDashboardView`, `CompanionTabView`, `RPGProfileView`, `SettingsView`) for a **second** `IkeruScreenBackground()` call. The root background should only be drawn once, in `MainTabView`. Per-screen views should NOT re-add it. Remove duplicates.

**Files (potentially):**
- `Ikeru/Assets.xcassets/Tatami/Marble/marble-{1..5}.imageset/` — PNG re-export
- `Ikeru/Views/Shared/Theme/Tatami/MarbleBackground.swift` — optional `colorMultiply`
- `Ikeru/Views/Home/HomeView.swift`, `Ikeru/Views/Home/ProgressDashboardView.swift`, `Ikeru/Views/Learning/Conversation/CompanionTabView.swift`, `Ikeru/Views/RPG/RPGProfileView.swift`, `Ikeru/Views/Settings/SettingsView.swift` — remove duplicate `IkeruScreenBackground()` if any.

**Verification:**
- Walkthrough screenshots show visible marble grain on Home, Study, Companion, RPG, Settings, and the SRS card screen.

---

### Fix 7 · Replace 🌱 emoji on Kana cells with a Tatami glyph

**Symptom (W-6):** Walkthrough agent observed 🌱 on every kana cell in `KanaPoolSelectorView`. Tatami direction excludes emoji.

**File:** `Ikeru/Views/Learning/Kana/KanaPoolSelectorView.swift` (and possibly `KanaGroupCard.swift`)

**Investigation needed:** grep returned no 🌱 / "seedling" matches. The emoji may be:
- A unicode char passed through localized strings.
- An SF Symbol like `leaf.fill` that the walkthrough described in plain language as 🌱.

**Action:**
1. Open the kana selector views, locate the per-cell glyph.
2. Replace with one of: `MonCrest(kind: .asanoha, size: 12, color: .ikeruPrimaryAccent)`, a small `HankoStamp("仮")` (kana literal), or a serif Japanese label.

---

### Fix 8 · Add `FusumaRail` to the SRS card progress slot

**Symptom (W-7 + theme-penetration audit):** Spec Task 5 calls for "fusuma progress" on `SRSCardView`. The file uses `tatamiRoom` and `BilingualLabel` but never invokes `FusumaRail`. Progress on the active session screen is hand-rolled rectangles, not the actual primitive.

**File:** `Ikeru/Views/Learning/CardReview/SRSCardView.swift`

**Action:** Locate the existing progress indicator (likely a `Rectangle` or `Capsule` driven by a `progress: Double` binding). Replace with `FusumaRail` (or wrap the progress bar with paired `FusumaRail` hairlines per the primitive's usage — see `FusumaRail.swift` for API).

**Verification:** Walkthrough on an active session screen shows a paired-hairline gold + ink rail above/below the progress slot, matching `FusumaRail` rendering elsewhere.

---

### Fix 9 · Remove residual `.ikeruGlass(...)` calls inside Tatami contexts

**Symptom:** Theme-penetration audit found two leaks:
- `Ikeru/Views/RPG/RPGProfileView.swift:482` — inventory item cells.
- `Ikeru/Views/Settings/SettingsView.swift:351` — inline name editor.

**Action:** Replace each `.ikeruGlass(...)` with `.tatamiRoom(.standard)` or `.tatamiRoom(.glass)` (whichever surface is appropriate for the context). For the inventory cells, the rarity tint can be applied as a `MonCrest` color or a sumi-corner `color:` parameter instead of a tinted glass surface.

**Optional follow-up:** also consider deprecating the legacy `IkeruGlassSurface` / `ikeruGlass` API if no callers remain after this pass. Out of scope for this branch.

---

## P3 — Code-level regressions from static audits

### Fix 10 · Restore HomeViewModel's view-only contract

**Symptom:** The Tatami plan's preamble committed to "zero functional change to view-models, persistence, or business logic." The diff added `skillBalance`, `sessionPreviewNewCount`, `sessionPreviewReviewCount`, `xpInCurrentLevel`, `xpRequiredForLevel`, `xpToNextLevel`, plus a new `ProgressService` dependency to `HomeViewModel`. **8 of 8 `HomeViewModelTests` fail.**

**File:** `Ikeru/ViewModels/HomeViewModel.swift` (and its tests in `IkeruTests/HomeViewModelTests.swift`)

**Decision needed (ask user):**
- **Option A — keep the additions, fix the tests.** The new properties are useful for the redesigned Home (skill radar, session preview counts, XP teaser). Update HomeViewModelTests to seed the new dependencies and assert on the new properties. Keeps the design pass functional.
- **Option B — revert the view-model additions, derive the values in the View.** Move the computation into `HomeView` private helpers using existing data sources. Honors the original "view-only" contract literally but bloats the view.

**Recommendation:** Option A. The redesign genuinely needs these signals (skill balance, session preview, XP teaser are new UI). Update the tests; document the contract change in this fix plan.

**Verification:** `xcodebuild test` reports 0 HomeViewModelTests failures.

---

### Fix 11 · Pin locale in Conversation tests so AppLocale doesn't leak

**Symptom:** Two `ConversationViewModelTests` ("Handles timeout error", "Handles rate limit error") assert against English substrings ("too long", "wait"), but the test process picks up the simulator's default French locale through `AppLocale`'s system-detection path, so the assertions get French strings.

**Files:**
- `IkeruTests/ConversationViewModelTests.swift`
- Possibly `Ikeru/Localization/AppLocale.swift` (to expose a test seam)

**Action:**
1. In the failing tests' setup, force `AppLocale(preference: .en)` before exercising the view-model.
2. Or assert on a stable error code / enum case instead of a substring.

**Verification:** Both tests green under `xcodebuild test`.

---

### Fix 12 · SwiftData test isolation across parallel `xcodebuild` runs

**Symptom:** ~36 session/integration tests fail with the pattern `sessionQueue.count → 0`, `currentCard → nil`, `xp → 0`, `level → 1` — SwiftData state leaking across the 15 parallel test processes that `xcodebuild` spawns. Pre-existing-but-exposed by the larger surface area of redesign tests.

**Files:** test infrastructure (likely `IkeruTests/Helpers/` or per-test `init`).

**Action:**
1. Each test must construct its own in-memory `ModelContainer(for: ..., configurations: ModelConfiguration(isStoredInMemoryOnly: true))` in its `init`.
2. Audit `SessionViewModelTests.swift`, `SessionIntegrationTests.swift`, `AdaptiveSessionViewModelTests.swift`, `ImmersiveSessionViewTests.swift` for any shared / static `ModelContainer` and remove it.
3. If running tests in parallel still leaks, set `-parallel-testing-enabled NO` in the scheme as a temporary cap while we restructure.

**Verification:** all session/integration suites green; `xcodebuild test` passes.

---

## P4 — Polish (this branch or next)

### Fix 13 · Localize the user-flow English literals in redesigned screens

**Symptom:** ~50 hardcoded English `Text(...)` calls in redesigned screens. The catalog itself is 100% FR-translated, but user-facing literals didn't migrate to the catalog.

**Priority subset to fix in this branch (user flow, high frequency):**
- `Ikeru/Views/Home/HomeView.swift:100` — "All caught up — enjoy the calm"
- `Ikeru/Views/Home/HomeView.swift:479` — "Begin Session"
- `Ikeru/Views/Home/ProgressDashboardView.swift:92,95,125,128` — "Kana", "Hiragana & katakana, par groupes" (mixed!), "Dictionary", "Personal vocabulary collection"
- `Ikeru/Views/Session/ActiveSessionView.swift:97-301` — END SESSION, Leave this session?, End Session, Keep Going, PAUSED, Session Paused, ALL CLEAR, etc.
- `Ikeru/Views/Session/SessionConfigView.swift:44-178` — Configure Session, Choose how much time you have, Duration, Audio exercises excluded, Start Session.
- `Ikeru/Views/Session/SessionSummaryView.swift:50` — proverb "七転び八起き · Fall seven, rise eight" (EN half).
- `Ikeru/Views/RPG/RPGProfileView.swift:60,64,136,425` — "YOUR JOURNEY", "RPG Profile", " XP", "Complete sessions to earn loot."
- `Ikeru/Views/RPG/LevelUpView.swift:39` — "LEVEL UP!"
- `Ikeru/Views/Settings/DeleteProfileSheet.swift:57-201` — DANGER ZONE, Delete Profile, etc.

**Defer (admin / advanced surfaces, EN-only is acceptable):**
- `AISettingsView` (provider / API-key UI)
- `RigJobsView`
- `AttributionView`

**Action per literal:** wrap in `Text("Begin Session", comment: "...")` so Xcode picks it up into the catalog, then add the FR translation in `Localizable.xcstrings`.

**Verification:** switch device locale to Français → walkthrough shows FR strings on every targeted screen.

---

## Execution order

1. **Fix 1** (root width clamp) — the linchpin. Everything else is hard to verify until this is done.
2. **Fix 3** (kanji-only tabs) — cheap, removes the W-3 spec violation, also lightens the tab-bar layout.
3. **Re-run MobAI walkthrough.** Many P1/P2 items may resolve themselves once the layout is correct.
4. Fix 4 (再 glyph), Fix 5 (onboarding text — only if still broken after Fix 1), Fix 6 (marble visibility — only if still flat after Fix 1).
5. **Fix 9** (kill stray `.ikeruGlass` calls) — cheap, finishes the spec direction across all 9 screens.
6. Fix 7 (kana emoji), Fix 8 (FusumaRail in SRS).
7. **Fix 10** (HomeViewModel contract decision) — needs user input. Block on user before touching.
8. Fix 11 (locale test pin), Fix 12 (SwiftData test isolation).
9. **Re-run full test suite** until 0 failures.
10. Fix 13 (localize remaining user-flow strings).
11. **Final walkthrough + final test pass + commit per fix** (one commit per Fix N).

---

## Out of scope (not in this branch)

- Deprecating `IkeruGlassSurface` / `ikeruGlass` API entirely.
- Migrating `Ikeru/Views/Onboarding/NameEntryView.swift:114` away from `IkeruGlassSurface` (onboarding wasn't in the original 9-screen Tatami scope).
- Localizing AI-provider / RigJobs / Attribution views.
- Pre-existing flaky `StrokeOrder > Random scribble` test.
- Pre-existing intermittent `CardReviewViewModelTests` nil-unwrap teardown crash.

---

## Decisions locked in (2026-05-02)

1. **Fix 10 — HomeViewModel contract:** **Option A**. Keep the new properties (`skillBalance`, session-preview counts, XP-teaser values, `ProgressService` dep) and update `HomeViewModelTests` to seed and assert on them. The view-model contract change is documented here; future "view-only" passes should re-read this section.
2. **Fix 6 — Marble brightness:** **Option (b)**. If Fix 1 doesn't restore the texture, reduce the underlying ink tint (lower the alpha of `Color.ikeruBackground` under the marble, or drop the marble's `.opacity(0.95)` to let the base color show less). Do NOT re-export the PNGs.
3. **Fix 13 — Localization scope:** Defer `AISettingsView`, `RigJobsView`, `AttributionView` to EN-only. Only the user-flow subset (Home empty state, Begin Session, ActiveSessionView, SessionConfigView, SessionSummaryView proverb half, RPG headers, LevelUpView, DeleteProfileSheet, ProgressDashboard literals) gets translated this branch.
