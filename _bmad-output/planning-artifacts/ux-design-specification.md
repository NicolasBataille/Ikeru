---
stepsCompleted: [step-01-init, step-02-discovery, step-03-core-experience, step-04-emotional-response, step-05-inspiration, step-06-design-system, step-07-defining-experience, step-08-visual-foundation, step-09-design-directions, step-10-user-journeys, step-11-component-strategy, step-12-ux-patterns, step-13-responsive-accessibility, step-14-complete]
status: 'complete'
completedAt: '2026-04-02'
inputDocuments:
  - prd.md
  - architecture.md
  - product-brief-Ikeru.md
  - product-brief-Ikeru-distillate.md
---

# UX Design Specification Ikeru

**Author:** Nico
**Date:** 2026-04-02

---

<!-- UX design content will be appended sequentially through collaborative workflow steps -->

## Executive Summary

### Project Vision

Ikeru is a premium native iOS + Apple Watch Japanese learning companion that unifies 10+ exercise types, RPG progression, and AI-powered adaptive coaching across 5 surfaces (iPhone, Apple Watch, Dynamic Island, Lock Screen, StandBy). The UX must feel like a single cohesive product despite radical differences in screen real estate and interaction modalities. Dark mode first, Japanese-inspired design language, with premium animation moments that reward learning progress.

### Target Users

**Primary — Nico:** Tech-savvy developer who expects a polished, high-performance experience. Uses the app across contexts: focused 30-min evening sessions at home, 2-5 min micro-sessions on the train (silent mode), nano-sessions on Watch while walking. Values substance over decoration — animations should celebrate real achievements, not pad thin content.

**Secondary — Friends:** Receive the app via direct distribution. Complete beginners with no prior context about the app's methodology. Must be able to onboard independently through a guided tour and immediately understand how to navigate, study, and progress.

### Key Design Challenges

1. **Multi-surface coherence:** Five surfaces with wildly different constraints — iPhone full-screen, Watch 45mm, Dynamic Island ~60pt wide, Lock Screen widget, StandBy dock view. Each needs purpose-built UX that still feels unmistakably Ikeru.
2. **Exercise diversity without fragmentation:** 10+ exercise types (SRS card review, kanji decomposition, stroke tracing, handwriting input, grammar fill-in-blank, sentence construction, audio listening, shadowing, pronunciation analysis, AI conversation, lootbox challenges) must share a visual language and interaction grammar while having distinct, optimized interfaces.
3. **Adaptive session transitions:** The planner dynamically composes sessions mixing different exercise types. Transitions between exercises must be smooth and contextual — no jarring mode switches, no loading interruptions.
4. **RPG layer balance:** XP bars, loot notifications, level-up celebrations must motivate without cluttering the learning UI. High-spectacle moments (Metal shader lootbox opening) contrast with subtle persistent indicators (XP bar in header).
5. **Companion accessibility:** Natural language chat (help, weekly check-in, leech intervention) must be reachable without disrupting study flow. The companion should feel like a persistent presence, not a separate mode.

### Design Opportunities

1. **Metal shader RPG moments:** Lootbox opening, level-up celebrations, rare loot reveals — premium visual payoffs for learning milestones
2. **Dynamic Island as ambient study companion:** Live timer, streak counter, and session progress visible system-wide during active sessions
3. **Haptic pitch accent on Watch:** Novel UX pattern — tap sequences mapping 頭高/中高/尾高/平板 pitch contours through wrist vibration
4. **StandBy passive exposure:** Flashcards cycling on charging dock — ambient Japanese immersion without opening the app
5. **Dark-first Japanese aesthetic:** Typography that honors kanji beauty, subtle ink-wash inspired textures, warm accent colors against dark backgrounds

## Core User Experience

### Defining Experience

**Core action: "Open → See your world → Study what matters"**

The defining interaction is NOT choosing what to study — it's trusting the planner's recommendation and immediately engaging. The user opens the app, sees their RPG/learning status at a glance, taps "Start Session," and the planner serves exactly the right exercises. The SRS card review is the most frequent micro-interaction: see card → respond → swipe to grade (with button fallback) → next card. This must be sub-100ms, completely frictionless.

**Grading interaction:** Primary: swipe gestures (left = again, right = good, up = easy, down = hard). Secondary: bottom-of-screen buttons for accessibility and precision. Both always available — swipe for speed, buttons for deliberation.

