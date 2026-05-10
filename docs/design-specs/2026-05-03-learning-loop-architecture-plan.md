# Learning Loop Architecture — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current dual-CTA learning loop with a clear two-tab architecture (Home = adaptive recommendation, Étude = browse + custom planner), driven by a research-grounded `ExerciseUnlockService` and a unified `SessionPlanner` that composes 40/30/20/10 Home sessions and bespoke Study sessions.

**Architecture:** Pure services in `IkeruCore` (`ExerciseType`, `ExerciseUnlockService`, `SessionPlanner`, `RestDayDetector`) consumed by SwiftUI views in `Ikeru/`. The legacy `PlannerService.composeAdaptiveSession` is deprecated; existing `ExerciseItem` carries content payload while a parallel `ExerciseType` enum identifies *capability* for unlocks. RPG state grows an `acknowledgedUnlocks: Set<ExerciseType>` field.

**Tech Stack:** Swift 6 strict concurrency, Swift Testing (`@Test` / `#expect`), SwiftData (`@Model`), SwiftUI, Combine via `@Observable`.

**Spec:** `docs/design-specs/2026-05-03-learning-loop-architecture-design.md` (committed at `7cbe2ba`).

**Branch:** `design/wabi-refinements` (continuation — no new branch).

**Conventions:**
- All new core types live under `IkeruCore/Sources/...`; tests under `IkeruCore/Tests/...`.
- All new SwiftUI files must be registered with the Xcode project via `ruby scripts/add-to-xcodeproj.rb <path> Ikeru` after creation.
- After every task that adds Swift files: run `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5` to verify the app target still compiles.
- Commit message format: `<type>(<scope>): <summary>` — e.g., `feat(planner): add ExerciseType enum`.
- One commit per task minimum.

---

## File Structure

### New core files (under `IkeruCore/Sources/`)

| Path | Responsibility |
|---|---|
| `Models/Session/ExerciseType.swift` | The 12-case capability enum + skill mapping + estimated duration |
| `Services/ExerciseUnlock/ExerciseUnlockState.swift` | `ExerciseUnlockState` + `ExerciseLockReason` enums |
| `Services/ExerciseUnlock/ProfileSnapshot.swift` | Read-only aggregator the unlock service consumes |
| `Services/ExerciseUnlock/ExerciseUnlockService.swift` | Protocol + `DefaultExerciseUnlockService` |
| `Services/ExerciseUnlock/ProfileSnapshotBuilder.swift` | Builds `ProfileSnapshot` from real `RPGState` + `[CardDTO]` |
| `Services/ExerciseUnlock/UnlockBackfillService.swift` | First-launch backfill helper |
| `Services/SessionPlanner/SessionPlannerInputs.swift` | Inputs DTO for the planner |
| `Services/SessionPlanner/SessionPlanner.swift` | Protocol |
| `Services/SessionPlanner/DefaultSessionPlanner.swift` | Concrete implementation (Home + Study composition) |
| `Services/SessionPlanner/VarietyPoolResolver.swift` | Pure: maps JLPT level → eligible `ExerciseType` set |
| `Services/SessionPlanner/RestDayDetector.swift` | Pure: 4-condition rest-day evaluator |

### Modified core files

| Path | Change |
|---|---|
| `IkeruCore/Sources/Models/RPG/RPGState.swift` | Add `acknowledgedUnlocksData: Data?` field + `acknowledgedUnlocks: Set<ExerciseType>` accessor |
| `IkeruCore/Sources/Services/PlannerService.swift` | Mark `composeAdaptiveSession` `@available(*, deprecated, ...)` — kept compiling so non-session callsites (skill balance computation) still work |

### New SwiftUI files (under `Ikeru/Views/Learning/Etude/`)

| Path | Responsibility |
|---|---|
| `EtudeView.swift` | New Étude tab root: JLPT hero + Browse grid + Compose row |
| `ExerciseTypeTile.swift` | One tile cell — locked state with reason, unlocked tappable |
| `EtudeBrowseGrid.swift` | Grid container of all 11 tiles (Sakura excluded — lives in Chat) |
| `CustomPlannerSheet.swift` | The 編成 / Compose sheet with multi-select chips + duration + Compose CTA |
| `ExerciseTileTokens.swift` | Tatami chrome tokens (icons, kanji glyphs) for each `ExerciseType` |

### Modified SwiftUI files

| Path | Change |
|---|---|
| `Ikeru/Views/Home/HomeView.swift` | Replace `proverbHero` CTA with rest-day-aware variant; route to new `SessionPlanner` |
| `Ikeru/Views/Home/ProgressDashboardView.swift` | DELETED — replaced by `EtudeView` |
| `Ikeru/ViewModels/ProgressDashboardViewModel.swift` | Renamed → `EtudeViewModel.swift`, four-winds removed |
| `Ikeru/Views/RPG/RPGProfileView.swift` | Receive the four-winds skill-balance card |
| `Ikeru/Views/Settings/SettingsView.swift` | Add "Durée par défaut" picker row in the Pratique section |
| `Ikeru/ViewModels/SessionViewModel.swift` | Replace `PlannerService.composeAdaptiveSession` with `SessionPlanner.compose`; on `endSession` call `unlockService.newlyUnlocked` and grant 「新しい稽古」 badges |
| `Ikeru/ViewModels/HomeViewModel.swift` | Add `restDayActive: Bool` published property |
| `Ikeru/Views/MainTabView.swift` | Route Étude tab to `EtudeView` |
| `Ikeru/IkeruApp.swift` | First-launch backfill of `acknowledgedUnlocks` |
| `Ikeru/Localization/Localizable.xcstrings` | Add ~30 new keys (Étude tab labels, ExerciseType display names, lock reasons, rest-day copy) |
| `Ikeru.xcodeproj/project.pbxproj` | Auto-modified by `scripts/add-to-xcodeproj.rb` after each new file |

### Removed/Replaced

| Path | Why |
|---|---|
| `IkeruCore/Tests/Services/AdaptivePlannerTests.swift` | Tests an API replaced by `DefaultSessionPlannerTests.swift` |
| `IkeruCore/Tests/Services/AdaptivePlannerIntegrationTests.swift` | Same — integration is covered by the new SessionPlanner suite |
| `Ikeru/Views/Home/ProgressDashboardView.swift` | Replaced by `Ikeru/Views/Learning/Etude/EtudeView.swift` |

---

## Task Plan

### Task 1: Add `ExerciseType` enum + skill mapping + duration estimate

**Files:**
- Create: `IkeruCore/Sources/Models/Session/ExerciseType.swift`
- Test: `IkeruCore/Tests/Models/Session/ExerciseTypeTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// IkeruCore/Tests/Models/Session/ExerciseTypeTests.swift
import Testing
@testable import IkeruCore

@Suite("ExerciseType")
struct ExerciseTypeTests {

    @Test("All 12 cases are present")
    func twelveCases() {
        #expect(ExerciseType.allCases.count == 12)
    }

    @Test("Skill mapping respects spec")
    func skillMapping() {
        #expect(ExerciseType.kanaStudy.skill == .reading)
        #expect(ExerciseType.kanjiStudy.skill == .reading)
        #expect(ExerciseType.vocabularyStudy.skill == .reading)
        #expect(ExerciseType.fillInBlank.skill == .reading)
        #expect(ExerciseType.grammarExercise.skill == .reading)
        #expect(ExerciseType.readingPassage.skill == .reading)
        #expect(ExerciseType.writingPractice.skill == .writing)
        #expect(ExerciseType.sentenceConstruction.skill == .writing)
        #expect(ExerciseType.listeningSubtitled.skill == .listening)
        #expect(ExerciseType.listeningUnsubtitled.skill == .listening)
        #expect(ExerciseType.speakingPractice.skill == .speaking)
        #expect(ExerciseType.sakuraConversation.skill == .speaking)
    }

    @Test("Duration estimates are positive integers in seconds")
    func durations() {
        for type in ExerciseType.allCases {
            #expect(type.estimatedDurationSeconds > 0)
            #expect(type.estimatedDurationSeconds <= 240)
        }
    }
}
```

- [ ] **Step 2: Run the test — expect compile failure**

Run: `swift test --package-path IkeruCore --filter ExerciseTypeTests 2>&1 | tail -10`
Expected: compile error `cannot find 'ExerciseType' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// IkeruCore/Sources/Models/Session/ExerciseType.swift
import Foundation

/// Capability identifier for an exercise. Distinct from `ExerciseItem`
/// (which carries the content payload). Used by `ExerciseUnlockService`
/// and `SessionPlanner` to gate and select exercises by category.
public enum ExerciseType: String, Codable, CaseIterable, Sendable, Hashable {
    case kanaStudy
    case kanjiStudy
    case vocabularyStudy
    case listeningSubtitled
    case fillInBlank
    case grammarExercise
    case sentenceConstruction
    case readingPassage
    case writingPractice
    case listeningUnsubtitled
    case speakingPractice
    case sakuraConversation

    public var skill: SkillType {
        switch self {
        case .kanaStudy, .kanjiStudy, .vocabularyStudy,
             .fillInBlank, .grammarExercise, .readingPassage:
            .reading
        case .writingPractice, .sentenceConstruction:
            .writing
        case .listeningSubtitled, .listeningUnsubtitled:
            .listening
        case .speakingPractice, .sakuraConversation:
            .speaking
        }
    }

    public var estimatedDurationSeconds: Int {
        switch self {
        case .kanaStudy: 25
        case .kanjiStudy: 60
        case .vocabularyStudy: 30
        case .listeningSubtitled: 60
        case .fillInBlank: 20
        case .grammarExercise: 45
        case .sentenceConstruction: 60
        case .readingPassage: 120
        case .writingPractice: 90
        case .listeningUnsubtitled: 75
        case .speakingPractice: 90
        case .sakuraConversation: 180
        }
    }
}
```

- [ ] **Step 4: Run the test — expect pass**

Run: `swift test --package-path IkeruCore --filter ExerciseTypeTests 2>&1 | tail -10`
Expected: `✔ Test run with 3 tests in 1 suite passed`.

- [ ] **Step 5: Build the app**

Run: `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add IkeruCore/Sources/Models/Session/ExerciseType.swift IkeruCore/Tests/Models/Session/ExerciseTypeTests.swift
git commit -m "feat(planner): add ExerciseType enum (12 capability cases)"
```

---

### Task 2: Add `ExerciseUnlockState` + `ExerciseLockReason` enums

**Files:**
- Create: `IkeruCore/Sources/Services/ExerciseUnlock/ExerciseUnlockState.swift`

- [ ] **Step 1: Write the implementation directly (no behaviour to test on enums alone)**

```swift
// IkeruCore/Sources/Services/ExerciseUnlock/ExerciseUnlockState.swift
import Foundation

public enum ExerciseUnlockState: Sendable, Equatable {
    case unlocked
    case locked(reason: ExerciseLockReason)

    public var isUnlocked: Bool {
        if case .unlocked = self { return true }
        return false
    }
}

public enum ExerciseLockReason: Sendable, Equatable {
    case vocabularyMastered(required: Int, current: Int)
    case kanjiMastered(required: Int, current: Int)
    case kanaMastered(syllabary: KanaScript)
    case grammarPointsMastered(required: Int, current: Int)
    case listeningAccuracyOver(required: Double, current: Double, window: Int)
    case listeningRecallOver(required: Double, current: Double, days: Int)
    case jlptLevelReached(required: JLPTLevel, current: JLPTLevel)
}
```

- [ ] **Step 2: Build core**

Run: `swift build --package-path IkeruCore 2>&1 | tail -3`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add IkeruCore/Sources/Services/ExerciseUnlock/ExerciseUnlockState.swift
git commit -m "feat(unlock): add ExerciseUnlockState + ExerciseLockReason enums"
```

---

### Task 3: Add `ProfileSnapshot` value type

**Files:**
- Create: `IkeruCore/Sources/Services/ExerciseUnlock/ProfileSnapshot.swift`
- Test: `IkeruCore/Tests/Services/ExerciseUnlock/ProfileSnapshotTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// IkeruCore/Tests/Services/ExerciseUnlock/ProfileSnapshotTests.swift
import Testing
import Foundation
@testable import IkeruCore

@Suite("ProfileSnapshot")
struct ProfileSnapshotTests {

    @Test("Empty snapshot defaults to N5 + zero counts")
    func empty() {
        let s = ProfileSnapshot.empty
        #expect(s.jlptLevel == .n5)
        #expect(s.vocabularyMasteredFamiliarPlus == 0)
        #expect(s.kanjiMasteredFamiliarPlus == 0)
        #expect(s.hiraganaMastered == false)
        #expect(s.katakanaMastered == false)
        #expect(s.dueCardCount == 0)
    }

    @Test("Skill imbalance ratio uses (max - min) / max")
    func imbalance() {
        let s = ProfileSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: false,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [.reading: 80, .listening: 70, .writing: 65, .speaking: 68],
            dueCardCount: 0,
            hasNewContentQueued: false,
            lastSessionAt: nil
        )
        #expect(abs(s.skillImbalance - 0.1875) < 0.0001)
    }

    @Test("Skill imbalance is 0 when all balances are equal")
    func balanced() {
        let s = ProfileSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: false,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [.reading: 50, .listening: 50, .writing: 50, .speaking: 50],
            dueCardCount: 0,
            hasNewContentQueued: false,
            lastSessionAt: nil
        )
        #expect(s.skillImbalance == 0)
    }
}
```

- [ ] **Step 2: Run the test — expect compile failure**

Run: `swift test --package-path IkeruCore --filter ProfileSnapshotTests 2>&1 | tail -10`
Expected: `cannot find 'ProfileSnapshot' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// IkeruCore/Sources/Services/ExerciseUnlock/ProfileSnapshot.swift
import Foundation

public struct ProfileSnapshot: Sendable, Equatable {

