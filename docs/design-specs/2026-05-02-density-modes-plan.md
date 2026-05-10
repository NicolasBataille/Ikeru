# Density Modes & Beginner-First UI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship beginner-first chrome (SF Symbols + FR/EN labels + sliding kintsugi gold rail + swipe-paged learning tabs) as default, keep current Tatami kanji-chrome as opt-in `Interface Tatami` toggle in Settings, suggested once per profile after threshold (21d streak + 500 reviews + 50 mastered cards).

**Architecture:** Single `DisplayMode` enum drives an environment value injected by `MainTabView`. Mode-aware chrome modifiers fork rendering between `.beginner` and `.tatami`. A profile-scoped UserDefaults repository holds the current value with lazy migration on first read. Tab bar is rebuilt with SF Symbols + a `matchedGeometryEffect` rail. Swipe is a custom `PagedLearningStack` HStack-with-offset over the 3 learning tabs only (companion + settings stay tap-only and live outside the pager).

**Tech Stack:** Swift 6 strict concurrency, SwiftUI iOS 17+, SwiftData, Swift Testing (`@Test`/`#expect`), `@MainActor` view models, `Combine.AnyPublisher` for repository observation, UserDefaults via `@AppStorage` & explicit reads. Reference spec: `docs/design-specs/2026-05-02-density-modes-design.md` (commit `a78339a`).

---

## File Structure

### New files

| Path | Responsibility |
|---|---|
| `IkeruCore/Sources/Models/Display/DisplayMode.swift` | `DisplayMode` enum (`.beginner`, `.tatami`), `Codable`, `CaseIterable`, `Sendable`. |
| `IkeruCore/Sources/Models/Display/DisplayModeReleaseDate.swift` | `densityModesReleaseDate` constant (single source of truth for migration cutoff). |
| `IkeruCore/Sources/Repositories/DisplayModePreferenceRepository.swift` | Protocol + `UserDefaultsDisplayModePreferenceRepository` concrete with profile-scoping + lazy migration logic + `Combine` publisher. |
| `IkeruCore/Sources/Services/DisplayModeAdvancedThresholdMonitor.swift` | Pure-logic monitor that reads `RPGState` + `CardRepository` and emits `.eligible` / `.notEligible`. |
| `IkeruCore/Tests/DisplayModeTests.swift` | Codable round-trip + enum invariants. |
| `IkeruCore/Tests/DisplayModePreferenceRepositoryTests.swift` | Profile-scoping, migration semantics, publisher behavior. |
| `IkeruCore/Tests/DisplayModeAdvancedThresholdMonitorTests.swift` | Each combination of three signals; only all-true yields `.eligible`. |
| `Ikeru/Views/Shared/Theme/DisplayModeEnvironment.swift` | `EnvironmentKey` + `EnvironmentValues.displayMode` extension. |
| `Ikeru/Views/Shared/Theme/IkeruTabBar+Beginner.swift` | Beginner-mode tab cell (SF Symbol + FR/EN label) — kept separate from existing kanji cell so the file each owns stays narrow. |
| `Ikeru/Views/Shared/Theme/IkeruTabBar+Rail.swift` | Kintsugi gold rail subview (mode-agnostic, `matchedGeometryEffect`). |
| `Ikeru/Views/Shared/Theme/PagedLearningStack.swift` | Custom horizontal pager over the 3 learning tabs with live drag tracking. |
| `Ikeru/Views/Shared/Theme/DensityAware.swift` | `View` modifiers: `.densityAwareBilingualLabel(...)`, `.densityAwareTatamiStatChip(...)`. Forks rendering by `\.displayMode`. |
| `Ikeru/Views/Home/DisplayModeSuggestionCard.swift` | Accueil card view + dismissal binding. |
| `Ikeru/Views/Settings/DisplayModeToggleRow.swift` | Settings row for `Interface Tatami`. |
| `IkeruTests/DisplayModeEnvironmentTests.swift` | Environment propagation across a stub view subtree. |
| `IkeruTests/DisplayModeSuggestionCardTests.swift` | Threshold gating against fixtures, dismissal persistence. |
| `IkeruTests/PagedLearningStackTests.swift` | Selection commit / spring-back / rubber-band against deterministic drag fixtures. |

### Modified files