### Platform Strategy

**5 surfaces, one identity:**

| Surface | Purpose | Interaction | Constraints |
|---|---|---|---|
| iPhone (full) | Primary learning, all exercises, companion chat, RPG, dashboard | Touch, voice, handwriting | Full capability |
| Apple Watch | Nano-sessions: kana quizzes, audio drills, haptic pitch | Tap, crown, wrist raise, voice | 45mm, limited text, 4-choice max |
| Dynamic Island | Ambient session companion: timer, streak, progress | Tap to expand, glance | ~60pt compact, ~180pt expanded |
| Lock Screen | Live Activity: session progress, next review countdown | Glance only | Read-only, minimal data |
| StandBy | Passive flashcards: kanji/vocab cycling on charging dock | Glance only | Large clock-like display, auto-rotation |

**Offline-first:** All surfaces function without network. No loading spinners for core interactions. Cloud AI degrades silently to on-device.

### Home Screen — "Your World"

The home screen is NOT a traditional dashboard. It's the learner's world:

**Hero section:** RPG character/avatar status — level, XP bar, recent achievements. Visually dominant, immediately communicates progress.

**Learning status:** Compact summary of where you are — JLPT level estimate, cards due, skill balance radar chart (reading/writing/listening/speaking), streak.

**Session CTA:** Prominent "Start Session" button. The planner has already composed the session — one tap to begin. Below it: estimated session time, exercise breakdown preview ("15 reviews, 3 new kanji, 1 grammar drill, shadowing").

**Companion presence:** Small avatar in bottom-right corner. Persistent across all screens. Tapping opens the companion chat sheet. Subtle animation (breathing, blinking) to feel alive. Badge indicator when weekly check-in is available.

### Effortless Interactions

- **Zero-decision study:** Open app → tap "Start" → study. The planner decides everything. Never "what should I study?"
- **Swipe grading:** Card review is swipe-first. One fluid gesture to grade and advance. No confirmation dialogs, no multi-step flows.
- **Silent mode auto-detection:** When system volume is muted, the app automatically switches to visual-only exercises. No manual toggle needed.
- **Watch nano-sessions:** Wrist raise → quiz appears → tap answer → haptic confirmation → next card. Under 90 seconds, zero navigation.
- **Session resume:** If interrupted (notification, phone call, app switch), resume exactly where you left off. No "restart session" screens.

### Critical Success Moments

1. **First session completion (Day 1):** The learner finishes their first 5 hiragana. XP bar fills. Level 1 unlocked. First loot drop. Must feel like the beginning of an adventure, not a tutorial.
2. **"It knows me" moment:** After ~2 weeks, the planner's recommendations feel uncannily accurate. The learner stops second-guessing and trusts the system.
3. **First lootbox opening:** Metal shader animation, haptic crescendo, reveal. The RPG payoff for learning effort. Must feel premium and earned.
4. **Weekly check-in conversation:** The companion says something specific and insightful about the learner's week. Not generic encouragement — real data-driven feedback. The learner feels seen.
5. **Watch pitch accent drill:** Haptic patterns tap out the pitch contour on the wrist. The learner gets it right. A novel sensation that no other app provides.

### Experience Principles

1. **The system thinks, you learn.** The app makes all the decisions (what to study, when, how long). The learner's only job is to engage and respond.
2. **Reward mastery, not attendance.** RPG progression maps to real skill growth. No empty streaks, no guilt mechanics. Lootboxes earned through demonstrated knowledge, not daily logins.
3. **Premium in the moments that matter.** Metal shaders for lootbox reveals, haptic pitch training, fluid swipe grading. Restraint everywhere else — no decoration for decoration's sake.
4. **Ambient presence, not interruption.** Dynamic Island, Watch complications, StandBy flashcards, companion avatar — Japanese is always present in the periphery without demanding attention.
5. **Dark-first Japanese aesthetic.** Design inspired by wabi-sabi minimalism — ink-wash textures as subtle backgrounds, generous whitespace, beautiful kanji typography (Noto Serif JP for display, SF Pro for UI), warm accent colors (amber, vermillion) against deep dark surfaces. Native `Material` blur and `MeshGradient` for depth.

### Visual Design Direction

**Design system approach:** Custom `IkeruDesignSystem` built on native SwiftUI primitives. No third-party UI kit — SwiftUI's native `Material`, `MeshGradient` (iOS 18+), `matchedGeometryEffect`, and `PhaseAnimator` are the building blocks.

