---
title: "Product Brief Distillate: Ikeru"
type: llm-distillate
source: "product-brief-Ikeru.md"
created: "2026-04-02"
purpose: "Token-efficient context for downstream PRD creation"
---

# Ikeru — Product Brief Distillate

## Product Identity
- Personal iOS + Apple Watch app for learning Japanese from complete beginner to B2/C1
- Built by Nico, for Nico — not commercial, not for App Store
- Shareable to friends as-is (no customization for others)
- Name: Ikeru

## Core Philosophy
- All 4 skills (reading, writing, listening, speaking) from day one — no phased rollout, no v1/v2 split
- App guides the learner to the right activities at the right stage — all features present, planner decides what's appropriate
- Evidence-based methodology only — no gamification, no streaks, no gems
- Pedagogically honest: can implement "brutal but effective" features (aggressive leech detection, mandatory production before progression) because no business model to optimize engagement over learning
- Anti-fragmentation: replaces the 4-6 app stack (WaniKani + Anki + Bunpro + Duolingo + speaking app) with one unified system
- Iterate based on Nico's direct feedback, not roadmap versioning

## User Profile
- Nico: complete Japanese beginner (prefers to start from absolute zero even if some bases exist)
- Tech-savvy developer, owns RTX 5090
- Existing Anthropic Claude subscription (consumer, not API)
- Prefers 30 min/day but wants flexibility: micro-sessions 2-5 min, nano-sessions on Watch, plus longer focused blocks
- Wants to use app in silent environments (no audio) as well as audio-rich contexts
- Expects to analyze his learning data externally via AI agents
- Secondary users: friends who get the exact same app, no customization — simple local profiles (just local storage per user, no auth/login/server)

## Technical Constraints (HARD)
- **Zero new paid subscriptions or API fees** — personal constraint, not negotiable
- Existing Claude subscription is fair game to leverage
- Native Swift/SwiftUI, latest iOS + watchOS
- Offline-first: core features must work without network
- No cloud infrastructure or backend services
- No App Store publication

## AI/LLM Strategy — Tiered Inference
1. **On-device**: Apple FoundationModels — offline, low-latency (quick corrections, simple exchanges)
2. **Gemini free tier**: 500-1000 req/day — higher-quality conversation when online
3. **Claude via existing subscription**: highest quality — complex grammar, nuanced conversation, content review. Feasibility of iOS integration needs technical validation (web API, automation, or proxy)
4. **RTX 5090 local server**: open-weight models for batch content pre-generation (mnemonics, grammar explanations, listening passages)
- AI conversation partner auto-adapts to learner's current level via system prompt injection (known grammar, vocab range, JLPT estimate)
- Learner can interact via text, voice, or both
- Beginner: scaffolded exchanges → advanced: free-form conversation

## Learning Methodology — Research Findings

### Spaced Repetition
- FSRS algorithm (not SM-2) — 20-30% fewer reviews for same 90% retention
- Sotaku app uses FSRS successfully, validated approach
- All card types: kanji, vocabulary, grammar points, listening clips

