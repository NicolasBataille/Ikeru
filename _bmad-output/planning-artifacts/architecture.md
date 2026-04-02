---
stepsCompleted: [step-01-init, step-02-context, step-03-starter, step-04-decisions, step-05-patterns, step-06-structure, step-07-validation, step-08-complete]
status: 'complete'
completedAt: '2026-04-02'
inputDocuments:
  - prd.md
  - product-brief-Ikeru.md
  - product-brief-Ikeru-distillate.md
workflowType: 'architecture'
project_name: 'Ikeru'
user_name: 'Nico'
date: '2026-04-02'
---

# Architecture Decision Document

_This document builds collaboratively through step-by-step discovery. Sections are appended as we work through each architectural decision together._

## Project Context Analysis

### Requirements Overview

**Functional Requirements:**
65 FRs across 10 capability areas. The architectural weight is concentrated in:
- FSRS spaced repetition engine (performance-critical, thousands of cards, sub-ms scheduling)
- Kanji knowledge graph (DAG traversal for radical → kanji → vocabulary dependency ordering)
- Tiered AI inference router (4 tiers with transparent failover and quality-based selection)
- Adaptive study planner (real-time session composition balancing 4 skills, time, and context)
- Multi-surface sync (iPhone ↔ Watch bidirectional real-time via WatchConnectivity)

**Non-Functional Requirements:**
19 NFRs driving architectural decisions:
- Performance: SRS card transitions <100ms, FSRS scheduling sub-ms, pronunciation feedback <500ms, Watch interactions <200ms, app launch <2s, session composition <500ms
- Reliability: atomic SRS mutations (zero tolerance for corruption), offline-first guarantee, Watch sync resilience, profile isolation, crash recovery with session state preservation
- Integration: AI tier transparency with <2s fallback, WatchConnectivity bidirectional sync, iCloud manual backup, iOS system features (Live Activities, StandBy, Shortcuts, Spotlight), seamless progressive content loading

**Scale & Complexity:**
- Primary domain: Native iOS + watchOS (Swift/SwiftUI)
- Complexity level: High
- Estimated architectural components: 12-15

### Technical Constraints & Dependencies

- **Zero paid APIs** — all AI must use free tiers or existing subscriptions
- **Offline-first** — core learning loop must function identically without network
- **Apple ecosystem only** — Swift/SwiftUI, latest iOS + watchOS
- **No backend** — fully local with opportunistic cloud AI
- **Direct distribution** — TestFlight/ad-hoc, no App Store compliance
- **Public repo** — no secrets, API keys, or personal info in committed code
- **Content licensing** — CC-licensed sources only (KanjiVG, Tatoeba, KANJIDIC, RADKFILE); Forvo and OJAD blocked
- **Initial install size** — target under 500MB with progressive content loading

### Cross-Cutting Concerns Identified

- **Offline-first architecture** — affects AI, content, sync, backup, and every data write
- **Per-profile data isolation** — all persistent state (SRS, progress, companion, RPG) sandboxed per user
- **Performance budget** — sub-100ms for SRS interactions, sub-ms for scheduling, <2s for AI fallback
- **Data integrity** — atomic operations for all SRS mutations, crash recovery, backup/restore consistency
- **AI tier routing** — transparent tier selection and fallback across conversation, companion, and content generation

## Starter Template Evaluation

### Primary Technology Domain

Native iOS + watchOS (Swift/SwiftUI) — no cross-platform consideration.

### Architecture & Technology Decisions

**Architecture Pattern: MVVM + @Observable + Repository Pattern + Shared SPM Package**

TCA (The Composable Architecture) evaluated and rejected: excessive boilerplate for this project. `@Observable` (iOS 17+) eliminates historical MVVM friction in SwiftUI. Selected pattern:
- **MVVM + @Observable** for views and state management
- **Repository pattern** for data access (SRS, content, companion history)
- **Service layer** with protocols for dependency injection and testability
- **Shared Swift Package (`IkeruCore`)** containing models, repositories, services — consumed by iOS, watchOS, and Widget targets

**Project Structure:**