    public let jlptLevel: JLPTLevel
    public let vocabularyMasteredFamiliarPlus: Int
    public let kanjiMasteredFamiliarPlus: Int
    public let hiraganaMastered: Bool
    public let katakanaMastered: Bool
    public let grammarPointsFamiliarPlus: Int
    public let listeningAccuracyLast30: Double
    public let listeningRecallLast30Days: Double
    public let skillBalances: [SkillType: Double]
    public let dueCardCount: Int
    public let hasNewContentQueued: Bool
    public let lastSessionAt: Date?

    public init(
        jlptLevel: JLPTLevel,
        vocabularyMasteredFamiliarPlus: Int,
        kanjiMasteredFamiliarPlus: Int,
        hiraganaMastered: Bool,
        katakanaMastered: Bool,
        grammarPointsFamiliarPlus: Int,
        listeningAccuracyLast30: Double,
        listeningRecallLast30Days: Double,
        skillBalances: [SkillType: Double],
        dueCardCount: Int,
        hasNewContentQueued: Bool,
        lastSessionAt: Date?
    ) {
        self.jlptLevel = jlptLevel
        self.vocabularyMasteredFamiliarPlus = vocabularyMasteredFamiliarPlus
        self.kanjiMasteredFamiliarPlus = kanjiMasteredFamiliarPlus
        self.hiraganaMastered = hiraganaMastered
        self.katakanaMastered = katakanaMastered
        self.grammarPointsFamiliarPlus = grammarPointsFamiliarPlus
        self.listeningAccuracyLast30 = listeningAccuracyLast30
        self.listeningRecallLast30Days = listeningRecallLast30Days
        self.skillBalances = skillBalances
        self.dueCardCount = dueCardCount
        self.hasNewContentQueued = hasNewContentQueued
        self.lastSessionAt = lastSessionAt
    }

    public var skillImbalance: Double {
        let values = skillBalances.values
        guard let maxV = values.max(), maxV > 0,
              let minV = values.min() else { return 0 }
        return (maxV - minV) / maxV
    }

    public static let empty = ProfileSnapshot(
        jlptLevel: .n5,
        vocabularyMasteredFamiliarPlus: 0,
        kanjiMasteredFamiliarPlus: 0,
        hiraganaMastered: false,
        katakanaMastered: false,
        grammarPointsFamiliarPlus: 0,
        listeningAccuracyLast30: 0,
        listeningRecallLast30Days: 0,
        skillBalances: [:],
        dueCardCount: 0,
        hasNewContentQueued: false,
        lastSessionAt: nil
    )
}
```

- [ ] **Step 4: Run the test — expect pass**

Run: `swift test --package-path IkeruCore --filter ProfileSnapshotTests 2>&1 | tail -10`
Expected: `✔ Test run with 3 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add IkeruCore/Sources/Services/ExerciseUnlock/ProfileSnapshot.swift IkeruCore/Tests/Services/ExerciseUnlock/ProfileSnapshotTests.swift
git commit -m "feat(unlock): add ProfileSnapshot value type with skillImbalance helper"
```

---

### Task 4: Add `ExerciseUnlockService` (12 unlock rules)

**Files:**
- Create: `IkeruCore/Sources/Services/ExerciseUnlock/ExerciseUnlockService.swift`
- Test: `IkeruCore/Tests/Services/ExerciseUnlock/ExerciseUnlockServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// IkeruCore/Tests/Services/ExerciseUnlock/ExerciseUnlockServiceTests.swift
import Testing
import Foundation
@testable import IkeruCore

@Suite("ExerciseUnlockService — research-grounded thresholds")
struct ExerciseUnlockServiceTests {

    private let service = DefaultExerciseUnlockService()

    @Test("kanaStudy is unlocked on a fresh profile")
    func dayOneKana() {
        #expect(service.state(for: .kanaStudy, profile: .empty) == .unlocked)
    }

    @Test("kanjiStudy / vocabularyStudy / listeningSubtitled are day-1 unlocked")
    func dayOneSet() {
        for type in [ExerciseType.kanjiStudy, .vocabularyStudy, .listeningSubtitled] {
            #expect(service.state(for: type, profile: .empty) == .unlocked, "type=\(type)")
        }
    }

    @Test("fillInBlank requires 50 vocab familiar+")
    func fillInBlankThreshold() {
        let below = ProfileSnapshot.empty.with(\.vocabularyMasteredFamiliarPlus, 49)
        let at = ProfileSnapshot.empty.with(\.vocabularyMasteredFamiliarPlus, 50)
        #expect(service.state(for: .fillInBlank, profile: below)
            == .locked(reason: .vocabularyMastered(required: 50, current: 49)))
        #expect(service.state(for: .fillInBlank, profile: at) == .unlocked)
    }

    @Test("grammarExercise locks until hiragana fully mastered")
    func grammarBlockedByKana() {
        var p = ProfileSnapshot.empty.with(\.hiraganaMastered, false)
        #expect(service.state(for: .grammarExercise, profile: p)
            == .locked(reason: .kanaMastered(syllabary: .hiragana)))
        p = p.with(\.hiraganaMastered, true)
        #expect(service.state(for: .grammarExercise, profile: p) == .unlocked)
    }

    @Test("readingPassage requires 100 vocab + 50 kanji")
    func readingPassageCompound() {
        var p = ProfileSnapshot.empty
            .with(\.vocabularyMasteredFamiliarPlus, 100)
            .with(\.kanjiMasteredFamiliarPlus, 49)
        #expect(service.state(for: .readingPassage, profile: p)
            == .locked(reason: .kanjiMastered(required: 50, current: 49)))
        p = p.with(\.kanjiMasteredFamiliarPlus, 50)
        #expect(service.state(for: .readingPassage, profile: p) == .unlocked)
    }

    @Test("writingPractice requires both kana scripts + 50 vocab")
    func writingPracticeCompound() {
        var p = ProfileSnapshot.empty
            .with(\.hiraganaMastered, true)
            .with(\.katakanaMastered, false)
            .with(\.vocabularyMasteredFamiliarPlus, 50)
        #expect(service.state(for: .writingPractice, profile: p)
            == .locked(reason: .kanaMastered(syllabary: .katakana)))
        p = p.with(\.katakanaMastered, true)
        #expect(service.state(for: .writingPractice, profile: p) == .unlocked)
    }

    @Test("listeningUnsubtitled requires 60 % accuracy over 30-window")
    func listeningUnsubtitled() {
        var p = ProfileSnapshot.empty.with(\.listeningAccuracyLast30, 0.59)
        #expect(service.state(for: .listeningUnsubtitled, profile: p)
            == .locked(reason: .listeningAccuracyOver(required: 0.6, current: 0.59, window: 30)))
        p = p.with(\.listeningAccuracyLast30, 0.6)
        #expect(service.state(for: .listeningUnsubtitled, profile: p) == .unlocked)
    }

    @Test("speakingPractice requires 60 % listening recall over 30 days")
    func speakingPractice() {
        var p = ProfileSnapshot.empty.with(\.listeningRecallLast30Days, 0.45)
        #expect(service.state(for: .speakingPractice, profile: p)
            == .locked(reason: .listeningRecallOver(required: 0.6, current: 0.45, days: 30)))
        p = p.with(\.listeningRecallLast30Days, 0.65)
        #expect(service.state(for: .speakingPractice, profile: p) == .unlocked)
    }

    @Test("sakuraConversation requires JLPT estimate ≥ N4")
    func sakuraConversation() {
        let n5 = ProfileSnapshot.empty.with(\.jlptLevel, .n5)
        #expect(service.state(for: .sakuraConversation, profile: n5)
            == .locked(reason: .jlptLevelReached(required: .n4, current: .n5)))
        let n4 = ProfileSnapshot.empty.with(\.jlptLevel, .n4)
        #expect(service.state(for: .sakuraConversation, profile: n4) == .unlocked)
    }

    @Test("newlyUnlocked returns only types crossed since `previous`")
    func deltaDetection() {
        let before = Set<ExerciseType>([.kanaStudy, .kanjiStudy, .vocabularyStudy, .listeningSubtitled])
        let p = ProfileSnapshot.empty
            .with(\.hiraganaMastered, true)
            .with(\.vocabularyMasteredFamiliarPlus, 50)
        let delta = service.newlyUnlocked(profile: p, previous: before)
        #expect(delta == [.fillInBlank, .grammarExercise])
    }

    @Test("unlockedTypes returns the full set on a maxed profile")
    func fullySet() {
        let p = ProfileSnapshot.empty
            .with(\.jlptLevel, .n1)
            .with(\.vocabularyMasteredFamiliarPlus, 1000)
            .with(\.kanjiMasteredFamiliarPlus, 1000)
            .with(\.hiraganaMastered, true)
            .with(\.katakanaMastered, true)
            .with(\.grammarPointsFamiliarPlus, 100)
            .with(\.listeningAccuracyLast30, 0.95)
            .with(\.listeningRecallLast30Days, 0.95)
        #expect(service.unlockedTypes(profile: p) == Set(ExerciseType.allCases))
    }
}

// Test-only mutation helper.
extension ProfileSnapshot {
    fileprivate func with<V>(_ keyPath: WritableKeyPath<MutableSnapshot, V>, _ value: V) -> ProfileSnapshot {
        var m = MutableSnapshot(self)
        m[keyPath: keyPath] = value
        return m.snapshot
    }

    fileprivate struct MutableSnapshot {
        var jlptLevel: JLPTLevel
        var vocabularyMasteredFamiliarPlus: Int
        var kanjiMasteredFamiliarPlus: Int
        var hiraganaMastered: Bool
        var katakanaMastered: Bool
        var grammarPointsFamiliarPlus: Int
        var listeningAccuracyLast30: Double
        var listeningRecallLast30Days: Double
        var skillBalances: [SkillType: Double]
        var dueCardCount: Int
        var hasNewContentQueued: Bool
        var lastSessionAt: Date?

        init(_ s: ProfileSnapshot) {
            jlptLevel = s.jlptLevel
            vocabularyMasteredFamiliarPlus = s.vocabularyMasteredFamiliarPlus
            kanjiMasteredFamiliarPlus = s.kanjiMasteredFamiliarPlus
            hiraganaMastered = s.hiraganaMastered
            katakanaMastered = s.katakanaMastered
            grammarPointsFamiliarPlus = s.grammarPointsFamiliarPlus
            listeningAccuracyLast30 = s.listeningAccuracyLast30
            listeningRecallLast30Days = s.listeningRecallLast30Days
            skillBalances = s.skillBalances
            dueCardCount = s.dueCardCount
            hasNewContentQueued = s.hasNewContentQueued
            lastSessionAt = s.lastSessionAt
        }

        var snapshot: ProfileSnapshot {
            ProfileSnapshot(
                jlptLevel: jlptLevel,
                vocabularyMasteredFamiliarPlus: vocabularyMasteredFamiliarPlus,
                kanjiMasteredFamiliarPlus: kanjiMasteredFamiliarPlus,
                hiraganaMastered: hiraganaMastered,
                katakanaMastered: katakanaMastered,
                grammarPointsFamiliarPlus: grammarPointsFamiliarPlus,
                listeningAccuracyLast30: listeningAccuracyLast30,
                listeningRecallLast30Days: listeningRecallLast30Days,
                skillBalances: skillBalances,
                dueCardCount: dueCardCount,
                hasNewContentQueued: hasNewContentQueued,
                lastSessionAt: lastSessionAt
            )
        }
    }
}
```

- [ ] **Step 2: Run the test — expect compile failure**

Run: `swift test --package-path IkeruCore --filter ExerciseUnlockServiceTests 2>&1 | tail -10`
Expected: `cannot find 'DefaultExerciseUnlockService' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// IkeruCore/Sources/Services/ExerciseUnlock/ExerciseUnlockService.swift
import Foundation

public protocol ExerciseUnlockService: Sendable {
    func state(for type: ExerciseType, profile: ProfileSnapshot) -> ExerciseUnlockState
    func unlockedTypes(profile: ProfileSnapshot) -> Set<ExerciseType>
    func newlyUnlocked(profile: ProfileSnapshot, previous: Set<ExerciseType>) -> Set<ExerciseType>
}

public struct DefaultExerciseUnlockService: ExerciseUnlockService {

    public static let fillInBlankVocabRequired = 50
    public static let sentenceConstructionGrammarRequired = 5
    public static let readingPassageVocabRequired = 100
    public static let readingPassageKanjiRequired = 50
    public static let writingPracticeVocabRequired = 50
    public static let listeningUnsubtitledAccuracyRequired = 0.6
    public static let listeningUnsubtitledWindow = 30
    public static let speakingRecallRequired = 0.6
    public static let speakingRecallWindowDays = 30
    public static let sakuraConversationMinJLPT: JLPTLevel = .n4

    public init() {}