| Path | Change |
|---|---|
| `Ikeru/Views/MainTabView.swift` | Inject `\.displayMode`. Reorder tabs to `[.companion, .study, .home, .rpg, .settings]`. Swap `tabContent` body to switch between `PagedLearningStack` (for the 3 learning tabs) and direct destination (for chat/settings). |
| `Ikeru/Views/Shared/Theme/IkeruTabBar.swift` | Read `\.displayMode`. In `.beginner` render `BeginnerTabCell`; in `.tatami` keep `TatamiTabCell`. Add rail layer in both. Accept a `railOffset: CGFloat` binding. |
| `Ikeru/Views/Shared/Theme/Tatami/BilingualLabel.swift` | Add `.densityAware()` rendering branch — beginner = chrome primary + small kanji suffix; tatami = current. |
| `Ikeru/Views/RPG/RPGProfileView.swift` | Replace `tatamiStatChip` callsites with `densityAwareTatamiStatChip(...)`. Sections via `BilingualLabel(...).densityAware()`. |
| `Ikeru/Views/Home/HomeView.swift` | Insert `DisplayModeSuggestionCard` above main content when monitor publishes `.eligible` && not yet shown. |
| `Ikeru/Views/Settings/SettingsView.swift` | Insert `DisplayModeToggleRow` inside the existing `Affichage` section (or a new section if absent). |
| `Ikeru/Views/Learning/Conversation/ConversationBubbleView.swift` (and the 3 furigana/romaji surfaces grep'd above) | Read `\.displayMode` to compute the **default** for their existing `@AppStorage` toggles when the toggle has never been touched. |
| `Ikeru/Localization/Localizable.xcstrings` | Add tab labels (5 × 2 locales), suggestion card copy (FR + EN), Settings row copy (FR + EN), 4 small mode-aware overrides for chip labels. |

### Tab order rationale

Current: `[.home, .study, .companion, .rpg, .settings]`. New: `[.companion, .study, .home, .rpg, .settings]`. Companion moves to position 0 (still tap-only, won't break swipe contiguity), study/home/rpg occupy positions 1–3 contiguously so the pager spans them naturally, settings stays at position 4. Default selected tab remains `.home`.

---

## Phase 1 — DisplayMode Foundation

### Task 1: Add `DisplayMode` enum

**Files:**
- Create: `IkeruCore/Sources/Models/Display/DisplayMode.swift`
- Test: `IkeruCore/Tests/DisplayModeTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// IkeruCore/Tests/DisplayModeTests.swift
import Testing
import Foundation
@testable import IkeruCore

@Suite("DisplayMode")
struct DisplayModeTests {

    @Test("Has exactly two cases, beginner is the default for fresh state")
    func twoCases() {
        let all = DisplayMode.allCases
        #expect(all.count == 2)
        #expect(all.contains(.beginner))
        #expect(all.contains(.tatami))
    }

    @Test("Codable round-trips both cases")
    func codableRoundTrip() throws {
        for mode in DisplayMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(DisplayMode.self, from: data)
            #expect(decoded == mode)
        }
    }

    @Test("Raw values match storage contract")
    func rawValues() {
        #expect(DisplayMode.beginner.rawValue == "beginner")
        #expect(DisplayMode.tatami.rawValue == "tatami")
    }
}
```

- [ ] **Step 2: Run test, expect failure**

Run: `swift test --package-path IkeruCore --filter DisplayModeTests`
Expected: FAIL with "cannot find type 'DisplayMode' in scope".

- [ ] **Step 3: Implement enum**

```swift
// IkeruCore/Sources/Models/Display/DisplayMode.swift
import Foundation

/// Controls overall UI density and reading-aid defaults across the app.
///
/// - `.beginner`: SF Symbols + FR/EN chrome labels, furigana/romaji on by default,
///   glossary popovers expanded, mnemonics in locale, Sakura reading aids on.
/// - `.tatami`: Kanji-first chrome (legacy default), reading aids minimal.
public enum DisplayMode: String, Codable, CaseIterable, Sendable {
    case beginner
    case tatami
}
```

- [ ] **Step 4: Run test, expect pass**

Run: `swift test --package-path IkeruCore --filter DisplayModeTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add IkeruCore/Sources/Models/Display/DisplayMode.swift IkeruCore/Tests/DisplayModeTests.swift
git commit -m "feat(display): add DisplayMode enum (beginner/tatami)"
```

---

### Task 2: Add release-date constant

**Files:**
- Create: `IkeruCore/Sources/Models/Display/DisplayModeReleaseDate.swift`

- [ ] **Step 1: Write the constant**

```swift
// IkeruCore/Sources/Models/Display/DisplayModeReleaseDate.swift
import Foundation

public enum DisplayModeReleaseDate {
    /// Profiles created strictly before this date are considered "existing"
    /// for the purpose of the beginner-first migration: they keep `.tatami`
    /// chrome on first launch after the update. Profiles created on or after
    /// this date get `.beginner` as their initial value.
    ///
    /// Update this once at release time; never bump it later.
    public static let value: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 2
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .iso8601).date(from: components)!
    }()
}
```

- [ ] **Step 2: Commit**

```bash
git add IkeruCore/Sources/Models/Display/DisplayModeReleaseDate.swift
git commit -m "feat(display): add migration cutoff date constant"
```

---

### Task 3: `DisplayModePreferenceRepository` — protocol + tests

**Files:**
- Create: `IkeruCore/Sources/Repositories/DisplayModePreferenceRepository.swift` (protocol only — concrete in next task)
- Test: `IkeruCore/Tests/DisplayModePreferenceRepositoryTests.swift` (against an in-memory mock first; will replace in Task 4)

- [ ] **Step 1: Write the protocol**

```swift
// IkeruCore/Sources/Repositories/DisplayModePreferenceRepository.swift
import Foundation
import Combine

/// Profile-scoped preference store for `DisplayMode`. Implementations must
/// resolve the active profile id internally on every call so a profile
/// switch is reflected without restarting.
public protocol DisplayModePreferenceRepository: Sendable {
    /// Current mode for the active profile. Triggers lazy migration on first
    /// read for a profile that has no stored value yet.
    func current() -> DisplayMode

    /// Persist a new mode for the active profile. Publishes on `publisher`.
    func set(_ mode: DisplayMode)

    /// Stream of mode values for the active profile. Replays the current
    /// value on subscribe.
    var publisher: AnyPublisher<DisplayMode, Never> { get }
}
```

- [ ] **Step 2: Commit**

```bash
git add IkeruCore/Sources/Repositories/DisplayModePreferenceRepository.swift
git commit -m "feat(display): add DisplayModePreferenceRepository protocol"
```

---

### Task 4: `UserDefaultsDisplayModePreferenceRepository` — concrete + tests

**Files:**
- Modify: `IkeruCore/Sources/Repositories/DisplayModePreferenceRepository.swift`
- Create: `IkeruCore/Tests/DisplayModePreferenceRepositoryTests.swift`

- [ ] **Step 1: Write failing tests first**

```swift
// IkeruCore/Tests/DisplayModePreferenceRepositoryTests.swift
import Testing
import Foundation
import Combine
@testable import IkeruCore

@Suite("UserDefaultsDisplayModePreferenceRepository")
struct DisplayModePreferenceRepositoryTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "DisplayModeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Lazy migration: pre-release profile defaults to .tatami")
    func migrationExisting() {
        let defaults = makeDefaults()
        let preReleaseDate = DisplayModeReleaseDate.value.addingTimeInterval(-86_400)
        let profileID = UUID()

        let repo = UserDefaultsDisplayModePreferenceRepository(
            defaults: defaults,
            activeProfileID: { profileID },
            profileCreatedAt: { _ in preReleaseDate }
        )

        #expect(repo.current() == .tatami)
        // Stored after first read
        #expect(defaults.string(forKey: "ikeru.display.mode.\(profileID.uuidString)") == "tatami")
    }

    @Test("Lazy migration: post-release profile defaults to .beginner")
    func migrationNew() {
        let defaults = makeDefaults()
        let postReleaseDate = DisplayModeReleaseDate.value.addingTimeInterval(86_400)
        let profileID = UUID()

        let repo = UserDefaultsDisplayModePreferenceRepository(
            defaults: defaults,
            activeProfileID: { profileID },
            profileCreatedAt: { _ in postReleaseDate }
        )

        #expect(repo.current() == .beginner)
        #expect(defaults.string(forKey: "ikeru.display.mode.\(profileID.uuidString)") == "beginner")
    }

    @Test("set persists and is read back")
    func setAndRead() {
        let defaults = makeDefaults()
        let profileID = UUID()
        let repo = UserDefaultsDisplayModePreferenceRepository(
            defaults: defaults,
            activeProfileID: { profileID },
            profileCreatedAt: { _ in Date() }
        )

        repo.set(.tatami)
        #expect(repo.current() == .tatami)
        repo.set(.beginner)
        #expect(repo.current() == .beginner)
    }

    @Test("Profile scoping: two profiles maintain independent values")
    func profileScoping() {
        let defaults = makeDefaults()
        let p1 = UUID()
        let p2 = UUID()
        var active = p1
        let repo = UserDefaultsDisplayModePreferenceRepository(
            defaults: defaults,
            activeProfileID: { active },
            profileCreatedAt: { _ in Date() }
        )

        repo.set(.tatami)
        active = p2
        #expect(repo.current() == .beginner) // p2's lazy default
        repo.set(.beginner)
        active = p1
        #expect(repo.current() == .tatami)
    }

    @Test("Publisher replays current and emits on set")
    func publisher() async {
        let defaults = makeDefaults()
        let profileID = UUID()
        let repo = UserDefaultsDisplayModePreferenceRepository(
            defaults: defaults,
            activeProfileID: { profileID },
            profileCreatedAt: { _ in Date() }
        )

        var received: [DisplayMode] = []
        let cancellable = repo.publisher.sink { received.append($0) }
        defer { cancellable.cancel() }

        // Wait one runloop tick for the replay
        try? await Task.sleep(nanoseconds: 50_000_000)
        repo.set(.tatami)
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(received == [.beginner, .tatami])
    }

    @Test("Missing profile resolution falls back to .beginner without writing")
    func missingProfile() {
        let defaults = makeDefaults()
        let repo = UserDefaultsDisplayModePreferenceRepository(
            defaults: defaults,
            activeProfileID: { nil },
            profileCreatedAt: { _ in nil }
        )

        #expect(repo.current() == .beginner)
        // No persistent write keyed on nil id
        #expect(defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("ikeru.display.mode.") } == false)
    }
}
```

- [ ] **Step 2: Run, expect failure**

Run: `swift test --package-path IkeruCore --filter DisplayModePreferenceRepositoryTests`
Expected: FAIL — type `UserDefaultsDisplayModePreferenceRepository` not in scope.

- [ ] **Step 3: Implement concrete repository**

Append to `IkeruCore/Sources/Repositories/DisplayModePreferenceRepository.swift`:

```swift
public final class UserDefaultsDisplayModePreferenceRepository:
    DisplayModePreferenceRepository
{
    private static let keyPrefix = "ikeru.display.mode."

    private let defaults: UserDefaults
    private let activeProfileID: @Sendable () -> UUID?
    private let profileCreatedAt: @Sendable (UUID) -> Date?
    private let subject: CurrentValueSubject<DisplayMode, Never>

    public init(
        defaults: UserDefaults = .standard,
        activeProfileID: @escaping @Sendable () -> UUID?,
        profileCreatedAt: @escaping @Sendable (UUID) -> Date?
    ) {
        self.defaults = defaults
        self.activeProfileID = activeProfileID
        self.profileCreatedAt = profileCreatedAt
        // Seed subject with whatever current() returns now (which performs
        // lazy migration if needed).
        self.subject = CurrentValueSubject(.beginner)
        self.subject.send(self.resolveCurrent())
    }

    public func current() -> DisplayMode {
        resolveCurrent()
    }

    public func set(_ mode: DisplayMode) {
        guard let id = activeProfileID() else { return }
        defaults.set(mode.rawValue, forKey: Self.keyPrefix + id.uuidString)
        subject.send(mode)
    }

    public var publisher: AnyPublisher<DisplayMode, Never> {
        subject.eraseToAnyPublisher()
    }

    // MARK: - Private

    private func resolveCurrent() -> DisplayMode {
        guard let id = activeProfileID() else { return .beginner }
        let key = Self.keyPrefix + id.uuidString
        if let raw = defaults.string(forKey: key), let mode = DisplayMode(rawValue: raw) {
            return mode
        }
        // Lazy migration: branch on profile age.
        let createdAt = profileCreatedAt(id) ?? Date()
        let migrated: DisplayMode = createdAt < DisplayModeReleaseDate.value
            ? .tatami
            : .beginner
        defaults.set(migrated.rawValue, forKey: key)
        return migrated
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

Run: `swift test --package-path IkeruCore --filter DisplayModePreferenceRepositoryTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add IkeruCore/Sources/Repositories/DisplayModePreferenceRepository.swift IkeruCore/Tests/DisplayModePreferenceRepositoryTests.swift
git commit -m "feat(display): UserDefaults-backed profile-scoped repository with lazy migration"
```

---

### Task 5: SwiftUI environment value

**Files:**
- Create: `Ikeru/Views/Shared/Theme/DisplayModeEnvironment.swift`
- Test: `IkeruTests/DisplayModeEnvironmentTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// IkeruTests/DisplayModeEnvironmentTests.swift
import Testing
import SwiftUI
@testable import Ikeru
@testable import IkeruCore

@Suite("DisplayMode environment")
@MainActor
struct DisplayModeEnvironmentTests {

    @Test("Default value is .beginner")
    func defaultValue() {
        let value = EnvironmentValues().displayMode
        #expect(value == .beginner)
    }

    @Test("Reads injected value")
    func injectedValue() {
        var env = EnvironmentValues()
        env.displayMode = .tatami
        #expect(env.displayMode == .tatami)
    }
}
```

- [ ] **Step 2: Run, expect failure**

Run: `xcodebuild test -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IkeruTests/DisplayModeEnvironmentTests 2>&1 | tail -20`
Expected: FAIL — `displayMode` not a member of EnvironmentValues.

- [ ] **Step 3: Implement environment value**

```swift
// Ikeru/Views/Shared/Theme/DisplayModeEnvironment.swift
import SwiftUI
import IkeruCore

private struct DisplayModeKey: EnvironmentKey {
    static let defaultValue: DisplayMode = .beginner
}

extension EnvironmentValues {
    var displayMode: DisplayMode {
        get { self[DisplayModeKey.self] }
        set { self[DisplayModeKey.self] = newValue }
    }
}
```

- [ ] **Step 4: Run, expect pass**

Run: `xcodebuild test -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IkeruTests/DisplayModeEnvironmentTests 2>&1 | tail -10`
Expected: 2 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Ikeru/Views/Shared/Theme/DisplayModeEnvironment.swift IkeruTests/DisplayModeEnvironmentTests.swift
git commit -m "feat(display): SwiftUI environment value with .beginner default"
```

---

### Task 6: Wire repository through `MainTabView`

**Files:**
- Modify: `Ikeru/Views/MainTabView.swift`
- Modify (already exists): `Ikeru/App/ActiveProfileResolver.swift` (no source change — used as-is)

- [ ] **Step 1: Inject the repository at app boot**

Locate the current `MainTabView` body. Above the `body`, add:

```swift
@State private var displayMode: DisplayMode = .beginner
@State private var displayModeRepo: (any DisplayModePreferenceRepository)?
```

In `.onAppear`, alongside `initializeCompanionViewModel()`:

```swift
let container = modelContext.container
let repo = UserDefaultsDisplayModePreferenceRepository(
    defaults: .standard,
    activeProfileID: { ActiveProfileResolver.activeProfileID() },
    profileCreatedAt: { id in
        let context = container.mainContext
        let descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetch(descriptor))?.first?.createdAt
    }
)
self.displayModeRepo = repo
self.displayMode = repo.current()
```

Also add a Combine subscription so external `set` calls update local state:

```swift
@State private var displayModeCancellable: AnyCancellable?
// ...
displayModeCancellable = repo.publisher
    .receive(on: DispatchQueue.main)
    .sink { mode in self.displayMode = mode }
```

Inject into the environment at the root:

```swift
.environment(\.displayMode, displayMode)
```

- [ ] **Step 2: Build & manual smoke**

Run: `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Ikeru/Views/MainTabView.swift
git commit -m "feat(display): inject DisplayMode environment from MainTabView"
```

---

## Phase 2 — Tab Bar Redesign

### Task 7: Reorder `AppTab.allCases` for swipe contiguity

**Files:**
- Modify: `Ikeru/Views/MainTabView.swift`

- [ ] **Step 1: Reorder enum cases**

Edit `AppTab` declaration:

```swift
enum AppTab: Int, CaseIterable, Identifiable {
    case companion   // tap-only, position 0
    case study       // swipe pager left
    case home        // swipe pager center (default)
    case rpg         // swipe pager right
    case settings    // tap-only, position 4

    // ... rest unchanged
}
```

The default `selectedTab` initializer remains `.home`; since `home` is now `rawValue == 2`, the `-startTab=` CLI arg semantics shift. Update the doc-comment near the `selectedTab` initializer:

```swift
// -startTab=N where N maps to: 0=companion, 1=study, 2=home (default), 3=rpg, 4=settings
```

- [ ] **Step 2: Build & manual smoke**

Run: `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Ikeru/Views/MainTabView.swift
git commit -m "refactor(tabs): reorder AppTab so 3 learning tabs are contiguous"
```

---

### Task 8: Extract kintsugi gold rail subview

**Files:**
- Create: `Ikeru/Views/Shared/Theme/IkeruTabBar+Rail.swift`

- [ ] **Step 1: Implement rail**

```swift
// Ikeru/Views/Shared/Theme/IkeruTabBar+Rail.swift
import SwiftUI
import IkeruCore

/// Sliding kintsugi-gold rail that marks the active tab. Lives below each
/// tab cell. Uses a `matchedGeometryEffect` source on the active cell;
/// only one rail instance is rendered for the whole tab bar.
struct KintsugiTabRail: View {

    let width: CGFloat
    let height: CGFloat
    /// Soft outer glow opacity, 0–1.
    let glowOpacity: CGFloat

    init(width: CGFloat = 28, height: CGFloat = 3, glowOpacity: CGFloat = 0.55) {
        self.width = width
        self.height = height
        self.glowOpacity = glowOpacity
    }

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.541, green: 0.427, blue: 0.290).opacity(0.0),
                        Color.ikeruPrimaryAccent,
                        Color(red: 0.541, green: 0.427, blue: 0.290).opacity(0.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: height)
            .shadow(
                color: Color.ikeruPrimaryAccent.opacity(glowOpacity),
                radius: 8,
                x: 0,
                y: 0
            )
            .accessibilityHidden(true)
    }
}

#Preview("KintsugiTabRail") {
    KintsugiTabRail()
        .padding(40)
        .background(Color.ikeruBackground)
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Ikeru/Views/Shared/Theme/IkeruTabBar+Rail.swift
git commit -m "feat(tabs): kintsugi gold rail subview"
```

---

### Task 9: Beginner-mode tab cell

**Files:**
- Create: `Ikeru/Views/Shared/Theme/IkeruTabBar+Beginner.swift`

- [ ] **Step 1: Implement beginner cell**

```swift
// Ikeru/Views/Shared/Theme/IkeruTabBar+Beginner.swift
import SwiftUI
import IkeruCore

/// Beginner-mode tab cell: SF Symbol on top, localized FR/EN label
/// underneath. Selected state tinted with `ikeruPrimaryAccent`.
struct BeginnerTabCell: View {

    let tab: AppTab
    let isActive: Bool
    let railNamespace: Namespace.ID
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: symbolName)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(
                        isActive ? Color.ikeruPrimaryAccent : TatamiTokens.paperGhost
                    )
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        isActive ? Color.ikeruPrimaryAccent : TatamiTokens.paperGhost
                    )
                ZStack {
                    Color.clear.frame(height: 5)
                    if isActive {
                        KintsugiTabRail()
                            .matchedGeometryEffect(id: "tab-rail", in: railNamespace)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var symbolName: String {
        switch tab {
        case .companion: return "bubble.left.and.bubble.right.fill"
        case .study:     return "book.fill"
        case .home:      return "house.fill"
        case .rpg:       return "rosette"
        case .settings:  return "gearshape.fill"
        }
    }

    private var label: LocalizedStringKey {
        switch tab {
        case .companion: return "Tab.Chat"
        case .study:     return "Tab.Study"
        case .home:      return "Tab.Home"
        case .rpg:       return "Tab.Rank"
        case .settings:  return "Tab.Settings"
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Ikeru/Views/Shared/Theme/IkeruTabBar+Beginner.swift
git commit -m "feat(tabs): beginner-mode tab cell (SF Symbol + label + rail)"
```

---

### Task 10: Fork `IkeruTabBar` by mode + add rail to Tatami cell

**Files:**
- Modify: `Ikeru/Views/Shared/Theme/IkeruTabBar.swift`

- [ ] **Step 1: Add namespace, environment read, mode fork**

Replace the current `IkeruTabBar` body and `TatamiTabCell` to thread a shared `Namespace`:

```swift
struct IkeruTabBar: View {

    @Binding var selection: AppTab
    let tabs: [AppTab]
    @Environment(\.displayMode) private var displayMode
    @Namespace private var railNamespace

    private static let tapSpring: Animation =
        .spring(response: 0.35, dampingFraction: 0.86)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Group {
                    switch displayMode {
                    case .beginner:
                        BeginnerTabCell(
                            tab: tab,
                            isActive: selection == tab,
                            railNamespace: railNamespace,
                            onTap: { tap(tab) }
                        )
                    case .tatami:
                        TatamiTabCell(
                            tab: tab,
                            isActive: selection == tab,
                            railNamespace: railNamespace,
                            onTap: { tap(tab) }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 26)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            FusumaRail(opacity: 0.7)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func tap(_ tab: AppTab) {
        withAnimation(Self.tapSpring) { selection = tab }
    }
}
```

Update the existing `TatamiTabCell` signature to accept the namespace and render a rail under the kanji glyph (replace its current `body`):

```swift
private struct TatamiTabCell: View {
    let tab: AppTab
    let isActive: Bool
    let railNamespace: Namespace.ID
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                if isActive {
                    MonCrest(kind: monKind, size: 10, color: .ikeruPrimaryAccent)
                } else {
                    Color.clear.frame(height: 10)
                }
                Text(japaneseLabel)
                    .font(.system(size: 17, design: .serif))
                    .foregroundStyle(
                        isActive ? Color.ikeruPrimaryAccent : TatamiTokens.paperGhost
                    )
                ZStack {
                    Color.clear.frame(height: 5)
                    if isActive {
                        KintsugiTabRail()
                            .matchedGeometryEffect(id: "tab-rail", in: railNamespace)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    // japaneseLabel / accessibilityLabel / monKind unchanged below this point.
}
```

- [ ] **Step 2: Build & visually smoke**

Run: `xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

Then `xcrun simctl boot 'iPhone 17'`, install, launch — verify default profile shows beginner-mode bar (icons + labels + sliding gold rail). Tap between tabs; the rail should slide with `matchedGeometryEffect` smoothness.

- [ ] **Step 3: Commit**

```bash
git add Ikeru/Views/Shared/Theme/IkeruTabBar.swift
git commit -m "feat(tabs): mode-aware IkeruTabBar with shared rail namespace"
```

---

## Phase 3 — Mode-Aware Chrome

### Task 11: `BilingualLabel.densityAware()` modifier

**Files:**
- Modify: `Ikeru/Views/Shared/Theme/Tatami/BilingualLabel.swift`

- [ ] **Step 1: Replace body to fork on environment**

```swift
struct BilingualLabel: View {
    let japanese: String
    let chrome: LocalizedStringKey
    var mon: MonKind? = nil
    /// Optional romaji rendered as a faint suffix in beginner mode.
    /// Pass nil to render no romaji caption.
    var romaji: String? = nil

    @Environment(\.displayMode) private var displayMode

    var body: some View {
        switch displayMode {
        case .beginner:
            beginnerBody
        case .tatami:
            tatamiBody
        }
    }

    private var beginnerBody: some View {
        HStack(spacing: 6) {
            if let mon {
                MonCrest(kind: mon, size: 10, color: TatamiTokens.goldDim.opacity(0.55))
            }
            Text(chrome)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ikeruTextPrimary)
            if let romaji {
                Text(romaji)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(TatamiTokens.paperGhost.opacity(0.7))
            }
        }
    }

    private var tatamiBody: some View {
        HStack(spacing: 8) {
            if let mon {
                MonCrest(kind: mon, size: 11, color: TatamiTokens.goldDim)
            }
            Text(japanese)
                .font(.system(size: 12, weight: .regular, design: .serif))
                .foregroundStyle(Color.ikeruTextSecondary)
                .tracking(1.5)
            Text("·")
                .foregroundStyle(TatamiTokens.paperGhost)
            Text(chrome)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(TatamiTokens.paperGhost)
                .tracking(2.4)
                .textCase(.uppercase)
        }
    }
}
```

- [ ] **Step 2: Build & visual smoke**

Build, run app, switch to RPG tab, verify section headers (Atouts, Inventaire) render as primary FR text in beginner mode.

- [ ] **Step 3: Commit**

```bash
git add Ikeru/Views/Shared/Theme/Tatami/BilingualLabel.swift
git commit -m "feat(display): BilingualLabel renders chrome-primary in beginner mode"
```

---

### Task 12: `densityAwareTatamiStatChip` for RPG header chips

**Files:**
- Create: `Ikeru/Views/Shared/Theme/DensityAware.swift`
- Modify: `Ikeru/Views/RPG/RPGProfileView.swift`

- [ ] **Step 1: Create the modifier file**

```swift
// Ikeru/Views/Shared/Theme/DensityAware.swift
import SwiftUI
import IkeruCore

/// Mode-aware variant of the RPG header chip (reviews / items / attributes).
/// Beginner: SF Symbol + numeral + caps label. Tatami: kanji glyph + numeral
/// + caps label (existing rendering).
struct DensityAwareStatChip: View {

    let kanjiGlyph: String
    let symbolName: String
    let value: Int
    let label: LocalizedStringKey
    let tint: Color

    @Environment(\.displayMode) private var displayMode

    var body: some View {
        HStack(spacing: 8) {
            switch displayMode {
            case .beginner:
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            case .tatami:
                Text(kanjiGlyph)
                    .font(.system(size: 16, weight: .light, design: .serif))
                    .foregroundStyle(tint)
            }
            SerifNumeral(value, size: 16, color: Color.ikeruTextPrimary)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(TatamiTokens.paperGhost)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08))
        .sumiCorners(color: tint, size: 6, weight: 1.0, inset: -1)
    }
}
```

- [ ] **Step 2: Replace `tatamiStatChip` in RPGProfileView**

Find the three callsites in `RPGProfileView.swift` (the reviews / items / attributes chips) and replace each with:

```swift
DensityAwareStatChip(
    kanjiGlyph: "又",        // (or "財" / "力")
    symbolName: "arrow.triangle.2.circlepath",  // (or "cube.fill" / "bolt.fill")
    value: rpgState.totalReviewsCompleted,       // (or items count / attrs count)
    label: "Reviews",                            // (or "Items" / "Attributes")
    tint: Color.ikeruPrimaryAccent
)
```

The existing `private func tatamiStatChip(...)` helper can be removed once all 3 callsites are migrated.

- [ ] **Step 3: Build & smoke**

Build, run, switch to Rang tab, verify chips show SF Symbol + number + caps label in beginner mode and kanji + number + caps in tatami mode (toggle in Settings to verify both).

- [ ] **Step 4: Commit**

```bash
git add Ikeru/Views/Shared/Theme/DensityAware.swift Ikeru/Views/RPG/RPGProfileView.swift
git commit -m "feat(display): mode-aware RPG header chip (kanji vs SF Symbol)"
```

---

## Phase 4 — Settings Toggle

### Task 13: `DisplayModeToggleRow`

**Files:**
- Create: `Ikeru/Views/Settings/DisplayModeToggleRow.swift`

- [ ] **Step 1: Implement the row**

```swift
// Ikeru/Views/Settings/DisplayModeToggleRow.swift
import SwiftUI
import IkeruCore