```
Ikeru/
├── IkeruCore/                    # Shared SPM package
│   ├── Sources/
│   │   ├── Models/               # Domain models (Card, Kanji, Profile, etc.)
│   │   ├── Repositories/         # Data access (SRS, Content, Profile, RPG)
│   │   ├── Services/             # Business logic (FSRS, Planner, AI Router)
│   │   └── Utilities/            # Shared helpers
│   └── Tests/
├── Ikeru/                        # iOS app target
│   ├── Views/                    # SwiftUI views organized by feature
│   ├── ViewModels/               # @Observable view models
│   └── App/                      # App entry, navigation, configuration
├── IkeruWatch/                   # watchOS app target
│   ├── Views/
│   └── App/
├── IkeruWidget/                  # WidgetKit + Live Activities extension
│   ├── Widgets/
│   └── LiveActivities/           # Dynamic Island + Lock Screen
└── IkeruTests/                   # swift-testing + XCTest
```

**Package Manager:** SPM exclusively (no CocoaPods/Carthage)

**Persistence:** SwiftData with `ModelActor` for background operations. Atomic writes for SRS state integrity. Per-profile data isolation via SwiftData model containers.

**Testing:**
- `swift-testing` (Xcode 16+) for unit and integration tests — `@Test` macro, `#expect`, parameterized tests
- XCTest for UI tests and performance tests

**UI & Animation Stack:**
- Stock SwiftUI animations: `PhaseAnimator`, `KeyframeAnimator`, spring animations, `matchedGeometryEffect`
- Custom `TimelineView` + Metal shaders (`layerEffect`/`colorEffect`) for premium effects (RPG lootbox openings, level-up celebrations)
- **Lottie** for designer-created animations (onboarding tour, companion character expressions)
- `.sensoryFeedback` modifier for haptic feedback on interactions
- Custom `ButtonStyle` / `LabelStyle` / `ShapeStyle` for consistent premium feel
- `containerRelativeFrame` for responsive layouts

**Dynamic Island & Live Activities:**
- ActivityKit for active study sessions: timer, progression, streak, next review
- Compact/minimal presentations for Dynamic Island during sessions
- Lock Screen Live Activity for progress visibility without opening the app
- Lightweight `ActivityAttributes` — only essential session data

**CI/CD:** GitHub Actions from day one
- Build + test on every push/PR
- `swift-testing` + XCTest in parallel
- Xcodebuild for iOS + watchOS targets

### Initialization

No CLI starter template — Xcode project templates are the standard for iOS. The shared SPM package (`IkeruCore`) is where the architectural decisions live. Project initialization via Xcode:
1. Create iOS App project
2. Add watchOS App target
3. Add Widget Extension target (with Live Activity)
4. Create shared Swift package (IkeruCore)

## Core Architectural Decisions

### Decision Priority Analysis

**Critical Decisions (Block Implementation):**
- SwiftData model design for SRS, kanji graph, profiles, RPG
- AI tier routing strategy
- WatchConnectivity protocol design
- Navigation architecture
- Secret management (public repo)

**Important Decisions (Shape Architecture):**
- Kanji knowledge graph representation
- Content storage format
- Design system approach
- Local GPU server protocol

**Deferred Decisions (Post-MVP iteration):**
- ML-based planner (starts rule-based, evolves later)
- Content pipeline automation (NHK Easy News, manga OCR)

### Data Architecture

**SwiftData as primary persistence.** Models use `@Model` macro with `ModelActor` for thread-safe background operations.

**Schema design — 6 core model groups:**

1. **Profile** — `UserProfile` (id, displayName, createdAt, settings). Each profile owns all data below via relationships. Profile switching changes the active `ModelContainer` configuration.

2. **SRS Engine** — `Card` (id, type enum [kanji/vocab/grammar/listening], fsrsState, easeFactor, interval, dueDate, lapseCount, leechFlag, responseHistory[]), `ReviewLog` (timestamp, card, grade, responseTimeMs). FSRS state stored as a lightweight struct — no redundant computed fields.

3. **Kanji Knowledge Graph** — `Kanji` (character, radicals[], readings[], meanings, jlptLevel, mnemonicText, strokeOrderSVGRef), `Radical` (character, meaning, strokeCount), `KanjiRadicalEdge` (radical→kanji dependency). The DAG is stored as an adjacency list via relationship edges. Topological sort at content load time to guarantee "radicals before kanji" ordering.