    public func state(for type: ExerciseType, profile p: ProfileSnapshot) -> ExerciseUnlockState {
        switch type {
        case .kanaStudy, .kanjiStudy, .vocabularyStudy, .listeningSubtitled:
            return .unlocked

        case .fillInBlank:
            return p.vocabularyMasteredFamiliarPlus >= Self.fillInBlankVocabRequired
                ? .unlocked
                : .locked(reason: .vocabularyMastered(
                    required: Self.fillInBlankVocabRequired,
                    current: p.vocabularyMasteredFamiliarPlus))

        case .grammarExercise:
            return p.hiraganaMastered
                ? .unlocked
                : .locked(reason: .kanaMastered(syllabary: .hiragana))

        case .sentenceConstruction:
            return p.grammarPointsFamiliarPlus >= Self.sentenceConstructionGrammarRequired
                ? .unlocked
                : .locked(reason: .grammarPointsMastered(
                    required: Self.sentenceConstructionGrammarRequired,
                    current: p.grammarPointsFamiliarPlus))

        case .readingPassage:
            if p.vocabularyMasteredFamiliarPlus < Self.readingPassageVocabRequired {
                return .locked(reason: .vocabularyMastered(
                    required: Self.readingPassageVocabRequired,
                    current: p.vocabularyMasteredFamiliarPlus))
            }
            if p.kanjiMasteredFamiliarPlus < Self.readingPassageKanjiRequired {
                return .locked(reason: .kanjiMastered(
                    required: Self.readingPassageKanjiRequired,
                    current: p.kanjiMasteredFamiliarPlus))
            }
            return .unlocked

        case .writingPractice:
            if !p.hiraganaMastered {
                return .locked(reason: .kanaMastered(syllabary: .hiragana))
            }
            if !p.katakanaMastered {
                return .locked(reason: .kanaMastered(syllabary: .katakana))
            }
            if p.vocabularyMasteredFamiliarPlus < Self.writingPracticeVocabRequired {
                return .locked(reason: .vocabularyMastered(
                    required: Self.writingPracticeVocabRequired,
                    current: p.vocabularyMasteredFamiliarPlus))
            }
            return .unlocked

        case .listeningUnsubtitled:
            return p.listeningAccuracyLast30 >= Self.listeningUnsubtitledAccuracyRequired
                ? .unlocked
                : .locked(reason: .listeningAccuracyOver(
                    required: Self.listeningUnsubtitledAccuracyRequired,
                    current: p.listeningAccuracyLast30,
                    window: Self.listeningUnsubtitledWindow))

        case .speakingPractice:
            return p.listeningRecallLast30Days >= Self.speakingRecallRequired
                ? .unlocked
                : .locked(reason: .listeningRecallOver(
                    required: Self.speakingRecallRequired,
                    current: p.listeningRecallLast30Days,
                    days: Self.speakingRecallWindowDays))

        case .sakuraConversation:
            return p.jlptLevel >= Self.sakuraConversationMinJLPT
                ? .unlocked
                : .locked(reason: .jlptLevelReached(
                    required: Self.sakuraConversationMinJLPT,
                    current: p.jlptLevel))
        }
    }

    public func unlockedTypes(profile p: ProfileSnapshot) -> Set<ExerciseType> {
        Set(ExerciseType.allCases.filter { state(for: $0, profile: p).isUnlocked })
    }

    public func newlyUnlocked(profile p: ProfileSnapshot, previous: Set<ExerciseType>) -> Set<ExerciseType> {
        unlockedTypes(profile: p).subtracting(previous)
    }
}
```

- [ ] **Step 4: Run the test — expect pass**

Run: `swift test --package-path IkeruCore --filter ExerciseUnlockServiceTests 2>&1 | tail -10`
Expected: `✔ Test run with 11 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add IkeruCore/Sources/Services/ExerciseUnlock/ExerciseUnlockService.swift IkeruCore/Tests/Services/ExerciseUnlock/ExerciseUnlockServiceTests.swift
git commit -m "feat(unlock): research-grounded ExerciseUnlockService (12 rules)"
```

---

### Task 5: Add `ProfileSnapshotBuilder`

**Files:**
- Create: `IkeruCore/Sources/Services/ExerciseUnlock/ProfileSnapshotBuilder.swift`
- Test: `IkeruCore/Tests/Services/ExerciseUnlock/ProfileSnapshotBuilderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// IkeruCore/Tests/Services/ExerciseUnlock/ProfileSnapshotBuilderTests.swift
import Testing
import Foundation
@testable import IkeruCore

@Suite("ProfileSnapshotBuilder")
struct ProfileSnapshotBuilderTests {

    @Test("Builds vocab + kanji familiar+ counts from cards")
    func vocabKanjiCounts() {
        let cards = [
            fixture(type: .vocabulary, stability: 8.0, reps: 3),
            fixture(type: .vocabulary, stability: 0.5, reps: 1),
            fixture(type: .kanji, front: "\u{4E00}", stability: 30.0, reps: 5),
            fixture(type: .kanji, front: "\u{4E8C}", stability: 8.0, reps: 4),
        ]
        let s = ProfileSnapshotBuilder.build(
            cards: cards,
            jlptLevel: .n5,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            hasNewContentQueued: false,
            lastSessionAt: nil,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(s.vocabularyMasteredFamiliarPlus == 1)
        #expect(s.kanjiMasteredFamiliarPlus == 2)
    }

    @Test("Detects hiragana mastery when all 46 syllabary cards are familiar+")
    func hiraganaDetection() {
        let allHiragana = "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん"
        var cards: [CardDTO] = []
        for ch in allHiragana {
            cards.append(fixture(type: .kanji, front: String(ch), stability: 8.0, reps: 4))
        }
        #expect(cards.count == 46)

        let s = ProfileSnapshotBuilder.build(
            cards: cards, jlptLevel: .n5,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            hasNewContentQueued: false,
            lastSessionAt: nil,
            now: Date()
        )
        #expect(s.hiraganaMastered)
        #expect(s.katakanaMastered == false)
    }

    @Test("Counts due cards (dueDate <= now)")
    func dueCount() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cards = [
            fixture(type: .vocabulary, dueDate: now.addingTimeInterval(-3600)),
            fixture(type: .vocabulary, dueDate: now),
            fixture(type: .vocabulary, dueDate: now.addingTimeInterval(3600)),
        ]
        let s = ProfileSnapshotBuilder.build(
            cards: cards, jlptLevel: .n5,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            hasNewContentQueued: false,
            lastSessionAt: nil,
            now: now
        )
        #expect(s.dueCardCount == 2)
    }

    private func fixture(
        type: CardType,
        front: String = "x",
        stability: Double = 0,
        reps: Int = 0,
        dueDate: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> CardDTO {
        CardDTO(
            id: UUID(),
            type: type,
            front: front,
            back: "",
            dueDate: dueDate,
            fsrsState: FSRSState(
                stability: stability,
                difficulty: 5,
                reps: reps,
                lapses: 0,
                lastReview: Date(timeIntervalSince1970: 1_799_000_000)
            ),
            leechFlag: false,
            lapseCount: 0,
            interval: 1
        )
    }
}
```

> If `CardDTO`'s actual init differs, mirror it. Only `type`, `front`, `dueDate`, and `fsrsState` are read by the builder.

- [ ] **Step 2: Run the test — expect compile failure**

Run: `swift test --package-path IkeruCore --filter ProfileSnapshotBuilderTests 2>&1 | tail -10`
Expected: `cannot find 'ProfileSnapshotBuilder' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// IkeruCore/Sources/Services/ExerciseUnlock/ProfileSnapshotBuilder.swift
import Foundation

public enum ProfileSnapshotBuilder {

    public static let hiraganaRange: ClosedRange<UInt32> = 0x3042...0x3093
    public static let katakanaRange: ClosedRange<UInt32> = 0x30A2...0x30F3
    public static let kanaSyllabaryCount = 46

    public static func build(
        cards: [CardDTO],
        jlptLevel: JLPTLevel,
        grammarPointsFamiliarPlus: Int,
        listeningAccuracyLast30: Double,
        listeningRecallLast30Days: Double,
        skillBalances: [SkillType: Double],
        hasNewContentQueued: Bool,
        lastSessionAt: Date?,
        now: Date
    ) -> ProfileSnapshot {

        var vocab = 0
        var kanji = 0
        var hiraganaFamiliarFronts: Set<String> = []
        var katakanaFamiliarFronts: Set<String> = []
        var due = 0

        for card in cards {
            let mastery = MasteryLevel.from(fsrsState: card.fsrsState, now: now)
            let familiarPlus = mastery.rawValue >= MasteryLevel.familiar.rawValue

            if card.dueDate <= now { due += 1 }

            switch card.type {
            case .vocabulary:
                if familiarPlus { vocab += 1 }
            case .kanji:
                let firstScalar = card.front.unicodeScalars.first?.value ?? 0
                if hiraganaRange.contains(firstScalar) {
                    if familiarPlus { hiraganaFamiliarFronts.insert(card.front) }
                } else if katakanaRange.contains(firstScalar) {
                    if familiarPlus { katakanaFamiliarFronts.insert(card.front) }
                } else if familiarPlus {
                    kanji += 1
                }
            case .grammar, .listening:
                break
            }
        }

        return ProfileSnapshot(
            jlptLevel: jlptLevel,
            vocabularyMasteredFamiliarPlus: vocab,
            kanjiMasteredFamiliarPlus: kanji,
            hiraganaMastered: hiraganaFamiliarFronts.count >= kanaSyllabaryCount,
            katakanaMastered: katakanaFamiliarFronts.count >= kanaSyllabaryCount,
            grammarPointsFamiliarPlus: grammarPointsFamiliarPlus,
            listeningAccuracyLast30: listeningAccuracyLast30,
            listeningRecallLast30Days: listeningRecallLast30Days,
            skillBalances: skillBalances,
            dueCardCount: due,
            hasNewContentQueued: hasNewContentQueued,
            lastSessionAt: lastSessionAt
        )
    }
}
```

- [ ] **Step 4: Run the test — expect pass**

Run: `swift test --package-path IkeruCore --filter ProfileSnapshotBuilderTests 2>&1 | tail -10`
Expected: `✔ Test run with 3 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add IkeruCore/Sources/Services/ExerciseUnlock/ProfileSnapshotBuilder.swift IkeruCore/Tests/Services/ExerciseUnlock/ProfileSnapshotBuilderTests.swift
git commit -m "feat(unlock): ProfileSnapshotBuilder maps cards → snapshot"
```

---

### Task 6: Add `acknowledgedUnlocks` field to `RPGState`

**Files:**
- Modify: `IkeruCore/Sources/Models/RPG/RPGState.swift`
- Test: `IkeruCore/Tests/Models/RPG/RPGStateAcknowledgedUnlocksTests.swift`

- [ ] **Step 1: Locate the existing `equippedBadgeIDsData` pattern**

Run: `grep -nE "equippedBadgeIDsData|equippedBadgeIDs" IkeruCore/Sources/Models/RPG/RPGState.swift | head -5`
Expected: line numbers of the existing field + accessor pair.

- [ ] **Step 2: Write the failing test**

```swift
// IkeruCore/Tests/Models/RPG/RPGStateAcknowledgedUnlocksTests.swift
import Testing
import Foundation
@testable import IkeruCore

@Suite("RPGState.acknowledgedUnlocks")
struct RPGStateAcknowledgedUnlocksTests {

    @Test("Defaults to empty set when never set")
    func defaultEmpty() {
        let s = RPGState(profileID: UUID())
        #expect(s.acknowledgedUnlocks.isEmpty)
    }

