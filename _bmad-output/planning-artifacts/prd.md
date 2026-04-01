---
stepsCompleted: [step-01-init, step-02-discovery, step-02b-vision, step-02c-executive-summary, step-03-success, step-04-journeys, step-05-domain, step-06-innovation, step-07-project-type, step-08-scoping, step-09-functional, step-10-nonfunctional, step-11-polish]
inputDocuments:
  - product-brief-Ikeru.md
  - product-brief-Ikeru-distillate.md
documentCounts:
  briefs: 2
  research: 0
  brainstorming: 0
  projectDocs: 0
workflowType: 'prd'
classification:
  projectType: mobile_app
  domain: edtech
  complexity: medium
  projectContext: greenfield
---

# Product Requirements Document - Ikeru

**Author:** Nico
**Date:** 2026-04-01

## Executive Summary

Ikeru is a native iOS application with an Apple Watch companion, designed to take a complete beginner toward fluency in Japanese across all four language skills: reading, writing, listening, and speaking. B2/C1 is the ideal milestone, but the system imposes no ceiling — if the learner can push further, the app scales with them. Built by its sole user — a developer with access to an RTX 5090 and an existing Claude subscription — it eliminates product-market fit risk entirely and enables pedagogically honest decisions that commercial apps cannot afford to make.

The core problem: serious Japanese learners today juggle 4–6 separate apps (WaniKani, Anki, Bunpro, Duolingo, dedicated speaking tools) and still lack a unified view of their progress or intelligent guidance on what to study next. Ikeru replaces this fragmented stack with a single adaptive system that maintains a precise, comprehensive model of the learner's state — current level across every skill, learning speed, weakness patterns, error history — and uses that model to compose the optimal study session every time.

The app combines established evidence-based methodologies (FSRS spaced repetition, comprehensible input at i+1, shadowing, mnemonic kanji decomposition via RTK/KKLC hybrid) with a tiered AI inference strategy (Apple FoundationModels on-device, Gemini free tier, Claude via existing subscription, RTX 5090 local server) — all at zero incremental cost. Every feature ships from day one; the adaptive planner decides what's pedagogically appropriate at each stage.

A RPG-inspired progression system wraps the learning experience: the learner levels up, unlocks attributes, earns loot, and opens lootboxes by completing challenges and tests (with infinite retries — no punishment for failure, only reward for mastery). This is not Duolingo-style engagement theater — it's meaningful game design that maps to real skill progression and makes the grind intrinsically rewarding.

### What Makes This Special

**The adaptive companion, not just a tool.** Ikeru's differentiator is not feature breadth — it's the depth of its learner model and the intelligence of its adaptive planner. The app doesn't present options; it knows what the learner should work on next, based on precise tracking across all four skills, response times, error patterns, and skill balance ratios. The goal: the learner never has to decide what to study — the system knows better than they do.

**RPG progression that maps to real mastery.** Levelling, attribute unlocks, loot drops, and lootboxes earned through challenges and tests. Infinite retries mean failure is never punished — only mastery is rewarded. The gamification layer is honest: progression reflects actual skill growth, not engagement metrics.

**Pitch accent as a first-class system from day one.** Most Japanese learning apps ignore pitch accent entirely. Ikeru treats it as foundational — 頭高, 中高, 尾高, 平板 pattern tracking with on-device pronunciation analysis — building correct neural pathways while they're still forming, rather than retrofitting later.

**Developer-as-user with zero complexity constraint.** Because Claude Code handles the implementation and there is no business model to optimize for engagement, Ikeru can implement features that are brutal but effective: aggressive leech detection, mandatory production before progression. The full feature set exists from day one — not as a roadmap aspiration, but as the baseline.

**Zero-cost AI at every layer.** On-device models for offline low-latency interactions, Gemini free tier for richer online conversation, Claude via existing subscription for the highest-quality exchanges, and a local RTX 5090 for batch content pre-generation. No new paid APIs or subscriptions — a hard constraint, not a compromise.

## Project Classification

- **Type:** Native iOS mobile application + Apple Watch companion (Swift/SwiftUI)
- **Domain:** EdTech — personal Japanese language learning
- **Complexity:** Medium (domain) / High (technical — on-device ML, tiered LLM inference, FSRS, kanji knowledge graph, handwritten recognition)
- **Context:** Greenfield — new project, no existing codebase
- **Distribution:** Direct (no App Store), shareable to friends as-is with local multi-user profiles

## Success Criteria

### User Success