4. **Content** — `GrammarPoint` (id, jlptLevel, title, explanation, examples[]), `Vocabulary` (word, reading, meaning, kanji?, sentences[], audioRef?), `ListeningPassage` (id, jlptLevel, transcript, audioRef, difficulty). Content loaded progressively by JLPT level. Static content stored in pre-built SQLite bundles (not SwiftData) for fast read-only access — only user-generated data (mnemonics, companion history) in SwiftData.

5. **RPG** — `RPGState` (xp, level, attributes{}, lootInventory[], unlockedItems[]), `LootBox` (id, challengeType, requiredScore, rewards[], opened). XP calculations and level thresholds defined as pure functions in `IkeruCore`.

6. **Companion** — `CompanionCheckIn` (date, weekSummary, overallSummary, conversationLog[], plannerAdjustments[]), `ChatMessage` (timestamp, role, content, context?). Conversation history kept per profile, with configurable retention limit.

**Static content vs user data split:**
- **Pre-built SQLite bundles** (read-only): KanjiVG stroke data, KANJIDIC readings, Tatoeba sentences, RADKFILE radicals, grammar explanations. Shipped per JLPT level. Fast reads, no SwiftData overhead.
- **SwiftData** (read-write): SRS card state, review logs, RPG state, companion history, user preferences, cached mnemonics. Atomic writes, profile-isolated.

**Migration strategy:** SwiftData lightweight migrations for user data schema changes. Static content bundles versioned — new bundles replace old on update.

**Caching:** LLM-generated content (mnemonics, grammar explanations) cached in SwiftData per-card. Cache invalidation: never auto-delete, user can regenerate manually.

### Authentication & Security

**No authentication** — local profiles only, no server, no login.

**Secret management (public repo):**
- **iOS Keychain** for runtime API keys (Gemini API key, Claude session tokens)
- **Xcode configuration files** (`.xcconfig`) for build-time secrets, excluded via `.gitignore`
- **No secrets in source code** — ever. `.gitignore` includes: `*.xcconfig`, `Secrets/`, `.env*`
- **Environment detection** — `#if DEBUG` for development-only configuration

**Data protection:** iOS Data Protection (file-level encryption) for SwiftData stores. Default `NSFileProtectionComplete` — data inaccessible when device locked.

### API & Communication Patterns

**AI Tier Router — `AIRouter` service:**

Tier selection logic:
1. Check network reachability
2. If offline → FoundationModels (on-device)
3. If online, evaluate request complexity:
   a. Simple (corrections, quick answers) → FoundationModels (on-device, low latency)
   b. Medium (conversation, grammar) → Gemini free tier
   c. Complex (nuanced conversation, content review) → Claude subscription
   d. Batch generation (mnemonics, explanations) → RTX 5090 local server
4. On tier failure → fallback to next available tier within 2s
5. All tier transitions invisible to caller

Protocol-based: `AIProvider` protocol with `FoundationModelsProvider`, `GeminiProvider`, `ClaudeProvider`, `LocalGPUProvider` implementations. Router handles retry, fallback, and timeout logic.

**WatchConnectivity protocol:**
- `WCSession` with bidirectional `applicationContext` for latest state
- `transferUserInfo` for queued updates (offline Watch sessions)
- `sendMessage` for real-time interactions when reachable
- Conflict resolution: timestamp-based last-write-wins for SRS state. Watch sessions always win if completed more recently.
- Shared data format: `Codable` structs via `IkeruCore` package

**Local GPU server protocol:**
- HTTP REST API on local network (RTX 5090 machine)
- Endpoints: `/generate/mnemonic`, `/generate/grammar`, `/generate/listening`
- Batch requests with job queue — responses cached in SwiftData
- Discovery via Bonjour/mDNS on local network
- Timeout: 30s per request, graceful failure if server unreachable

**iCloud backup format:**
- CloudKit private database for manual backup
- Backup payload: serialized SwiftData snapshot (all user data, no static content)
- Restore: full replacement of local SwiftData store from CloudKit record
- Conflict: manual backup = no conflicts (user-initiated, not automatic)

**Export formats:**
- JSON: full learning data with metadata schema (what each field means)
- CSV: flat tables (cards, reviews, progress) for spreadsheet analysis
- Parquet: columnar format for AI agent consumption (efficient for large datasets)
- All exports include `context.json` explaining the data model for external agents

### Frontend Architecture

**Navigation:** `NavigationStack` with path-based navigation. Coordinator pattern via `@Observable` `NavigationCoordinator` — single source of truth for navigation state, enables deep linking from Shortcuts/Spotlight.