    @Test("Round-trips a set through encoding")
    func roundTrip() {
        let s = RPGState(profileID: UUID())
        s.acknowledgedUnlocks = [.kanaStudy, .vocabularyStudy, .listeningSubtitled]
        #expect(s.acknowledgedUnlocks == [.kanaStudy, .vocabularyStudy, .listeningSubtitled])
    }
}
```

- [ ] **Step 3: Run the test — expect compile failure**

Run: `swift test --package-path IkeruCore --filter RPGStateAcknowledgedUnlocksTests 2>&1 | tail -10`
Expected: `value of type 'RPGState' has no member 'acknowledgedUnlocks'`.

- [ ] **Step 4: Add the field + accessors**

In `IkeruCore/Sources/Models/RPG/RPGState.swift`, after the `public var equippedBadgeIDsData: Data?` declaration, add:

```swift
    /// JSON-encoded `Set<ExerciseType>`. Tracks which types have already
    /// been awarded their one-time 「新しい稽古」 unlock badge so re-running
    /// the unlock service doesn't re-award them.
    public var acknowledgedUnlocksData: Data?
```

Then near the existing `equippedBadgeIDs` accessor, add:

```swift
    /// Decoded set of `ExerciseType` already acknowledged. Returns empty
    /// when no data stored.
    public var acknowledgedUnlocks: Set<ExerciseType> {
        get {
            guard let data = acknowledgedUnlocksData else { return [] }
            return (try? JSONDecoder().decode(Set<ExerciseType>.self, from: data)) ?? []
        }
        set {
            acknowledgedUnlocksData = try? JSONEncoder().encode(newValue)
        }
    }
```

- [ ] **Step 5: Run the test — expect pass**

Run: `swift test --package-path IkeruCore --filter RPGStateAcknowledgedUnlocksTests 2>&1 | tail -10`
Expected: `✔ Test run with 2 tests in 1 suite passed`.

- [ ] **Step 6: Build app to verify SwiftData migration is non-breaking**

Run: `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add IkeruCore/Sources/Models/RPG/RPGState.swift IkeruCore/Tests/Models/RPG/RPGStateAcknowledgedUnlocksTests.swift
git commit -m "feat(rpg): add RPGState.acknowledgedUnlocks (JSON-encoded Set<ExerciseType>)"
```

---

### Task 7: Add `defaultDurationMinutes` Settings UI

**Files:**
- Modify: `Ikeru/Views/Settings/SettingsView.swift`
- Modify: `Ikeru/Localization/Localizable.xcstrings`

- [ ] **Step 1: Add the `@AppStorage` declaration**

In `Ikeru/Views/Settings/SettingsView.swift` (near the other `@AppStorage` declarations around line 36), add:

```swift
    @AppStorage("ikeru.session.defaultDurationMinutes") private var defaultDurationMinutes = 15
```

- [ ] **Step 2: Add the picker row to the Pratique section**

Inside `practiceSection` (around line 215), insert above `settingRow(jp: "音声", ...)`:

```swift
            sessionDurationRow()
```

Add the helper near `inlineHourPicker`:

```swift
    private func sessionDurationRow() -> some View {
        HStack(spacing: 10) {
            Text("\u{6642}\u{9593}")
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(TatamiTokens.paperGhost)
            Text("Settings.SessionDuration")
                .font(.system(size: 13))
                .foregroundStyle(Color.ikeruTextPrimary)
            Spacer(minLength: 4)
            Menu {
                ForEach([5, 15, 30, 45], id: \.self) { minutes in
                    Button("\(minutes) min") { defaultDurationMinutes = minutes }
                }
            } label: {
                HStack(spacing: 3) {
                    Text("\(defaultDurationMinutes) min")
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                    Text("\u{25BE}")
                        .font(.system(size: 9))
                        .foregroundStyle(TatamiTokens.goldDim)
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TatamiTokens.goldDim.opacity(0.2))
                .frame(height: 1).padding(.horizontal, 16)
        }
    }
```

- [ ] **Step 3: Add the localization key**

Run:

```bash
python3 - <<'PY'
import json
p = "Ikeru/Localization/Localizable.xcstrings"
with open(p, "r", encoding="utf-8") as f:
    d = json.load(f)
d["strings"]["Settings.SessionDuration"] = {
    "extractionState": "manual",
    "localizations": {
        "en": {"stringUnit": {"state": "translated", "value": "Default session length"}},
        "fr": {"stringUnit": {"state": "translated", "value": "Durée par défaut"}},
    },
}
with open(p, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
    f.write("\n")
print("ok")
PY
```

- [ ] **Step 4: Build app**

Run: `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Ikeru/Views/Settings/SettingsView.swift Ikeru/Localization/Localizable.xcstrings
git commit -m "feat(settings): add default session length picker (5/15/30/45)"
```

---

### Task 8: Add `SessionPlannerInputs` value type

**Files:**
- Create: `IkeruCore/Sources/Services/SessionPlanner/SessionPlannerInputs.swift`

- [ ] **Step 1: Write the implementation**

```swift
// IkeruCore/Sources/Services/SessionPlanner/SessionPlannerInputs.swift
import Foundation

public struct SessionPlannerInputs: Sendable, Equatable {

    public enum Source: Sendable, Equatable {
        case homeRecommendation
        case studyCustom(types: Set<ExerciseType>, jlptLevels: Set<JLPTLevel>)
    }

    public let source: Source
    public let durationMinutes: Int
    public let profile: ProfileSnapshot
    public let unlockedTypes: Set<ExerciseType>
    public let availableCards: [CardDTO]

    public init(
        source: Source,
        durationMinutes: Int,
        profile: ProfileSnapshot,
        unlockedTypes: Set<ExerciseType>,
        availableCards: [CardDTO]
    ) {
        self.source = source
        self.durationMinutes = durationMinutes
        self.profile = profile
        self.unlockedTypes = unlockedTypes
        self.availableCards = availableCards
    }
}
```

- [ ] **Step 2: Build and commit**

Run: `swift build --package-path IkeruCore 2>&1 | tail -3`
Expected: build succeeds.

```bash
git add IkeruCore/Sources/Services/SessionPlanner/SessionPlannerInputs.swift
git commit -m "feat(planner): add SessionPlannerInputs DTO with Source enum"
```

---

### Task 9: Add `VarietyPoolResolver`

**Files:**
- Create: `IkeruCore/Sources/Services/SessionPlanner/VarietyPoolResolver.swift`
- Test: `IkeruCore/Tests/Services/SessionPlanner/VarietyPoolResolverTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// IkeruCore/Tests/Services/SessionPlanner/VarietyPoolResolverTests.swift
import Testing
@testable import IkeruCore

@Suite("VarietyPoolResolver")
struct VarietyPoolResolverTests {

    @Test("N5 pool: subtitled listening + fill-in-blank")
    func n5() {
        let pool = VarietyPoolResolver.pool(for: .n5)
        #expect(pool == [.listeningSubtitled, .fillInBlank])
    }

    @Test("N4 adds grammar + sentence construction")
    func n4() {
        let pool = VarietyPoolResolver.pool(for: .n4)
        #expect(pool.contains(.grammarExercise))
        #expect(pool.contains(.sentenceConstruction))
        #expect(pool.contains(.listeningSubtitled))
    }

    @Test("N1 contains all pool entries")
    func n1() {
        let pool = VarietyPoolResolver.pool(for: .n1)
        #expect(pool.contains(.speakingPractice))
        #expect(pool.contains(.sakuraConversation))
        #expect(pool.contains(.readingPassage))
    }

    @Test("Effective pool intersects with unlocked types")
    func intersects() {
        let resolved = VarietyPoolResolver.effectivePool(
            for: .n3,
            unlockedTypes: [.listeningSubtitled, .fillInBlank, .grammarExercise]
        )
        #expect(resolved == [.listeningSubtitled, .fillInBlank, .grammarExercise])
    }
}
```

- [ ] **Step 2: Run the test — expect compile failure**

Run: `swift test --package-path IkeruCore --filter VarietyPoolResolverTests 2>&1 | tail -10`
Expected: `cannot find 'VarietyPoolResolver' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// IkeruCore/Sources/Services/SessionPlanner/VarietyPoolResolver.swift
import Foundation

/// Pure: maps a learner's JLPT estimate to the eligible variety pool.
/// JLPT ordering is N5 < N4 < N3 < N2 < N1 (lower number = harder).
public enum VarietyPoolResolver {

    public static func pool(for level: JLPTLevel) -> Set<ExerciseType> {
        var result: Set<ExerciseType> = [.listeningSubtitled, .fillInBlank]
        if level >= .n4 {
            result.formUnion([.grammarExercise, .sentenceConstruction])
        }
        if level >= .n3 {
            result.formUnion([.readingPassage, .writingPractice, .listeningUnsubtitled])
        }
        if level >= .n2 {
            result.formUnion([.speakingPractice, .sakuraConversation])
        }
        return result
    }

    public static func effectivePool(
        for level: JLPTLevel,
        unlockedTypes: Set<ExerciseType>
    ) -> Set<ExerciseType> {
        pool(for: level).intersection(unlockedTypes)
    }
}
```

- [ ] **Step 4: Run the test — expect pass**

Run: `swift test --package-path IkeruCore --filter VarietyPoolResolverTests 2>&1 | tail -10`
Expected: `✔ Test run with 4 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add IkeruCore/Sources/Services/SessionPlanner/VarietyPoolResolver.swift IkeruCore/Tests/Services/SessionPlanner/VarietyPoolResolverTests.swift
git commit -m "feat(planner): VarietyPoolResolver maps JLPT level → eligible types"
```

---

### Task 10: Add `RestDayDetector`

**Files:**
- Create: `IkeruCore/Sources/Services/SessionPlanner/RestDayDetector.swift`
- Test: `IkeruCore/Tests/Services/SessionPlanner/RestDayDetectorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// IkeruCore/Tests/Services/SessionPlanner/RestDayDetectorTests.swift
import Testing
import Foundation
@testable import IkeruCore

@Suite("RestDayDetector")
struct RestDayDetectorTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("All four conditions met → rest day")
    func allConditions() {
        let p = ProfileSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: false,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [.reading: 50, .listening: 48, .writing: 47, .speaking: 49],
            dueCardCount: 4,
            hasNewContentQueued: false,
            lastSessionAt: now.addingTimeInterval(-3600)
        )
        #expect(RestDayDetector.shouldShowRestDay(profile: p, now: now))
    }

    @Test("Due cards >= 5 prevents rest day")
    func tooManyDue() {
        let p = ProfileSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: false,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [.reading: 50, .listening: 50, .writing: 50, .speaking: 50],
            dueCardCount: 5,
            hasNewContentQueued: false,
            lastSessionAt: now.addingTimeInterval(-3600)
        )
        #expect(RestDayDetector.shouldShowRestDay(profile: p, now: now) == false)
    }

    @Test("Imbalance > 15% prevents rest day")
    func skillImbalance() {
        let p = ProfileSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: false,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [.reading: 100, .listening: 80, .writing: 60, .speaking: 70],
            dueCardCount: 0,
            hasNewContentQueued: false,
            lastSessionAt: now.addingTimeInterval(-3600)
        )
        #expect(RestDayDetector.shouldShowRestDay(profile: p, now: now) == false)
    }

    @Test("Last session > 24h ago expires rest day")
    func expires() {
        let p = ProfileSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: false,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [.reading: 50, .listening: 50, .writing: 50, .speaking: 50],
            dueCardCount: 0,
            hasNewContentQueued: false,
            lastSessionAt: now.addingTimeInterval(-25 * 3600)
        )
        #expect(RestDayDetector.shouldShowRestDay(profile: p, now: now) == false)
    }

    @Test("New content queue blocks rest day")
    func newContent() {
        let p = ProfileSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: false,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [.reading: 50, .listening: 50, .writing: 50, .speaking: 50],
            dueCardCount: 0,
            hasNewContentQueued: true,
            lastSessionAt: now.addingTimeInterval(-3600)
        )
        #expect(RestDayDetector.shouldShowRestDay(profile: p, now: now) == false)
    }
}
```

- [ ] **Step 2: Run the test — expect compile failure**

Run: `swift test --package-path IkeruCore --filter RestDayDetectorTests 2>&1 | tail -10`
Expected: `cannot find 'RestDayDetector' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// IkeruCore/Sources/Services/SessionPlanner/RestDayDetector.swift
import Foundation

public enum RestDayDetector {

    public static let dueCardCeiling = 5
    public static let skillImbalanceCeiling = 0.15
    public static let inactivityHours = 24.0

    public static func shouldShowRestDay(profile: ProfileSnapshot, now: Date) -> Bool {
        guard profile.dueCardCount < dueCardCeiling else { return false }
        guard profile.skillImbalance <= skillImbalanceCeiling else { return false }
        guard profile.hasNewContentQueued == false else { return false }
        guard let last = profile.lastSessionAt else { return false }
        let hoursSinceLast = now.timeIntervalSince(last) / 3600
        return hoursSinceLast < inactivityHours
    }
}
```

- [ ] **Step 4: Run the test — expect pass**

Run: `swift test --package-path IkeruCore --filter RestDayDetectorTests 2>&1 | tail -10`
Expected: `✔ Test run with 5 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add IkeruCore/Sources/Services/SessionPlanner/RestDayDetector.swift IkeruCore/Tests/Services/SessionPlanner/RestDayDetectorTests.swift
git commit -m "feat(planner): RestDayDetector — 4-condition gate + 24h expiry"
```

---

### Task 11: Add `SessionPlanner` protocol

**Files:**
- Create: `IkeruCore/Sources/Services/SessionPlanner/SessionPlanner.swift`

- [ ] **Step 1: Write the implementation**

```swift
// IkeruCore/Sources/Services/SessionPlanner/SessionPlanner.swift
import Foundation

public protocol SessionPlanner: Sendable {
    func compose(inputs: SessionPlannerInputs) async -> SessionPlan
}
```

- [ ] **Step 2: Build and commit**

Run: `swift build --package-path IkeruCore 2>&1 | tail -3`

```bash
git add IkeruCore/Sources/Services/SessionPlanner/SessionPlanner.swift
git commit -m "feat(planner): add SessionPlanner protocol"
```

---

### Task 12: Implement `DefaultSessionPlanner` (Home + Study composition)

**Files:**
- Create: `IkeruCore/Sources/Services/SessionPlanner/DefaultSessionPlanner.swift`
- Test: `IkeruCore/Tests/Services/SessionPlanner/DefaultSessionPlannerTests.swift`

- [ ] **Step 1: Write the failing tests (Home + Study)**

```swift
// IkeruCore/Tests/Services/SessionPlanner/DefaultSessionPlannerTests.swift
import Testing
import Foundation
@testable import IkeruCore

@Suite("DefaultSessionPlanner — Home recommendation")
struct DefaultSessionPlannerHomeTests {

    private let planner = DefaultSessionPlanner()

    @Test("Home plan obeys ~40/30/20/10 segment split for 15 min")
    func segmentSplit() async {
        let cards = (0..<30).map { _ in fixtureDueCard() }
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 15,
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: cards
        )
        let plan = await planner.compose(inputs: inputs)

        let totalSec = plan.exercises.map(\.estimatedDurationSeconds).reduce(0, +)
        let reviewSec = plan.exercises
            .filter { if case .srsReview = $0 { return true }; return false }
            .map(\.estimatedDurationSeconds).reduce(0, +)

        #expect(totalSec >= 700 && totalSec <= 1100, "totalSec=\(totalSec)")
        let fraction = Double(reviewSec) / Double(totalSec)
        #expect(fraction >= 0.25 && fraction <= 0.55, "reviewFraction=\(fraction)")
    }

    @Test("N5 learner never gets speakingPractice in Home, even if unlocked")
    func n5VarietyPool() async {
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 15,
            profile: ProfileSnapshot.empty.withJLPT(.n5),
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: []
        )
        let plan = await planner.compose(inputs: inputs)
        let hasSpeaking = plan.exercises.contains {
            if case .speakingExercise = $0 { return true }
            return false
        }
        #expect(hasSpeaking == false)
    }

    private func fixtureDueCard() -> CardDTO {
        CardDTO(
            id: UUID(),
            type: .vocabulary,
            front: "x",
            back: "y",
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            fsrsState: FSRSState(stability: 5, difficulty: 5, reps: 1, lapses: 0, lastReview: nil),
            leechFlag: false,
            lapseCount: 0,
            interval: 1
        )
    }
}

@Suite("DefaultSessionPlanner — Study custom")
struct DefaultSessionPlannerStudyTests {

    private let planner = DefaultSessionPlanner()

    @Test("Study custom respects user-selected types only")
    func studyCustomRespectsTypes() async {
        let inputs = SessionPlannerInputs(
            source: .studyCustom(types: [.kanaStudy, .vocabularyStudy], jlptLevels: [.n5]),
            durationMinutes: 15,
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: []
        )
        let plan = await planner.compose(inputs: inputs)
        for ex in plan.exercises {
            switch ex {
            case .kanjiStudy, .vocabularyStudy: continue
            default:
                Issue.record("Unexpected exercise type: \(ex)")
            }
        }
        #expect(plan.exercises.count > 0)
    }

    @Test("Study custom drops types the user picked but isn't actually unlocked")
    func studyCustomFiltersToUnlocked() async {
        let inputs = SessionPlannerInputs(
            source: .studyCustom(types: [.kanaStudy, .speakingPractice], jlptLevels: [.n5]),
            durationMinutes: 15,
            profile: .empty,
            unlockedTypes: [.kanaStudy],
            availableCards: []
        )
        let plan = await planner.compose(inputs: inputs)
        for ex in plan.exercises {
            if case .speakingExercise = ex { Issue.record("speaking should be filtered out") }
        }
        #expect(plan.exercises.count > 0)
    }
}