- **Planner satisfaction:** The learner rarely feels the app is recommending the wrong activity — sessions feel appropriately challenging, well-balanced, and aligned with current motivation. No concrete metric; the signal is absence of friction ("I never think 'this is boring / too hard / not what I need right now'").
- **Companion quality:** The AI learning companion feels like a real partner. Weekly conversational check-ins where the learner shares feedback on how learning is going — and the companion debates, pushes back, and reasons through the feedback pragmatically rather than blindly applying instructions.
- **Self-sufficiency:** When looking at competing apps (WaniKani, Anki, Bunpro, Sotaku, etc.), the learner never thinks "I need to install that because Ikeru doesn't cover this." Ikeru is the only Japanese learning tool required.
- **RPG engagement:** The XP and progression system creates genuine desire to grind — unlocking new content, loot, and rewards feels motivating without being bloated or disconnected from actual learning.
- **Skill balance:** All four skills (reading, writing, listening, speaking) progress without significant gaps. No "can read but can't speak" syndrome.

### Business Success

Not applicable in the traditional sense — this is a personal tool, not a commercial product. Success is measured by:

- **Sole-app status:** Ikeru replaces the entire multi-app stack with zero gaps.
- **Daily pull:** The learner consistently wants to open the app — driven by genuine learning motivation and RPG progression, not guilt or streaks.
- **Friend adoption:** Secondary users (friends) can pick up the app and learn effectively with the same system, no customization needed.

### Technical Success

- **Offline reliability:** Core features (SRS, pronunciation analysis, kanji recognition) work flawlessly without network.
- **AI tier seamless:** Transitions between on-device, Gemini free tier, Claude subscription, and local GPU are invisible to the learner — the right model is used at the right time.
- **Zero incremental cost:** No new paid APIs or subscriptions at any point.
- **FSRS accuracy:** Spaced repetition scheduling achieves target 90% retention rate with minimal unnecessary reviews.
- **Pitch accent analysis:** On-device F0 contour extraction provides accurate, actionable pronunciation feedback.

### Measurable Outcomes

- **JLPT progression:** N5 mastery within 6 months (>90% N5 kanji at FSRS "mature" status, grammar >90% recall, listening >80% on N5 passages). N4 within 12 months. N3 within 18 months. Beyond N3: system continues scaling — no ceiling.
- **Pitch accent:** Measurable improvement in pitch accent pattern accuracy over time, tracked per-pattern (頭高, 中高, 尾高, 平板).
- **Monthly checkpoints:** Progress snapshots at regular intervals for trend analysis and AI agent consumption.
- **Session consistency:** Mix of micro-sessions (2–5 min), focused blocks (30 min), and Watch nano-sessions across the week.

## User Journeys

### Journey 1: Nico — Day One (First Launch)

**Opening Scene:** Nico downloads Ikeru via direct distribution. He's a complete beginner in Japanese — knows maybe a few words from anime but has never studied formally. He opens the app for the first time.

**Rising Action:** The app asks his name. "Nico" — this name will be used everywhere: prompts, companion conversations, UI greetings. Then, a guided tour begins. Not a wall of text — a warm, visual walkthrough that explains: "Here's what your journey looks like. You'll start with hiragana and katakana — the two phonetic writing systems. Once those click, we'll introduce your first kanji, vocabulary, and grammar. All four skills — reading, writing, listening, speaking — are built in from day one, but I'll guide you to the right activities at the right time." The tour introduces the companion: "I'm your learning partner. I'll track everything, recommend what to study, and check in with you weekly. You can talk to me anytime."

**Climax:** The tour ends. The planner presents the first session: kana recognition drills, stroke order for あいうえお, and a first listening exercise — hearing the sounds. Nico completes his first review. XP earned. Level 1. The RPG system gives its first small reward — a loot drop for completing the very first session.

**Resolution:** Nico closes the app after 20 minutes. He can recognize 5 hiragana. The Watch complication shows his progress. He already wants to come back.

### Journey 2: Nico — Daily Routine (Mixed Sessions)

**Opening Scene:** It's week 3. Nico has learned all hiragana, most katakana, and his first 10 kanji. He's on the train to work — 5 minutes to kill.

**Rising Action (Micro-session, phone):** He opens Ikeru. The planner knows he's in a short window — it presents a focused SRS review: 8 cards due (3 hiragana refresh, 3 katakana, 2 vocabulary). Silent mode is on — no audio exercises. He blasts through the cards in 3 minutes. XP ticks up.

**Rising Action (Nano-session, Watch):** Walking to grab coffee. Wrist raise — the Watch shows a kana quiz. 4-choice recognition: which one is "く"? He taps the answer. Three more cards. Haptic feedback confirms correct answers. Done in 90 seconds.

**Climax (Focused block, home):** Evening. 30 minutes. The planner composes a full session: new kanji introduction (radicals first, then the kanji that uses them, then vocabulary with that kanji), a grammar point (particle は vs が), a shadowing exercise (repeat after the audio at natural speed), and a short AI conversation practice (scaffolded at N5 level — "こんにちは、ニコさん。今日は何をしましたか？"). The conversation partner adapts — simple vocabulary, furigana hints, gentle corrections.