**State sharing:**
- `@Observable` view models per feature area
- `@Environment` for app-wide services (AI router, profile manager, planner)
- No global singletons — dependency injection via SwiftUI environment

**View composition:**
- Feature-based organization: `Views/Learning/`, `Views/Companion/`, `Views/RPG/`, `Views/Dashboard/`, `Views/Settings/`
- Shared components: `Views/Shared/` (card views, progress indicators, haptic buttons)
- Exercise views implement a common `ExerciseView` protocol for planner integration

**Design system:**
- Custom `IkeruTheme` with consistent colors, typography, spacing
- Custom `ButtonStyle` variants: `.primary`, `.secondary`, `.rpg`, `.danger`
- Haptic feedback via `.sensoryFeedback` on all interactive elements
- Dark mode first (default), with light mode support
- Custom SF Symbol configurations for consistent iconography

### Infrastructure & Deployment

**GitHub Actions CI/CD:**
- Trigger: push to `main`, pull requests
- Steps: lint (SwiftLint), build (iOS + watchOS + Widget), test (swift-testing + XCTest)
- macOS runner with latest Xcode
- No deployment pipeline (manual TestFlight/ad-hoc distribution)

**No hosting** — fully local application, no cloud infrastructure.

**Local GPU server:** Self-hosted on RTX 5090 machine. Docker container with REST API. Not part of CI/CD — separate infrastructure managed independently.

**Logging:** `os.Logger` (unified logging system) for structured logs. Categories per service (SRS, AI, Planner, Sync). Debug builds log to console; release builds log to system log accessible via Console.app.

### Decision Impact Analysis

**Implementation Sequence:**
1. Project scaffolding (Xcode project, SPM package, targets)
2. Data layer (SwiftData models, static content bundles, repositories)
3. FSRS engine (core scheduling, card management)
4. Kanji knowledge graph (DAG, topological sort, content loading)
5. Adaptive planner (rule-based session composition)
6. Exercise views (SRS review, kanji study, grammar, writing, listening)
7. AI tier router + conversation partner
8. RPG progression system
9. Companion (chat + weekly check-in)
10. Watch app + WatchConnectivity sync
11. iOS integration (Live Activities, Dynamic Island, StandBy, Shortcuts, Spotlight)
12. Onboarding + profiles
13. Data export + iCloud backup

**Cross-Component Dependencies:**
- `IkeruCore` is the foundation — everything depends on it
- FSRS engine must exist before exercise views
- Kanji knowledge graph must exist before kanji-related exercises
- AI router must exist before companion and conversation features
- Data layer must exist before everything else

## Implementation Patterns & Consistency Rules

### Pattern Categories Defined

**12 critical conflict points identified** where AI agents could make divergent implementation choices.

### Naming Patterns

**SwiftData Model Naming:**
- Models: PascalCase singular — `Card`, `UserProfile`, `ReviewLog`
- Properties: camelCase — `dueDate`, `lapseCount`, `jlptLevel`
- Enums: PascalCase type, camelCase cases — `CardType.kanji`, `CardType.vocabulary`
- Relationships: named by the related type — `profile.cards`, `kanji.radicals`

**File Naming:**
- Swift files: PascalCase matching the primary type — `Card.swift`, `FSRSEngine.swift`
- View files: suffix `View` — `CardReviewView.swift`, `DashboardView.swift`
- ViewModel files: suffix `ViewModel` — `CardReviewViewModel.swift`
- Repository files: suffix `Repository` — `CardRepository.swift`
- Service files: suffix `Service` — `FSRSService.swift`, `AIRouterService.swift`
- Protocol files: suffix `Protocol` or prefix with type — `AIProvider.swift`
- Test files: suffix `Tests` — `FSRSEngineTests.swift`

**Asset Naming:**
- Images: kebab-case — `loot-box-gold`, `icon-kanji-study`
- Colors: kebab-case with semantic prefix — `color-primary`, `color-rpg-xp`
- Lottie animations: kebab-case — `anim-level-up`, `anim-lootbox-open`

### Structure Patterns

**Project Organization — Feature-based:**