struct DisplayModeToggleRow: View {

    let repository: any DisplayModePreferenceRepository
    @State private var isTatamiOn: Bool

    init(repository: any DisplayModePreferenceRepository) {
        self.repository = repository
        _isTatamiOn = State(initialValue: repository.current() == .tatami)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings.InterfaceTatami.Title")
                        .font(.ikeruHeading3)
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Text("Settings.InterfaceTatami.Subtitle")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
                Spacer()
                Toggle("", isOn: $isTatamiOn)
                    .labelsHidden()
                    .tint(Color.ikeruPrimaryAccent)
            }
            Text(isTatamiOn
                 ? "Settings.InterfaceTatami.HelpOn"
                 : "Settings.InterfaceTatami.HelpOff")
                .font(.ikeruCaption)
                .foregroundStyle(TatamiTokens.paperGhost)
        }
        .onChange(of: isTatamiOn) { _, new in
            repository.set(new ? .tatami : .beginner)
        }
    }
}
```

- [ ] **Step 2: Insert into `SettingsView`**

In `SettingsView.swift`, locate the `Affichage` (Display) section. If absent, create one near the existing furigana row:

```swift
Section {
    DisplayModeToggleRow(repository: displayModeRepo)
} header: {
    BilingualLabel(japanese: "表示", chrome: "Display")
}
```

The `displayModeRepo` is held by `MainTabView`; expose it via a new `@Environment` value `\.displayModeRepository` (mirror the pattern of `\.profileViewModel`). Add to `DisplayModeEnvironment.swift`:

```swift
private struct DisplayModeRepositoryKey: EnvironmentKey {
    static let defaultValue: (any DisplayModePreferenceRepository)? = nil
}

