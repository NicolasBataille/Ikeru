---
title: "Product Brief: Ikeru"
status: "complete"
created: "2026-04-01"
updated: "2026-04-02"
inputs: [user-conversation, web-research-sotaku, web-research-japanese-learning-landscape, skeptic-review, opportunity-review]
---

# Product Brief: Ikeru

## Executive Summary

Ikeru is a personal iOS application — with an Apple Watch companion — designed to take a complete beginner to B2/C1-level Japanese proficiency across all four language skills: reading, writing, listening, and speaking. Built by its own user, for its own user — eliminating all product-market fit risk and enabling pedagogically honest decisions that commercial apps cannot afford to make.

It combines the most established, evidence-based learning methodologies (FSRS spaced repetition — 20–30% more efficient than SM-2, comprehensible input, shadowing, mnemonic kanji decomposition) with modern AI capabilities (LLM-powered conversation partner, on-device pronunciation analysis, adaptive learning path) into a single, unified experience — with zero additional paid APIs or subscriptions. AI runs on a tiered model: on-device (Apple FoundationModels), free cloud tiers (Gemini free, Claude via existing subscription), and local GPU (RTX 5090) for heavy content generation.

Today, serious Japanese learners juggle 4–6 separate apps and still lack personalized guidance on what to study next. Ikeru eliminates this fragmentation with a complete, adaptive system that fits into micro-moments (2–5 min) as well as focused study blocks (30 min) — an approach aligned with cognitive science research showing that short, distributed practice sessions are optimal for long-term retention. The app guides the learner through the right activities at the right time, from absolute beginner through to fluency.

## The Problem

Learning Japanese as a complete beginner is uniquely challenging: three writing systems (hiragana, katakana, kanji), pitch accent, an SOV grammar structure radically different from European languages, and a progression from absolute beginner to functional fluency that spans years. The current tooling landscape forces learners into a fragmented workflow:

- **WaniKani** teaches kanji but locks you into rigid pacing and a paid subscription
- **Anki** is powerful but complex to configure and maintain — most beginners bounce off it
- **Duolingo Japanese** optimizes for engagement streaks at the expense of real learning depth
- **Bunpro** handles grammar well but nothing else
- **Sotaku** uses excellent FSRS scheduling but lacks speaking, writing, listening, and watchOS support
- **No single app** covers reading, writing, listening, AND speaking with adaptive AI

The result: learners spend more time managing their tool stack than actually learning. Progress tracking is scattered across apps. There's no unified view of "where am I weak?" and no intelligent system saying "here's what you should work on next."

## The Solution

Ikeru is a fully integrated Japanese learning companion that covers all four language skills in one adaptive system. All features ship from day one — the app itself guides which activities are appropriate at the learner's current stage.