extension ProfileSnapshot {
    fileprivate func withJLPT(_ level: JLPTLevel) -> ProfileSnapshot {
        ProfileSnapshot(
            jlptLevel: level,
            vocabularyMasteredFamiliarPlus: vocabularyMasteredFamiliarPlus,
            kanjiMasteredFamiliarPlus: kanjiMasteredFamiliarPlus,
            hiraganaMastered: hiraganaMastered,
            katakanaMastered: katakanaMastered,
            grammarPointsFamiliarPlus: grammarPointsFamiliarPlus,
            listeningAccuracyLast30: listeningAccuracyLast30,
            listeningRecallLast30Days: listeningRecallLast30Days,
            skillBalances: skillBalances,
            dueCardCount: dueCardCount,
            hasNewContentQueued: hasNewContentQueued,
            lastSessionAt: lastSessionAt
        )
    }
}
```

- [ ] **Step 2: Run the test — expect compile failure**

Run: `swift test --package-path IkeruCore --filter DefaultSessionPlanner 2>&1 | tail -10`
Expected: `cannot find 'DefaultSessionPlanner' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// IkeruCore/Sources/Services/SessionPlanner/DefaultSessionPlanner.swift
import Foundation
import os

extension Logger {
    static let learningLoop = Logger(subsystem: "com.ikeru.app", category: "learning-loop")
}

public struct DefaultSessionPlanner: SessionPlanner {

    public static let homeReviewFraction: Double = 0.40
    public static let homeSkillBalanceBoosterFraction: Double = 0.30
    public static let homeVarietyTileFraction: Double = 0.20
    public static let homeNewContentFraction: Double = 0.10

    public init() {}

    public func compose(inputs: SessionPlannerInputs) async -> SessionPlan {
        let plan: SessionPlan
        switch inputs.source {
        case .homeRecommendation:
            plan = composeHome(inputs: inputs)
        case .studyCustom(let types, let levels):
            plan = composeStudy(inputs: inputs, types: types, levels: levels)
        }
        Logger.learningLoop.info("session.composed source=\(String(describing: inputs.source)) duration=\(inputs.durationMinutes)")
        return plan
    }

    private func composeHome(inputs: SessionPlannerInputs) -> SessionPlan {
        let totalSec = inputs.durationMinutes * 60
        var exercises: [ExerciseItem] = []

        let reviewBudget = Int(Double(totalSec) * Self.homeReviewFraction)
        exercises.append(contentsOf: pickReviews(
            from: inputs.availableCards, secondsBudget: reviewBudget))

        let skillBoosterBudget = Int(Double(totalSec) * Self.homeSkillBalanceBoosterFraction)
        let lowestSkill = lowestSkill(in: inputs.profile.skillBalances)
        if let item = pickFirstFitting(
            forSkill: lowestSkill,
            inPool: VarietyPoolResolver.effectivePool(
                for: inputs.profile.jlptLevel,
                unlockedTypes: inputs.unlockedTypes),
            secondsBudget: skillBoosterBudget,
            availableCards: inputs.availableCards
        ) {
            exercises.append(item)
        }

        let varietyBudget = Int(Double(totalSec) * Self.homeVarietyTileFraction)
        let varietyPool = VarietyPoolResolver
            .effectivePool(for: inputs.profile.jlptLevel, unlockedTypes: inputs.unlockedTypes)
            .filter { $0.skill != lowestSkill }
        if let item = pickRotating(
            inPool: varietyPool,
            secondsBudget: varietyBudget,
            day: dayOfYear(),
            availableCards: inputs.availableCards
        ) {
            exercises.append(item)
        }

        let newContentBudget = Int(Double(totalSec) * Self.homeNewContentFraction)
        if let item = pickNewContent(
            secondsBudget: newContentBudget,
            availableCards: inputs.availableCards
        ) {
            exercises.append(item)
        }

        return finalize(exercises: exercises)
    }

    private func composeStudy(
        inputs: SessionPlannerInputs,
        types: Set<ExerciseType>,
        levels: Set<JLPTLevel>
    ) -> SessionPlan {
        let candidate = types.intersection(inputs.unlockedTypes)
        let totalSec = inputs.durationMinutes * 60
        var exercises: [ExerciseItem] = []
        var spent = 0

        let ordered = candidate.sorted { $0.skill.pedagogicalOrder < $1.skill.pedagogicalOrder }
        var idx = 0
        var safety = 0
        while spent < totalSec, safety < 100, !ordered.isEmpty {
            let type = ordered[idx % ordered.count]
            let item = synthesise(type: type, availableCards: inputs.availableCards)
            if spent + item.estimatedDurationSeconds > totalSec, !exercises.isEmpty { break }
            exercises.append(item)
            spent += item.estimatedDurationSeconds
            idx += 1
            safety += 1
        }
        _ = levels
        return finalize(exercises: exercises)
    }

    private func pickReviews(from cards: [CardDTO], secondsBudget: Int) -> [ExerciseItem] {
        var items: [ExerciseItem] = []
        var spent = 0
        for card in cards {
            let exercise = ExerciseItem.srsReview(card)
            if spent + exercise.estimatedDurationSeconds > secondsBudget { break }
            items.append(exercise)
            spent += exercise.estimatedDurationSeconds
        }
        return items
    }

    private func pickFirstFitting(
        forSkill skill: SkillType,
        inPool pool: Set<ExerciseType>,
        secondsBudget: Int,
        availableCards: [CardDTO]
    ) -> ExerciseItem? {
        let candidates = pool.filter { $0.skill == skill }
        for type in candidates.sorted(by: { $0.estimatedDurationSeconds < $1.estimatedDurationSeconds }) {
            let item = synthesise(type: type, availableCards: availableCards)
            if item.estimatedDurationSeconds <= secondsBudget { return item }
        }
        return nil
    }

    private func pickRotating(
        inPool pool: Set<ExerciseType>,
        secondsBudget: Int,
        day: Int,
        availableCards: [CardDTO]
    ) -> ExerciseItem? {
        guard !pool.isEmpty else { return nil }
        let sorted = pool.sorted { $0.rawValue < $1.rawValue }
        let type = sorted[day % sorted.count]
        let item = synthesise(type: type, availableCards: availableCards)
        return item.estimatedDurationSeconds <= secondsBudget ? item : nil
    }

    private func pickNewContent(secondsBudget: Int, availableCards: [CardDTO]) -> ExerciseItem? {
        if let card = availableCards.first(where: { $0.fsrsState.reps == 0 }) {
            let exercise = ExerciseItem.srsReview(card)
            return exercise.estimatedDurationSeconds <= secondsBudget ? exercise : nil
        }
        return nil
    }

    private func synthesise(type: ExerciseType, availableCards: [CardDTO]) -> ExerciseItem {
        switch type {
        case .kanaStudy, .kanjiStudy:
            let kanjiCards = availableCards.filter { $0.type == .kanji }
            return .kanjiStudy(kanjiCards.randomElement()?.front ?? "\u{4E00}")
        case .vocabularyStudy:
            return .vocabularyStudy(UUID())
        case .listeningSubtitled, .listeningUnsubtitled:
            return .listeningExercise(UUID())
        case .fillInBlank:
            return .fillInBlank(UUID())
        case .grammarExercise:
            return .grammarExercise(UUID())
        case .sentenceConstruction:
            return .sentenceConstruction(UUID())
        case .readingPassage:
            return .readingPassage(UUID())
        case .writingPractice:
            let kanjiCards = availableCards.filter { $0.type == .kanji }
            return .writingPractice(kanjiCards.randomElement()?.front ?? "\u{4E00}")
        case .speakingPractice, .sakuraConversation:
            return .speakingExercise(UUID())
        }
    }

    private func lowestSkill(in balances: [SkillType: Double]) -> SkillType {
        let sorted = SkillType.allCases.sorted { (balances[$0] ?? 0) < (balances[$1] ?? 0) }
        return sorted.first ?? .reading
    }

    private func dayOfYear(now: Date = Date()) -> Int {
        Calendar(identifier: .gregorian).ordinality(of: .day, in: .year, for: now) ?? 0
    }

    private func finalize(exercises: [ExerciseItem]) -> SessionPlan {
        let secs = exercises.map(\.estimatedDurationSeconds).reduce(0, +)
        var breakdown: [SkillType: Int] = [:]
        for ex in exercises { breakdown[ex.skill, default: 0] += 1 }
        return SessionPlan(
            exercises: exercises,
            estimatedDurationMinutes: max(0, secs / 60),
            exerciseBreakdown: breakdown
        )
    }
}
```

- [ ] **Step 4: Run the tests — expect 4 passes**

Run: `swift test --package-path IkeruCore --filter DefaultSessionPlanner 2>&1 | tail -10`
Expected: `✔ Test run with 4 tests in 2 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add IkeruCore/Sources/Services/SessionPlanner/DefaultSessionPlanner.swift IkeruCore/Tests/Services/SessionPlanner/DefaultSessionPlannerTests.swift
git commit -m "feat(planner): DefaultSessionPlanner (Home 40/30/20/10 + Study custom)"
```

---

### Task 13: Migrate `SessionViewModel` to `SessionPlanner`

**Files:**
- Modify: `Ikeru/ViewModels/SessionViewModel.swift`

- [ ] **Step 1: Locate the existing planner call site**

Run: `grep -nE "PlannerService|composeAdaptiveSession|composeSession" Ikeru/ViewModels/SessionViewModel.swift | head -10`
Expected: 1–4 lines.

- [ ] **Step 2: Replace dependencies**

Find the existing `private let plannerService:` declaration and replace with:

```swift
    private let sessionPlanner: any SessionPlanner
    private let unlockService: any ExerciseUnlockService
    @AppStorage("ikeru.session.defaultDurationMinutes") private var defaultDurationMinutes = 15
```

Update the initialiser. Example shape (preserve existing parameters not shown):

```swift
    init(
        cardRepository: CardRepository,
        modelContainer: ModelContainer,
        sessionPlanner: any SessionPlanner = DefaultSessionPlanner(),
        unlockService: any ExerciseUnlockService = DefaultExerciseUnlockService()
    ) {
        self.cardRepository = cardRepository
        self.modelContainer = modelContainer
        self.sessionPlanner = sessionPlanner
        self.unlockService = unlockService
    }
```

- [ ] **Step 3: Replace the planner invocation in `startSession()`**

Replace the existing call body (likely `plannerService.composeAdaptiveSession(config:)`) with:

```swift
        let cards = await cardRepository.allCards()
        let snapshot = await buildSnapshot(cards: cards)
        let unlockedTypes = unlockService.unlockedTypes(profile: snapshot)
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: defaultDurationMinutes,
            profile: snapshot,
            unlockedTypes: unlockedTypes,
            availableCards: cards
        )
        let plan = await sessionPlanner.compose(inputs: inputs)
        self.queue = plan.exercises
```

- [ ] **Step 4: Add `buildSnapshot` helper**

Add anywhere private inside the class:

```swift
    private func buildSnapshot(cards: [CardDTO]) async -> ProfileSnapshot {
        let now = Date()
        let progressService = ProgressService(cardRepository: cardRepository)
        let progress = await progressService.computeProgress()
        let jlptLevel = JLPTLevel(rawValue: progress.jlptEstimate.level.lowercased()) ?? .n5
        let lastSession = ActiveProfileResolver
            .fetchActiveRPGState(in: modelContainer.mainContext)?.lastSessionDate
        return ProfileSnapshotBuilder.build(
            cards: cards,
            jlptLevel: jlptLevel,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            hasNewContentQueued: cards.contains(where: { $0.fsrsState.reps == 0 }),
            lastSessionAt: lastSession,
            now: now
        )
    }
```

- [ ] **Step 5: Build app**

Run: `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **` (or precise error to fix iteratively).

- [ ] **Step 6: Commit**

```bash
git add Ikeru/ViewModels/SessionViewModel.swift
git commit -m "refactor(session): SessionViewModel uses SessionPlanner + UnlockService"
```

---

### Task 14: Wire 「新しい稽古」 badge granting on session end

**Files:**
- Modify: `Ikeru/ViewModels/SessionViewModel.swift`
- Modify: `Ikeru/Localization/Localizable.xcstrings`

- [ ] **Step 1: Add the localization key**

```bash
python3 - <<'PY'
import json
p = "Ikeru/Localization/Localizable.xcstrings"
with open(p, "r", encoding="utf-8") as f:
    d = json.load(f)
d["strings"]["Loot.NewExerciseUnlocked"] = {
    "extractionState": "manual",
    "localizations": {
        "en": {"stringUnit": {"state": "translated", "value": "New practice unlocked"}},
        "fr": {"stringUnit": {"state": "translated", "value": "Nouvelle pratique débloquée"}},
    },
}
with open(p, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
    f.write("\n")
print("ok")
PY
```

- [ ] **Step 2: Locate `endSession()`**

Run: `grep -nE "public func endSession" Ikeru/ViewModels/SessionViewModel.swift | head -3`
Expected: 1 line near 543.

- [ ] **Step 3: Append unlock-detection at the end of `endSession()`**

Just before the closing `}` of `endSession()`, add:

```swift
        Task { await processNewlyUnlocked() }
```

Then add the helper method elsewhere in the class:

```swift
    private func processNewlyUnlocked() async {
        let cards = await cardRepository.allCards()
        let snapshot = await buildSnapshot(cards: cards)
        let context = modelContainer.mainContext
        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else { return }
        let previous = state.acknowledgedUnlocks
        let delta = unlockService.newlyUnlocked(profile: snapshot, previous: previous)
        guard !delta.isEmpty else { return }
        for type in delta {
            let drop = LootItem(
                category: .badge,
                rarity: .rare,
                name: String(localized: "Loot.NewExerciseUnlocked"),
                iconName: "leaf.fill"
            )
            state.addLootItem(drop)
            Logger.rpg.info("unlock.granted type=\(type.rawValue)")
        }
        state.acknowledgedUnlocks = previous.union(delta)
        try? context.save()
    }