extension EnvironmentValues {
    var displayModeRepository: (any DisplayModePreferenceRepository)? {
        get { self[DisplayModeRepositoryKey.self] }
        set { self[DisplayModeRepositoryKey.self] = newValue }
    }
}
```

In `MainTabView`:

```swift
.environment(\.displayModeRepository, displayModeRepo)
```

In `SettingsView`:

```swift
@Environment(\.displayModeRepository) private var displayModeRepo
// ...
if let repo = displayModeRepo {
    DisplayModeToggleRow(repository: repo)
}
```

- [ ] **Step 3: Build & smoke**

Build, run, open Settings, verify toggle is present, flip it once — tab bar should re-render to the other mode without restart.

- [ ] **Step 4: Commit**

```bash
git add Ikeru/Views/Settings/DisplayModeToggleRow.swift Ikeru/Views/Settings/SettingsView.swift Ikeru/Views/Shared/Theme/DisplayModeEnvironment.swift Ikeru/Views/MainTabView.swift
git commit -m "feat(settings): Interface Tatami toggle row"
```

---

## Phase 5 — Reading-Aid Defaults

### Task 14: Hook reading-aid defaults to display mode

**Files:**
- Modify: `Ikeru/Views/Settings/SettingsView.swift` (already has `furiganaEnabled` `@AppStorage`)
- Modify: `Ikeru/Views/Learning/Conversation/ConversationBubbleView.swift` and `KanaRubyText.swift` — read mode-aware default
- Modify: `Ikeru/Views/Learning/Reading/ReadingPassageView.swift`

The pattern: each reading-aid `@AppStorage("ikeru.<feature>.enabled")` key keeps its value once user-touched. To detect "never touched", we add a sibling `@AppStorage("ikeru.<feature>.userTouched")` boolean default `false`. The toggle UI sets `userTouched = true` on first interaction. When `userTouched == false`, the effective value falls back to a mode-aware default.

- [ ] **Step 1: Helper protocol**

Append to `Ikeru/Views/Shared/Theme/DensityAware.swift`:

```swift
/// Resolves a reading-aid's effective value:
///   - If the user has explicitly toggled it: use stored value.
///   - Else: use the mode-default (true in beginner, false in tatami).
struct ReadingAidResolver {
    let mode: DisplayMode
    let userTouched: Bool
    let storedValue: Bool