```
IkeruCore/Sources/
├── Models/
│   ├── SRS/            # Card, ReviewLog, FSRSState
│   ├── Content/        # Kanji, Radical, Vocabulary, GrammarPoint
│   ├── Profile/        # UserProfile, ProfileSettings
│   ├── RPG/            # RPGState, LootBox, LootItem
│   └── Companion/      # CompanionCheckIn, ChatMessage
├── Repositories/
│   ├── CardRepository.swift
│   ├── ContentRepository.swift
│   ├── ProfileRepository.swift
│   └── RPGRepository.swift
├── Services/
│   ├── FSRSService.swift
│   ├── PlannerService.swift
│   ├── AIRouterService.swift
│   ├── WatchSyncService.swift
│   └── ExportService.swift
└── Utilities/
    ├── Extensions/
    └── Helpers/

Ikeru/Views/
├── Learning/
│   ├── CardReview/     # SRS review flow
│   ├── KanjiStudy/     # Kanji decomposition, mnemonics
│   ├── Grammar/        # Grammar exercises
│   ├── Writing/        # Stroke order, handwriting
│   ├── Listening/      # Audio, shadowing
│   └── Speaking/       # Pronunciation, pitch accent
├── Companion/
│   ├── Chat/           # Natural language chat
│   └── CheckIn/        # Weekly check-in flow
├── RPG/
│   ├── Profile/        # Level, attributes, inventory
│   └── LootBox/        # Lootbox opening, challenges
├── Dashboard/          # Progress, skill breakdown
├── Onboarding/         # Guided tour
├── Settings/           # Profile, backup, export, preferences
└── Shared/             # Reusable components
    ├── Cards/          # Card view variants
    ├── Buttons/        # Custom button styles
    ├── Progress/       # Progress indicators
    └── Feedback/       # Haptic, visual feedback
```

**Test organization — mirrors source:**
- `IkeruCoreTests/Services/FSRSServiceTests.swift`
- `IkeruCoreTests/Repositories/CardRepositoryTests.swift`
- `IkeruTests/ViewModels/CardReviewViewModelTests.swift`

### Format Patterns

**Codable & Data Exchange:**
- All JSON keys: camelCase (Swift default `JSONEncoder`/`JSONDecoder`)
- Dates: ISO 8601 strings in JSON, `Date` in Swift — configured via `JSONEncoder.dateEncodingStrategy = .iso8601`
- Optionals: omitted from JSON when nil
- Enums: string raw values in JSON — `"kanji"`, `"vocabulary"`, not integers

**Export format schema:**
```
export/
├── context.json       # Schema description for external agents
├── cards.json         # All cards with SRS state
├── reviews.csv        # Flat review history
├── progress.json      # Per-skill progress snapshots
└── data.parquet       # Full dataset for analytics
```

**Error types — structured enum:**
```swift
enum IkeruError: LocalizedError {
    case srs(SRSError)
    case ai(AIError)
    case content(ContentError)
    case sync(SyncError)
    case export(ExportError)
}
```
Each sub-error enum has specific cases. Never use generic `Error` or string-based errors.

### Communication Patterns

**Async patterns — always `async/await`:**
- No completion handlers — all async code uses `async/await`
- No Combine publishers for new code — use `AsyncStream` if streaming needed
- `@MainActor` for all ViewModels and UI-touching code
- `ModelActor` for all SwiftData background operations
- `Task {}` for launching async work from sync contexts (SwiftUI `.task` modifier preferred)

**State updates — `@Observable` pattern:**
- Never use `@Published` or `ObservableObject` — always `@Observable` (iOS 17+)
- Direct property mutation — `@Observable` handles change tracking
- Never use `objectWillChange.send()`

**Notifications — only for cross-cutting events:**
- Use `NotificationCenter` only for app lifecycle events and Watch sync events
- All other communication: direct method calls via dependency injection
- Notification names: `Notification.Name.ikeru` prefix

### Process Patterns

**Error handling — structured and explicit:**
- Always catch specific `IkeruError` cases
- Never generic catch-all with `print(error)`
- User-facing errors via `LocalizedError` conformance
- Technical errors via `os.Logger`

**Loading states — per-view enum:**
```swift
enum LoadingState<T> {
    case idle
    case loading
    case loaded(T)
    case error(IkeruError)
}
```
Every view that loads data uses this pattern. No boolean `isLoading` flags.

**Dependency injection — SwiftUI environment:**
- Register services in app root via `.environment()`
- Consume in views via `@Environment(Type.self)`
- No service locators, no singletons, no global state