**Color palette (dark-first):**
- Background: deep charcoal (#1A1A2E) with subtle mesh gradient warmth
- Surface: elevated cards with `.ultraThinMaterial` glass effect
- Primary accent: warm amber (#FFB347) — XP, progress, CTAs
- Secondary accent: vermillion (#FF6B6B) — notifications, leech alerts
- Success: jade green (#4ECDC4) — correct answers, mastery
- Kanji display: warm white (#F5F0E8) on dark — evokes washi paper

**Typography:**
- Kanji/Japanese display: Noto Serif JP — respects character beauty
- UI text: SF Pro — native, accessible, multilingual
- Numbers/stats: SF Mono — clean data display

**Depth and glass:**
- Card surfaces: `.ultraThinMaterial` with subtle shadow for layered depth
- Modal sheets: `.regularMaterial` backdrop
- RPG panels: `MeshGradient` backgrounds with animated color shifts
- Transitions: `matchedGeometryEffect` for seamless card-to-detail animations

## Desired Emotional Response

### Primary Emotional Goals

1. **Trust** — "This system understands me better than I understand myself." The learner stops questioning what to study and surrenders to the planner's intelligence. This trust is earned through consistently accurate recommendations, not demanded through onboarding claims.
2. **Earned accomplishment** — Every level-up, loot drop, and mastery milestone feels real because it maps to actual skill growth. The dopamine hit comes from knowing you genuinely learned something, not from an artificial reward.
3. **Companionship** — The AI companion feels like a knowledgeable friend traveling alongside you. Not a teacher (authority), not a coach (pressure), not a chatbot (hollow) — a friend who happens to know a lot about Japanese and cares about your progress.
4. **Flow** — Sessions are so fluid that the learner loses track of time. No friction between exercises, no decision points, no waiting. One swipe leads to the next challenge naturally.

### Emotional Journey Mapping

| Stage | Desired Emotion | Design Response |
|---|---|---|
| **First launch** | Curiosity + excitement | Warm guided tour, companion introduction, "your adventure begins" framing |
| **First session** | Confident capability | Easy first exercises (kana), immediate XP reward, first loot drop — "I can do this" |
| **Week 1** | Growing momentum | Visible progress (XP bar, kanji count), planner variety keeps it fresh |
| **Week 2-3** | Trust forming | Planner recommendations start feeling right. "How did it know I needed to review this?" |
| **Month 1-2** | Proud ownership | "Look at my level, my kanji count, my radar chart." The RPG state becomes personal identity |
| **Month 3 (The Wall)** | Supported resilience | Companion detects struggle, intervenes with empathy and practical help |
| **Weekly check-in** | Seen + understood | Companion gives specific, data-driven feedback — not generic encouragement |
| **Lootbox moment** | Thrill + reward | Metal shader spectacle. Haptic crescendo. Rare loot reveal |
| **Watch nano-session** | Effortless engagement | 90 seconds of learning while walking. No cognitive load. Haptic confirmation |
| **Returning after absence** | Welcome, not guilt | Companion acknowledges gap without judgment. No punishment, no lost streaks |

### Micro-Emotions

**Critical to cultivate:**
- **Confidence → never confusion.** Every screen answers "what should I do?" within 1 second.
- **Excitement → never anxiety.** Lootboxes have infinite retries — failure is impossible, only delayed success.
- **Accomplishment → never frustration.** Leech detection catches failing cards before frustration builds.
- **Trust → never skepticism.** Planner recommendations must be transparently good.

**Critical to avoid:**
- **Never guilt.** No "you missed X days" messages. No declining streak counters.
- **Never overwhelm.** Never show "2,136 kanji to learn." Only "here's your next session."
- **Never loneliness.** Companion avatar always visible. Weekly check-in always available.

### Design Implications

| Emotion | UX Decision |
|---|---|
| Trust | Planner CTA is dominant home screen element. No "browse exercises" mode that undermines planner authority |
| Accomplishment | XP bar visible during session. Micro-celebrations on correct answers. Full celebration on level-up |
| Companionship | Companion avatar persists across screens with breathing animation. Chat opens as sheet, not navigation |
| Flow | Exercise transitions use `matchedGeometryEffect`. No loading screens. Session progress bar is only persistent UI |
| No guilt | Overdue cards show as "X cards ready" (positive), never "X days missed" (negative) |
| No overwhelm | Show "N5: 42% mastered" not "2,136 remaining." Radar chart shows balance, not deficit |

### Emotional Design Principles

1. **Celebrate growth, never punish absence.** XP is never lost, levels never decrease, loot is never taken away.
2. **Spectacle is earned.** Metal shaders and full celebrations reserved for genuine milestones. Routine correct answers get subtle haptic + brief green flash.
3. **The companion is warm, not perfect.** Has opinions, pushes back, makes occasional gentle jokes. Imperfection creates connection.
4. **Progress is always visible, scale is always hidden.** Show how far they've come, never how far they have left.
5. **Silence is acceptable.** In silent mode, haptics replace audio, visual indicators replace voice. Emotional core survives without sound.

## UX Pattern Analysis & Inspiration

### Inspiring Products Analysis

**Duolingo — Gamified Learning**
- Adopt: Character with personality as persistent UI presence. Session completion celebrations. Progress visualization with clear milestones.
- Reject: Streak guilt mechanics, notification spam, shallow gamification, overly childish aesthetic.

**Gentler Streak — Apple Design Award Winner**
- Adopt: Calm dark mode with warm gradient accents. Ring/circular progress visualizations. Generous whitespace. Typography-first hierarchy.
- Adapt: More energy for RPG moments — same restraint in daily UI, more spectacle at milestones.

**Genshin Impact / Honkai: Star Rail — RPG UI**
- Adopt: Layered panel design for inventory. Particle effects for rare item reveals. Animated mesh gradient backgrounds. Loot rarity color coding.
- Adapt: RPG spectacle is event-driven, not persistent. Learning app, not game.

**shadcn/ui & aura.build — Web Design Systems**
- Adopt: Clean component borders with subtle glow. Dark-first palette with single warm accent. Glass/blur on elevated surfaces. Minimal chrome.
- Adapt: Web paradigms → native SwiftUI `Material`, `MeshGradient`, `ShapeStyle`.

**WaniKani — Kanji Learning**
- Adopt: Radical → kanji → vocabulary progression visualization. Color-coded SRS stages.
- Reject: Rigid pacing, locked content, web-first non-native design.

### Transferable UX Patterns

**Navigation:** Tab bar (Home, Session, Companion, RPG, Settings) + floating companion avatar. Active sessions take over full screen as modal flow.

**Interaction:** Swipe card stack for SRS grading. Progressive disclosure for kanji (tap to expand layers). Haptic rhythm for pitch accent patterns.

**Visual:** Glass card surfaces (`.ultraThinMaterial` + warm shadow). Animated `MeshGradient` hero section on home. Loot rarity edge glow (gray/blue/purple/gold).

### Anti-Patterns to Avoid

1. Streak counter as primary motivation — creates anxiety
2. Web-in-a-box — every interaction must be native SwiftUI
3. Settings overload — planner makes decisions, settings stay minimal
4. Separate modes per skill — planner composes mixed sessions, no "kanji mode" vs "grammar mode"
5. Gamification chrome everywhere — RPG elements breathe; not every screen needs XP bars

### Design Inspiration Strategy

**Adopt:** shadcn/aura dark glass aesthetic, Gentler Streak restraint, Genshin RPG spectacle, Duolingo character presence

**Adapt:** Genshin maximalism → event-driven spectacle, shadcn web → native SwiftUI, WaniKani SRS colors → warm palette

**Avoid:** Duolingo guilt streaks, WaniKani web-first patterns, Genshin always-on complexity, "choose your mode" navigation

## Design System Foundation

### Design System Choice

**Custom `IkeruDesignSystem`** — Built entirely on native SwiftUI primitives. No third-party UI framework.

### Rationale for Selection

- Native SwiftUI `Material`, `MeshGradient`, `PhaseAnimator`, `.sensoryFeedback` deliver premium effects with zero dependency overhead
- Ikeru's dark-first Japanese aesthetic with RPG elements doesn't fit any existing design system
- Solo developer with Claude Code — design system lives in code (`IkeruTheme`), not Figma

### Implementation Approach

**Design Tokens — `IkeruTheme`:**

**Colors:**
- Background: deep charcoal (#1A1A2E)
- Surface: elevated (#252540), glass (`.ultraThinMaterial`)
- Primary accent: warm amber (#FFB347) — XP, CTAs
- Secondary accent: vermillion (#FF6B6B) — alerts, leeches
- Success: jade green (#4ECDC4) — correct, mastery
- Kanji text: warm white (#F5F0E8) — washi paper feel
- Loot rarity: gray (common), blue #4A9EFF (rare), purple #B44AFF (epic), gold #FFD700 (legendary)

**Typography:**
- Kanji display: Noto Serif JP (48pt bold, 32pt medium)
- UI text: SF Pro (system default)
- Stats/numbers: SF Mono

**Spacing:** xs(4), sm(8), md(16), lg(24), xl(32), xxl(48)

**Radius:** sm(8), md(12), lg(16), xl(24)

**Animation:** quick (0.2s spring), standard (0.35s spring), dramatic (0.6s bounce), mesh shift (4s ease-in-out repeat)

**Shadows:** card (black 0.3, r12, y4), glow (amber 0.3, r16), loot glow (r24, color by rarity)

**Custom Component Library:**

| Component | Purpose |
|---|---|
| `IkeruCard` | Glass surface container (`.ultraThinMaterial`, rounded, shadow) |
| `IkeruButton` | Styled actions (`.primary`, `.secondary`, `.rpg`, `.danger` + haptic) |
| `XPBarView` | Animated XP progress with gradient amber fill |
| `SkillRadarView` | 4-skill radar chart (reading/writing/listening/speaking) |
| `CompanionAvatarView` | Floating companion with breathing animation + badge |
| `SRSCardView` | Swipeable flashcard with gestures + grade buttons + stack depth |
| `KanjiDisplayView` | Large kanji in Noto Serif JP, warm white, optional furigana |
| `MeshHeroView` | Animated mesh gradient background, RPG-level-dependent palette |
| `LootRevealView` | Metal shader lootbox opening with rarity glow + haptics |
| `SessionProgressBar` | Thin bar at top during sessions with exercise type indicators |

### Customization Strategy

- Dark mode only — no theme switching, the aesthetic IS the brand
- RPG-driven visual evolution: `MeshGradient` palette evolves with learner level (cool blues → warm golds)
- Companion chat bubbles use warmer tint + softer radius to distinguish companion voice from system UI
- Watch uses simplified IkeruTheme: same colors, reduced spacing, system fonts, haptics replace visual spectacle

## Detailed Core Experience

### Defining Experience

**"Ikeru knows what you need. You just show up."**

The defining experience is: open the app and immediately study exactly what matters most, without deciding anything. The learner describes it to friends as: "I just open it and it knows what I should work on. I swipe through cards, do exercises, and level up."

The magic is the absence of choice paralysis. Every other Japanese learning app presents menus, modes, skill trees, and settings. Ikeru presents a single button: "Start Session." Behind it, the planner has already composed the optimal combination of exercises.

### User Mental Model

**Current (fragmented):** "I need to open WaniKani for kanji, then Anki for vocab, then Bunpro for grammar. I decide what to study, when, and for how long."

**Ikeru (unified companion):** "I open Ikeru. My companion has a session ready. I study. I level up. If I'm stuck, I chat with my companion. I never decide what to study — I just show up."

**Shift required:** The learner must surrender control. The onboarding establishes trust by making the first recommendation obviously correct (kana for absolute beginners).

### Success Criteria

1. < 3 seconds from app open to first interaction
2. Learner agrees with planner recommendations > 90% of the time
3. Session completion rate > 85%
4. Swipe grading card transition < 100ms
5. Every XP gain correlates to a visible learning action

### Novel UX Patterns

**Established (familiar):** Swipe card stack (Tinder/Anki), tab bar navigation, chat bubbles (iMessage), progress bars (RPG), push notifications

**Novel (self-evident):**
- Haptic pitch accent training — tap patterns mapping pitch mora
- Companion avatar as persistent UI element — corner of every screen
- Session as immersive modal — full screen, no tab bar, no escape routes
- Dynamic Island as study companion — timer + streak system-wide

**Combined (familiar elements, innovative composition):**
- Planner-composed mixed sessions with `matchedGeometryEffect` transitions between exercise types
- RPG layer mapped to real JLPT metrics — level reflects actual progress

### Experience Mechanics

**1. Initiation:** Open app → home screen → "Start Session" with preview → one tap → session begins

**2. Session Flow:** Full-screen immersive mode. Dynamic Island shows timer. Planner serves exercises sequentially: SRS review (swipe) → new kanji (tap to expand) → grammar (type answer) → shadowing (listen + speak). XP bar fills incrementally. Companion avatar tappable if stuck.

**3. Feedback:**
- Correct: jade green flash + `.success` haptic + XP tick
- Wrong: vermillion flash + `.warning` haptic + card re-queued
- Leech: companion avatar bounces + chat opens with help
- Milestone: brief celebration overlay

**4. Completion:** Session summary (XP earned, items learned, skill breakdown, duration). Level-up check → Metal shader celebration if threshold crossed. Lootbox check → challenge prompt. Return to home with updated RPG status. Dynamic Island dismisses.

## Visual Design Foundation

### Color System

**Core palette defined in IkeruTheme.** Additional semantic mappings:

**SRS Stage Colors:**
- Apprentice: #FF9A76 (warm coral) — new/learning
- Guru: #FFB347 (amber) — gaining confidence
- Master: #4ECDC4 (jade) — solid knowledge
- Enlightened: #B44AFF (purple) — deep retention
- Burned: #FFD700 (gold) — permanent mastery

**Skill Colors (radar chart):**
- Reading: #4A9EFF (blue)
- Writing: #4ECDC4 (jade)
- Listening: #FFB347 (amber)
- Speaking: #FF6B6B (vermillion)

**Contrast:** Kanji text on background 13.2:1 (AAA). Primary text 15.4:1 (AAA). Secondary text 7.8:1 (AA). All text meets WCAG AA minimum.

### Typography System

| Level | Font | Size | Use |
|---|---|---|---|
| Kanji Hero | Noto Serif JP Bold | 64pt | Single kanji on study card |
| Kanji Large | Noto Serif JP Bold | 48pt | Kanji in decomposition |
| Kanji Medium | Noto Serif JP Medium | 32pt | Kanji in vocabulary context |
| H1 | SF Pro Bold | 28pt | Screen titles |
| H2 | SF Pro Semibold | 22pt | Section headers |
| H3 | SF Pro Semibold | 18pt | Card titles |
| Body | SF Pro Regular | 16pt | Primary content |
| Caption | SF Pro Regular | 13pt | Secondary info |
| Stats | SF Mono Medium | 16pt | XP, percentages, timers |

**Japanese rendering:** Always Noto Serif JP for kanji. Furigana at 50% parent size above. No vertical text.

### Spacing & Layout Foundation

**Layout principles:**
1. Generous breathing room — minimum 16pt between elements, 24pt between sections
2. Card-based architecture — every content piece on a glass `IkeruCard`
3. Full-width immersion during sessions — exercises use full screen
4. Bottom-heavy interaction — CTAs in bottom 40%, content in top 60%

**Grid:** No rigid columns. `containerRelativeFrame` for responsive sizing. Max content width 600pt. Card insets 16pt. Session exercises edge-to-edge.

### Accessibility Considerations

- All text meets WCAG AA contrast (kanji exceeds AAA for legibility)
- Interactive elements min 44pt touch target (38pt on Watch)
- Fixed type scale (no Dynamic Type — tuned for kanji display)
- VoiceOver not prioritized — Japanese learning requires visual character interaction

## Design Direction Decision

### Design Direction: "Ink & Amber"

Dark ink-wash backgrounds meet warm amber light. The dark background (ink) represents the blank page of Japanese learning. The amber accents (light) represent knowledge being written. As the learner progresses, more amber/gold appears (MeshGradient evolution, higher loot rarity, more golden UI elements).

### Key Screen Compositions

**Home Screen — "Your World":** MeshGradient hero (RPG level/XP/achievements) + glass card (learning status with skill radar) + amber "Start Session" CTA with session preview + companion avatar (bottom-right, breathing animation) + tab bar (Home, Study, Companion, RPG, Settings)

**SRS Card Review (In Session):** Full-screen immersive, no tab bar. Session progress bar + timer at top. Dynamic Island shows compact timer. Kanji hero (64pt Noto Serif JP) + reading + meaning + example vocabulary on glass card. Grade buttons bottom + swipe gestures. XP tick fades after 1s. Card stack with depth shadow for next card peek.

**Kanji Decomposition:** Progressive disclosure — tap to expand radicals → readings → mnemonic. `matchedGeometryEffect` transition from card to detail. Stroke order animation on kanji tap.

**Lootbox Opening:** Metal shader glow pulsing with rarity color. Challenge prompt with infinite retries. On completion: shader explosion, haptic crescendo, rarity reveal (gray → blue → purple → gold), item appears with particle trail.

**Companion Chat:** Sheet overlay (not navigation). Companion bubbles with warmer tint/softer radius. Can embed kanji displays, mnemonics, mini-quizzes inline. Text input at bottom.

**Apple Watch Nano-Session:** Minimal: target kana (large) + 2x2 answer grid + progress dots. Haptic confirmation. Digital Crown for scrolling details.

### Design Rationale

- Glass cards create depth through blur and shadow rather than hard lines
- Spectacle concentrated in 10% of interactions (lootbox, level-up) — 90% is calm restraint
- All screen compositions map directly to SwiftUI views defined in architecture

### View Mapping

| Screen | SwiftUI Views |
|---|---|
| Home | DashboardView + MeshHeroView + CompanionAvatarView |
| SRS Review | CardReviewView + SRSCardView + GradeButtonsView |
| Kanji Study | KanjiDetailView + RadicalDecompositionView + MnemonicView |
| Lootbox | LootBoxOpenView + LootRevealView (Metal) |
| Companion | CompanionChatView + ChatBubbleView (sheet) |
| Watch | KanaQuizView (IkeruWatch) |

## User Journey Flows

### Flow 1: First Launch & Onboarding

Name entry (single field, no signup) → Create profile → 3-screen guided tour (journey overview, companion intro, first session preview) → Auto-compose first session (hiragana あいうえお) → Session complete → XP + Level 1 + first loot drop → Home. Total: < 5 minutes.

### Flow 2: Core Session Loop

Home → "Start Session" → Planner composes (< 500ms) → Immersive mode (tab bar hidden) → Dynamic Island timer → Exercises served sequentially (SRS review with swipe grading → new kanji with progressive disclosure → grammar fill-in-blank → shadowing) → Session summary → Level-up check (Metal shader if yes) → Lootbox check → Home.

Exercise transitions use `matchedGeometryEffect`. Companion avatar visible and tappable throughout. Session pausable (swipe down), not skippable.

### Flow 3: Weekly Check-In

Push notification → Companion chat sheet → Weekly summary (stats + specific observations) → Asks for feedback → Debates pragmatically if disagreement (uses data) → Adjusts planner weights → Overall progress review → Companion ends conversation → Optional export for Claude Code.

### Flow 4: Leech Intervention

Card fails 3+ times → LeechDetectionService flags → Companion avatar bounces → Chat opens automatically → Companion identifies confusion pattern → Personalized mnemonic → Mini practice exercise → Loop until resolved → Tighter FSRS interval set → Return to session.

### Journey Patterns

1. Single entry, guided path — one clear entry point, guided forward
2. Companion as safety net — available without disrupting primary interaction
3. Celebrate, don't punish — flows end with positive outcomes
4. Immersive when active — sessions take full screen; passive views have navigation
5. Graceful interruption — any flow resumes exactly where paused

### Flow Optimization Principles

1. Minimum taps to value: Home → Learning in 2 taps
2. Zero dead ends: every screen has clear "next" action
3. Progressive complexity: planner introduces exercise types gradually
4. Context-aware: silent mode auto-detected, time-aware composition, Watch vs phone automatic

## Component Strategy

### SwiftUI Native Components

NavigationStack (custom coordinator), TabView (hidden during sessions), List/ScrollView (glass backgrounds), TextField (amber focus border), Button (IkeruButtonStyle), Sheet (.regularMaterial), ProgressView (amber tint), Toggle/Picker (amber accent).

### Custom Components

| Component | Purpose | Key Feature |
|---|---|---|
| `SRSCardView` | Swipeable flashcard for SRS review | Swipe L/R/U/D grading, card stack with depth, 4 card type variants |
| `MeshHeroView` | Animated gradient hero section | Color palette evolves with RPG level (blues → golds) |
| `CompanionAvatarView` | Persistent companion presence | 44pt floating, breathing animation, bounce on attention, badge for check-in |
| `XPBarView` | XP progress visualization | Animated fill with sparkle, pulse glow near level-up threshold |
| `SkillRadarView` | 4-axis skill balance chart | Gradient-filled polygon, mini + full variants |
| `KanjiDisplayView` | Large kanji rendering | Noto Serif JP, warm white, tap for stroke order animation |
| `LootRevealView` | Lootbox opening celebration | Metal shader particles, haptic crescendo, rarity glow escalation |
| `SessionProgressBar` | Session progress during study | 4pt bar + exercise type icons, extends behind status bar |
| `IkeruCard` | Glass container | .standard, .elevated, .interactive, .companion variants |
| `ChatBubbleView` | Companion/user chat messages | .companion (warm tint, left) / .user (glass, right), inline content embeds |

### Implementation Roadmap

**Phase 1 (Core Loop):** SRSCardView, IkeruCard, IkeruButton styles, SessionProgressBar, KanjiDisplayView

**Phase 2 (Home & RPG):** MeshHeroView, XPBarView, SkillRadarView, CompanionAvatarView

**Phase 3 (Companion & Rewards):** ChatBubbleView, LootRevealView

## UX Consistency Patterns

### Button Hierarchy

| Style | Use | Visual | Haptic |
|---|---|---|---|
| `.primary` | Main CTA | Amber fill, white text | `.impact(.medium)` |
| `.secondary` | Supporting actions | Glass outline, amber text | `.impact(.light)` |
| `.rpg` | RPG actions | Gradient fill (rarity-colored), glow | `.impact(.heavy)` |
| `.danger` | Destructive (confirmation required) | Vermillion outline | `.notification(.warning)` |
| `.ghost` | Tertiary | No background, white 60% | None |

Max 1 primary per screen. Destructive requires confirmation. All buttons 44pt min.

### Feedback Patterns

| Event | Visual | Haptic | Duration |
|---|---|---|---|
| Correct | Jade green flash | `.notification(.success)` | 300ms |
| Wrong | Vermillion flash | `.notification(.warning)` | 300ms |
| XP gained | "+XP ✨" float-up, bar fills | `.impact(.light)` | 500ms |
| Level up | Full-screen Metal shader + Lottie | Crescendo × 3 + success | 2s |
| Leech detected | Companion bounces, chat opens | `.notification(.warning)` | Auto |
| Error (network) | Amber toast "Offline — on-device AI" | None | 3s |
| Error (data) | Vermillion toast, persists until resolved | `.notification(.error)` | Persist |

No blocking modals for non-critical errors. Toasts auto-dismiss for info.

### Navigation Patterns

**Tab bar:** Home, Study, Companion (badge for check-in), RPG, Settings. Hidden during sessions. Active: amber. Inactive: white 40%.

**Drill-down:** NavigationStack push/pop. **Overlays:** Sheet for non-replacing context (chat, export). **Immersive:** Full-screen cover for sessions, lootbox, onboarding.

**Session exit:** Swipe-down → pause menu (Resume/End). Never accidental navigation away.

### Loading & Empty States

**Loading:** Amber shimmer skeleton (never full-screen spinner). AI: typing indicator dots. Content fetch: background, non-blocking.

**Empty:** Companion-driven messaging. "All caught up!" (positive), "Start your first session!" (encouraging). Never "nothing here."

### Modal Patterns

- Sheet: companion chat, settings, export, summary (swipe-down dismiss)
- Full-screen cover: sessions, lootbox, onboarding, level-up (explicit dismiss)
- Alert: destructive confirmations only
- Toast: non-blocking info/error at top

## Responsive Design & Accessibility

### Multi-Surface Adaptation

| Surface | Adaptation |
|---|---|
| iPhone (all sizes) | Full experience, `containerRelativeFrame`, max 600pt content width, bottom-heavy interaction |
| Apple Watch (45mm) | Radically simplified: 4-choice quizzes, system font only, haptics primary feedback |
| Dynamic Island | Compact: streak + timer. Expanded: exercise type + XP mini bar |
| Lock Screen | Read-only: next review countdown, streak, kanji of the day |
| StandBy | Single flashcard: large kanji + reading, auto-rotate every 10s |

### Accessibility

Baseline readability only (personal app). All text WCAG AA contrast. Kanji at AAA (13.2:1). 44pt touch targets (38pt Watch). No VoiceOver, Dynamic Type, or Reduced Motion support.

### Testing

iPhone SE (smallest) + Pro Max (largest) for layout. Watch 45mm for kanji legibility. Dynamic Island compact/expanded. StandBy at arm's length.
