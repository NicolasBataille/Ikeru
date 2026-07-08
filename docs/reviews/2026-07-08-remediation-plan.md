# Ikeru — Remediation Plan

> Companion to `2026-07-08-project-review.md`. Every con from the review mapped to a concrete fix,
> grouped into phases. Each item is tagged with where it can be verified:
> **[here]** = fully verifiable in a Linux CI/agent environment (no Xcode) ·
> **[ci]** = compiles/tests only on the macOS GitHub Actions runner ·
> **[mac]** = needs Xcode locally (project regeneration, simulator) ·
> **[device]** = needs a physical iPhone/Watch (haptics, mic, Live Activities, FoundationModels).

## Decision: how Claude designs UI/UX without an iOS simulator

**Keep SwiftUI. Do not rewrite the app.** Rewriting a shipping ~50k LOC SwiftUI codebase (plus Watch,
widgets, Live Activities, SwiftData, FoundationModels) to React Native / Flutter / Kotlin Multiplatform
solely to gain web previews would cost months, regress every platform feature that differentiates the
app, and still not render the *actual* product (a cross-platform port is a second implementation, not
a preview of the first).

Instead this repo gains a **`design-rig/`** — a zero-build HTML/CSS design harness that mimics the
iPhone rendering of the app:

- `tokens.css` — the Tatami/IkeruTheme design tokens (colors, spacing, radii, type scale) transcribed
  from `IkeruCore/Sources/Theme/IkeruTheme.swift` + `TatamiTokens.swift`, so web mockups use the same
  values the app compiles.
- `device.css` + `rig.js` — an iPhone-16-class frame (393×852 pt, Dynamic Island, home indicator,
  safe-area insets), dark scheme, SF-adjacent system font stack + the real Noto Serif JP for kanji.
- `components/` — HTML/CSS mirrors of the Tatami component set (IkeruCard, glass, enso rank, XP bars,
  hanko, tab bar, toasts, grade buttons…).
- `screens/` — one HTML page per app screen, composed from the components.
- `screenshot.mjs` — Playwright script that renders every screen headlessly to PNG, so an agent can
  *look at* its design work, iterate, and attach images to reviews.

Design workflow: design/iterate in the rig (agents can render and screenshot it) → human approves the
PNGs → port the approved design to SwiftUI → the rig page is kept as the design's reference spec.
The rig is a design tool, not a product: no app logic, no data, never shipped.

Known fidelity limits (accepted): no real SF Pro metrics (uses -apple-system where available), no
native materials/blur physics, no haptics/gesture feel. Those still require the existing
TestFlight/device loop — the rig removes blindness on layout, hierarchy, color, and typography.

---

## Phase 0 — Assets & ground truth (prerequisites)

| # | Item | Fix | Verify |
|---|------|-----|--------|
| 0.1 | Noto Serif JP fonts don't ship (declared in Info.plist, 28 call sites, zero files in repo, empty pbxproj Fonts group) | Commit `NotoSerifJP-Bold.ttf` / `-Medium.ttf` (Google Fonts CDN build; PostScript names verified to match `Font.custom` call sites), update `UIAppFonts` `.otf`→`.ttf` in `Ikeru/Info.plist` + `project.yml`, add to pbxproj Resources via `xcodeproj` gem, add OFL license file + Attribution entry | [here] files/plist/pbxproj · [mac] visual |
| 0.2 | `TODO.md` stale in both directions | Rewrite against verified reality; keep only genuinely open debt with dates | [here] |

## Phase 1 — Trust surfaces (public claims that are wrong today)

| # | Item | Fix | Verify |
|---|------|-----|--------|
| 1.1 | `docs/privacy.html` claims "no data sent to third-party servers", "E2E-encrypted iCloud", omits Speech Recognition permission, understates notifications | Rewrite EN+FR: disclose AI-provider submission (Gemini/Groq/Cerebras/OpenRouter/GitHub Models, only when user configures a key), Apple server speech fallback, CloudKit private-DB (not app-level E2E), all three notification types, Speech Recognition permission; keep the no-tracking/no-analytics claims that are true | [here] |
| 1.2 | `AttributionView` credits KanjiVG/Tatoeba/JMdict for content the shipped bundle doesn't use; strings not localized (verbatim `Text(String)`) | Correct entries to actual provenance ("original compositions" for current vocab/sentences; keep KanjiVG once 4.2 lands; add Noto OFL, VOICEVOX terms for rig); localize via `LocalizedStringKey`/`String(localized:)` | [here] text · [ci] compile |
| 1.3 | Privacy manifest may need revisiting if AI chat counts as data collection | Re-check `PrivacyInfo.xcprivacy` once 1.1 lands; document rationale in the file comment | [here] |

## Phase 2 — One-line-from-working bugs (hours each, huge value)