**Logging — structured with `os.Logger`:**
- Categories: `SRS`, `AI`, `Planner`, `Sync`, `RPG`, `Content`
- Subsystem: `com.ikeru`
- Never use `print()` or `NSLog`

### Enforcement Guidelines

**All AI Agents MUST:**
- Follow `@Observable` pattern — never `ObservableObject`/`@Published`
- Use `async/await` — never completion handlers or Combine
- Use structured `IkeruError` — never generic errors
- Use `LoadingState<T>` enum — never boolean loading flags
- Use `@Environment` DI — never singletons
- Use `os.Logger` — never `print()` or `NSLog`
- Follow file naming conventions — PascalCase + suffix
- Place tests mirroring source structure

### Anti-Patterns (FORBIDDEN)

- Singleton pattern (`static let shared`)
- Completion handlers
- Generic error strings / `NSError`
- Boolean `isLoading` flags
- `print()` for logging
- `ObservableObject` / `@Published`
- Service locator pattern
- Global mutable state

## Project Structure & Boundaries

### Complete Project Directory Structure

```
Ikeru/
├── .github/workflows/ci.yml
├── .gitignore
├── .swiftlint.yml
├── README.md
├── IkeruCore/                              # Shared SPM Package
│   ├── Package.swift
│   ├── Sources/
│   │   ├── Models/
│   │   │   ├── SRS/                        # Card, ReviewLog, FSRSState, CardType, Grade
│   │   │   ├── Content/                    # Kanji, Radical, KanjiRadicalEdge, Vocabulary,
│   │   │   │                               # GrammarPoint, ListeningPassage, JLPTLevel
│   │   │   ├── Profile/                    # UserProfile, ProfileSettings
│   │   │   ├── RPG/                        # RPGState, LootBox, LootItem, RPGConstants
│   │   │   ├── Companion/                  # CompanionCheckIn, ChatMessage, PlannerAdjustment
│   │   │   └── Common/                     # IkeruError, LoadingState
│   │   ├── Repositories/
│   │   │   ├── CardRepository.swift
│   │   │   ├── ContentRepository.swift
│   │   │   ├── ProfileRepository.swift
│   │   │   ├── RPGRepository.swift
│   │   │   ├── CompanionRepository.swift
│   │   │   └── KanjiGraphRepository.swift
│   │   ├── Services/
│   │   │   ├── FSRSService.swift
│   │   │   ├── PlannerService.swift
│   │   │   ├── AIRouterService.swift
│   │   │   ├── AIProviders/
│   │   │   │   ├── AIProvider.swift         # Protocol
│   │   │   │   ├── FoundationModelsProvider.swift
│   │   │   │   ├── GeminiProvider.swift
│   │   │   │   ├── ClaudeProvider.swift
│   │   │   │   └── LocalGPUProvider.swift
│   │   │   ├── WatchSyncService.swift
│   │   │   ├── ExportService.swift
│   │   │   ├── BackupService.swift
│   │   │   ├── AudioService.swift
│   │   │   ├── PronunciationService.swift
│   │   │   ├── HandwritingService.swift
│   │   │   ├── LeechDetectionService.swift
│   │   │   └── ContentLoadingService.swift
│   │   └── Utilities/
│   │       ├── Extensions/
│   │       ├── Loggers.swift
│   │       └── Constants.swift
│   └── Tests/
│       ├── Services/                       # FSRSServiceTests, PlannerServiceTests, etc.
│       ├── Repositories/                   # CardRepositoryTests, KanjiGraphTests, etc.
│       └── Models/                         # FSRSStateTests, RPGConstantsTests
├── Ikeru/                                  # iOS App Target
│   ├── App/
│   │   ├── IkeruApp.swift
│   │   ├── NavigationCoordinator.swift
│   │   └── AppConfiguration.swift
│   ├── ViewModels/
│   │   ├── Learning/                       # CardReview, KanjiStudy, Grammar, Writing,
│   │   │                                   # Listening, Speaking ViewModels
│   │   ├── CompanionChatViewModel.swift
│   │   ├── CheckInViewModel.swift
│   │   ├── RPGViewModel.swift
│   │   ├── DashboardViewModel.swift
│   │   ├── SessionViewModel.swift
│   │   ├── OnboardingViewModel.swift
│   │   └── SettingsViewModel.swift
│   ├── Views/
│   │   ├── Learning/
│   │   │   ├── CardReview/                 # CardReviewView, CardFront/Back, GradeButtons
│   │   │   ├── KanjiStudy/                 # KanjiDetail, RadicalDecomposition, Mnemonic, StrokeOrder
│   │   │   ├── Grammar/                    # GrammarLesson, FillInBlank
│   │   │   ├── Writing/                    # StrokeTracing, HandwritingCanvas, SentenceConstruction
│   │   │   ├── Listening/                  # AudioPlayer, Shadowing
│   │   │   └── Speaking/                   # Pronunciation, PitchAccent
│   │   ├── Companion/
│   │   │   ├── Chat/                       # CompanionChat, ChatBubble
│   │   │   └── CheckIn/                    # WeeklyCheckIn, ProgressSummary
│   │   ├── RPG/                            # RPGProfile, LootBoxOpen, LevelUp, Inventory
│   │   ├── Dashboard/                      # Dashboard, SkillBreakdown, JLPTProgress
│   │   ├── Session/                        # ActiveSession orchestrator
│   │   ├── Onboarding/                     # Onboarding, TourStep, NameEntry
│   │   ├── Settings/                       # Settings, ProfileManagement, Backup, Export, Attribution
│   │   └── Shared/
│   │       ├── Cards/                      # KanjiCard, VocabularyCard
│   │       ├── Buttons/                    # IkeruButtonStyles
│   │       ├── Progress/                   # XPBar, SkillRadar
│   │       ├── Feedback/                   # HapticFeedback
│   │       └── Theme/                      # IkeruTheme, IkeruColors
│   └── Resources/
│       ├── Assets.xcassets/
│       ├── Animations/                     # Lottie JSON files
│       └── ContentBundles/                 # SQLite per JLPT: n5-content.sqlite, etc.
├── IkeruWatch/                             # watchOS App Target
│   ├── App/IkeruWatchApp.swift
│   ├── Views/                              # KanaQuiz, AudioDrill, HapticPitch, WatchSession
│   ├── Complications/ProgressComplication.swift
│   └── Resources/Assets.xcassets/
├── IkeruWidget/                            # WidgetKit + Live Activities
│   ├── Widgets/                            # ProgressWidget, FlashcardWidget (StandBy)
│   └── LiveActivities/                     # StudySessionActivity, DynamicIslandView, LockScreenView
├── IkeruTests/                             # iOS App Tests
│   ├── ViewModels/                         # CardReviewVM, SessionVM, DashboardVM tests
│   └── UITests/                            # Onboarding, ReviewFlow UI tests
└── Ikeru.xcodeproj/
```