**Resolution:** Session complete. Level up. A lootbox unlocked — he answers a challenge question (kanji reading test, infinite retries) to open it. New loot: a cosmetic reward. Daily progress saved. Monthly checkpoint approaches — the data is ready for export.

### Journey 3: Nico — Weekly Check-In

**Opening Scene:** Sunday evening. A subtle push notification appears: "Weekly check-in ready — let's talk about your week." Nico taps it.

**Rising Action:** The companion opens with a warm summary: "Hey Nico! This week you did 12 sessions, 45 minutes average. You reviewed 180 cards, learned 8 new kanji, and your listening accuracy went up to 74%. Your pitch accent on 平板 words is improving — nice work. But your katakana recall is slipping a bit, and you skipped writing practice three days in a row. Let's talk about that."

**Climax:** Nico says "Yeah, I've been lazy on writing. Honestly I find stroke order practice boring." The companion doesn't just comply — it pushes back: "I get it, but here's the thing: your kanji retention drops 15% when you skip active production. What if we try shorter writing bursts — 3 minutes max, mixed into other exercises instead of a dedicated block? That way it doesn't feel like a chore." They go back and forth. Nico agrees to try the shorter format. The companion updates the planner weighting internally — writing exercises will appear in smaller, more frequent doses rather than long blocks.

**Resolution:** The companion wraps up when it's satisfied the key points are covered: "Good talk. I've adjusted your planner — you'll see writing pop up in shorter bursts this week. Let's see how it feels. Also, here's your overall progress since you started: 6 weeks in, 46 hiragana mastered, 46 katakana at 85%, 35 kanji learned, N5 grammar 40% complete. You're on track. See you next week." If needed, Nico can export the check-in insights to a Claude Code agent for deeper analysis or app-level modifications.

### Journey 4: Nico — The Wall (Struggle Moment)

**Opening Scene:** Month 3. Nico has been progressing well — N5 kanji nearly complete, grammar solid, listening improving. But three kanji keep coming back wrong. They're leeches. And motivation is dipping — the initial excitement has faded.

**Rising Action:** The app detects the leech pattern (same cards failing repeatedly despite reviews). A natural language chat opens with the companion: "Hey Nico, I noticed 食, 飲, and 読 keep tripping you up. Want to work through them together?" Nico types: "Yeah, I keep mixing up 食べる and 飲む, the readings just won't stick."

**Climax:** The companion responds with targeted help — not generic advice, but personalized mnemonics: "Let's try this: 食 (た.べる) — the radical on top looks like a person sitting at a table. They're EATING (taberu). 飲 (の.む) — see the 欠 radical? That's a person with their mouth open, DRINKING (nomu). Try writing both three times, then we'll do a mini-quiz." Nico works through it. The companion also addresses the motivation dip: "You're at the 3-month mark — this is where most people quit. But look at this: you know 120 kanji now. A month ago it was 60. The curve feels flat but it's not. Want to unlock a challenge lootbox? Beat a 10-kanji reading speed test and there's something good in it."

**Resolution:** The leeches get tagged with new mnemonics. The companion schedules them with tighter FSRS intervals. Nico opens the lootbox after the challenge — gets a reward. The dip passes. The companion will monitor these cards more closely and check back in the weekly review.

### Journey 5: Friend — Onboarding Without Nico

**Opening Scene:** Nico's friend Marie gets the app via AirDrop. She knows nothing about Japanese and hasn't talked to Nico about the learning methodology.

**Rising Action:** She opens Ikeru. The app asks her name: "Marie." A new local profile is created — fresh SRS state, fresh progress, fresh companion context. The same guided tour plays: the journey overview, the companion introduction, the first session preview. Marie gets the exact same pedagogical system Nico uses — the same planner logic, the same RPG progression, the same companion personality.

**Climax:** Marie completes her first session. The companion greets her by name: "Nice work, Marie! You just learned your first 5 hiragana." The RPG system awards her first XP. She has no idea this app was built by one person for himself — it just works.

**Resolution:** Marie's progress is entirely independent from Nico's. Different profile, different SRS state, different companion history. If Nico later updates the app based on his own needs, Marie gets the same update — the methodology evolves based on Nico's experience, but that benefits all users equally.

**Additional note — Username flexibility:** Any user can change their display name at any time in settings. The change propagates everywhere: companion prompts, UI greetings, push notifications, weekly check-in summaries. No restart required.

### Journey Requirements Summary

These journeys reveal the following capability areas:

- **Onboarding system:** Guided tour, name capture, profile creation, journey preview
- **Adaptive planner:** Session composition based on time available, context (silent/audio), skill balance, and learner state
- **Multi-surface sessions:** Phone (micro + focused), Watch (nano), with seamless context
- **RPG engine:** XP tracking, levelling, loot drops, lootbox challenges with infinite retries
- **AI companion (chat):** Natural language chat for struggle moments, personalized mnemonics, motivation coaching
- **AI companion (weekly check-in):** Initiated via push notification, structured review (weekly + overall), two-way conversation, companion-controlled session end, internal planner adjustment, exportable insights
- **Leech detection:** Automatic identification of failing cards, companion intervention, adjusted FSRS intervals
- **Local profiles:** Independent per-user state (SRS, progress, companion history), name changeable anytime, reflected across all surfaces
- **Notification system:** Push notifications for weekly check-in, SRS reminders, Watch complications

## Domain-Specific Requirements

### Content Licensing

All third-party content must comply with licensing terms for personal, non-commercial distribution:

| Resource | License | Status | Attribution Required |
|---|---|---|---|
| KanjiVG (stroke order/SVG) | CC BY-SA 3.0 | Usable | Ulrich Apel |
| Tatoeba (sentences) | CC BY 2.0 | Usable | Tatoeba + contributors |
| KANJIDIC/KANJIDIC2 (readings) | CC BY-SA 3.0 | Usable | EDRDG / Jim Breen |
| RADKFILE/KRADFILE (radicals) | CC BY-SA 3.0 | Usable | EDRDG |
| Forvo (native audio) | Proprietary | Not usable | N/A |
| OJAD (pitch accent) | No open license | Not usable | N/A |

**Alternatives for blocked resources:**
- Native audio: Apple TTS for drills, open-source TTS/speech models (to be sourced — e.g., JTalk, VITS-based Japanese models, or other open-weight models discoverable online). On-device models preferred for offline capability; cloud-generated audio cached locally as fallback.
- Pitch accent data: source from open datasets or generate/validate via local models
- The app must function in a limited offline mode — core learning (SRS, kanji, grammar) fully offline; audio-dependent features gracefully degrade when no network and no cached audio is available.

An attribution screen/section in the app must credit all CC-licensed sources.

### Data Integrity & Backup

SRS state is the most critical user data — losing it means losing months of learning progress.

- **Primary backup:** iCloud sync for seamless device-to-device continuity
- **Manual export:** JSON/CSV export of all learning data (SRS state, progress, companion history) to local storage or external backup
- **Data model:** Must support atomic operations — no partial writes that could corrupt SRS state
- **Profile isolation:** Each user profile's data is fully independent; corruption in one profile must not affect others

### Linguistic Accuracy

LLM-generated content (mnemonics, grammar explanations, conversation) carries risk of errors in a language as complex as Japanese.

- **Prefer established sources:** Use verified open datasets (KANJIDIC, Tatoeba, KanjiVG) as ground truth for kanji readings, meanings, and decomposition
- **Multi-pass validation:** LLM-generated content (mnemonics, grammar explanations) must be cross-validated against reference data before being presented to the learner
- **Batch pre-generation with review:** Content generated on the RTX 5090 should be pre-validated in bulk rather than served raw
- **Companion guardrails:** The AI conversation partner must not teach incorrect grammar or vocabulary — system prompt must include accuracy constraints

## Innovation & Novel Patterns

### Detected Innovation Areas

**Apple Watch as primary learning surface.** No serious Japanese learning companion exists on watchOS today. Ikeru treats the Watch not as a notification relay but as a first-class learning surface: kana/kanji recognition quizzes, audio pronunciation drills via speaker/mic during walks, haptic-guided pitch accent patterns (tap sequences mapping high/low pitch contours). This is greenfield territory.

**Pitch accent as a first-class system from day one.** The overwhelming majority of Japanese learning apps ignore pitch accent entirely, treating it as an advanced topic or omitting it altogether. Ikeru builds 頭高, 中高, 尾高, 平板 pattern tracking into the core learning loop from the first session, leveraging on-device pronunciation analysis to build correct neural pathways while they're still forming.

**Zero-cost tiered AI inference architecture.** A novel four-tier inference strategy that delivers AI capabilities at every quality level without any new paid APIs: Apple FoundationModels (on-device, offline), Gemini free tier (online, mid-quality), Claude via existing subscription (highest quality), RTX 5090 local server (batch content pre-generation). The system selects the appropriate tier transparently.

**AI companion that debates, not obeys.** The weekly check-in companion and natural language chat interface are not a yes-man chatbot. The companion analyzes learner data, forms opinions on progression, pushes back on learner feedback when it disagrees, and can directly modify planner weights and learning data based on conversation outcomes — a level of autonomy unusual in learning apps.

**Developer-as-user enabling pedagogically honest design.** No business model means no engagement optimization trade-offs. This enables features commercial apps cannot afford: aggressive leech detection, mandatory production before progression, no guilt-driven retention mechanics. Every design decision serves learning effectiveness, not metrics.

