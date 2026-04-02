# Story 1.2: SwiftData Models and FSRS Engine

Status: draft

## Story

As a learner,
I want my learning progress tracked reliably with an intelligent scheduling algorithm,
so that I review cards at optimal intervals for 90% retention.

## Acceptance Criteria

1. UserProfile model exists with id, displayName, createdAt, settings — each profile owns all learning data via relationships
2. Card model exists with id, type (kanji/vocab/grammar/listening), FSRSState struct, easeFactor, interval, dueDate, lapseCount, leechFlag, responseHistory
3. ReviewLog model exists with timestamp, card relationship, grade, responseTimeMs
4. FSRSState is a lightweight Codable struct — no redundant computed fields
5. FSRS scheduling algorithm computes next review date in sub-millisecond per card
6. Card state mutations are atomic — no partial writes on crash (app crash, battery death, force quit)
7. All learning data is logged locally regardless of network state
8. Response times and accuracy are tracked per card per review
9. CardRepository provides CRUD + query operations (due cards, leech cards, cards by type)
10. Grade enum supports: again, hard, good, easy

## Tasks / Subtasks

- [ ] Task 1: Create SwiftData domain models (AC: #1, #2, #3, #4, #10)
  - [ ] Create IkeruCore/Sources/Models/SRS/Card.swift with @Model macro
  - [ ] Create IkeruCore/Sources/Models/SRS/FSRSState.swift as Codable struct (difficulty, stability, retrievability, lastReview, reps, lapses)
  - [ ] Create IkeruCore/Sources/Models/SRS/CardType.swift enum (kanji, vocabulary, grammar, listening) with String rawValue
  - [ ] Create IkeruCore/Sources/Models/SRS/Grade.swift enum (again, hard, good, easy) with Int rawValue
  - [ ] Create IkeruCore/Sources/Models/SRS/ReviewLog.swift with @Model macro
  - [ ] Create IkeruCore/Sources/Models/Profile/UserProfile.swift with @Model macro, relationship to cards
  - [ ] Create IkeruCore/Sources/Models/Profile/ProfileSettings.swift as Codable struct
  - [ ] Write unit tests for model initialization and Codable conformance

- [ ] Task 2: Implement FSRS scheduling algorithm (AC: #5)
  - [ ] Create IkeruCore/Sources/Services/FSRSService.swift
  - [ ] Implement FSRS-5 algorithm: schedule(card:grade:) → updated FSRSState with new dueDate
  - [ ] Parameters: w[] weights array (FSRS defaults), desired retention 0.9, maximum interval 36500
  - [ ] Core functions: stability after success, stability after failure, difficulty update, retrievability decay
  - [ ] Ensure pure function — no side effects, no database access, takes FSRSState + Grade → returns new FSRSState
  - [ ] Write comprehensive unit tests: verify scheduling for all 4 grades, verify sub-millisecond performance with 1000 cards, verify retention target convergence

- [ ] Task 3: Implement CardRepository (AC: #6, #7, #8, #9)
  - [ ] Create IkeruCore/Sources/Repositories/CardRepository.swift as @Observable class
  - [ ] Implement with ModelActor for thread-safe background operations
  - [ ] CRUD: create, read, update, delete cards
  - [ ] Query: dueCards(before: Date) → [Card], leechCards() → [Card], cards(byType: CardType) → [Card]
  - [ ] gradeCard(card:grade:responseTimeMs:) → atomically updates card FSRSState + creates ReviewLog
  - [ ] Atomic operations: use SwiftData transaction/autosave with proper error handling
  - [ ] Write unit tests with in-memory ModelContainer for: CRUD operations, due card queries, grade + review log creation, atomic guarantees

- [ ] Task 4: Integrate models into IkeruApp (AC: #1)
  - [ ] Update IkeruApp.swift to configure ModelContainer with UserProfile, Card, ReviewLog schemas
  - [ ] Pass ModelContainer to SwiftUI environment
  - [ ] Verify app still launches with SwiftData configured
  - [ ] Create a simple seed function that creates a default profile if none exists on first launch

## Dev Notes

### Architecture Compliance

- SwiftData models use @Model macro — NOT manual NSManagedObject
- FSRSService is a pure function service — no database access, no side effects
- CardRepository uses ModelActor for background thread safety
- All async operations use async/await — NEVER completion handlers
- @Observable for CardRepository — NEVER ObservableObject
- os.Logger.srs for all SRS-related logging

### FSRS Algorithm Reference

The FSRS (Free Spaced Repetition Scheduler) algorithm v5:
- Based on DSR (Difficulty, Stability, Retrievability) model
- Stability = expected time for retrievability to drop to 90%
- Key formulas:
  - R(t) = (1 + t/(9*S))^(-1) where t = days since last review, S = stability
  - New stability after success: S' = S * (e^(w[8]) * (11-D) * S^(-w[9]) * (e^(w[10]*(1-R))-1) * f_short_term + 1)
  - New stability after failure: S' = w[11] * D^(-w[12]) * ((S+1)^w[13] - 1) * e^(w[14]*(1-R))
  - Difficulty update: D' = w[7] * D_0(G) + (1-w[7]) * D_prev
- Reference implementation: https://github.com/open-spaced-repetition/fsrs-rs

### SwiftData Threading Model

- @Model objects are NOT Sendable — they're bound to their ModelContext's actor
- Use ModelActor for background operations
- For the repository pattern: CardRepository wraps a ModelActor that owns its ModelContext
- Main thread reads via @Query or @Environment(\.modelContext)
- Background writes via CardRepository's ModelActor

### Key Constraints

- FSRSState must be a Codable struct stored as transformable in SwiftData (NOT a separate @Model)
- Card.responseHistory should be stored as [ReviewLog] relationship, not inline array
- Profile isolation: each UserProfile has its own cards — query by profile relationship
- Sub-millisecond scheduling: FSRSService.schedule() must handle 1000 calls in under 1 second
- Atomic card grading: gradeCard() must update card state AND create ReviewLog in same transaction

### File Structure

```
IkeruCore/Sources/
├── Models/
│   ├── SRS/
│   │   ├── Card.swift
│   │   ├── FSRSState.swift
│   │   ├── CardType.swift
│   │   ├── Grade.swift
│   │   └── ReviewLog.swift
│   └── Profile/
│       ├── UserProfile.swift
│       └── ProfileSettings.swift
├── Repositories/
│   └── CardRepository.swift
└── Services/
    └── FSRSService.swift

IkeruCore/Tests/
├── Models/
│   └── SRS/
│       └── CardModelTests.swift
├── Services/
│   └── FSRSServiceTests.swift
└── Repositories/
    └── CardRepositoryTests.swift
```

### Previous Story Intelligence (Story 1.1)

- IkeruCore is a local SPM package at /IkeruCore with Package.swift
- IkeruTheme.swift is in IkeruCore/Sources/Theme/
- Loggers.swift is in IkeruCore/Sources/Utilities/ with Logger extensions (.srs, .ai, etc.)
- IkeruCore is pure Swift — @Model from SwiftData is fine (it's a Swift framework, not SwiftUI)
- The project uses project.yml with XcodeGen for project generation
- App entry point is at Ikeru/App/IkeruApp.swift

### References

- [Source: architecture.md#Data Architecture] — SwiftData models, 6 model groups, static/dynamic split
- [Source: architecture.md#Implementation Patterns] — @Observable, async/await, ModelActor
- [Source: prd.md#Functional Requirements] — FR1 (FSRS review), FR2 (knowledge graph ordering), FR5 (track response times), FR6 (log all activity)
- [Source: epics.md#Story 1.2] — Acceptance criteria

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List

### Change Log