### Architectural Boundaries

**Data Boundaries:**
- `IkeruCore` owns ALL data access — app targets never touch SwiftData or SQLite directly
- Static content (SQLite bundles) accessed only via `ContentRepository`
- User data (SwiftData) accessed only via typed repositories
- Profile isolation enforced at `ModelContainer` level — switching profile = switching container

**Service Boundaries:**
- Services depend on repositories (never on each other directly)
- Exception: `PlannerService` depends on `FSRSService` + `LeechDetectionService` (composition)
- `AIRouterService` depends on `AIProvider` implementations (strategy pattern)
- ViewModels depend on services (never on repositories directly)

**Target Boundaries:**
- `IkeruCore`: pure Swift — no UIKit, no SwiftUI, no platform-specific imports
- `Ikeru` (iOS): imports `IkeruCore` + SwiftUI + platform frameworks
- `IkeruWatch`: imports `IkeruCore` + SwiftUI + WatchKit
- `IkeruWidget`: imports `IkeruCore` (subset) + WidgetKit + ActivityKit

**Communication Boundaries:**
- iOS ↔ Watch: exclusively via `WatchSyncService` (wraps WCSession)
- App ↔ Widget: via shared App Group container + ActivityKit
- App ↔ Local GPU: via `LocalGPUProvider` HTTP REST (Bonjour discovery)
- App ↔ Cloud AI: via `GeminiProvider` / `ClaudeProvider` HTTPS

### FR Category to Structure Mapping