| # | Item | Fix | Verify |
|---|------|-----|--------|
| 2.1 | Live Activities dead: main app Info.plist lacks `NSSupportsLiveActivities` | Add key to `Ikeru/Info.plist` + `project.yml`; switch island timer to `Text(timerInterval:)` so it ticks between grades | [here] plist · [device] behavior |
| 2.2 | Claude keychain mismatch (`claudeAPIKey` saved, `claudeSessionToken` read) | `ClaudeProvider` reads `claudeAPIKey` with one-time read-migration from the legacy key | [ci] tests |
| 2.3 | Gemini absent from `.simple` chain → mnemonics fail on pre-iOS-26 devices with the recommended setup | Append `.gemini` to `.simple` chain (after groq); fix stale "2-second budget" doc comment | [ci] |
| 2.4 | `FoundationModelsProvider` uses `String(describing: response)` | Use the response's `content` accessor | [ci] compile · [device] iOS 26 |
| 2.5 | iCloud backup rows shown while `iCloudEnabled = false` | Gate the Settings backup section on `CloudBackupManager.iCloudEnabled` | [ci] |
| 2.6 | Home "STREAK / 0 days" dead tile contradicts anti-streak stance | Remove tile; replace with a real stat (total reviews or days active) | [ci] |
| 2.7 | `MainTabView` ships `Text("Detail: …")` placeholder for all navigation destinations | Route real destinations where they exist; `assertionFailure` + safe fallback otherwise; delete dead `AppTab.title/icon` vocabulary | [ci] |
| 2.8 | `SessionConfigView` orphaned (referenced only by its own #Preview) | Delete the file (git history preserves it) | [here] grep · [ci] |
| 2.9 | Watch app never ships (no embed dependency) | `project.yml`: Ikeru target depends on IkeruWatch with `embed: true`; mirror in checked-in pbxproj via xcodeproj gem (Embed Watch Content phase) | [here] pbxproj · [mac] archive check |
| 2.10 | `CompanionTabView`/previews construct fresh `AIRouterService` instances | Use the environment-injected instance | [ci] |
| 2.11 | LocalGPU tier dead code (discovery never started, in no chain) | Either start Bonjour discovery on settings screen appear + add to `.medium` chain when available, or remove the tier from Settings UI; pick removal for now (less blind risk), keep provider code | [ci] |

## Phase 3 — SRS engine correctness (the app's core loop)

| # | Item | Fix | Verify |
|---|------|-----|--------|
| 3.1 | Review wave ignores due-ness (raw `allCards()` order) | Planner consumes due cards sorted by `dueDate` ascending (overdue first); `SessionViewModel` passes `dueCards(before:)`-style sorted input | [ci] tests |
| 3.2 | Session segments blocked, not interleaved | Interleave review/booster/variety/new segments deterministically (round-robin by fraction) | [ci] tests |
| 3.3 | Silent `try?` saves in `CardModelActor` | Make saves throwing; propagate to callers; log `.error` + user-facing toast on grade-save failure | [ci] tests |
| 3.4 | Mastery too cheap (one Good → familiar; one Easy → mastered) | Require `reps >= 2` in addition to stability thresholds for familiar+/mastered counting toward unlocks & JLPT readiness | [ci] tests |
| 3.5 | Slow-correct quiz answers counted as mistakes (`.hard` → missedCardIDs) | Count only `.again` as a mistake | [ci] tests |
| 3.6 | No same-day relearning (interval clamps to ≥1 day) | Re-queue `.again`-graded new/lapsed cards within the current session (bounded by existing `maxRetriesPerCard`) before FSRS handoff | [ci] tests |
| 3.7 | `easeFactor`-derived speaking/accuracy metrics render constants | Derive accuracy from `ReviewLog` grades (rolling window); remove easeFactor proxies | [ci] tests |
| 3.8 | Kana cards seeded with inconsistent `CardType` (.kanji vs .vocabulary) | Unify on one type + one-time backfill migration for existing rows | [ci] tests |
| 3.9 | FSRS-5 weights on an FSRS-4 curve; w6/w17/w18 unused; retention hardcoded | Phase A: document honestly in FSRSService header. Phase B (later): adopt FSRS-5 curve + short-term steps, expose desiredRetention setting, per-user weight fitting from ReviewLog | header [here] · rest [ci]+[device] |

## Phase 4 — Pedagogy wiring & content

| # | Item | Fix | Verify |
|---|------|-----|--------|
| 4.1 | Non-SRS exercises render placeholders in sessions; real drill views are islands | Wire existing views (Listening, Shadowing, SentenceConstruction, Handwriting, VocabularyStudy, FillInBlank, Reading) into `ExerciseTransitionContainer` with real content payloads from `ContentRepository`; hook `EtudeViewModel.startSingleSurface` navigation | [ci] compile · [mac] flows |
| 4.2 | Stroke-order SVG empty for all 90 kanji | Fetch KanjiVG paths (CC BY-SA 3.0, network-verified reachable) for all bundle kanji; populate `stroke_order_svg` via `scripts/`; regenerate bundle; keep KanjiVG attribution | [here] sqlite verified |
| 4.3 | LearnerSnapshot inputs stubbed to zero (grammar, listening, skillBalances) | Persist grammar-card mastery; aggregate listening/shadowing accuracy into snapshot; feed real skillBalances from `ProgressService` | [ci] tests |
| 4.4 | Output exercises never feed FSRS | Map exercise outcomes to grades (e.g. shadowing ≥0.9→good, <0.5→again) on the corresponding cards | [ci] tests |
| 4.5 | Content volume (206 vocab / 31 grammar; no N4+) | Expand N5 bundle toward ~800 vocab/~80 grammar/~300 sentences via `scripts/generate_content_bundles.py` (native-checked lists; JLPT N5 inventories are public domain knowledge); then N4. Human/native review pass required before release | generate [here] · quality [human] |
| 4.6 | Leech-quiz distractors are filler strings | Sample same-level distractors from the content bundle via `ContentRepository` | [ci] tests |
| 4.7 | All listening is TTS | Near-term: label mode honestly, vary TTS voices/rates; wire rig/VOICEVOX playback (see 6.3). Long-term: record or license human audio for passages | [ci]/[device] |

## Phase 5 — Accessibility, i18n, gamification integrity

| # | Item | Fix | Verify |
|---|------|-----|--------|
| 5.1 | Zero Dynamic Type (380 fixed-size call sites) | Convert `FontExtensions`/`IkeruTheme.Typography` to `relativeTo:` text styles (single-file leverage); `minimumScaleFactor` guards on hero numerals | [ci] · [mac] visual |
| 5.2 | ~20 VoiceOver annotations app-wide | Label meaning-bearing glyphs (EnsoRank, MonCrest, Hanko, SerifNumeral); `.accessibilityHidden` decorative ones; `AccessibilityNotification` for XP/level-up; Button instead of bare tap in LootReveal | [ci] · [device] VO pass |
| 5.3 | Reduce Motion honored in one view | Gate repeatForever/particles/haptic crescendos behind `accessibilityReduceMotion`; replace `DispatchQueue.asyncAfter` chains with cancelable Tasks | [ci] |
| 5.4 | i18n leaks in reward loop (~10 keys), notifications, permission prompts | Add missing keys to `Localizable.xcstrings` (FR+EN); `String(localized:)` in NotificationManager; add `InfoPlist.xcstrings` for permission strings | [here] catalogue · [ci] |
| 5.5 | Lootbox challenge leaks its answer & has no learning content | Real question drawn from the user's learned/due cards; identical styling on all options; localize | [ci] tests |
| 5.6 | LevelUpView off-brand (star-burst "LEVEL UP!") | Restyle in Tatami vocabulary (enso + serif 段 numeral + hanko), tap-to-dismiss, reduce-motion aware | [ci] · [mac] visual |
| 5.7 | Three competing XP bars; cosmetics recolor only one | Consolidate on one component; route all through `ThemePaletteService`; move inline hex literals into tokens | [ci] |
| 5.8 | Error toasts use sakura pink instead of danger token | Use `#C97064` danger token | [ci] |
| 5.9 | Tatami-mode eligibility drifted from spec; "Later" = never | Restore `OR active days ≥ 30` path; show threshold progress in Settings row; re-offer after 14-day cooldown | [ci] tests |
| 5.10 | No i18n lint | CI step diffing string literals in Views against catalogue keys | [ci] |
| 5.11 | Watch/Widget off-brand (system colors) | Shared minimal token set (ink, gold, danger) for both targets | [ci] |

## Phase 6 — AI honesty & robustness

| # | Item | Fix | Verify |
|---|------|-----|--------|
| 6.1 | Companion chat sheet is a keyword-matching stub presented as AI | Route through `ConversationService`/router when AI available; when not, label visibly as scripted ("Sakura is resting — offline mode") | [ci] · [device] |
| 6.2 | Router never consults tier health; no 429 cooldown | Skip `.degraded`/rate-limited tiers for a cooldown; parse `Retry-After` | [ci] tests |
| 6.3 | Rig TTS never played; BG prewarm burns budget for nothing | Wire `RigAudioCoordinator.audioForText` into `AudioService` as primary with AVSpeech fallback (contract already documented); feature-flag prewarm until then | [ci] · [device] |
| 6.4 | Marker parsing brittle (`[CORRECTION]`/`[VOCAB]` string split) | Tolerant parsing + structured-output request mode where providers support it | [ci] tests |
| 6.5 | Flattened single-message history | Send real multi-turn message arrays | [ci] tests |
| 6.6 | GitHub Models legacy endpoint; no remote config | Update endpoint to `models.github.ai`; add a remotely-fetched provider/model manifest (GitHub Pages JSON) with baked-in fallback | [ci] |
| 6.7 | Mnemonic/correction hallucination risk cached forever | Validate furigana readings against bundle readings where the kanji is known; add per-mnemonic regenerate button | [ci] |
| 6.8 | BYO-key friction | Inline "add a free key (2 min)" CTA in the chat surface; longer-term: tiny proxy with free daily allowance | [ci] · product decision |

## Phase 7 — Platform features that lie

| # | Item | Fix | Verify |
|---|------|-----|--------|
| 7.1 | Widgets have no data channel (app group referenced by zero files) | Add `group.com.ikeru.shared` to `IkeruWidget.entitlements`; write due/level/last-study to `UserDefaults(suiteName:)` after sessions; read in timeline providers; deep-link the home widget | [ci] · [device] |
| 7.2 | StandBy widget: 10 s timeline (coalesced) over 12 hardcoded kanji | Feed from user's due/leech cards via app group; ≥15 min entry spacing | [ci] · [device] |
| 7.3 | Watch complication homeless + hardcoded | New watchOS widget-extension target hosting it; app-group data path | [mac] |
| 7.4 | Watch state sync one-directional; synced values unused in UI | `sendStateToWatch()` at launch + session end; render level/due on `WatchHomeView` | [ci] · [device] |
| 7.5 | Watch XP bypasses reward pipeline; pitch drill awards passive XP | Route watch results through `RPGRewardService`/`SkillXPLedger`; pitch drill awards only on an active "which pattern?" answer | [ci] tests |
| 7.6 | Backup restore drops FSRS state; destructive; 1 MB record ceiling | Extend `CardSnapshot` with reps/stability/difficulty (schemaVersion 2); pre-restore safety export; move payload to `CKAsset`; map `quotaExceeded` | [ci] tests |
| 7.7 | Export promises `reviews.json` but never writes it; ShareLink on a bare dir | Export review logs; zip the directory before sharing | [ci] tests |
| 7.8 | Handwriting fallback auto-passes any scribble | Honest "recognition unavailable — self-grade" path; longer-term stroke-order matching once 4.2 data exists | [ci] |
| 7.9 | `isSilentMode` detects volume-0, not the mute switch | Remove the broken skip logic (TTS in `.playback` ignores the switch anyway) | [ci] |

## Phase 8 — Engineering health

| # | Item | Fix | Verify |
|---|------|-----|--------|
| 8.1 | CI runs ~12% of tests (allowlist filter; legacy suites SIGSEGV) | Reproduce SIGSEGV on macOS runner, fix or delete offending suites, invert to full `swift test` + explicit skip-list | [ci]/[mac] |
| 8.2 | No SwiftData migration plan with live beta users | `VersionedSchema` + `SchemaMigrationPlan` before the next `@Model` change ships | [ci] · [device] upgrade test |
| 8.3 | O(all-cards) in-memory filtering in hot paths; UserDefaults read inside actor | `#Predicate`-based `dueCards`/`leechCards`/`cards(byType:)` with injected profile ID | [ci] tests |
| 8.4 | `SessionViewModel` 1,111 lines (god object) | Extract RPG/loot persistence, timer, LiveActivity coordination into services along existing MARK seams | [ci] |
| 8.5 | Code-review CI only fires on PRs to master | Retarget to `[dev, master]`; document/remove the opt-in variable | [here] |
| 8.6 | SwiftLint non-strict (~200 legacy warnings tolerated) | Baseline legacy warnings; `--strict` on changed files | [ci] |
| 8.7 | No UI test target despite complete fixture infra | Minimal UITest target: onboarding → start session → grade card smoke, on the CI simulator | [mac] |
| 8.8 | Timestamp build numbers; deploy-by-empty-commit | `workflow_dispatch` deploy path; run-number build numbers; MARKETING_VERSION bump discipline | [here] yml · [ci] |

## Phase 9 — Product decisions (need the owner, not code)

- **Gamification identity**: quiet the loot pipeline to match the wabi-sabi brief, or update the brief. (5.5/5.6 make it coherent either way.)
- **Placement onboarding**: "know kana already? target level?" seeding — unlocks the N4+ segment the market research targets.
- **Monetization / App Store strategy**: currently zero StoreKit and personal-app framing; decide before 1.0.
- **Daily term default**: flip to opt-out, or prompt once after the first session (only ambient retention mechanism).
- **Content licensing**: if real JMdict/Tatoeba imports replace hand-authored content, attribution obligations return.

## Execution status legend

Work executed by agent workflows in this session is committed to
`claude/project-review-analysis-40lc01` with one commit per phase; anything tagged [mac]/[device]
lands as prepared-but-unverified and is called out in commit messages and the session report.