### Kanji Strategy
- RTK (Remembering the Kanji) by Heisig: good for mnemonic decomposition, BUT teaches zero readings/vocabulary/context
- KKLC (Kodansha Kanji Learner's Course): teaches readings + vocabulary in context
- **Ikeru approach**: hybrid — RTK-style radical decomposition with KKLC-style immediate reading/vocab integration
- Kanji knowledge graph: never encounter a kanji before learning its component radicals
- LLM-generated personalized mnemonics (reference learner's own context, not generic)
- JLPT-aligned progression N5→N1
- Books to potentially integrate: Remembering the Kanji (Heisig) — Nico will provide ePub/PDF. Verify additional book recommendations during PRD phase.

### Reading
- Comprehensible input at i+1 level (Krashen's input hypothesis)
- JLPT-graded passages
- Future: NHK Easy News RSS, manga OCR, song lyrics as real-world content pipeline

### Writing
- Stroke order display and tracing
- Particle and conjugation fill-in-the-blank
- Typed sentence construction
- Handwritten kanji recognition via on-device ML (CoreML)

### Listening
- Comprehensible input at i+1, shadowing exercises
- Progressive difficulty: simple phrases → natural-speed conversation
- TTS for repeatable drills + native audio (Forvo/OJAD) for natural examples

### Speaking & Pronunciation
- Pitch accent as FIRST-CLASS system — 頭高, 中高, 尾高, 平板 pattern tracking
- Most apps ignore pitch accent entirely — building it from day one while neural pathways are forming is dramatically more effective
- Multiple evaluation methods: isolated word, shadowing accuracy, conversational speech
- On-device pronunciation analysis (AVAudioEngine, F0 contour extraction — feasibility to validate)
- Real-time feedback during shadowing

### General Principles
- Consistency (30-60 min/day) beats intensity
- Short distributed sessions are scientifically optimal for long-term retention
- All 4 skills in parallel, planner balances based on weakness detection

## Adaptive Study Planner
- Rule-based heuristics analyzing: error rates, response times, skill balance ratios
- Dynamically composes each session based on learner's current state
- Day-1 beginner → kana drills. Advanced → N2 kanji + free conversation
- Session adapts to available time: 2-min micro → 30-min focused block
- Silent mode for no-audio environments
- Evolves to ML-based engine as usage data accumulates

## Apple Watch Design
- NOT just notification relay — primary surface for audio-centric skills
- Kana/kanji recognition quizzes (4-choice)
- Audio pronunciation drills via Watch speaker/mic (walks, commute)
- Haptic-guided pitch accent patterns (tap patterns for high/low pitch)
- Spaced repetition reminders via complications
- Progress glances
- Technical validation needed: complex kanji legibility at 45mm screen

## iOS System Integration
- Live Activities: current study streak, next review due
- StandBy mode: flashcards on charging dock
- Shortcuts: "Hey Siri, quiz me"
- Spotlight suggestions
- Goal: passive Japanese exposure without opening the app

## Data Export & Agent Analysis
- Formats: JSON, CSV, Parquet
- Export includes learning context metadata (how the app works, what metrics mean)
- Structured so an external AI agent can immediately interpret and provide insights
- Use case: export data → pass to Claude/agent → discuss progress, get feedback, identify patterns

## Multi-User Profiles
- Simple local storage per user: config + progress + SRS state
- No login, no auth, no database, no server
- User switching in-app
- Learning methodology is identical for all users (Nico's approach)

## Content Pipeline
| Type | Source | Notes |
|---|---|---|
| Kanji decomposition | KanjiVG + open radical databases | RTK/KKLC-style components |
| Vocabulary & sentences | Tatoeba corpus + JLPT frequency lists | All levels, tagged by difficulty |
| Grammar explanations | LLM-generated (RTX 5090 batch), validated vs Tae Kim/Genki | Pre-generated, concise, example-driven |
| Native audio | Apple TTS + Forvo/OJAD | TTS for drills, native for immersion |
| Mnemonics | LLM on-demand on-device, cached | Personalized to learner context |
| Listening passages | Curated open sources + NHK Easy News + manga/song | Graded by JLPT level |

## Competitive Intelligence
- **WaniKani**: kanji only, rigid pacing, paid subscription ($9/mo). Strength: community mnemonics. Weakness: no readings until late, locked pacing.
- **Anki**: powerful SRS, complex UX, most beginners bounce. Uses SM-2 (inferior to FSRS).
- **Bunpro**: grammar-focused SRS. Weakness: strict answer acceptance, nothing beyond grammar.
- **Duolingo Japanese**: shallow, gamified. Optimizes engagement over learning.
- **Sotaku**: uses FSRS, good free tier, but no speaking/writing/listening/watchOS.
- **LingoDeer**: better than Duolingo for Asian languages, but still shallow at advanced levels.
- Apple Watch learning apps: essentially greenfield — TokeiTango (basic flashcards), Daily Kanji (notifications). No serious companion.
- **Market gap**: no single app covers all 4 skills with adaptive AI + modern SRS + pitch accent + Watch support.

## Technical Validations Needed
1. AVAudioEngine F0 contour extraction for pitch accent — feasible on-device?
2. Apple FoundationModels Japanese conversation quality at N5→N1 levels
3. Claude subscription integration from iOS app — web API/automation/proxy approach
4. Complex kanji legibility on 45mm Apple Watch
5. FSRS Swift implementation — port open-spaced-repetition or build native
6. CoreML handwritten kanji recognition — model availability and accuracy
7. RTX 5090 local LLM server — latency and quality for batch content generation

## Success Metrics
- N5 mastery in 6 months: >90% N5 kanji at "mature" FSRS, grammar >90% recall, listening >80% accuracy on N5 passages
- N4 in 12 months, N3 in 18 months
- Balanced skill progression (no "can read but can't speak")
- Measurable pitch accent improvement over time
- Adaptive planner recommendations feel relevant
- Monthly progress snapshots for trend analysis

## Rejected / Out of Scope Decisions
- **No App Store publication** — personal tool, shared via direct distribution
- **No methodology customization for other users** — friends get the exact same system
- **No other languages** — Japanese only (though architecture should handle hardest case)
- **No social features / leaderboards** — anti-gamification stance
- **No cloud backend** — fully local + opportunistic free cloud APIs
- **No phased versioning (v1/v2/beta)** — full feature set from day one, iterate based on feedback
- **No paid APIs of any kind** — hard constraint. Existing Claude subscription OK.

## Open Questions for PRD Phase
- Exact mechanism for integrating Claude subscription from iOS (needs technical spike)
- Specific CoreML model for handwritten kanji recognition (or need to train one)
- Audio content licensing: are Forvo/OJAD audio clips usable in a personal non-commercial app?
- Curriculum sequencing: exact day-1 → week-1 → month-1 user journey
- Session composition algorithm: precise rules for how planner distributes time across skills
- Data model design: SwiftData vs SQLite vs Core Data, iCloud sync considerations
- How to handle the RTK/KKLC hybrid when the two systems disagree on radical decomposition
- Offline fallback quality: is FoundationModels good enough for meaningful Japanese conversation, or just corrections?