```

- [ ] **Step 4: Build app**

Run: `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Ikeru/ViewModels/SessionViewModel.swift Ikeru/Localization/Localizable.xcstrings
git commit -m "feat(session): grant 「新しい稽古」 badge per newly unlocked exercise type"
```

---

### Task 15: HomeViewModel publishes `restDayActive`

**Files:**
- Modify: `Ikeru/ViewModels/HomeViewModel.swift`

- [ ] **Step 1: Locate HomeViewModel surface**

Run: `grep -nE "@Observable|class HomeViewModel|public var dueCardCount|skillBalance" Ikeru/ViewModels/HomeViewModel.swift | head -10`

- [ ] **Step 2: Add `restDayActive` + `refreshRestDay`**

Add inside the class:

```swift
    private(set) var restDayActive: Bool = false

    public func refreshRestDay() async {
        let cards = await cardRepository.allCards()
        let context = modelContainer.mainContext
        let lastSession = ActiveProfileResolver.fetchActiveRPGState(in: context)?.lastSessionDate
        let balances: [SkillType: Double] = [
            .reading:   skillBalance.reading,
            .listening: skillBalance.listening,
            .writing:   skillBalance.writing,
            .speaking:  skillBalance.speaking,
        ]
        let snapshot = ProfileSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: false,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: balances,
            dueCardCount: cards.filter { $0.dueDate <= Date() }.count,
            hasNewContentQueued: cards.contains(where: { $0.fsrsState.reps == 0 }),
            lastSessionAt: lastSession
        )
        restDayActive = RestDayDetector.shouldShowRestDay(profile: snapshot, now: Date())
        Logger.rpg.info("restDay.\(restDayActive ? "shown" : "hidden")")
    }
```

> If `skillBalance`'s field names differ from `reading/listening/writing/speaking`, mirror its actual surface.

- [ ] **Step 3: Build app**

Run: `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Ikeru/ViewModels/HomeViewModel.swift
git commit -m "feat(home): HomeViewModel.restDayActive driven by RestDayDetector"
```

---

### Task 16: HomeView renders rest-day state

**Files:**
- Modify: `Ikeru/Views/Home/HomeView.swift`
- Modify: `Ikeru/Localization/Localizable.xcstrings`

- [ ] **Step 1: Locate the proverb hero CTA**

Run: `grep -nE "稽古を始める|COMMENCER|BEGIN PRACTICE" Ikeru/Views/Home/HomeView.swift | head -5`

- [ ] **Step 2: Wrap the gold CTA in a conditional**

Replace the gold "COMMENCER" Button block with:

```swift
            if vm.restDayActive {
                restDayBlock
            } else {
                Button {
                    startSession()
                } label: {
                    HStack {
                        Spacer()
                        Text("\u{7A3D}\u{53E4}\u{3092}\u{59CB}\u{3081}\u{308B}\u{30FB} ")
                            .font(.system(size: 13, weight: .regular, design: .serif))
                        Text("BEGIN PRACTICE", comment: "Hero CTA on Home")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(1.6)
                        Spacer()
                    }
                    .foregroundStyle(Color.ikeruBackground)
                    .padding(.vertical, 14)
                    .background(Color.ikeruPrimaryAccent)
                    .sumiCorners(color: Color.ikeruBackground.opacity(0.6),
                                 size: 6, weight: 1.2, inset: -1)
                }
                .buttonStyle(.plain)
            }
```

Add the rest-day block as a private property:

```swift
    private var restDayBlock: some View {
        VStack(spacing: 6) {
            Text("\u{4ECA}\u{65E5}\u{306F}\u{4F11}")
                .font(.system(size: 26, design: .serif))
                .foregroundStyle(Color.ikeruPrimaryAccent)
            Text("Home.RestDay.Title", comment: "Rest day chrome label")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Color.ikeruTextSecondary)
            Text("Home.RestDay.Body", comment: "Rest day body copy")
                .font(.system(size: 11))
                .italic()
                .foregroundStyle(TatamiTokens.paperGhost)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
    }
```

In the body's `.task` block, add:

```swift
        .task {
            await vm.refreshRestDay()
        }
```

- [ ] **Step 3: Add localization**

```bash
python3 - <<'PY'
import json
p = "Ikeru/Localization/Localizable.xcstrings"
with open(p, "r", encoding="utf-8") as f:
    d = json.load(f)
d["strings"]["Home.RestDay.Title"] = {
    "extractionState": "manual",
    "localizations": {
        "en": {"stringUnit": {"state": "translated", "value": "REST DAY"}},
        "fr": {"stringUnit": {"state": "translated", "value": "JOUR DE REPOS"}},
    },
}
d["strings"]["Home.RestDay.Body"] = {
    "extractionState": "manual",
    "localizations": {
        "en": {"stringUnit": {"state": "translated", "value": "You're balanced and reviews are clear. Honor the rest."}},
        "fr": {"stringUnit": {"state": "translated", "value": "Tu es équilibré et tes révisions sont à jour. Honore le repos."}},
    },
}
with open(p, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
    f.write("\n")
print("ok")
PY
```

- [ ] **Step 4: Build app**

Run: `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Ikeru/Views/Home/HomeView.swift Ikeru/Localization/Localizable.xcstrings
git commit -m "feat(home): rest-day state replaces CTA when conditions hold"
```

---

### Task 17: Add `ExerciseTileTokens`

**Files:**
- Create: `Ikeru/Views/Learning/Etude/ExerciseTileTokens.swift`
- Modify: `Ikeru/Localization/Localizable.xcstrings`

- [ ] **Step 1: Write the implementation**

```swift
// Ikeru/Views/Learning/Etude/ExerciseTileTokens.swift
import SwiftUI
import IkeruCore

enum ExerciseTileTokens {

    static func glyph(for type: ExerciseType) -> String {
        switch type {
        case .kanaStudy:            return "\u{30A2}" // ア
        case .kanjiStudy:           return "\u{6F22}" // 漢
        case .vocabularyStudy:      return "\u{8A9E}" // 語
        case .listeningSubtitled:   return "\u{8033}" // 耳
        case .fillInBlank:          return "\u{7A7A}" // 空
        case .grammarExercise:      return "\u{6587}" // 文
        case .sentenceConstruction: return "\u{7D44}" // 組
        case .readingPassage:       return "\u{8AAD}" // 読
        case .writingPractice:      return "\u{66F8}" // 書
        case .listeningUnsubtitled: return "\u{97F3}" // 音
        case .speakingPractice:     return "\u{53E3}" // 口
        case .sakuraConversation:   return "\u{6843}" // 桜
        }
    }

    static func label(for type: ExerciseType) -> LocalizedStringKey {
        switch type {
        case .kanaStudy:            return "Etude.Type.Kana"
        case .kanjiStudy:           return "Etude.Type.Kanji"
        case .vocabularyStudy:      return "Etude.Type.Vocabulary"
        case .listeningSubtitled:   return "Etude.Type.ListeningSub"
        case .fillInBlank:          return "Etude.Type.FillInBlank"
        case .grammarExercise:      return "Etude.Type.Grammar"
        case .sentenceConstruction: return "Etude.Type.Sentence"
        case .readingPassage:       return "Etude.Type.Reading"
        case .writingPractice:      return "Etude.Type.Writing"
        case .listeningUnsubtitled: return "Etude.Type.ListeningUnsub"
        case .speakingPractice:     return "Etude.Type.Speaking"
        case .sakuraConversation:   return "Etude.Type.Sakura"
        }
    }
}
```

- [ ] **Step 2: Register file**

```bash
ruby scripts/add-to-xcodeproj.rb Ikeru/Views/Learning/Etude/ExerciseTileTokens.swift Ikeru
```

- [ ] **Step 3: Add localization keys**

```bash
python3 - <<'PY'
import json
p = "Ikeru/Localization/Localizable.xcstrings"
keys = {
    "Etude.Type.Kana":          ("Kana",         "Kana"),
    "Etude.Type.Kanji":         ("Kanji",        "Kanji"),
    "Etude.Type.Vocabulary":    ("Vocabulary",   "Vocabulaire"),
    "Etude.Type.ListeningSub":  ("Subtitled listening", "Écoute sous-titrée"),
    "Etude.Type.FillInBlank":   ("Fill in blank","Remplir le vide"),
    "Etude.Type.Grammar":       ("Grammar",      "Grammaire"),
    "Etude.Type.Sentence":      ("Sentence build","Construction de phrase"),
    "Etude.Type.Reading":       ("Reading",      "Lecture"),
    "Etude.Type.Writing":       ("Writing",      "Écriture"),
    "Etude.Type.ListeningUnsub":("Listening",    "Écoute"),
    "Etude.Type.Speaking":      ("Speaking",     "Parole"),
    "Etude.Type.Sakura":        ("Sakura",       "Sakura"),
}
with open(p, "r", encoding="utf-8") as f:
    d = json.load(f)
for k, (en, fr) in keys.items():
    d["strings"][k] = {
        "extractionState": "manual",
        "localizations": {
            "en": {"stringUnit": {"state": "translated", "value": en}},
            "fr": {"stringUnit": {"state": "translated", "value": fr}},
        },
    }
with open(p, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
    f.write("\n")
print("added", len(keys))
PY
```

- [ ] **Step 4: Build app**

Run: `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Ikeru/Views/Learning/Etude/ExerciseTileTokens.swift Ikeru/Localization/Localizable.xcstrings Ikeru.xcodeproj/project.pbxproj
git commit -m "feat(etude): ExerciseTileTokens — kanji glyph + label per ExerciseType"
```

---

### Task 18: Add `ExerciseTypeTile` view

**Files:**
- Create: `Ikeru/Views/Learning/Etude/ExerciseTypeTile.swift`
- Modify: `Ikeru/Localization/Localizable.xcstrings`

- [ ] **Step 1: Write the implementation**

```swift
// Ikeru/Views/Learning/Etude/ExerciseTypeTile.swift
import SwiftUI
import IkeruCore

struct ExerciseTypeTile: View {

    let type: ExerciseType
    let state: ExerciseUnlockState
    let onTap: () -> Void

    private var isUnlocked: Bool { state.isUnlocked }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(ExerciseTileTokens.glyph(for: type))
                    .font(.system(size: 32, weight: .light, design: .serif))
                    .foregroundStyle(isUnlocked ? Color.ikeruPrimaryAccent : TatamiTokens.paperGhost)
                Text(ExerciseTileTokens.label(for: type))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isUnlocked ? Color.ikeruTextPrimary : Color.ikeruTextSecondary)
                if !isUnlocked, case .locked(let reason) = state {
                    Text(lockHint(reason))
                        .font(.system(size: 10))
                        .italic()
                        .foregroundStyle(TatamiTokens.paperGhost)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white.opacity(isUnlocked ? 0.04 : 0.02))
            .overlay(Rectangle().strokeBorder(
                isUnlocked ? TatamiTokens.goldDim : TatamiTokens.goldDim.opacity(0.3),
                lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
    }

    private func lockHint(_ reason: ExerciseLockReason) -> String {
        switch reason {
        case .vocabularyMastered(let req, let cur):
            return String(localized: "Etude.Lock.Vocab \(cur) \(req)")
        case .kanjiMastered(let req, let cur):
            return String(localized: "Etude.Lock.Kanji \(cur) \(req)")
        case .kanaMastered(let script):
            return script == .hiragana
                ? String(localized: "Etude.Lock.Hiragana")
                : String(localized: "Etude.Lock.Katakana")
        case .grammarPointsMastered(let req, let cur):
            return String(localized: "Etude.Lock.Grammar \(cur) \(req)")
        case .listeningAccuracyOver(let req, _, let win):
            return String(localized: "Etude.Lock.ListenAccuracy \(Int(req * 100)) \(win)")
        case .listeningRecallOver(let req, _, let days):
            return String(localized: "Etude.Lock.ListenRecall \(Int(req * 100)) \(days)")
        case .jlptLevelReached(let req, _):
            return String(localized: "Etude.Lock.JLPT \(req.displayLabel)")
        }
    }
}
```

- [ ] **Step 2: Register file**

```bash
ruby scripts/add-to-xcodeproj.rb Ikeru/Views/Learning/Etude/ExerciseTypeTile.swift Ikeru
```

- [ ] **Step 3: Add lock-hint localization keys**

```bash
python3 - <<'PY'
import json
p = "Ikeru/Localization/Localizable.xcstrings"
keys = {
    "Etude.Lock.Vocab":          ("%lld / %lld vocab to unlock",  "%lld / %lld mots pour débloquer"),
    "Etude.Lock.Kanji":          ("%lld / %lld kanji to unlock",  "%lld / %lld kanji pour débloquer"),
    "Etude.Lock.Hiragana":       ("Master hiragana to unlock",     "Maîtrise les hiragana pour débloquer"),
    "Etude.Lock.Katakana":       ("Master katakana to unlock",     "Maîtrise les katakana pour débloquer"),
    "Etude.Lock.Grammar":        ("%lld / %lld grammar to unlock", "%lld / %lld points de grammaire pour débloquer"),
    "Etude.Lock.ListenAccuracy": ("%lld%% on last %lld listens",   "%lld%% sur %lld dernières écoutes"),
    "Etude.Lock.ListenRecall":   ("%lld%% recall over %lld days",  "%lld%% de rappel sur %lld jours"),
    "Etude.Lock.JLPT":           ("Reach %@ to unlock",            "Atteins %@ pour débloquer"),
}
with open(p, "r", encoding="utf-8") as f:
    d = json.load(f)
for k, (en, fr) in keys.items():
    d["strings"][k] = {
        "extractionState": "manual",
        "localizations": {
            "en": {"stringUnit": {"state": "translated", "value": en}},
            "fr": {"stringUnit": {"state": "translated", "value": fr}},
        },
    }
with open(p, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
    f.write("\n")
print("added", len(keys))
PY
```

- [ ] **Step 4: Build app**

Run: `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Ikeru/Views/Learning/Etude/ExerciseTypeTile.swift Ikeru/Localization/Localizable.xcstrings Ikeru.xcodeproj/project.pbxproj
git commit -m "feat(etude): ExerciseTypeTile — locked / unlocked states with progress hint"
```

---

### Task 19: Add `EtudeBrowseGrid`

**Files:**
- Create: `Ikeru/Views/Learning/Etude/EtudeBrowseGrid.swift`

- [ ] **Step 1: Write the implementation**

```swift
// Ikeru/Views/Learning/Etude/EtudeBrowseGrid.swift
import SwiftUI
import IkeruCore

struct EtudeBrowseGrid: View {

    let snapshot: ProfileSnapshot
    let unlockService: any ExerciseUnlockService
    let onTap: (ExerciseType) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ExerciseType.allCases.filter { $0 != .sakuraConversation }, id: \.self) { type in
                let state = unlockService.state(for: type, profile: snapshot)
                ExerciseTypeTile(type: type, state: state, onTap: { onTap(type) })
            }
        }
    }
}
```

- [ ] **Step 2: Register file**

```bash
ruby scripts/add-to-xcodeproj.rb Ikeru/Views/Learning/Etude/EtudeBrowseGrid.swift Ikeru
```

- [ ] **Step 3: Build app**

Run: `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Ikeru/Views/Learning/Etude/EtudeBrowseGrid.swift Ikeru.xcodeproj/project.pbxproj
git commit -m "feat(etude): EtudeBrowseGrid — 2-col layout, sakura excluded (lives in Chat)"
```

---

### Task 20: Add `CustomPlannerSheet`

**Files:**
- Create: `Ikeru/Views/Learning/Etude/CustomPlannerSheet.swift`
- Modify: `Ikeru/Localization/Localizable.xcstrings`

- [ ] **Step 1: Write the implementation**

```swift
// Ikeru/Views/Learning/Etude/CustomPlannerSheet.swift
import SwiftUI
import IkeruCore