    var effective: Bool {
        userTouched ? storedValue : (mode == .beginner)
    }
}
```

- [ ] **Step 2: Migrate existing `furiganaEnabled` to use the resolver**

In `SettingsView.swift`, change:

```swift
@AppStorage("ikeru.furigana.enabled") private var furiganaEnabled = true
@AppStorage("ikeru.furigana.userTouched") private var furiganaUserTouched = false
```

Wherever the toggle is rendered, in its `onChange`:

```swift
.onChange(of: furiganaEnabled) { _, _ in furiganaUserTouched = true }
```

Wherever `furiganaEnabled` is read by other views, replace with `ReadingAidResolver(mode: displayMode, userTouched: furiganaUserTouched, storedValue: furiganaEnabled).effective`.

Apply the same `userTouched` companion key + resolver call pattern to:
- `ikeru.romaji.enabled` (vocab cards)
- `ikeru.glossary.expanded` (glossary popover default-state)
- `ikeru.mnemonics.locale` (an enum with `.localeOnly` / `.japaneseFirst` — beginner default `.localeOnly`)
- `ikeru.sakura.pronunciation.enabled`
- `ikeru.sakura.kana.enabled`

For each, follow the same edit: add `userTouched` companion, gate `onChange` to set it, wrap reads in `ReadingAidResolver`.

- [ ] **Step 3: Build & smoke**

Run app on a fresh-state simulator (delete app first to clear UserDefaults), verify:
- Beginner mode: furigana visible by default on vocab review.
- Toggle to Tatami via Settings: vocab review now hides furigana **for new keys not yet user-touched**.

- [ ] **Step 4: Commit**

```bash
git add Ikeru/Views/Shared/Theme/DensityAware.swift Ikeru/Views/Settings/SettingsView.swift Ikeru/Views/Learning/Conversation/ConversationBubbleView.swift Ikeru/Views/Learning/Conversation/KanaRubyText.swift Ikeru/Views/Learning/Reading/ReadingPassageView.swift
git commit -m "feat(display): mode-aware defaults for furigana/romaji/glossary/sakura"
```

---

## Phase 6 — Swipe-Paged Learning Tabs

### Task 15: `PagedLearningStack` container

**Files:**
- Create: `Ikeru/Views/Shared/Theme/PagedLearningStack.swift`
- Test: `IkeruTests/PagedLearningStackTests.swift`

- [ ] **Step 1: Write failing tests for selection commit logic**

```swift
// IkeruTests/PagedLearningStackTests.swift
import Testing
import SwiftUI
@testable import Ikeru

@Suite("PagedLearningStack selection logic")
@MainActor
struct PagedLearningStackTests {

    @Test("Drag past halfway commits to next page")
    func commitForward() {
        let model = PagedLearningStackLogic(width: 400)
        let next = model.commit(currentIndex: 1, dragTranslation: -210, velocity: 0)
        #expect(next == 2)
    }

    @Test("Drag below halfway springs back")
    func springBack() {
        let model = PagedLearningStackLogic(width: 400)
        let next = model.commit(currentIndex: 1, dragTranslation: -120, velocity: 0)
        #expect(next == 1)
    }

    @Test("High forward velocity commits even below halfway")
    func velocityCommit() {
        let model = PagedLearningStackLogic(width: 400)
        let next = model.commit(currentIndex: 1, dragTranslation: -80, velocity: -800)
        #expect(next == 2)
    }

    @Test("Cannot swipe past first or last")
    func clamping() {
        let model = PagedLearningStackLogic(width: 400, pageCount: 3)
        let nextLeft = model.commit(currentIndex: 0, dragTranslation: 250, velocity: 0)
        #expect(nextLeft == 0)
        let nextRight = model.commit(currentIndex: 2, dragTranslation: -250, velocity: 0)
        #expect(nextRight == 2)
    }

    @Test("Rubber band scales offset past edges")
    func rubberBand() {
        let model = PagedLearningStackLogic(width: 400, pageCount: 3)
        let raw = model.rubberBandedOffset(currentIndex: 0, dragTranslation: 200)
        #expect(raw < 200) // damped
        #expect(raw > 0)
        let center = model.rubberBandedOffset(currentIndex: 1, dragTranslation: 100)
        #expect(center == 100) // not at boundary
    }
}
```

- [ ] **Step 2: Run, expect failure**

Run: `xcodebuild test -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IkeruTests/PagedLearningStackTests 2>&1 | tail -15`
Expected: FAIL — type `PagedLearningStackLogic` not in scope.

- [ ] **Step 3: Implement logic + view**

```swift
// Ikeru/Views/Shared/Theme/PagedLearningStack.swift
import SwiftUI
import IkeruCore

/// Pure-logic helper. Lives outside the view so it's unit-testable
/// without bringing up SwiftUI.
struct PagedLearningStackLogic {
    let width: CGFloat
    let pageCount: Int
    /// Velocity threshold (pt/s) above which a small drag still commits.
    let velocityThreshold: CGFloat
    /// Halfway threshold for distance-based commit.
    var distanceThreshold: CGFloat { width / 2 }

    init(width: CGFloat, pageCount: Int = 3, velocityThreshold: CGFloat = 600) {
        self.width = width
        self.pageCount = pageCount
        self.velocityThreshold = velocityThreshold
    }

