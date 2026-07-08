# Ikeru — Full Project Review

> Date: 2026-07-08 · Scope: entire repository (product, pedagogy, UI/UX, architecture, AI, platform integrations)
> Method: six parallel deep-dive analyses + adversarial verification pass against the actual code and shipped assets.
> Every factual claim below was checked against source files, the shipped `n5-content.sqlite`, `project.pbxproj`, and the published docs.

---

## 1. What Ikeru is

Ikeru is a solo-developed, portfolio-public, **all-four-skills Japanese learning app for iPhone** (iOS 17+, dark-mode, FR/EN), with an Apple Watch companion, widgets, and an AI companion ("Sakura"). Its founding thesis is written down in `docs/market-research.json`: learners today juggle 4–6 fragmented apps (Anki + WaniKani + Bunpro + a speaking app…), and no comprehensive Apple Watch Japanese app exists. Ikeru's answer is one app built around:

- an **FSRS spaced-repetition core** (the modern successor to Anki's SM-2),
- an **adaptive session planner** that composes a daily one-tap session,
- **12 exercise types** across reading / writing / listening / speaking, unlocked progressively,
- a deliberately quiet, **wabi-sabi "anti-gamification" RPG layer** (XP, ranks, loot — but no streaks, no leagues, no login pressure),
- an **AI companion** for conversation practice and mnemonics, routed across free-tier LLM providers with on-device fallback.

It genuinely ships: TestFlight releases #16–#21, a public beta link, a privacy policy page, and complete FR+EN localization (458/458 keys). That end-to-end completeness is rare for a solo project.

## 2. How you use it, day to day

**Onboarding:** name entry → 3-page tour (道 your journey / 友 your companion / 始 begin — "you'll start with hiragana") → optional AI setup (detects on-device Apple FoundationModels; otherwise guides pasting a free Gemini key). Then a live spotlight tour of the real UI and a first-flashcard swipe tutorial.

**The daily loop:** open Home → Japanese-date greeting, a rotating yojijukugo proverb, the due-card count as a 56pt serif numeral → one gold CTA **稽古を始める / Begin practice**. That single tap composes a ~15-minute session with zero configuration: 40% FSRS reviews / 30% weakest-skill booster / 20% daily-rotating variety / 10% new content (`DefaultSessionPlanner`). Cards are graded by 4-direction swipes mapped to FSRS grades (again/hard/good/easy) with haptics; the summary attributes XP to the four skills (読・書・聴・話) and offers a mistakes-only re-run. When you're caught up, Home shows a **rest-day state (今日は休)** that *removes* the CTA — the philosophical opposite of a streak.

**Power path:** the Étude (Study) tab is an 11-tile "稽古場" practice ground with research-grounded unlock gates (e.g. reading passages at 100 vocab + 50 kanji familiar+; Sakura conversation at ~N4), plus a Compose sheet for custom sessions (types × JLPT levels × duration). The Companion tab hosts Sakura chat; RPG shows level, attributes, inventory, cosmetics; Settings covers AI keys, notifications, backup, export, profiles.

## 3. Teaching methods — assessment

### What's pedagogically sound (and real)

- **Genuine FSRS**, not a marketing label: `FSRSService.swift` implements the DSR update equations with published FSRS-5 pretrained weights (w0–w18), retrievability computation, pure functions with injectable clock, atomic grade+ReviewLog persistence, and Anki-style predicted-interval transparency on the grade buttons.
- **Receptive-before-productive sequencing** (`SkillType.pedagogicalOrder`) and unlock gates that cite SLA research (Swain's output hypothesis, Tadoku graded-reader coverage) — beginners aren't drowned in production tasks.
- **Leech remediation beyond flagging**: 3-lapse detection with confusion-type analysis including a curated visually-similar-kanji table (日/目, 持/待/特…), feeding a companion intervention with mnemonic + inline quiz.
- **i+1 scaffolding fade**: reading passages hide furigana only on kanji the learner has demonstrably retained (interval ≥ 7 days) — genuinely adaptive comprehensible input.
- **Pitch-accent training that competitors skip**: real on-device autocorrelation F0 extraction, mora segmentation, four Tokyo-dialect pattern classification, per-pattern accuracy tracking — plus a haptic pitch drill on the Watch (high/low mora as distinct taps), a genuinely novel wrist-native idea.
- **RTK/KKLC-style kanji study**: radical decomposition graph (79 radicals, 176 edges), progressive disclosure (radicals → readings → vocabulary), AI keyword-method mnemonics cached per kanji.
- **Multi-modal evaluation where wired**: shadowing scored via LCS diff of speech-recognition output; handwriting via Vision + stroke-path distance tiers.

### Where the pedagogy breaks down

1. **Content volume cannot teach Japanese past week one.** The only shipped bundle is `n5-content.sqlite`: **90 kanji, 206 vocabulary, 96 sentences, 31 grammar points** (verified by direct query) — versus ~800 vocab for real N5. No N4–N1 bundles exist, so the 80%-mastery progressive-unlock ladder leads nowhere. Sentence construction has 12 hardcoded templates; reading has ~2 hardcoded passages; **stroke-order SVG is empty for all 90 kanji** (0 rows), so stroke tracing has no targets.
2. **Planned sessions don't deliver the exercises.** `ExerciseTransitionContainer` renders every non-SRS exercise type as a **placeholder view**; the functional drill views (Listening, Shadowing, Sentence Construction…) exist but are islands, some only instantiated in `#Preview`. Roughly 70% of the built pedagogy is dead code from the user's seat.
3. **The adaptive system's inputs are stubbed to zero** in production (`grammarPointsFamiliarPlus: 0`, `listeningAccuracy: 0`, `skillBalances: [:]`): three unlock gates are unreachable, the "weakest skill" booster always picks reading, and JLPT readiness is pinned to N5 because the grammar axis of a `min()` formula is permanently zero.
4. **The review wave ignores due-ness**: the planner consumes `allCards()` in raw order rather than due-date-sorted due cards — undermining the core point of SRS — and session segments are blocked, not interleaved.
5. **Mastery is too cheap**: one "Good" makes a card *familiar*, one "Easy" makes it *mastered*, and these single-tap cards immediately count toward unlock gates and JLPT readiness. Slow-but-correct quiz answers (>5 s → `.hard`) are counted as mistakes.
6. **No same-day relearning steps**: intervals clamp to ≥1 day, so a failed new card vanishes until tomorrow; FSRS-5's short-term weights (w17/w18) are declared but unused, and the forgetting curve is actually the FSRS-4 form.
7. **All listening is synthesized TTS** (AVSpeechSynthesizer) — learners never hear natural human Japanese. And **output exercises never feed the SRS**: shadowing, listening, handwriting, pitch and sentence results are evaluated locally but never call `gradeCard`, so the scheduler models the learner from flashcards alone.
8. Broken proxy metrics are shown to the learner: speaking score and monthly accuracy derive from an `easeFactor` that grading never mutates — both render as a constant ~0.71.

**Verdict on pedagogy:** the *design* is research-literate and above most commercial apps (FSRS + gated output + pitch accent + leech interventions is a strong stack). The *execution* is ~30% wired end-to-end; today the app effectively teaches kana and N5 flashcards well, and everything else is scaffolding.

## 4. UI / UX — assessment

### Strengths

- **A real, documented design language** ("Tatami": enso, kintsugi hairlines, mon crests, hanko stamps, torii, fusuma rails) with centralized tokens and *restraint rules encoded in code* — vermilion "at most once per screen", glass "sparingly on hero cards". The hand-tuned enso brush ring is genuine craft.
- **The Beginner ↔ Tatami density-mode system** is a rare, well-reasoned answer to a real problem (kanji-saturated chrome is backwards for beginners): dense Japanese chrome becomes *a destination you grow into*, with lossless profile migration and per-user override preservation.
- **Layered onboarding**: slides → skippable AI setup → an 8-step coach-mark tour that spotlights the *live* UI (anchorPreference cutouts, auto tab-switching) → contextual swipe tutorial on the first real card. Replayable from Settings.
- Systematic feedback: severity-aware toasts, modern `.sensoryFeedback` haptics, Dynamic-Island-aware XP overlay placement, dead-end-aware CTAs.
- Humane gamification framing where designed: lootbox challenges "failure only delays, never punishes", rest days, calm caught-up states.

### Weaknesses

- **Accessibility is far below the visual polish**: 380 fixed-size font uses, **zero Dynamic Type**; ~20 VoiceOver annotations app-wide; Reduce Motion honored in exactly one view; level-up auto-dismisses in 2 s with no announcement. For a text-centric learning app this is the biggest UX debt.
- **The lootbox challenge is an empty placeholder that leaks its own answer**: the correct button is styled `.primary` (gold) while wrong ones are `.secondary`, and there is no actual question — just "tap the correct answer" over arbitrary kana. The centerpiece reward mechanic has zero learning content and undermines reward integrity.
- **Identity tension**: the brief demands "no gamification theatre", yet the app ships loot rarities, an inventory, and a generic star-burst "LEVEL UP!" overlay untouched by the Tatami restyle — while Home renders a **dead "STREAK / 0 days" placeholder tile** that contradicts the anti-streak stance stated 250 lines earlier in the same file.
- **i18n leaks concentrate in the reward loop** ("Level %lld", "Start Challenge", "Retry", "Tap for next item"… all missing from the catalogue) — FR users see raw English at the most emotionally charged moments. Notifications and permission prompts are English-only too.
- **Tatami-mode eligibility silently drifted from spec** (the "OR ≥30 active days" path was dropped; a 21-day unbroken streak is now mandatory in an app that hides streaks — users can't see progress toward it), and "Later" on the suggestion card actually means "never again".
- **The signature kanji typography doesn't ship**: `Info.plist` declares Noto Serif JP and 28 call sites use it, but **no font files exist in the repo, the pbxproj Fonts group is empty, and CI never downloads them** — every distributed build silently renders hero kanji in the system font. The design intent is excellent; the shipped product doesn't show it.
- Watch and widgets use raw system colors (zero theme tokens) — the design system stops at the iPhone edge. Three competing XP-bar visualizations coexist and equipped cosmetic themes recolor only one of them.
- `MainTabView` ships a debug placeholder (`Text("Detail: …")`) as the navigation destination for every route.

## 5. Architecture & engineering health

### Strengths

- **Unusually clean layering for a solo project**: a zero-dependency `IkeruCore` SPM package (~17.7k LOC) holding models/repositories/services as pure functions or actor-isolated types, consumed by a ~32.8k LOC SwiftUI app. Disciplined Swift 6 concurrency (Sendable facades → `@ModelActor` → DTOs; no `@Model` leaks across actors). Zero external dependencies = zero supply-chain surface.
- **Large modern test corpus**: ~1,150 test functions in 121 files, 100% Swift Testing, mirrored structure, protocol mocks, injectable clocks.
- **Battle-tested CI/CD**: lint → 3-scheme parallel build → tests → device-build sanity → master-gated TestFlight deploy, with real-world fixes documented inline (dynamic simulator pick, `altool` exit-0 grep guard, compiler-error PR comments).
- Good public-repo security posture: Keychain (`WhenUnlockedThisDeviceOnly`) for API keys, all signing material in Actions secrets, os.Logger privacy annotations, idempotent version-gated backfills.

### Weaknesses

- **Test quarantine is severe: CI runs ~12% of the suite** (a hand-picked `--filter` allowlist, because full `swift test` SIGSEGVs in legacy suites). ~87% of tests provide no regression protection, and new suites silently never run unless someone extends the filter string.
- **No SwiftData migration plan** (zero `VersionedSchema`/`SchemaMigrationPlan`) while schema drift has already happened on `@Model` classes and external TestFlight testers have data on device. This is the top data-loss risk.
- **Silent persistence failures**: every save in `CardModelActor` is `try?` — a failed grading save is swallowed, corrupting FSRS state relative to the review log.
- Hot-path inefficiency: `dueCards`/`leechCards` fetch *all* cards and filter in memory (no `#Predicate`), executed on every session start — degrades with collection growth.
- God objects: `SessionViewModel` is 1,111 lines (session lifecycle + timers + XP/loot + Live Activities + snapshots); `SettingsView` 970; `HomeView` 762.
- The Claude code-review CI gate only fires on PRs to `master` — but per the two-stage flow all feature work lands on `dev`, so it reviews only pure release merges (and is double-gated behind an opt-in variable).
- `TODO.md` is badly stale in both directions (lists fixed things as open, omits real risks) — it can't be trusted as a debt register. No UI-test target exists despite complete launch-arg fixture infrastructure and a written E2E plan.

## 6. AI integration

### Strengths

- A genuinely well-engineered **8-tier router** (on-device FoundationModels + Gemini/Groq/OpenRouter/Cerebras/GitHub Models free tiers + paid Claude + a local-GPU tier) with complexity-based chains, offline short-circuit to on-device, per-error UI messaging, and $0-cloud economics. 4 of 6 cloud providers are ~44-line shells over one shared OpenAI-compatible transport; 74 tests cover the layer.
- Real prompt-product thinking: Sakura's system prompt enforces machine-parseable furigana `漢字(かんじ)` that feeds the ruby renderer, JLPT-tiered language constraints, and `[CORRECTION]`/`[VOCAB]` markers that feed a vocabulary-encounter pipeline.
- The self-hosted "rig" (FastAPI + VOICEVOX Japanese TTS job queue in Docker, content-addressed Opus cache, SRS-aware background pre-warming) is a legitimately well-built mini-service.

### Weaknesses (several are outright bugs)

- **Claude keychain mismatch (bug)**: Settings saves the key under `claudeAPIKey`; the provider reads the deprecated `claudeSessionToken`. Paying users get a permanently unavailable provider.
- **Gemini can't serve mnemonics (bug-adjacent)**: onboarding pushes Gemini as *the* key, but `MnemonicService` uses the `.simple` chain `[onDevice, cerebras, groq]` — on pre-iOS-26 devices with only the recommended key, every mnemonic fails.
- **The flagship companion chat is fake**: the Sakura sheet wired into every tab answers with hardcoded keyword-matched strings and a simulated 800 ms typing delay. The AI-looking surface users find first contains no AI. (Real AI powers only the Conversation exercise and mnemonics.)
- **Rig TTS is never played back**: `RigAudioCoordinator.audioForText` has zero call sites; the app uses AVSpeechSynthesizer exclusively. The background pre-warm task enqueues jobs whose output nobody fetches.
- `FoundationModelsProvider` uses `String(describing: response)` instead of the response's content accessor — likely emitting a debug description on real iOS 26 hardware.
- Rate-limit handling is shallow (tier statuses tracked but never consulted; no Retry-After/cooldown), teaching content from free Llama/Gemini is trusted verbatim (wrong readings cached forever), and the BYO-API-key requirement is hostile for a consumer app — below iOS 26 there is no zero-setup path to the headline feature.

## 7. Platform features (Watch, widgets, notifications, backup)

Wiring is far better than `TODO.md` claims (all four "unwired" items are in fact wired), but several features are **dead in practice**:

- **Live Activities never start**: the main app's Info.plist lacks `NSSupportsLiveActivities` — the manager's guard silently skips every session. One plist line unlocks an already-built feature.
- **The Watch app never ships**: `IkeruWatch` has no embed dependency in the Ikeru target and no Embed Watch Content phase — TestFlight builds contain no watch app at all. The watch complication additionally has no widget-extension target to host it and returns hardcoded data.
- **All three widgets are placeholders**: the app group `group.com.ikeru.shared` is referenced by zero Swift files, so no data channel exists; the StandBy flashcard widget emits 10-second timeline entries WidgetKit will coalesce (~5 min minimum) over 12 hardcoded kanji.
- **iCloud backup is compile-time disabled (`iCloudEnabled = false`) but Settings still shows the rows** — every tap dead-ends. Restore also drops FSRS `reps`/stability/difficulty (degrading the memory model), is destructive with no safety copy, and stores the snapshot in a plain CKRecord field that will hit the 1 MB limit.
- The handwriting *fallback* recognizer returns the target character for any scribble (auto-pass); the Watch pitch drill awards full XP for passively tapping "next", writing XP directly to state and bypassing the reward pipeline — an XP-farming side channel.
- Genuinely good: on-device `SFSpeechRecognizer ja-JP` with correct permission and audio-session handling; Vision-based handwriting with a clean provider abstraction; positively-framed notifications with deep links; an export format with an embedded machine-readable schema (`context.json`) designed for AI-agent analysis — though the promised `reviews.json` is never actually exported.

## 8. Trust & compliance findings (verified)

- **The published privacy policy contradicts shipped data flows.** `docs/privacy.html` (registered with TestFlight) claims "No data is sent to any third-party server" — yet chat messages and prompts go to Google/Groq/Cerebras/OpenRouter/GitHub Models; speech falls back to Apple's servers on devices without on-device recognition; the Speech Recognition permission is omitted. Its iCloud claim of end-to-end encryption is also wrong: backups use plain CKRecord fields (no `encryptedValues`), i.e. Apple-held keys unless the user enables ADP. **This is the most urgent fix in the repo — it's a live public claim.**
- **The Attribution screen misstates provenance in both directions**: it credits KanjiVG for stroke paths that are empty in the shipped bundle, and Tatoeba/JMdict for content that is actually hand-authored in `scripts/generate_content_bundles.py` ("original compositions" — the scripts download nothing). Noto Serif JP's OFL notice is absent (moot only because the fonts don't ship).
- **No monetization surface exists** (zero StoreKit code, version pinned 1.0.0, no App Store metadata) — fine for a portfolio/personal app, but an unstated strategic gap given the commercial market-thesis framing.
- Multi-profile support, incidentally, is real and reasonably complete (switcher, per-profile scoping, styled delete-loss summary) — an uncovered strength.

## 9. Verdict

### Pros

1. **Design ambition matched by unusually good design documentation** — market research, design specs, and a coded-in restraint discipline most teams never write down.
2. **A pedagogically serious core**: real FSRS, research-grounded gating, leech interventions, i+1 furigana fading, pitch-accent training. The stack on paper beats most commercial apps.
3. **Clean, modern engineering**: layered zero-dependency core, Swift 6 concurrency discipline, 1,150 tests, pragmatic CI/CD that actually deploys to TestFlight.
4. **Coherent product philosophy** (anti-burnout, wabi-sabi calm) that is *implemented* in places — rest days, no streaks, quiet states — not just claimed.
5. **It ships**, bilingually, with onboarding, tours, notifications, export, and multi-profile support.

### Cons

1. **The gap between designed and delivered is the defining problem**: placeholder exercise views in the main session flow, one thin N5 bundle, empty stroke data, unshipped fonts, unembedded Watch app, dead Live Activities/widgets/backup, a fake companion chat. A reviewer's honest one-liner: *a beautifully architected app whose product is ~30% installed*.
2. **Trust-surface inaccuracies** (privacy policy, attribution screen) that are publicly published and materially wrong.
3. **Accessibility debt** (no Dynamic Type, near-zero VoiceOver) unacceptable for a text-centric learning app.
4. **Quality-control asymmetry**: 88% of tests quarantined, no schema-migration plan with beta users' data live, silent `try?` saves in the SRS hot path.
5. **The AI pillar is fragile**: BYO-key friction, free-tier dependence, two wiring bugs that break the recommended and the paid paths, unvalidated teaching content.

### If I had to prioritize the rework (highest leverage first)

1. **Fix the public claims** — rewrite `privacy.html` to match real data flows and correct `AttributionView` (days, not weeks, of work; it's live and wrong).
2. **Close the "one-line-from-working" gaps**: `NSSupportsLiveActivities` in the app plist; embed `IkeruWatch` in the app target; ship the Noto fonts (commit or CI-download); fix the Claude keychain key; add Gemini to the `.simple` chain; hide the disabled iCloud rows; remove the STREAK-0 tile and the `Detail:` placeholder route. Each is hours, not days, and together they convert a lot of built value into shipped value.
3. **Wire the real exercise views into planned sessions** and stop stubbing `LearnerSnapshot` inputs — this turns ~70% of the built pedagogy from dead code into product, and makes the adaptive planner actually adaptive.
4. **Fix the SRS loop**: due-sorted review queue, same-day relearning steps, throwing saves, stricter mastery thresholds. This is the app's engine; it must be correct before content scales.
5. **Content pipeline**: bring N5 to its own research targets (~800 vocab, ~80 grammar), populate KanjiVG stroke data, then generate N4+. Without this, nothing else matters past week one.
6. **Engineering hygiene**: un-quarantine tests (invert allowlist → skip-list), add a `VersionedSchema` migration plan, retarget code review CI at `dev`, refresh `TODO.md`.
7. **Accessibility pass**: Dynamic Type at the font-token layer (one file fixes 380 call sites' scaling), VoiceOver + Reduce Motion on the celebration loop, localize the reward-flow and notification strings.
8. **Decide the AI story**: either make Sakura honest (real AI in the chat sheet, scripted-mode labeling, provider health-aware routing) or descope the Companion tab until it is.

### Bottom line

Ikeru is an exceptional *blueprint* — arguably a top-tier one for indie language apps — executed to about a third of its depth. Its strongest asset is that the hard, differentiating thinking (FSRS engine, unlock pedagogy, design language, provider routing, watch-native drills) is already done and mostly built; its biggest risk is shipping surfaces that quietly don't work (or aren't true), which erodes exactly the calm, trustworthy character the product is designed around. Six months of disciplined wiring-and-content work, with no new features, would transform it.