| FR Category | IkeruCore Location | App Views Location |
|---|---|---|
| SRS Engine (FR1-6) | Services/FSRSService, Repositories/CardRepository, Models/SRS/ | Views/Learning/CardReview/ |
| Reading & Kanji (FR7-12) | Repositories/ContentRepository, KanjiGraphRepository, Models/Content/ | Views/Learning/KanjiStudy/, Grammar/ |
| Writing (FR13-16) | Services/HandwritingService | Views/Learning/Writing/ |
| Listening (FR17-19) | Services/AudioService | Views/Learning/Listening/ |
| Speaking (FR20-23) | Services/PronunciationService, AudioService | Views/Learning/Speaking/ |
| AI Companion (FR24-32) | Services/AIRouterService, AIProviders/, Repositories/CompanionRepository | Views/Companion/ |
| Planner (FR33-38) | Services/PlannerService | Views/Session/, Dashboard/ |
| RPG (FR39-44) | Repositories/RPGRepository, Models/RPG/ | Views/RPG/ |
| Profiles (FR45-49) | Repositories/ProfileRepository, Models/Profile/ | Views/Onboarding/, Settings/ |
| Watch (FR50-55) | Services/WatchSyncService | IkeruWatch/Views/ |
| Data & iOS (FR56-65) | Services/ExportService, BackupService, ContentLoadingService | IkeruWidget/, Views/Settings/ |

### Data Flow

```
User Input → View → ViewModel → Service → Repository → SwiftData/SQLite
                                    ↓
                              AIRouterService → [FoundationModels | Gemini | Claude | LocalGPU]
                                    ↓
                              PlannerService → Session Composition → View
```

## Architecture Validation Results

### Coherence Validation ✅

**Decision Compatibility:** All technology choices are Apple-native and fully compatible: SwiftData + SPM + @Observable + async/await + SwiftUI. No version conflicts. SwiftData with ModelActor handles the atomic write requirement. SQLite bundles for static content complement SwiftData's read-write role without conflict.

**Pattern Consistency:** MVVM + Repository + Service layer + DI via @Environment is consistently applied throughout. Naming conventions are Swift-idiomatic and uniform. No contradictions between patterns and decisions.

**Structure Alignment:** Feature-based project organization supports all decisions. `IkeruCore` as pure Swift package cleanly isolates business logic from platform-specific UI. Target boundaries respect the dependency graph.

### Requirements Coverage Validation ✅

**Functional Requirements:** 65/65 covered (100%). Every FR category has explicit architectural support with mapped source locations.

**Non-Functional Requirements:** 19/19 covered (100%). Performance (SwiftData + ModelActor, SQLite for static reads, sub-ms FSRS), Reliability (atomic writes, profile isolation, crash recovery), Integration (AI tier router, WatchConnectivity, CloudKit, ActivityKit).

### Implementation Readiness Validation ✅

- All critical decisions documented with technology choices and rationale
- 100+ files/directories explicitly defined in project tree
- 12 conflict points identified and resolved with patterns
- Anti-patterns explicitly forbidden with enforcement guidelines
- FR-to-structure mapping at 100% coverage

### Gap Analysis Results

**Critical Gaps:** None

**Important Gaps:**
- RTX 5090 local server needs separate documentation (out of scope for iOS architecture)
- App Group entitlement needed for Widget/Live Activity data access (add during implementation)

**Nice-to-Have Gaps:**
- SwiftLint rule configuration details (deferred to implementation)
- CoreML model selection for handwriting (pending technical validation spike)

### Architecture Completeness Checklist

- [x] Project context analyzed (65 FRs, 19 NFRs, high complexity)
- [x] Data architecture: SwiftData + SQLite bundles, 6 model groups, profile isolation
- [x] AI tier routing: 4-tier strategy with transparent fallback <2s
- [x] Communication: WatchConnectivity, CloudKit, Bonjour, HTTPS
- [x] Frontend: NavigationStack + @Observable + @Environment DI
- [x] Security: Keychain + .xcconfig + .gitignore for public repo
- [x] Naming conventions, structure patterns, communication patterns, process patterns
- [x] Complete directory tree, component boundaries, FR-to-structure mapping
- [x] Coherence, coverage, and readiness validated

### Architecture Readiness Assessment

**Overall Status:** READY FOR IMPLEMENTATION
**Confidence Level:** High

**Implementation Handoff — First Priorities:**
1. Create Xcode project with all 4 targets (iOS, watchOS, Widget, IkeruCore package)
2. Implement SwiftData models (SRS, Content, Profile, RPG, Companion)
3. Build FSRSService with card scheduling
4. Build KanjiGraphRepository with topological sort