    func commit(currentIndex: Int, dragTranslation: CGFloat, velocity: CGFloat) -> Int {
        let goingForward = dragTranslation < 0
        let absTranslation = abs(dragTranslation)
        let absVelocity = abs(velocity)

        let crossedDistance = absTranslation > distanceThreshold
        let crossedVelocity = absVelocity > velocityThreshold && absTranslation > 20

        guard crossedDistance || crossedVelocity else { return currentIndex }

        let candidate = goingForward ? currentIndex + 1 : currentIndex - 1
        return max(0, min(pageCount - 1, candidate))
    }

    func rubberBandedOffset(currentIndex: Int, dragTranslation: CGFloat) -> CGFloat {
        let isAtLeft = currentIndex == 0
        let isAtRight = currentIndex == pageCount - 1
        let pullingPastEdge = (isAtLeft && dragTranslation > 0)
            || (isAtRight && dragTranslation < 0)
        guard pullingPastEdge else { return dragTranslation }
        return dragTranslation * 0.35
    }
}

/// Horizontal pager over a fixed array of pages. The active index is bound
/// externally so the surrounding tab bar can render the correct rail
/// position. While dragging, `liveOffsetFraction` reports a value in
/// `[0, pageCount-1]` that the tab bar rail can interpolate against.
struct PagedLearningStack<Content: View>: View {

    let pageCount: Int
    @Binding var activeIndex: Int
    /// 0 ... pageCount-1, fractional during drag.
    @Binding var liveOffsetFraction: CGFloat
    @ViewBuilder let content: (Int) -> Content

    @State private var dragTranslation: CGFloat = 0
    @GestureState private var velocity: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let logic = PagedLearningStackLogic(width: width, pageCount: pageCount)
            let damped = logic.rubberBandedOffset(
                currentIndex: activeIndex,
                dragTranslation: dragTranslation
            )

            HStack(spacing: 0) {
                ForEach(0..<pageCount, id: \.self) { index in
                    if abs(index - activeIndex) <= 1 {
                        content(index)
                            .frame(width: width)
                    } else {
                        Color.clear.frame(width: width) // page placeholder
                    }
                }
            }
            .frame(width: width * CGFloat(pageCount), alignment: .leading)
            .offset(x: -CGFloat(activeIndex) * width + damped)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        // Only horizontal-dominated drags engage.
                        guard abs(value.translation.width) > abs(value.translation.height) else {
                            return
                        }
                        dragTranslation = value.translation.width
                        let fractional = CGFloat(activeIndex) - damped / width
                        liveOffsetFraction = fractional
                    }
                    .onEnded { value in
                        let v = value.predictedEndTranslation.width - value.translation.width
                        let next = logic.commit(
                            currentIndex: activeIndex,
                            dragTranslation: value.translation.width,
                            velocity: v
                        )
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            activeIndex = next
                            dragTranslation = 0
                            liveOffsetFraction = CGFloat(next)
                        }
                    }
            )
            .onChange(of: activeIndex) { _, new in
                liveOffsetFraction = CGFloat(new)
            }
        }
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

Run: `xcodebuild test -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IkeruTests/PagedLearningStackTests 2>&1 | tail -10`
Expected: 5 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Ikeru/Views/Shared/Theme/PagedLearningStack.swift IkeruTests/PagedLearningStackTests.swift
git commit -m "feat(tabs): swipe-paged learning stack with logic unit tests"
```

---

### Task 16: Wire `PagedLearningStack` into `MainTabView`

**Files:**
- Modify: `Ikeru/Views/MainTabView.swift`

- [ ] **Step 1: Replace `tabContent`**

Replace the existing `tabContent` body with a switch that returns a pager for the 3 learning tabs and a direct destination otherwise.

```swift
@State private var liveOffsetFraction: CGFloat = 1 // home is index 1 within the pager

private var learningPagerIndex: Binding<Int> {
    Binding(
        get: {
            switch selectedTab {
            case .study: return 0
            case .home:  return 1
            case .rpg:   return 2
            default:     return 1
            }
        },
        set: { new in
            switch new {
            case 0: selectedTab = .study
            case 2: selectedTab = .rpg
            default: selectedTab = .home
            }
        }
    )
}

@ViewBuilder
private var tabContent: some View {
    ZStack {
        switch selectedTab {
        case .study, .home, .rpg:
            PagedLearningStack(
                pageCount: 3,
                activeIndex: learningPagerIndex,
                liveOffsetFraction: $liveOffsetFraction,
                content: { index in
                    switch index {
                    case 0: TabContentView(tab: .study)
                    case 1: TabContentView(tab: .home)
                    case 2: TabContentView(tab: .rpg)
                    default: Color.clear
                    }
                }
            )
            .transition(.opacity)
        case .companion:
            TabContentView(tab: .companion)
                .transition(.opacity)
        case .settings:
            TabContentView(tab: .settings)
                .transition(.opacity)
        }
    }
    .animation(.spring(response: 0.42, dampingFraction: 0.86), value: selectedTab)
}
```

- [ ] **Step 2: Build & device smoke**

Build, run, on Accueil swipe right → arrives at Étude; swipe left → arrives at Rang. Tap Chat or Réglages → no swipe behavior, modal feel preserved.

- [ ] **Step 3: Commit**

```bash
git add Ikeru/Views/MainTabView.swift
git commit -m "feat(tabs): swipe pager for the 3 learning tabs"
```

---

## Phase 7 — Suggestion Card

### Task 17: `DisplayModeAdvancedThresholdMonitor`

**Files:**
- Create: `IkeruCore/Sources/Services/DisplayModeAdvancedThresholdMonitor.swift`
- Test: `IkeruCore/Tests/DisplayModeAdvancedThresholdMonitorTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// IkeruCore/Tests/DisplayModeAdvancedThresholdMonitorTests.swift
import Testing
import Foundation
@testable import IkeruCore

@Suite("DisplayModeAdvancedThresholdMonitor")
struct DisplayModeAdvancedThresholdMonitorTests {

    @Test("All three signals true → eligible")
    func allTrue() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            currentDailyStreak: 21,
            totalReviewsCompleted: 500,
            cardsAtFamiliarOrAbove: 50
        )
        #expect(result == .eligible)
    }

    @Test("Streak below threshold → not eligible")
    func streakLow() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            currentDailyStreak: 20,
            totalReviewsCompleted: 500,
            cardsAtFamiliarOrAbove: 50
        )
        #expect(result == .notEligible)
    }

    @Test("Reviews below threshold → not eligible")
    func reviewsLow() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            currentDailyStreak: 30,
            totalReviewsCompleted: 499,
            cardsAtFamiliarOrAbove: 50
        )
        #expect(result == .notEligible)
    }

    @Test("Mastery below threshold → not eligible")
    func masteryLow() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            currentDailyStreak: 30,
            totalReviewsCompleted: 600,
            cardsAtFamiliarOrAbove: 49
        )
        #expect(result == .notEligible)
    }

    @Test("Boundary values: 21 / 500 / 50 are inclusive")
    func boundary() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            currentDailyStreak: 21,
            totalReviewsCompleted: 500,
            cardsAtFamiliarOrAbove: 50
        )
        #expect(result == .eligible)
    }
}
```

- [ ] **Step 2: Run, expect failure**

Run: `swift test --package-path IkeruCore --filter DisplayModeAdvancedThresholdMonitorTests`
Expected: FAIL — type not in scope.

- [ ] **Step 3: Implement monitor**

```swift
// IkeruCore/Sources/Services/DisplayModeAdvancedThresholdMonitor.swift
import Foundation

public enum DisplayModeThresholdResult: Sendable, Equatable {
    case eligible
    case notEligible
}

public enum DisplayModeAdvancedThresholdMonitor {

    public static let streakThreshold = 21
    public static let reviewsThreshold = 500
    public static let masteryThreshold = 50