struct CustomPlannerSheet: View {

    let unlockedTypes: Set<ExerciseType>
    let onCompose: (Set<ExerciseType>, Set<JLPTLevel>, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("ikeru.session.defaultDurationMinutes") private var initialDuration = 15
    @AppStorage("ikeru.etude.lastTypes") private var lastTypesData: Data = .init()
    @AppStorage("ikeru.etude.lastLevels") private var lastLevelsData: Data = .init()

    @State private var selectedTypes: Set<ExerciseType> = []
    @State private var selectedLevels: Set<JLPTLevel> = [.n5]
    @State private var duration: Int = 15

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    sectionTypes
                    sectionLevels
                    sectionDuration
                    composeButton
                }
                .padding(20)
            }
            .background(Color.ikeruBackground.ignoresSafeArea())
            .navigationTitle(Text("Etude.Compose.Title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Etude.Compose.Cancel") { dismiss() }
                }
            }
            .onAppear {
                duration = initialDuration
                if let restored = try? JSONDecoder().decode(Set<ExerciseType>.self, from: lastTypesData),
                   !restored.isEmpty {
                    selectedTypes = restored.intersection(unlockedTypes)
                }
                if let restored = try? JSONDecoder().decode(Set<JLPTLevel>.self, from: lastLevelsData),
                   !restored.isEmpty {
                    selectedLevels = restored
                }
            }
        }
    }

    private var sectionTypes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Etude.Compose.Types")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ikeruTextSecondary)
            FlowChips(items: ExerciseType.allCases.filter { unlockedTypes.contains($0) }) { type in
                ChipButton(
                    label: ExerciseTileTokens.label(for: type),
                    isSelected: selectedTypes.contains(type)
                ) {
                    if selectedTypes.contains(type) { selectedTypes.remove(type) }
                    else { selectedTypes.insert(type) }
                }
            }
        }
    }

    private var sectionLevels: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Etude.Compose.Levels")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ikeruTextSecondary)
            FlowChips(items: JLPTLevel.allCases) { level in
                ChipButton(
                    label: LocalizedStringKey(level.displayLabel),
                    isSelected: selectedLevels.contains(level)
                ) {
                    if selectedLevels.contains(level) { selectedLevels.remove(level) }
                    else { selectedLevels.insert(level) }
                }
            }
        }
    }

    private var sectionDuration: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Etude.Compose.Duration")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ikeruTextSecondary)
            Picker("", selection: $duration) {
                ForEach([5, 15, 30, 45], id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var composeButton: some View {
        Button {
            lastTypesData = (try? JSONEncoder().encode(selectedTypes)) ?? .init()
            lastLevelsData = (try? JSONEncoder().encode(selectedLevels)) ?? .init()
            onCompose(selectedTypes, selectedLevels, duration)
            dismiss()
        } label: {
            HStack {
                Spacer()
                Text("Etude.Compose.Action")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.6)
                Spacer()
            }
            .foregroundStyle(Color.ikeruBackground)
            .padding(.vertical, 14)
            .background(canCompose
                        ? Color.ikeruPrimaryAccent
                        : Color.ikeruPrimaryAccent.opacity(0.35))
        }
        .buttonStyle(.plain)
        .disabled(!canCompose)
    }

    private var canCompose: Bool {
        !selectedTypes.isEmpty && !selectedLevels.isEmpty
    }
}

private struct FlowChips<Item: Hashable, Cell: View>: View {
    let items: [Item]
    let cell: (Item) -> Cell
    init(items: [Item], @ViewBuilder cell: @escaping (Item) -> Cell) {
        self.items = items
        self.cell = cell
    }
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { cell($0) }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if rowWidth + s.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = s.width + spacing
                rowHeight = s.height
            } else {
                rowWidth += s.width + spacing
                rowHeight = max(rowHeight, s.height)
            }
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        let maxX = bounds.maxX
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y),
                      proposal: ProposedViewSize(width: s.width, height: s.height))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

private struct ChipButton: View {
    let label: LocalizedStringKey
    let isSelected: Bool
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.ikeruBackground : Color.ikeruTextPrimary)
                .background(isSelected ? Color.ikeruPrimaryAccent : Color.white.opacity(0.04))
                .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Register file**

```bash
ruby scripts/add-to-xcodeproj.rb Ikeru/Views/Learning/Etude/CustomPlannerSheet.swift Ikeru
```

- [ ] **Step 3: Add localization keys**

```bash
python3 - <<'PY'
import json
p = "Ikeru/Localization/Localizable.xcstrings"
keys = {
    "Etude.Compose.Title":   ("Compose a session", "Composer une session"),
    "Etude.Compose.Cancel":  ("Cancel",            "Annuler"),
    "Etude.Compose.Types":   ("Exercise types",    "Types d'exercice"),
    "Etude.Compose.Levels":  ("JLPT levels",       "Niveaux JLPT"),
    "Etude.Compose.Duration":("Duration",          "Durée"),
    "Etude.Compose.Action":  ("COMPOSE",           "COMPOSER"),
}
with open(p, "r", encoding="utf-8") as f:
    d = json.load(f)
for k, (en, fr) in keys.items():
    d["strings"][k] = {
        "extractionState": "manual",
        "localizations": {
            "en": {"stringUnit": {"state": "translated", "value": en}},
            "fr": {"stringUnit": {"state": "translated", "value": fr}},
        },
    }
with open(p, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
    f.write("\n")
print("added", len(keys))
PY
```

- [ ] **Step 4: Build app**

Run: `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Ikeru/Views/Learning/Etude/CustomPlannerSheet.swift Ikeru/Localization/Localizable.xcstrings Ikeru.xcodeproj/project.pbxproj
git commit -m "feat(etude): CustomPlannerSheet — multi-select types/levels + duration + Compose"
```

---

### Task 21: Add `EtudeView` (replaces `ProgressDashboardView`)

**Files:**
- Create: `Ikeru/Views/Learning/Etude/EtudeView.swift`
- Rename: `Ikeru/ViewModels/ProgressDashboardViewModel.swift` → `Ikeru/ViewModels/EtudeViewModel.swift`
- Delete: `Ikeru/Views/Home/ProgressDashboardView.swift`
- Modify: `Ikeru/Views/MainTabView.swift`
- Modify: `Ikeru/Localization/Localizable.xcstrings`

- [ ] **Step 1: Find current Étude tab routing**

Run: `grep -rnE "ProgressDashboardView" Ikeru/Views/ Ikeru/ViewModels/ 2>/dev/null | head -10`
Expected: 1 line in `MainTabView.swift` plus the file's own definition.

- [ ] **Step 2: Rename and trim the existing view-model**

```bash
git mv Ikeru/ViewModels/ProgressDashboardViewModel.swift Ikeru/ViewModels/EtudeViewModel.swift
sed -i '' 's/ProgressDashboardViewModel/EtudeViewModel/g' Ikeru/ViewModels/EtudeViewModel.swift
```

Then open `Ikeru/ViewModels/EtudeViewModel.swift` and remove any property/method that exposes `skillBalance` (it moves to RPG in Task 22).

- [ ] **Step 3: Append session-routing methods to `EtudeViewModel`**

Add inside the class:

```swift
    public func buildSnapshot() async -> ProfileSnapshot {
        let cards = await cardRepository.allCards()
        let progressService = ProgressService(cardRepository: cardRepository)
        let progress = await progressService.computeProgress()
        let jlpt = JLPTLevel(rawValue: progress.jlptEstimate.level.lowercased()) ?? .n5
        let lastSession = ActiveProfileResolver
            .fetchActiveRPGState(in: modelContainer.mainContext)?.lastSessionDate
        return ProfileSnapshotBuilder.build(
            cards: cards,
            jlptLevel: jlpt,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            hasNewContentQueued: cards.contains(where: { $0.fsrsState.reps == 0 }),
            lastSessionAt: lastSession,
            now: Date()
        )
    }

    public func startSingleSurface(type: ExerciseType) {
        Logger.planner.info("Etude → drill type=\(type.rawValue)")
    }

    public private(set) var lastComposedPlan: SessionPlan?

    public func startCustomSession(
        types: Set<ExerciseType>,
        levels: Set<JLPTLevel>,
        duration: Int
    ) {
        Logger.planner.info("Etude → custom session types=\(types.map(\.rawValue))")
        Task {
            let snapshot = await buildSnapshot()
            let cards = await cardRepository.allCards()
            let unlocked = DefaultExerciseUnlockService().unlockedTypes(profile: snapshot)
            let inputs = SessionPlannerInputs(
                source: .studyCustom(types: types, jlptLevels: levels),
                durationMinutes: duration,
                profile: snapshot,
                unlockedTypes: unlocked,
                availableCards: cards
            )
            self.lastComposedPlan = await DefaultSessionPlanner().compose(inputs: inputs)
        }
    }
```

- [ ] **Step 4: Write `EtudeView.swift`**

```swift
// Ikeru/Views/Learning/Etude/EtudeView.swift
import SwiftUI
import IkeruCore
import SwiftData

struct EtudeView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: EtudeViewModel?
    @State private var showCompose = false
    @State private var snapshot: ProfileSnapshot = .empty
    @State private var unlockedTypes: Set<ExerciseType> = []
    private let unlockService: any ExerciseUnlockService = DefaultExerciseUnlockService()

    var body: some View {
        ZStack {
            IkeruScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if let vm = viewModel { jlptHero(vm) }
                    BilingualLabel(japanese: "\u{7A3D}\u{53E4}\u{5834}", chrome: "Practice ground", mon: .asanoha)
                    EtudeBrowseGrid(
                        snapshot: snapshot,
                        unlockService: unlockService,
                        onTap: { type in viewModel?.startSingleSurface(type: type) }
                    )
                    composeRow
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 140)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await initialize() }
        .sheet(isPresented: $showCompose) {
            CustomPlannerSheet(unlockedTypes: unlockedTypes) { types, levels, duration in
                viewModel?.startCustomSession(types: types, levels: levels, duration: duration)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            BilingualLabel(japanese: "\u{5B66}\u{7FD2}", chrome: "Study")
            Text("Etude.Title")
                .font(.system(size: 28, weight: .light, design: .serif))
                .foregroundStyle(Color.ikeruTextPrimary)
        }
    }

    @ViewBuilder
    private func jlptHero(_ vm: EtudeViewModel) -> some View {
        let level = vm.jlptEstimate.level
        let percent = Int(vm.jlptEstimate.masteryFraction * 100)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                BilingualLabel(japanese: "\u{63A8}\u{5B9A}", chrome: "JLPT estimate")
                Spacer()
                HankoStamp(kanji: level, size: 36)
            }
            HStack(alignment: .firstTextBaseline) {
                SerifNumeral(percent, size: 40)
                Text("%").foregroundStyle(TatamiTokens.paperGhost).tracking(1.4)
            }
        }
        .tatamiRoom(.glass, padding: 20)
    }

    private var composeRow: some View {
        Button { showCompose = true } label: {
            HStack {
                Text("\u{7DE8}\u{6210}")
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(TatamiTokens.paperGhost)
                Text("Etude.Compose.Row")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ikeruTextPrimary)
                Spacer()
                Text("\u{203A}").foregroundStyle(TatamiTokens.goldDim)
            }
            .padding(14)
            .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private func initialize() async {
        if viewModel == nil {
            viewModel = EtudeViewModel(modelContainer: modelContext.container)
        }
        await viewModel?.loadProgress()
        snapshot = await viewModel?.buildSnapshot() ?? .empty
        unlockedTypes = unlockService.unlockedTypes(profile: snapshot)
    }
}
```

- [ ] **Step 5: Update `MainTabView` routing**

Open `Ikeru/Views/MainTabView.swift`, find the `case .etude:` (or equivalent) branch that previously rendered `ProgressDashboardView()` and replace with `EtudeView()`.