### Market Context & Competitive Landscape

- No watchOS Japanese learning companion exists beyond basic flashcard apps (TokeiTango, Daily Kanji)
- No single app unifies all four skills with adaptive AI, FSRS, and pitch accent
- Pitch accent tools exist in isolation (OJAD, Dogen's Patreon) but are never integrated into a full learning loop
- Tiered free AI inference is a novel architectural pattern with no direct precedent in consumer edtech

### Validation Approach

Six technical validations identified in the product brief, ordered by risk:

1. **AVAudioEngine F0 contour extraction** — Can on-device pitch accent analysis deliver actionable feedback? Spike required.
2. **Apple FoundationModels Japanese quality** — Is on-device LLM quality sufficient for N5-level conversation? Test at multiple JLPT levels.
3. **Claude subscription integration from iOS** — Feasibility of using existing consumer Anthropic subscription via web API, automation, or proxy.
4. **Apple Watch kanji legibility** — Are complex kanji readable at 45mm screen size?
5. **FSRS Swift implementation** — Port from open-spaced-repetition or build native?
6. **CoreML handwritten kanji recognition** — Model availability and accuracy for on-device recognition.

### Risk Mitigation

See [Project Scoping > Risk Mitigation Strategy](#risk-mitigation-strategy) for the detailed risk/fallback matrix covering all six technical validations.

## Mobile App Specific Requirements

### Project-Type Overview

Native iOS application (Swift/SwiftUI) with watchOS companion. Distributed directly (TestFlight or ad-hoc), no App Store compliance required. Single-platform: Apple ecosystem only (iPhone + Apple Watch).

### Platform Requirements

- **iOS:** Latest iOS version, Swift/SwiftUI
- **watchOS:** Latest watchOS, SwiftUI for Watch
- **Minimum devices:** iPhone (primary), Apple Watch (companion)
- **No iPad-specific layout** — iPhone layout scales if used on iPad
- **No Mac Catalyst** — iOS only

### Device Permissions

Minimum required permissions at launch:

| Permission | Purpose | Required At |
|---|---|---|
| Microphone | Pronunciation analysis, shadowing, voice conversation | First audio exercise |
| Notifications | Weekly check-in, SRS reminders | Onboarding |
| Speech Recognition | Voice input for conversation partner | First speaking exercise |

Additional permissions discovered at usage time — not pre-planned. Request permissions just-in-time, not at first launch.

### Offline Mode

**Core principle:** All learning and progress tracking works fully offline. Network is never required for the core learning loop.

**Always offline:**
- SRS reviews (FSRS scheduling, card presentation, answer grading)
- Kanji study (decomposition, stroke order, readings, mnemonics — all pre-loaded)
- Grammar exercises (fill-in-the-blank, conjugation drills)
- Writing practice (stroke order tracing, handwritten recognition via CoreML)
- Progress tracking and logging (all local, no server dependency)
- RPG progression (XP, levelling, loot — all computed locally)
- On-device AI via Apple FoundationModels (simple corrections, basic exchanges)

**Online only:**
- AI conversation partner at higher quality tiers (Gemini free, Claude subscription)
- Weekly check-in companion (requires cloud AI for conversation quality)
- iCloud backup sync (manual trigger from settings)
- Content updates (new audio, expanded content packs)

**Graceful degradation:** When offline, AI features fall back to on-device FoundationModels. If on-device quality is insufficient for a specific interaction, the app queues it for when network returns rather than delivering a bad experience.

### Push & Notification Strategy

- **Weekly check-in:** Configurable day/time, subtle notification, not aggressive
- **SRS reminders:** "You have X cards due" — frequency configurable
- **Watch complications:** Progress display, next review due, streak data
- **Live Activities:** Current study session progress, next review countdown
- **StandBy mode:** Flashcard display on charging dock

### Watch ↔ iPhone Sync

- **Real-time sync** via WatchConnectivity framework (WCSession)
- SRS state, progress, and RPG data synced bidirectionally in real-time
- Watch sessions immediately reflected on iPhone and vice versa
- Offline Watch sessions queued and synced when connection restores
- Companion history shared across both surfaces

### Storage & Size Management

- **Progressive content loading:** Don't bundle all JLPT levels at install. Load content progressively as the learner advances (N5 content at install, N4 content when approaching N4, etc.)
- **Target:** Keep initial install size reasonable (under ~500MB). Monitor and rework if needed after development.
- **CoreML models:** Ship minimal required models; evaluate size vs. quality trade-offs
- **KanjiVG/KANJIDIC data:** Compact formats (binary/SQLite), not raw JSON/XML
- **Cache management:** LLM-generated content (mnemonics, explanations) cached locally, with configurable cache limits

### iCloud Backup

- **Manual sync trigger** from Settings screen — user controls when backup happens
- **No automatic background sync** — user decides when to push to iCloud
- **Backup scope:** Full learning state (SRS data, progress, companion history, RPG state, user preferences)
- **Restore:** Settings screen allows restoring from most recent iCloud backup
- **Export alternative:** JSON/CSV export remains available as a manual backup option independent of iCloud

### Implementation Considerations

- **Data persistence:** Evaluate SwiftData vs. SQLite vs. Core Data. SwiftData preferred for modern Swift integration; SQLite if performance-critical queries needed for FSRS scheduling.
- **FSRS engine:** Must handle thousands of cards with sub-millisecond scheduling calculations. Consider native Swift port of open-spaced-repetition.
- **Watch app architecture:** Independent WatchKit app with shared data layer via WatchConnectivity. Must handle extended runtime sessions for audio exercises.
- **Audio pipeline:** AVAudioEngine for pronunciation capture and F0 analysis. Must support simultaneous playback + recording for shadowing exercises.

## Project Scoping & Phased Development

### MVP Strategy & Philosophy

**MVP Approach:** No phased MVP. The full feature set ships as a single cohesive release. This is a personal tool built with Claude Code — the traditional "minimum viable" framing doesn't apply because there's no market timing pressure, no investor expectations, and the developer is the user. The constraint is not "what's the minimum to ship?" but "what's the complete experience I want to use every day?"

**Resource Requirements:** Solo developer (Nico) + Claude Code. RTX 5090 for local model inference and content generation. Existing Claude subscription for development assistance and as an AI tier in the app.

### MVP Feature Set (Phase 1)

Since there is no phased distinction, the complete feature set constitutes the single release:

**Core User Journeys Supported:**
- Day-1 onboarding with guided tour (Journey 1)
- Daily mixed sessions: micro (phone), nano (Watch), focused (home) (Journey 2)
- Weekly companion check-in with two-way conversation (Journey 3)
- Struggle/leech intervention with natural language chat (Journey 4)
- Friend onboarding with independent profile (Journey 5)

**Must-Have Capabilities:**

| Capability | Complexity | Risk Level |
|---|---|---|
| FSRS spaced repetition engine | High | Low (proven algorithm, open-source reference) |
| Kanji knowledge graph (RTK/KKLC hybrid) | High | Low (data sources available, CC-licensed) |
| Adaptive study planner (rule-based) | High | Medium (tuning required via real usage) |
| AI conversation partner (tiered inference) | High | Medium (FoundationModels quality unknown for Japanese) |
| Pitch accent analysis (on-device) | High | High (F0 extraction feasibility unvalidated) |
| Handwritten kanji recognition (CoreML) | Medium | Medium (model availability uncertain) |
| RPG progression system | Medium | Low (well-understood game design patterns) |
| Weekly companion check-in | Medium | Low (LLM chat with structured data) |
| Apple Watch companion | Medium | Medium (kanji legibility, WatchConnectivity complexity) |
| iOS system integration (Live Activities, StandBy, Shortcuts) | Medium | Low (well-documented Apple APIs) |
| Onboarding guided tour | Low | Low |
| Local multi-user profiles | Low | Low |
| iCloud manual backup + JSON/CSV export | Low | Low |
| Data export (Parquet) | Low | Low |

### Post-MVP Features

Not a separate phase — iterative improvements driven by real usage feedback:

**Iteration Wave 1 (Usage-Driven):**
- Planner tuning based on actual learning patterns
- Companion personality refinement based on check-in feedback
- RPG balance adjustments (XP curves, loot frequency, challenge difficulty)
- Content expansion (additional vocabulary, sentences, grammar points beyond N5)

**Iteration Wave 2 (Data-Driven):**
- Adaptive planner evolution from rule-based to ML-based as usage data accumulates
- Enhanced leech detection algorithms informed by real failure patterns
- Companion intelligence improvements based on check-in conversation history

**Iteration Wave 3 (Content Pipeline):**
- Real-world content pipeline (NHK Easy News RSS, manga OCR, song lyrics)
- Expanded audio sources (open-source TTS/speech models)
- New RPG content tiers (attribute trees, challenge variety, cosmetic rewards)

**Vision (Long-Term):**
- Architecture extensible to other languages (Japanese as hardest test case)
- Learning methodology as shareable, opinionated template
- Full learning corpus for external AI agent longitudinal analysis

### Risk Mitigation Strategy

**Technical Risks:**

| Risk | Impact | Mitigation | Fallback |
|---|---|---|---|
| Pitch accent F0 extraction on-device | High | Early spike with AVAudioEngine | Cloud-based analysis or simplified pattern matching |
| FoundationModels Japanese quality | High | Test at N5→N3 levels early | Route to Gemini/Claude; on-device for corrections only |
| Claude subscription iOS integration | Medium | Spike web API/proxy approach | Gemini free tier as primary; Claude via data export only |
| Watch kanji legibility at 45mm | Medium | Prototype with complex kanji early | Limit Watch to kana + audio exercises |
| CoreML handwriting recognition | Medium | Survey available models | Stroke-order tracing with visual comparison |
| App size with all bundled data | Low | Progressive content loading by JLPT level | Compress assets, lazy-load on progression |

**Market Risks:** None — single-user product, no market validation needed. Success criteria is personal satisfaction.

**Resource Risks:** Solo developer with Claude Code. Mitigated by the fact that there's no deadline, no stakeholders, and iteration is built into the process. If a feature proves too complex, it can be simplified without business consequences.

## Functional Requirements

### Spaced Repetition & Learning Engine

- FR1: Learner can review due cards using FSRS scheduling algorithm with optimized intervals for 90% retention
- FR2: Learner can see new cards introduced according to the kanji knowledge graph (component radicals before composite kanji)
- FR3: System can detect leech cards (repeatedly failed items) and flag them for companion intervention
- FR4: Learner can view their review queue size, upcoming reviews, and daily review forecast
- FR5: System can track response times, error rates, and accuracy per card across all review sessions
- FR6: System can log all learning activity and progression data locally, regardless of network state

### Japanese Language Skills — Reading & Kanji

- FR7: Learner can study kanji with radical decomposition (RTK/KKLC hybrid), readings (on'yomi, kun'yomi), meanings, and example vocabulary
- FR8: Learner can view personalized mnemonics for each kanji, generated by AI and cached locally
- FR9: Learner can study vocabulary in context with example sentences sourced from Tatoeba corpus
- FR10: Learner can study grammar points aligned to JLPT levels with concise, example-driven explanations
- FR11: Learner can practice grammar through fill-in-the-blank exercises (particles, conjugations)
- FR12: Learner can read comprehensible input passages graded at i+1 level relative to their current proficiency

### Japanese Language Skills — Writing

- FR13: Learner can view stroke order animations for kana and kanji
- FR14: Learner can practice stroke order through guided tracing exercises
- FR15: Learner can submit handwritten kanji for on-device recognition and feedback
- FR16: Learner can practice typed sentence construction exercises

### Japanese Language Skills — Listening

- FR17: Learner can listen to audio pronunciation of vocabulary and sentences at variable speeds
- FR18: Learner can perform shadowing exercises (listen then repeat) with progressive difficulty
- FR19: Learner can study comprehensible input audio passages graded by JLPT level

### Japanese Language Skills — Speaking & Pronunciation

- FR20: Learner can receive on-device pronunciation feedback on spoken Japanese
- FR21: System can analyze pitch accent patterns (頭高, 中高, 尾高, 平板) and provide per-pattern accuracy tracking
- FR22: Learner can practice isolated word pronunciation with real-time feedback
- FR23: Learner can receive pronunciation feedback during shadowing exercises

### AI Companion & Conversation

- FR24: Learner can engage in AI-powered conversational practice adapted to their current JLPT level
- FR25: System can select the appropriate AI tier transparently (on-device FoundationModels → Gemini free → Claude subscription → local GPU)
- FR26: Learner can interact with the AI conversation partner via text, voice, or both
- FR27: Learner can initiate natural language chat with the companion at any time for help, mnemonics, or motivation
- FR28: Companion can proactively intervene when leech cards are detected, offering personalized mnemonics and strategies
- FR29: Companion can conduct weekly check-in conversations: summarize weekly and overall progress, give opinions, ask for learner feedback, debate pragmatically, and decide when to end the conversation
- FR30: Companion can modify planner weights and learning data based on check-in conversation outcomes
- FR31: Learner can export companion check-in insights for consumption by external AI agents (e.g., Claude Code)
- FR32: System can fall back to on-device AI when offline, with graceful degradation of conversation quality

### Adaptive Study Planner

- FR33: System can compose each study session dynamically based on learner's current state (error rates, response times, skill balance ratios, SRS queue)
- FR34: System can adapt session content to available time (2-min micro-session vs. 30-min focused block)
- FR35: System can adapt session content to context (silent mode disables audio exercises)
- FR36: System can balance all four skills (reading, writing, listening, speaking) to prevent skill gaps
- FR37: System can sequence activities based on pedagogical appropriateness for the learner's current level (day-1 beginner gets kana, not N2 kanji)
- FR38: Learner can view a progress dashboard with per-skill breakdown and overall JLPT level estimate

### RPG Progression

- FR39: Learner can earn XP from completing learning activities
- FR40: Learner can level up based on accumulated XP
- FR41: Learner can unlock attributes and rewards through progression
- FR42: Learner can earn loot drops from learning sessions
- FR43: Learner can unlock lootboxes by completing challenges and tests (with infinite retries)
- FR44: System can map RPG progression to real skill growth (progression reflects actual mastery, not just engagement)

### User Profiles & Onboarding

- FR45: New user can enter their name at first launch and receive a personalized guided tour of the app
- FR46: Learner can change their display name at any time, reflected across all surfaces (prompts, UI, notifications, companion)
- FR47: System can maintain multiple independent local profiles (separate SRS state, progress, companion history, RPG state per user)
- FR48: Learner can switch between profiles in-app
- FR49: Onboarding tour can explain the learning journey, introduce the companion, and present the first session

### Apple Watch

- FR50: Learner can perform kana/kanji recognition quizzes (4-choice) on Watch
- FR51: Learner can perform audio pronunciation drills via Watch speaker and microphone
- FR52: Learner can receive haptic-guided pitch accent pattern feedback on Watch
- FR53: Learner can view progress via Watch complications (progress, next review due)
- FR54: System can sync SRS state, progress, and RPG data between Watch and iPhone in real-time via WatchConnectivity
- FR55: Watch sessions completed offline can queue and sync when connection restores

### Data Management & iOS Integration

- FR56: Learner can manually trigger iCloud backup of all learning data from Settings
- FR57: Learner can restore learning data from an iCloud backup via Settings
- FR58: Learner can export all learning data in JSON, CSV, and Parquet formats with agent-friendly context metadata
- FR59: System can display Live Activities (current session progress, next review countdown)
- FR60: System can display flashcards in StandBy mode on charging dock
- FR61: Learner can trigger study sessions via Siri Shortcuts ("Hey Siri, quiz me")
- FR62: System can appear in Spotlight suggestions based on learning patterns
- FR63: System can send configurable push notifications (weekly check-in, SRS reminders)
- FR64: System can progressively load content by JLPT level (N5 at install, higher levels as learner advances)
- FR65: System can display an attribution screen crediting all CC-licensed content sources

## Non-Functional Requirements

### Performance

- **SRS card transitions:** Card presentation and answer grading must complete in under 100ms — any perceptible lag during reviews breaks flow and frustrates the learner
- **FSRS scheduling calculations:** Sub-millisecond per card, even with thousands of cards in the database. Scheduling must never be a bottleneck when composing sessions
- **Pronunciation feedback latency:** On-device F0 analysis must return pitch accent feedback within 500ms of utterance completion for real-time feel
- **Watch interactions:** Quiz answer registration and haptic feedback must complete within 200ms — Watch UI tolerance for lag is lower than phone
- **App launch to first interaction:** Under 2 seconds from tap to usable screen (session ready or review queue visible)
- **AI conversation response:** On-device FoundationModels responses within 1-2 seconds. Cloud tier (Gemini/Claude) acceptable up to 5 seconds with a loading indicator
- **Session composition:** Planner must compose a session (select activities, balance skills, apply constraints) in under 500ms

### Reliability & Data Integrity

- **SRS state durability:** Zero tolerance for SRS data corruption or loss. All card state mutations must be atomic — no partial writes under any circumstance (app crash, battery death, force quit)
- **Offline-first guarantee:** Core learning loop (SRS reviews, kanji study, grammar drills, writing practice, RPG progression) must function identically with or without network. No silent failures, no degraded local experience
- **Watch sync resilience:** If WatchConnectivity drops mid-sync, no data is lost. Offline Watch sessions queue reliably and merge without conflicts when connection restores
- **Profile isolation:** A corrupted profile must never affect other profiles. Each profile's data is fully sandboxed
- **iCloud backup integrity:** Backup and restore must be all-or-nothing — no partial restores that leave the learning state inconsistent
- **Crash recovery:** App must resume exactly where the learner left off after a crash — mid-session progress preserved, no lost reviews

### Integration

- **AI tier transparency:** Switching between on-device, Gemini, Claude, and local GPU must be invisible to the learner. No manual tier selection, no visible errors when a tier is unavailable — system falls back silently
- **AI tier fallback latency:** When a cloud tier is unavailable, fallback to the next tier must complete within 2 seconds without user-visible interruption
- **WatchConnectivity:** Bidirectional real-time sync using WCSession. Must handle: background transfers, complication updates, and application context sharing
- **iCloud:** CloudKit or NSUbiquitousKeyValueStore for manual backup. Must handle: quota limits gracefully, conflict resolution (last-write-wins acceptable for manual sync), and clear error reporting if iCloud is unavailable
- **iOS system features:** Live Activities, StandBy, Shortcuts, and Spotlight must follow Apple's latest API contracts and degrade gracefully on older OS versions if applicable
- **Content pipeline integration:** Progressive content loading must be seamless — learner never sees a "downloading content" blocker during a session. Pre-fetch next JLPT level content in background when learner approaches threshold