    /// Pure function: returns `.eligible` iff all three signals meet the
    /// inclusive thresholds.
    public static func evaluate(
        currentDailyStreak: Int,
        totalReviewsCompleted: Int,
        cardsAtFamiliarOrAbove: Int
    ) -> DisplayModeThresholdResult {
        let streakOK = currentDailyStreak >= streakThreshold
        let reviewsOK = totalReviewsCompleted >= reviewsThreshold
        let masteryOK = cardsAtFamiliarOrAbove >= masteryThreshold
        return (streakOK && reviewsOK && masteryOK) ? .eligible : .notEligible
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

Run: `swift test --package-path IkeruCore --filter DisplayModeAdvancedThresholdMonitorTests`
Expected: 5 tests passing.

- [ ] **Step 5: Commit**

```bash
git add IkeruCore/Sources/Services/DisplayModeAdvancedThresholdMonitor.swift IkeruCore/Tests/DisplayModeAdvancedThresholdMonitorTests.swift
git commit -m "feat(display): pure threshold monitor with unit tests"
```

---

### Task 18: `DisplayModeSuggestionCard` view + dismissal persistence

**Files:**
- Create: `Ikeru/Views/Home/DisplayModeSuggestionCard.swift`
- Test: `IkeruTests/DisplayModeSuggestionCardTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// IkeruTests/DisplayModeSuggestionCardTests.swift
import Testing
import Foundation
@testable import Ikeru
@testable import IkeruCore

@Suite("DisplayModeSuggestionCardController")
struct DisplayModeSuggestionCardTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "SuggestionCardTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Eligible + not yet shown → shouldShow = true")
    func showsWhenEligible() {
        let defaults = makeDefaults()
        let id = UUID()
        let controller = DisplayModeSuggestionCardController(
            defaults: defaults,
            profileID: id,
            currentMode: .beginner
        )
        controller.onSignalsChanged(
            streak: 25, reviews: 600, mastery: 60
        )
        #expect(controller.shouldShow == true)
    }

    @Test("Already dismissed → shouldShow = false even when eligible")
    func dismissedSticks() {
        let defaults = makeDefaults()
        let id = UUID()
        defaults.set(true, forKey: "ikeru.display.mode.suggestionShown.\(id.uuidString)")
        let controller = DisplayModeSuggestionCardController(
            defaults: defaults,
            profileID: id,
            currentMode: .beginner
        )
        controller.onSignalsChanged(streak: 25, reviews: 600, mastery: 60)
        #expect(controller.shouldShow == false)
    }

    @Test("Mode is .tatami → shouldShow = false (already advanced)")
    func tatamiHidesCard() {
        let defaults = makeDefaults()
        let id = UUID()
        let controller = DisplayModeSuggestionCardController(
            defaults: defaults,
            profileID: id,
            currentMode: .tatami
        )
        controller.onSignalsChanged(streak: 25, reviews: 600, mastery: 60)
        #expect(controller.shouldShow == false)
    }

    @Test("dismiss() persists and hides")
    func dismissPersists() {
        let defaults = makeDefaults()
        let id = UUID()
        let controller = DisplayModeSuggestionCardController(
            defaults: defaults,
            profileID: id,
            currentMode: .beginner
        )
        controller.onSignalsChanged(streak: 25, reviews: 600, mastery: 60)
        controller.dismiss()
        #expect(controller.shouldShow == false)
        #expect(defaults.bool(forKey: "ikeru.display.mode.suggestionShown.\(id.uuidString)") == true)
    }
}
```

- [ ] **Step 2: Run, expect failure**

Run: `xcodebuild test -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IkeruTests/DisplayModeSuggestionCardTests 2>&1 | tail -15`
Expected: FAIL — controller type not in scope.

- [ ] **Step 3: Implement controller + view**

```swift
// Ikeru/Views/Home/DisplayModeSuggestionCard.swift
import SwiftUI
import IkeruCore
import Observation

@Observable
final class DisplayModeSuggestionCardController {

    private static let keyPrefix = "ikeru.display.mode.suggestionShown."

    private let defaults: UserDefaults
    private let profileID: UUID
    private(set) var currentMode: DisplayMode
    private(set) var isEligible: Bool = false

    init(
        defaults: UserDefaults = .standard,
        profileID: UUID,
        currentMode: DisplayMode
    ) {
        self.defaults = defaults
        self.profileID = profileID
        self.currentMode = currentMode
    }

    var shouldShow: Bool {
        guard currentMode == .beginner else { return false }
        guard !alreadyDismissed else { return false }
        return isEligible
    }

    private var alreadyDismissed: Bool {
        defaults.bool(forKey: Self.keyPrefix + profileID.uuidString)
    }

    func onSignalsChanged(streak: Int, reviews: Int, mastery: Int) {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            currentDailyStreak: streak,
            totalReviewsCompleted: reviews,
            cardsAtFamiliarOrAbove: mastery
        )
        self.isEligible = (result == .eligible)
    }

    func setMode(_ mode: DisplayMode) {
        self.currentMode = mode
    }

    func dismiss() {
        defaults.set(true, forKey: Self.keyPrefix + profileID.uuidString)
        // Trigger Observation update
        self.isEligible = self.isEligible
    }
}

struct DisplayModeSuggestionCard: View {

    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 14) {
                Text("\u{9053}") // 道
                    .font(.system(size: 34, weight: .light, design: .serif))
                    .foregroundStyle(Color.ikeruPrimaryAccent)

                VStack(alignment: .leading, spacing: 6) {
                    Text("DisplayMode.Suggestion.Title")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Text("DisplayMode.Suggestion.Body")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ikeruTextSecondary)
                    HStack(spacing: 10) {
                        Button(action: onAccept) {
                            Text("DisplayMode.Suggestion.Accept")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.ikeruPrimaryAccent)
                                .foregroundStyle(Color.black)
                                .cornerRadius(6)
                        }
                        Button(action: onDismiss) {
                            Text("DisplayMode.Suggestion.Later")
                                .font(.system(size: 12))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(TatamiTokens.paperGhost, lineWidth: 1)
                                )
                                .foregroundStyle(Color.ikeruTextSecondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(18)
            .background(
                LinearGradient(
                    colors: [
                        Color.ikeruPrimaryAccent.opacity(0.06),
                        Color.ikeruPrimaryAccent.opacity(0.02)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.ikeruPrimaryAccent.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TatamiTokens.paperGhost)
                    .padding(12)
            }
            .accessibilityLabel("Dismiss")
        }
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

Run: `xcodebuild test -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IkeruTests/DisplayModeSuggestionCardTests 2>&1 | tail -10`
Expected: 4 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Ikeru/Views/Home/DisplayModeSuggestionCard.swift IkeruTests/DisplayModeSuggestionCardTests.swift
git commit -m "feat(display): suggestion card view + dismissal-persisting controller"
```

---

### Task 19: Hook the card into `HomeView`

**Files:**
- Modify: `Ikeru/Views/Home/HomeView.swift`

- [ ] **Step 1: Add the controller and signal-feeding effect**

Inside `HomeView`, near the existing `@State` properties, add:

```swift
@State private var suggestionController: DisplayModeSuggestionCardController?
@Environment(\.displayMode) private var displayMode
@Environment(\.displayModeRepository) private var displayModeRepo
```

In `.onAppear`, initialize the controller using the active profile and feed signals. Pseudocode for the wiring (use existing `HomeViewModel` accessors for streak/reviews/mastery counts; if those don't exist, add stub computed properties on the view model that read from `RPGState` and `CardRepository`):

```swift
.task {
    guard let profileID = ActiveProfileResolver.activeProfileID() else { return }
    let controller = DisplayModeSuggestionCardController(
        profileID: profileID,
        currentMode: displayMode
    )
    self.suggestionController = controller
    let signals = await viewModel.advancedThresholdSignals()
    controller.onSignalsChanged(
        streak: signals.streak,
        reviews: signals.reviews,
        mastery: signals.mastery
    )
}
.onChange(of: displayMode) { _, new in
    suggestionController?.setMode(new)
}
```

Above the main content `VStack` body:

```swift
if let controller = suggestionController, controller.shouldShow {
    DisplayModeSuggestionCard(
        onAccept: {
            displayModeRepo?.set(.tatami)
            controller.dismiss()
        },
        onDismiss: { controller.dismiss() }
    )
    .padding(.horizontal, IkeruTheme.Spacing.md)
    .padding(.top, IkeruTheme.Spacing.sm)
}
```

- [ ] **Step 2: Add the signals helper to `HomeViewModel`**

In `HomeViewModel`, add:

```swift
struct AdvancedThresholdSignals: Sendable {
    let streak: Int
    let reviews: Int
    let mastery: Int
}

func advancedThresholdSignals() async -> AdvancedThresholdSignals {
    let context = modelContainer.mainContext
    let profile = ActiveProfileResolver.fetchActiveProfile(in: context)
    let streak = profile?.rpgState?.currentDailyStreak ?? 0
    let reviews = profile?.rpgState?.totalReviewsCompleted ?? 0
    let masteryCount = await CardRepository(modelContainer: modelContainer)
        .countCardsAt(masteryAtLeast: .familiar)
    return AdvancedThresholdSignals(
        streak: streak,
        reviews: reviews,
        mastery: masteryCount
    )
}
```

If `CardRepository.countCardsAt(masteryAtLeast:)` does not yet exist, add it as a thin async wrapper around `allCards()` that filters by `MasteryLevel.from(fsrsState:)` `>= .familiar`.

- [ ] **Step 3: Build & smoke**

Build, run with a fixture profile that meets all three thresholds → suggestion card visible on Accueil. Tap "Plus tard" → card hides; relaunch → still hidden.

- [ ] **Step 4: Commit**

```bash
git add Ikeru/Views/Home/HomeView.swift Ikeru/ViewModels/HomeViewModel.swift IkeruCore/Sources/Repositories/CardRepository.swift
git commit -m "feat(display): suggestion card on Accueil, fed from HomeViewModel signals"
```

---

## Phase 8 — Localization

### Task 20: Add new strings to `Localizable.xcstrings`

**Files:**
- Modify: `Ikeru/Localization/Localizable.xcstrings`

- [ ] **Step 1: Add tab labels**

Required keys (each with `en` + `fr` localizations):

| Key | EN | FR |
|---|---|---|
| `Tab.Chat` | Chat | Chat |
| `Tab.Study` | Study | Étude |
| `Tab.Home` | Home | Accueil |
| `Tab.Rank` | Rank | Rang |
| `Tab.Settings` | Settings | Réglages |

- [ ] **Step 2: Add settings + suggestion strings**

| Key | EN | FR |
|---|---|---|
| `Settings.InterfaceTatami.Title` | Tatami interface | Interface Tatami |
| `Settings.InterfaceTatami.Subtitle` | Kanji throughout, translations hidden | Kanji partout, traductions masquées |
| `Settings.InterfaceTatami.HelpOff` | Designed for learners comfortable with Japanese. | Conçu pour les apprenants à l'aise avec le japonais. |
| `Settings.InterfaceTatami.HelpOn` | To return to beginner-friendly mode, turn this off. | Pour revenir au mode beginner-friendly, désactive ici. |
| `DisplayMode.Suggestion.Title` | You're reading Japanese with ease now. | Tu lis maintenant le japonais avec aisance. |
| `DisplayMode.Suggestion.Body` | Activate the Tatami interface — kanji throughout, romaji and translations hidden by default. A mode for confirmed learners. Adjustable any time in Settings. | Active l'interface Tatami — kanji partout, romaji et traductions masqués par défaut. Un mode pour les apprenants confirmés. Ajustable à tout moment dans Réglages. |
| `DisplayMode.Suggestion.Accept` | Try it | Essayer |
| `DisplayMode.Suggestion.Later` | Later | Plus tard |

- [ ] **Step 3: Add chip labels (already in catalog as Reviews/Items/Attributes — verify)**

Confirm these keys exist with FR translations: `Reviews`/`Révisions`, `Items`/`Objets`, `Attributes`/`Atouts`. If missing, add. (User's prior FR-translation pass commit `1f89980` should already cover these — `git grep -n 'Reviews' Ikeru/Localization/Localizable.xcstrings` to verify.)

- [ ] **Step 4: Commit**

```bash
git add Ikeru/Localization/Localizable.xcstrings
git commit -m "i18n: add tab labels, settings copy, and suggestion card strings (en+fr)"
```

---

## Phase 9 — Final Verification

### Task 21: Acceptance-criteria checklist run

**Files:** none modified — manual verification only.

- [ ] **Step 1: Fresh-install smoke**

```bash
xcrun simctl uninstall 'iPhone 17' com.nicolas.Ikeru
xcodebuild -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' install 2>&1 | tail -5
xcrun simctl launch 'iPhone 17' com.nicolas.Ikeru
```

Then walk the spec's Acceptance Criteria one by one:

- New profile → tab bar shows SF Symbols + FR labels + sliding gold rail.
- Settings toggle flips → tab bar re-renders to other mode without restart.
- Swipe right on Étude → arrives at Accueil; rail tracks finger.
- Spring-back below halfway works.
- Past-edge swipe rubber-bands.
- Chat / Réglages tap-only (no swipe).
- Sakura defaults pronunciation+kana ON in beginner, OFF in tatami.
- Cross threshold via fixture (XP injection or seeding) → suggestion card on Accueil.
- "Plus tard" → permanent hide.
- "Essayer" → mode flips, card dismisses.

- [ ] **Step 2: Existing-profile migration smoke**

Test that pre-release profiles (`createdAt` < `densityModesReleaseDate`) keep `.tatami` on first read after the update. Use `xcrun simctl spawn 'iPhone 17' defaults read com.nicolas.Ikeru` to inspect persisted UserDefaults.

- [ ] **Step 3: Run full test suite**

Run:
```bash
swift test --package-path IkeruCore 2>&1 | tail -20
xcodebuild test -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: all green except the 13 pre-existing Session XP-rule failures noted in `docs/design-specs/2026-05-02-tatami-fix-plan.md` (out of scope).

- [ ] **Step 4: Commit any final fix-ups**

```bash
git add -A
git commit -m "fix(display): final adjustments after acceptance-criteria walk" || echo "nothing to commit"
```

---

### Task 22: Push branch + open PR

**Files:** none.

- [ ] **Step 1: Push**

```bash
git push origin design/wabi-refinements
```

- [ ] **Step 2: Open PR**

```bash
gh pr create --title "feat(display): density modes & beginner-first UI" --body "$(cat <<'EOF'
## Summary
- Beginner-first chrome by default: SF Symbols + FR/EN labels + sliding kintsugi gold rail tab indicator.
- Tatami kanji-chrome preserved as opt-in via Settings → Interface Tatami.
- Swipe horizontally between the 3 learning tabs (Étude ↔ Accueil ↔ Rang); Chat & Réglages remain tap-only.
- Reading-aid defaults (furigana / romaji / glossary / Sakura) follow the mode unless user-touched.
- One-time suggestion card on Accueil at threshold (21d streak + 500 reviews + 50 mastered).
- Lazy migration: existing profiles keep Tatami; new profiles land in beginner.

Spec: \`docs/design-specs/2026-05-02-density-modes-design.md\`
Plan: \`docs/design-specs/2026-05-02-density-modes-plan.md\`

## Test plan
- [ ] Fresh install → beginner-mode chrome
- [ ] Existing profile → tatami chrome preserved
- [ ] Settings toggle → live re-render (no restart)
- [ ] Swipe gestures across 3 learning tabs
- [ ] Suggestion card appears at threshold and dismisses permanently
- [ ] Sakura reading aids default per mode
- [ ] All existing tests pass (modulo known pre-existing Session XP failures)
EOF
)"
```

- [ ] **Step 3: Done**

---

## Self-Review

**Spec coverage**

- DisplayMode enum + repository → Tasks 1–4 ✓
- Environment propagation → Tasks 5–6 ✓
- BilingualLabel densityAware → Task 11 ✓
- RPG chip densityAware → Task 12 ✓
- IkeruTabBar redesign with kintsugi rail + matchedGeometry → Tasks 8–10 ✓
- PagedLearningStack swipe → Tasks 15–16 ✓
- MainTabView container switching → Tasks 7, 16 ✓
- Reading-aid defaults (furigana/romaji/glossary/mnemonic/Sakura) → Task 14 ✓
- DisplayModeAdvancedThresholdMonitor → Task 17 ✓
- Suggestion card → Tasks 18–19 ✓
- Settings toggle → Task 13 ✓
- Lazy migration → Task 4 (covered in repository) ✓
- FR/EN localization → Task 20 ✓
- Tests for all of the above → Tasks 1, 4, 5, 15, 17, 18 ✓

**Type consistency** — `displayMode` (env value), `displayModeRepo` (state), `displayModeRepository` (env value) — distinct names, consistent across tasks. `liveOffsetFraction` named identically in `PagedLearningStack` and `MainTabView`. `isEligible` matches across controller and tests. `currentDailyStreak` / `totalReviewsCompleted` match `RPGState` field names verified against source.

**Placeholder scan** — none. Every step has executable content.

**Scope check** — single cohesive feature, single plan, ~22 tasks, mostly atomic (2–5 minutes each). Phase boundaries map to commit groups.