### Reading & Kanji
FSRS-based spaced repetition with kanji decomposition by radicals and components (inspired by RTK's mnemonic approach, enhanced with immediate reading and vocabulary integration from KKLC methodology). Kanji knowledge graph ensures component radicals are always learned before the kanji that use them. LLM-generated personalized mnemonics that reference the learner's own context. JLPT-aligned progression from N5 through N1.

### Writing
Active production exercises: stroke order display and tracing, particle and conjugation fill-in-the-blank, typed sentence construction, handwritten kanji recognition via on-device ML.

### Listening
Comprehensible input at i+1 level, shadowing exercises, progressive difficulty from simple phrases to natural-speed conversation. Content sourced from TTS for drills plus curated native audio for natural listening. Future content pipeline includes NHK Easy News, manga OCR, and song lyrics as real-world comprehensible input.

### Speaking & Pronunciation
On-device pronunciation and pitch accent analysis with pitch accent treated as a first-class system (頭高, 中高, 尾高, 平板 pattern tracking), not an afterthought. Real-time feedback during shadowing. Multiple evaluation methods: isolated word pronunciation, shadowing accuracy, and conversational speech analysis.

### AI Conversation Partner
LLM-powered conversational practice using a tiered inference strategy:
1. **On-device** — Apple FoundationModels for low-latency, offline-capable interactions (quick corrections, simple exchanges)
2. **Free cloud APIs** — Gemini free tier for higher-quality conversation when online (500–1000 req/day, sufficient for personal use)
3. **Claude via existing subscription** — leverage Nico's current Anthropic subscription for the highest-quality interactions (complex grammar explanations, nuanced conversation, content review)
4. **Local GPU server** — RTX 5090 running open-weight models for batch content pre-generation (mnemonics, grammar explanations, listening passages)

The AI **automatically adapts to the learner's current level** — the system injects current proficiency data (known grammar, vocabulary range, JLPT level estimate) into the system prompt so the conversation partner always matches where the learner is. At beginner level: scaffolded exchanges (greetings, set phrases, guided dialogues). As proficiency grows: increasingly free-form conversation. The learner can interact via text, voice, or both. Feedback on pronunciation, grammar, vocabulary choice, and naturalness.

### Adaptive Study Planner
The app guides what to do at every stage of learning. Rule-based heuristics analyze error rates, response times, and skill balance ratios to dynamically compose each session. Example: if listening accuracy drops below 70%, listening exercises get increased share of session time. All four skills are available from the start, but the planner sequences activities based on what's pedagogically appropriate — a day-1 beginner gets kana drills, not N2 kanji. Evolves to ML-based engine as usage data accumulates.

### Flexible Sessions
Designed for micro-sessions (2–5 min SRS review on the train), standard blocks (30 min multi-skill study at home), and Watch-based nano-sessions (review 3 cards while waiting for coffee). The app adapts content to available time and context — silent mode for environments without audio.

### Apple Watch Companion
Quick kana/kanji recognition quizzes (4-choice), spaced repetition reminders, progress complications, and audio-based pronunciation drills via Watch speaker/mic during walks. Haptic-guided pitch accent patterns. Designed as a primary surface for audio-centric skills, not just a notification relay.

### Deep iOS Integration
Live Activities for current study streak/next review, StandBy mode flashcards, Shortcuts integration ("Hey Siri, quiz me"), Spotlight suggestions. Passive exposure without opening the app.

### Data Export & Agent Analysis
Full export of all learning data (JSON, CSV, Parquet) structured for AI agent consumption. Export includes learning context (how the app works, what metrics mean) so an external agent can immediately interpret the data and provide insights, feedback, and recommendations without additional briefing.

## What Makes This Different

1. **All four skills, one app** — No other Japanese learning app unifies reading, writing, listening, and speaking with AI in a single experience. The market is fragmented; Ikeru is integrated.
2. **Developer-as-user** — Every design decision is validated in real-time by the only user who matters. No engagement hacks, no gamification theater, no business model incentivizing wasted time. Pedagogically honest by design.
3. **FSRS over SM-2** — Measurably superior scheduling: 20–30% fewer reviews for the same 90% retention rate. Faster progress with less daily time investment.
4. **Pitch accent as a first-class system** — Most apps completely ignore pitch accent, yet it is the single biggest marker of natural-sounding Japanese. Building this from day one, while neural pathways are still forming, is dramatically more effective than retrofitting later.
5. **Micro-session native** — Not a compromise but the optimal learning pattern. Short, distributed practice sessions align with spaced repetition science. Watch nano-sessions push this further.
6. **Apple Watch as ambient learning surface** — Greenfield territory. No serious Japanese learning companion exists on watchOS. Watch-first audio drills during walks, haptic pitch training, wrist-raise micro-quizzes.
7. **Offline-first with smart cloud fallback** — Core features (SRS, pronunciation, kanji) run fully on-device. When online, the app opportunistically uses stronger cloud models (Gemini free tier, Claude via existing subscription) for richer AI interactions. Works perfectly offline on trains, planes, or in Japan with spotty connectivity.
8. **Zero incremental cost** — No new subscriptions or API fees. Leverages existing Claude subscription, Gemini free tier, Apple on-device models, and personal RTX 5090 for local inference. The app costs nothing beyond the initial development time.
9. **Self-adapting AI conversation** — The conversation partner reads the learner's current progress and automatically calibrates its level — no manual difficulty selection needed.
10. **Data sovereignty** — Full export of all learning data for external analysis, AI agent consultation, or personal analytics. Your learning data belongs to you, period.

## Who This Serves

**Primary user:** Nico — a complete beginner in Japanese, tech-savvy developer with a RTX 5090 for local model inference. Wants a deeply personalized learning experience that adapts to his learning style, pace, and schedule. Values evidence-based methodology over gamification. Comfortable with AI tools and expects to interact with his learning data analytically. The app is instrumented for his own feedback loops: session abandonment logging, confusion point detection, leech identification.

**Secondary users:** Friends who receive the app as-is — same methodology, same learning approach, no customization. They benefit from the system Nico has optimized but don't modify it. The app supports simple local profiles (separate progress and SRS state per user, stored locally — no login, no auth, no server).

## What Ikeru Is Not

- **Not a grammar textbook replacement** — users should pair with Genki or Tae Kim for deep grammar study; Ikeru reinforces and tests grammar, it does not replace reference material
- **Not an immersion substitute** — Ikeru builds the foundation; real-world exposure is still essential
- **Not a platform for others to customize** — sharing means sharing the exact system, not building a configurable product
- **Not a cloud-dependent service** — core features work fully offline; cloud models (Gemini free, Claude subscription) enhance the experience when available but are never required

## Success Criteria

- **JLPT progression** — In-app N5 mastery within 6 months (measured by: >90% of N5 kanji at "mature" FSRS status, grammar points with >90% recall, listening comprehension accuracy >80% on N5-graded passages). N4 within 12 months. N3 within 18 months.
- **Daily engagement** — Consistent usage pattern mixing micro-sessions and focused blocks
- **Skill balance** — All four skills progressing without significant gaps (no "can read but can't speak" syndrome)
- **Pronunciation accuracy** — Measurable improvement in pitch accent pattern accuracy over time
- **Adaptive relevance** — The system's recommended study plan feels correct ("it knows what I need to work on")
- **Monthly milestone checkpoints** — Progress snapshots at regular intervals for trend analysis

## Scope

### Included
- iOS app (latest iOS), native Swift/SwiftUI
- Apple Watch companion (latest watchOS)
- Full kana + kanji learning with FSRS, N5 through N1 progression
- Grammar lessons aligned to JLPT levels
- Listening exercises (TTS drills + curated native audio)
- Pronunciation and pitch accent analysis (on-device ML)
- Handwritten kanji recognition (on-device ML)
- AI conversation partner (tiered: on-device FoundationModels + Gemini free tier + Claude subscription + RTX 5090 local server)
- Adaptive study planner (rule-based, evolves to ML)
- Progress dashboard with per-skill breakdown
- Spaced repetition reminders, Live Activities, Watch complications, Shortcuts
- Data export (JSON, CSV, Parquet) with agent-friendly context
- Local multi-user profiles (no auth, just local storage per user)
- Fully offline-capable

### Excluded
- App Store publication
- User customization of learning methodology
- Other languages
- Social features or leaderboards
- Any new paid APIs or subscriptions (existing Claude subscription is fair game)
- Dedicated cloud infrastructure or backend services

### Technical Validations (Early Phase)
Before investing deep in specific features, validate feasibility:
1. Japanese pitch accent analysis with AVAudioEngine — is F0 contour extraction feasible on-device?
2. Apple FoundationModels quality for Japanese conversation at various JLPT levels
2b. Claude subscription integration — feasibility of using existing Anthropic subscription from an iOS app (web API, automation, or proxy approach)
3. Apple Watch kanji rendering — are complex kanji legible at 45mm?
4. FSRS Swift implementation — port from open-spaced-repetition or build native?
5. On-device handwritten kanji recognition — CoreML model availability and accuracy
6. Local LLM server on RTX 5090 — latency and quality for content pre-generation

## Content Pipeline

Content is co-equal in effort with code — and on the critical path for every feature. The RTX 5090 can be used to pre-generate content offline using local LLMs.

| Content Type | Source | Notes |
|---|---|---|
| Kanji decomposition | KanjiVG + open radical databases | Map to RTK/KKLC-style components |
| Vocabulary & sentences | Tatoeba corpus + JLPT frequency lists | All JLPT levels, tagged by difficulty |
| Grammar explanations | LLM-generated (local), validated against Tae Kim/Genki | Concise, example-driven, pre-generated on GPU |
| Native audio | Apple TTS (drills) + Forvo/OJAD (natural examples) | TTS for repeatability, native for immersion |
| Mnemonics | LLM-generated, personalized to learner context | Generated on-demand on-device, cached locally |
| Listening passages | Curated open sources + NHK Easy News + manga/song pipeline | Graded by JLPT level |

## Vision

Ikeru becomes proof that one person with the right tools can build a learning experience more effective than any commercial app, because it's tuned to exactly one learner's brain. No gems, no streaks, no guilt — just honest, evidence-based acquisition. The methodologies proven through Nico's journey to fluency become a shareable template: a complete, opinionated system that friends can adopt wholesale, without the paradox of choice that paralyzes most learners. The architecture — designed for Japanese as the hardest test case — naturally extends to other languages if desired.