- [ ] **Step 6: Add localization for Étude title + Compose row**

```bash
python3 - <<'PY'
import json
p = "Ikeru/Localization/Localizable.xcstrings"
keys = {
    "Etude.Title":      ("Practice library", "Bibliothèque de pratique"),
    "Etude.Compose.Row":("Compose a session","Composer une session"),
}
with open(p, "r", encoding="utf-8") as f:
    d = json.load(f)
for k, (en, fr) in keys.items():
    d["strings"][k] = {
        "extractionState": "manual",
        "localizations": {
            "en": {"stringUnit": {"state": "translated", "value": en}},
            "fr": {"stringUnit": {"state": "translated", "value": fr}},
        },
    }
with open(p, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
    f.write("\n")
print("ok")
PY
```

- [ ] **Step 7: Delete the old dashboard view + register the new one**

```bash
git rm Ikeru/Views/Home/ProgressDashboardView.swift
ruby scripts/add-to-xcodeproj.rb Ikeru/Views/Learning/Etude/EtudeView.swift Ikeru
```

- [ ] **Step 8: Build app**

Run: `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -8`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
git add Ikeru/Views/Learning/Etude/EtudeView.swift \
        Ikeru/ViewModels/EtudeViewModel.swift \
        Ikeru/Views/MainTabView.swift \
        Ikeru/Localization/Localizable.xcstrings \
        Ikeru.xcodeproj/project.pbxproj
git commit -m "feat(etude): EtudeView — JLPT hero + Browse grid + Compose row"
```

---

### Task 22: Move four-winds skill balance to Rang (RPG) tab

**Files:**
- Modify: `Ikeru/Views/RPG/RPGProfileView.swift`
- Modify: `Ikeru/ViewModels/RPGProfileViewModel.swift` (or equivalent)

- [ ] **Step 1: Find where the four-winds card was previously rendered**

Run: `grep -rnE "skillBalanceSection|SkillRadarView|Tes quatre vents|Your four winds" Ikeru/ 2>/dev/null | head -10`

- [ ] **Step 2: Port the skill-balance card into `RPGProfileView`**

Add inside `RPGProfileView`'s body, after the existing attribute panels:

```swift
            if let balance = vm.skillBalance {
                skillBalanceCard(balance)
            }
```

Add the helper:

```swift
    @ViewBuilder
    private func skillBalanceCard(_ balance: SkillBalance) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            BilingualLabel(japanese: "\u{6280}\u{80FD}", chrome: "Skill balance", mon: .asanoha)
            HStack(alignment: .center, spacing: 16) {
                SkillRadarView(skillBalance: balance, variant: .mini)
                    .frame(width: 110, height: 110)
                VStack(alignment: .leading, spacing: 6) {
                    skillRow("Reading",   value: balance.reading)
                    skillRow("Listening", value: balance.listening)
                    skillRow("Writing",   value: balance.writing)
                    skillRow("Speaking",  value: balance.speaking)
                }
            }
        }
        .tatamiRoom(.standard, padding: 20)
    }

    private func skillRow(_ label: LocalizedStringKey, value: Double) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12)).foregroundStyle(Color.ikeruTextSecondary)
            Spacer()
            Text("\(Int(value))").font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.ikeruPrimaryAccent)
        }
    }
```

- [ ] **Step 3: Expose `skillBalance` on the RPG view-model**

In `RPGProfileViewModel.swift`, add:

```swift
    private(set) var skillBalance: SkillBalance? = nil

    public func loadSkillBalance() async {
        let planner = PlannerService(cardRepository: cardRepository)
        let balances = await planner.computeSkillBalances()
        self.skillBalance = SkillBalance(
            reading: balances[.reading] ?? 0,
            listening: balances[.listening] ?? 0,
            writing: balances[.writing] ?? 0,
            speaking: balances[.speaking] ?? 0
        )
    }
```

> If `SkillBalance`'s init differs, mirror its actual surface (read `IkeruCore/Sources/Models/Session/SkillBalance.swift` first).

- [ ] **Step 4: Call `loadSkillBalance` in the view's `.task`**

Add inside `RPGProfileView`'s `.task` block:

```swift
            await vm.loadSkillBalance()
```

- [ ] **Step 5: Build app**

Run: `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Ikeru/Views/RPG/RPGProfileView.swift Ikeru/ViewModels/RPGProfileViewModel.swift
git commit -m "refactor(rpg): four-winds skill balance moved from Étude to Rang"
```

---

### Task 23: Migration — backfill `acknowledgedUnlocks` on first launch

**Files:**
- Create: `IkeruCore/Sources/Services/ExerciseUnlock/UnlockBackfillService.swift`
- Test: `IkeruCore/Tests/Services/ExerciseUnlock/UnlockBackfillServiceTests.swift`
- Modify: `Ikeru/IkeruApp.swift`

- [ ] **Step 1: Write the failing test**

```swift
// IkeruCore/Tests/Services/ExerciseUnlock/UnlockBackfillServiceTests.swift
import Testing
import Foundation
@testable import IkeruCore

@Suite("UnlockBackfillService")
struct UnlockBackfillServiceTests {

    @Test("Adds the 4 day-1 types when acknowledgedUnlocks is empty")
    func backfillsDayOne() {
        let unlock = DefaultExerciseUnlockService()
        let result = UnlockBackfillService.backfill(
            previous: [], profile: .empty, unlockService: unlock)
        #expect(result.contains(.kanaStudy))
        #expect(result.contains(.kanjiStudy))
        #expect(result.contains(.vocabularyStudy))
        #expect(result.contains(.listeningSubtitled))
    }

    @Test("Includes earned types already crossed by current state")
    func backfillsAlreadyEarned() {
        let unlock = DefaultExerciseUnlockService()
        let p = ProfileSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 60,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: true,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            dueCardCount: 0,
            hasNewContentQueued: false,
            lastSessionAt: nil
        )
        let result = UnlockBackfillService.backfill(
            previous: [], profile: p, unlockService: unlock)
        #expect(result.contains(.fillInBlank))
        #expect(result.contains(.grammarExercise))
    }

    @Test("Idempotent — running twice returns the same set")
    func idempotent() {
        let unlock = DefaultExerciseUnlockService()
        let first = UnlockBackfillService.backfill(
            previous: [], profile: .empty, unlockService: unlock)
        let second = UnlockBackfillService.backfill(
            previous: first, profile: .empty, unlockService: unlock)
        #expect(first == second)
    }
}
```

- [ ] **Step 2: Run the test — expect compile failure**

Run: `swift test --package-path IkeruCore --filter UnlockBackfillServiceTests 2>&1 | tail -10`
Expected: `cannot find 'UnlockBackfillService' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// IkeruCore/Sources/Services/ExerciseUnlock/UnlockBackfillService.swift
import Foundation

public enum UnlockBackfillService {
    public static func backfill(
        previous: Set<ExerciseType>,
        profile: ProfileSnapshot,
        unlockService: any ExerciseUnlockService
    ) -> Set<ExerciseType> {
        previous.union(unlockService.unlockedTypes(profile: profile))
    }
}
```

- [ ] **Step 4: Wire into `IkeruApp.swift`**

In `Ikeru/IkeruApp.swift`, find the root `WindowGroup` (or its child view) and attach a `.task` that:

```swift
            .task {
                let context = container.mainContext
                guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else { return }
                if state.acknowledgedUnlocks.isEmpty {
                    let cards = ((try? context.fetch(FetchDescriptor<Card>())) ?? []).map(CardDTO.init)
                    let snapshot = ProfileSnapshotBuilder.build(
                        cards: cards, jlptLevel: .n5,
                        grammarPointsFamiliarPlus: 0,
                        listeningAccuracyLast30: 0,
                        listeningRecallLast30Days: 0,
                        skillBalances: [:],
                        hasNewContentQueued: false,
                        lastSessionAt: state.lastSessionDate,
                        now: Date()
                    )
                    state.acknowledgedUnlocks = UnlockBackfillService.backfill(
                        previous: state.acknowledgedUnlocks,
                        profile: snapshot,
                        unlockService: DefaultExerciseUnlockService()
                    )
                    try? context.save()
                }
            }
```

> Adjust the host view if the existing app shape differs — preserve every other initialiser. The exact placement is wherever the modelContainer is first available.

- [ ] **Step 5: Run the test — expect pass**

Run: `swift test --package-path IkeruCore --filter UnlockBackfillServiceTests 2>&1 | tail -10`
Expected: `✔ Test run with 3 tests in 1 suite passed`.

- [ ] **Step 6: Build app**

Run: `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add IkeruCore/Sources/Services/ExerciseUnlock/UnlockBackfillService.swift \
        IkeruCore/Tests/Services/ExerciseUnlock/UnlockBackfillServiceTests.swift \
        Ikeru/IkeruApp.swift
git commit -m "feat(unlock): one-shot UnlockBackfillService — populate day-1 + already-earned on first launch"
```

---

### Task 24: Deprecate old planner + delete obsolete tests

**Files:**
- Delete: `IkeruCore/Tests/Services/AdaptivePlannerTests.swift`
- Delete: `IkeruCore/Tests/Services/AdaptivePlannerIntegrationTests.swift`
- Modify: `IkeruCore/Sources/Services/PlannerService.swift`

- [ ] **Step 1: Mark `composeAdaptiveSession` deprecated**

In `IkeruCore/Sources/Services/PlannerService.swift` decorate the method:

```swift
    @available(*, deprecated, message: "Use DefaultSessionPlanner.compose(inputs:) instead.")
    public func composeAdaptiveSession(config: SessionConfig) async -> SessionPlan {
        // ... existing body unchanged
```

> Keep `composeSession`, `computeSkillBalances`, and other methods undeprecated — they remain in use.

- [ ] **Step 2: Delete the old tests**

```bash
git rm IkeruCore/Tests/Services/AdaptivePlannerTests.swift
git rm IkeruCore/Tests/Services/AdaptivePlannerIntegrationTests.swift
```

- [ ] **Step 3: Run the full IkeruCore test suite**

Run: `swift test --package-path IkeruCore 2>&1 | tail -15`
Expected: all suites pass; `Adaptive Planner` no longer in the list.

- [ ] **Step 4: Build app — accept deprecation warnings**

Run: `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **` (warnings about deprecated method are acceptable).

- [ ] **Step 5: Commit**

```bash
git add IkeruCore/Sources/Services/PlannerService.swift
git commit -m "deprecate(planner): AdaptivePlanner tests replaced by SessionPlannerTests"
```

---

### Task 25: End-to-end smoke test (manual)

**Files:** none — manual verification only.

- [ ] **Step 1: Reset the simulator and reinstall**

```bash
xcrun simctl uninstall 'iPhone 17' com.nicolas.Ikeru
xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
```
Expected: clean install, `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Walk through the verification checklist**

| # | Surface | Expected |
|---|---|---|
| 1 | Settings → Pratique | "Durée par défaut" row exists, defaults to 15 min, picker offers 5/15/30/45 |
| 2 | Home / Accueil | One CTA only; tap → starts a session whose duration target matches Setting |
| 3 | Home / Accueil (after first session, no due cards, balanced state, < 24h) | "今日は休 / Rest day" surface shows |
| 4 | Étude tab | JLPT hero + 11-tile grid (no Sakura tile) + "編成 / Compose" row |
| 5 | Étude → tap a locked tile | Shows lock-reason hint (e.g., "0 / 50 vocab to unlock"); tap is disabled |
| 6 | Étude → Compose | Sheet opens; Compose disabled until ≥1 type and ≥1 level selected |
| 7 | Étude → Compose → submit | `lastComposedPlan` set; the existing session UI path is reused |
| 8 | Rang tab | Four-winds skill-balance card visible; no longer in Étude |
| 9 | Chat tab (no AI provider) | Existing pre-N4 message preserved |
| 10 | After a session that crosses an unlock threshold | "Nouvelle pratique débloquée" badge appears in inventory exactly once per type |

- [ ] **Step 3: If anything fails, file a fix-up task**

Capture a screenshot, append it to a follow-up issue, and resume the executing-plans loop with that fix as the next task.

---

## Acceptance Criteria → Task Cross-Reference

| Spec acceptance criterion | Task(s) |
|---|---|
| `ExerciseType` enum lives in `IkeruCore` | 1 |
| `ExerciseUnlockService` returns unlocked for the 4 day-1 types | 4 |
| `readingPassage` requires 100 vocab + 50 kanji | 4 |
| `newlyUnlocked` returns deltas; one-time badge | 4, 14 |
| Home CTA respects user duration | 7, 12, 13 |
| Home composition skeleton (40/30/20/10) | 12 |
| Level-tied variety pool | 9, 12 |
| Étude Browse grid shows the 12 (sans Sakura ⇒ 11 tiles) | 17, 18, 19, 21 |
| Étude Custom planner sheet remembers last selection | 20 |
| Rest-day surfaces under all 4 conditions; 24 h expiry | 10, 15, 16 |
| Migration backfill | 23 |
| Adaptive planner tests rewritten | 24 |

---

## Self-Review Notes

**Coverage check:** every spec acceptance bullet maps to at least one task (cross-reference table above). The "skill-balance booster from next-best pool when content is empty" risk-mitigation behavior is implicit in `pickFirstFitting` returning nil when no candidate fits; the planner gracefully skips that segment.

**Placeholder scan:** every step that touches code includes a complete code block. No `TBD`, no `// implement here`, no `similar to Task N` references that hide the actual code.

**Type consistency:** `ExerciseType` cases used in Tasks 4, 9, 12, 17–21 all match the 12-case declaration in Task 1. `ProfileSnapshot` fields used in Tasks 4, 5, 10, 12 match the declaration in Task 3. `ExerciseUnlockState` usage in Tasks 18, 19 matches Task 2.

**Scope check:** the plan is large (25 tasks) but all serve one cohesive subsystem (the learning loop). Splitting further would fragment the planner / unlock / UI triad that has to land together for the Étude tab to work end-to-end.
