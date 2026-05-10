# Tatami Direction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the Tatami visual vocabulary across every Ikeru screen and add EN/FR localization, with zero functional change to view-models, persistence, or business logic.

**Architecture:** New theme primitives under `Ikeru/Views/Shared/Theme/Tatami/` (marble background, fusuma rails, sumi corners, mon crests, hanko stamps, torii frame, tatami room modifier). New `Ikeru/Localization/` folder with String Catalog + `AppLocale` service driving a root-level `\.locale` environment override on `MainTabView`. Per-screen passes restyle `body` only and migrate strings into the catalog with FR translations.

**Tech Stack:** SwiftUI, Swift 6 (strict concurrency), iOS 17 deployment target, Swift Testing for unit tests, Xcode 15+ String Catalog (`Localizable.xcstrings`).

**Spec:** `docs/design-specs/2026-04-29-tatami-direction.md` (commits `dbb3042` + `5355a6b`).

**Branch:** `design/wabi-refinements`. Work on this branch; do not create new branches.

**Stop condition:** After Task 11, build green and app installs on iPhone simulator. **Do not** drive MobAI — wait for the user's explicit go-ahead.

**Build verification command (run at every step that touches code):**
```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -40
```
Expected: ends with `** BUILD SUCCEEDED **`. If it fails, fix before moving on.

**Test verification command:**
```bash
xcodebuild test -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -30
```

---

## File Structure

### New files

**Theme primitives** (`Ikeru/Views/Shared/Theme/Tatami/`):
| File | Lines | Purpose |
|---|---:|---|
| `TatamiTokens.swift` | ~40 | Vermilion, gold-dim hex constants; mon-kind enum. |
| `SerifNumeral.swift` | ~40 | Convenience for Noto Serif JP numerals. |
| `FusumaRail.swift` | ~50 | Paired-hairline rail (gold + ink shadow), horizontal/vertical. |
| `SumiCornerFrame.swift` | ~80 | Four sharp ink-brushed L-marks at corners. |
| `MonCrest.swift` | ~120 | 4 geometric family crests as `Path` shapes. |
| `HankoStamp.swift` | ~50 | Vermilion clipped square with serif kanji. |
| `BilingualLabel.swift` | ~50 | Section-header pattern (mon + serif JP + middot + caps EN/FR). |
| `MarbleBackground.swift` | ~60 | Picks a marble PNG variant per screen identifier. |
| `ToriiFrame.swift` | ~80 | 鳥居 temple-gate shape around content. |
| `RPGRankCrest.swift` | ~60 | Torii + serif kanji wrapper for the RPG hero crest. |
| `TatamiRoom.swift` | ~140 | ViewModifier: solid fill + fusuma rails + sumi corners + sharp 0px radius. |

**Localization** (`Ikeru/Localization/`):
| File | Purpose |
|---|---|
| `Localizable.xcstrings` | String Catalog with EN+FR translations. |
| `AppLocale.swift` | `@Observable` service, auto-detect rule, `currentLocale: Locale`. |
| `LanguagePickerView.swift` | Settings sheet (Auto / English / Français). |

**Marble PNG assets** (`Ikeru/Assets.xcassets/Tatami/Marble/`):
- `marble-1.imageset/` (Home)
- `marble-2.imageset/` (Active session)
- `marble-3.imageset/` (Session summary)
- `marble-4.imageset/` (RPG profile)
- `marble-5.imageset/` (Study, Companion, Settings, Tab-bar overlay)

Each `.imageset` contains `Contents.json` + `marble-N.png` at `@1x`/`@2x`/`@3x` (3 PNGs per imageset, 750×1624 base size to cover iPhone 14 Pro at @3x).

**Tests** (`IkeruTests/`):
| File | Tests |
|---|---|
| `AppLocaleTests.swift` | Auto-detect rule, preference storage, locale resolution. |
| `MonCrestTests.swift` | Path generation correctness (point counts, bounds). |

### Modified files

| File | Why |
|---|---|
| `Ikeru.xcodeproj/project.pbxproj` | Add `fr` to `knownRegions`. Add Tatami folder + Localization folder + Localizable.xcstrings + Marble assets to the project. |
| `Ikeru/Views/Shared/Theme/IkeruGlass.swift` | Replace `IkeruScreenBackground` body with `MarbleBackground`. |
| `Ikeru/Views/MainTabView.swift` | Inject `\.environment(\.locale, appLocale)` at the root. |
| `Ikeru/Views/Home/HomeView.swift` | Restyle every section to Tatami; localize strings. |
| `Ikeru/Views/Learning/CardReview/SRSCardView.swift` | Tatami card + corners + serif kana. |
| `Ikeru/Views/Learning/CardReview/GradeButtonsView.swift` | Sharp tatami buttons with kanji headers. |
| `Ikeru/Views/Session/SessionSummaryView.swift` | Triumph header + 3 serif numerals + fusuma XP rail. |
| `Ikeru/Views/RPG/RPGProfileView.swift` | Torii hero crest + hanko achievements. |
| `Ikeru/Views/Home/ProgressDashboardView.swift` | JLPT hero + fusuma deck rows. |
| `Ikeru/Views/Learning/Conversation/CompanionTabView.swift` | Sumi-bordered Sakura cell + topic chips. |
| `Ikeru/Views/Settings/SettingsView.swift` | Bilingual rows + Language picker entry. |
| `Ikeru/Views/Shared/Theme/IkeruTabBar.swift` | Kanji-only labels + mon active marker. |

---

## Task 1: Foundations — Theme primitives + asset scaffolding

**Files:**
- Create: `Ikeru/Views/Shared/Theme/Tatami/` (folder)
- Create: 11 Swift files listed in File Structure
- Create: `Ikeru/Assets.xcassets/Tatami/Marble/marble-{1..5}.imageset/`

### Task 1a: Make the Tatami folder and add `TatamiTokens.swift`

- [ ] **Step 1: Create the folder**

```bash
mkdir -p Ikeru/Views/Shared/Theme/Tatami
```

- [ ] **Step 2: Write `TatamiTokens.swift`**

Path: `Ikeru/Views/Shared/Theme/Tatami/TatamiTokens.swift`

```swift
import SwiftUI

// MARK: - Tatami Tokens
//
// Tatami-specific colors that don't belong in `IkeruTheme.Colors` because
// they don't apply outside the Tatami visual vocabulary. Vermilion is the
// hanko-stamp red — used at most once per screen. Gold-dim is the lower-
// intensity sibling of `IkeruTheme.Colors.primaryAccent` used for hairline
// shadows in fusuma rails and inactive sumi corners.

enum TatamiTokens {
    // The single warm red of the entire UI. Used only on hanko stamps.
    static let vermilion = Color(red: 0.78, green: 0.243, blue: 0.20)   // #C73E33

    // Subdued gold, used for hairline shadows and quiet sumi marks.
    static let goldDim = Color(red: 0.541, green: 0.427, blue: 0.290)   // #8A6D4A

    // Paper-ghost — barely-visible labels.
    static let paperGhost = Color(red: 0.478, green: 0.467, blue: 0.439) // #7A7770
}

// MARK: - Mon Kind
//
// Four geometric family-crest patterns. Each kind has a stable identity
// across the app (Hiragana = maru, Katakana = genji, Vocabulary = asanoha,
// Listening = kikkou) so users learn to associate a deck with its crest.

enum MonKind: String, Sendable, CaseIterable {
    case asanoha   // hemp-leaf — 6-pointed star inside circle
    case genji     // genji-wheel — circle with cross
    case kikkou    // hexagon (tortoiseshell)
    case maru      // simple ring
}
```

- [ ] **Step 3: Verify the file compiles**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. (The file isn't in the Xcode project yet so it won't compile into the bundle — but the file should at least parse without errors when added later. Add the new folder to the Xcode project: open `Ikeru.xcodeproj` in Xcode → drag `Ikeru/Views/Shared/Theme/Tatami/` into the project navigator under `Theme/`, choose "Create groups", target = Ikeru.)

If you cannot open Xcode interactively in this environment, add the folder via `xcodebuild`-friendly tooling: use `xcodeproj` Ruby gem or edit `project.pbxproj` directly. The simplest path: put the file in place, then run the build — Xcode automatically detects new `.swift` files in folders that map to a group reference. If your `.pbxproj` uses file references (not group folders), you'll need to add the file explicitly.

For this plan, **assume the engineer can open Xcode**. Each new `.swift` file under `Ikeru/Views/Shared/Theme/Tatami/` should be added to the Ikeru target before that file's commit step.

- [ ] **Step 4: Commit**

```bash
git add Ikeru/Views/Shared/Theme/Tatami/TatamiTokens.swift Ikeru.xcodeproj
git commit -m "feat(tatami): add TatamiTokens with vermilion and mon kinds"
```

### Task 1b: Add `SerifNumeral.swift`

- [ ] **Step 1: Write the file**

Path: `Ikeru/Views/Shared/Theme/Tatami/SerifNumeral.swift`

```swift
import SwiftUI

// MARK: - SerifNumeral
//
// All numerals in the Tatami vocabulary render in Noto Serif JP. This view
// wraps the `Text` + `.font(.system(...design: .serif))` pattern so call
// sites stay readable and consistent.

struct SerifNumeral: View {
    let value: String
    var size: CGFloat = 32
    var weight: Font.Weight = .light
    var color: Color = .ikeruTextPrimary

    init(_ value: String, size: CGFloat = 32, weight: Font.Weight = .light, color: Color = .ikeruTextPrimary) {
        self.value = value
        self.size = size
        self.weight = weight
        self.color = color
    }

    init(_ value: Int, size: CGFloat = 32, weight: Font.Weight = .light, color: Color = .ikeruTextPrimary) {
        self.value = "\(value)"
        self.size = size
        self.weight = weight
        self.color = color
    }

    var body: some View {
        Text(value)
            .font(.system(size: size, weight: weight, design: .serif))
            .foregroundStyle(color)
    }
}

#Preview("SerifNumeral") {
    VStack(spacing: 24) {
        SerifNumeral(12, size: 56)
        SerifNumeral("84", size: 32)
        SerifNumeral("6:42", size: 40, color: .ikeruPrimaryAccent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Add file to Xcode project, build**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Ikeru/Views/Shared/Theme/Tatami/SerifNumeral.swift Ikeru.xcodeproj
git commit -m "feat(tatami): add SerifNumeral helper"
```

### Task 1c: Add `FusumaRail.swift`

- [ ] **Step 1: Write the file**

Path: `Ikeru/Views/Shared/Theme/Tatami/FusumaRail.swift`

```swift
import SwiftUI

// MARK: - FusumaRail
//
// Paired-hairline rail. Comes from sliding-door rail joinery — a 1px gold
// line on top, a 1px transparent gap, a 1px ink-shadow line below. Total
// thickness 3px. Used wherever a 1px border would normally go.

struct FusumaRail: View {
    enum Orientation { case horizontal, vertical }

    var orientation: Orientation = .horizontal
    var gold: Color = .ikeruPrimaryAccent
    var shadow: Color = .black.opacity(0.7)
    var opacity: Double = 1
    /// When true, the gold line is on the bottom (ink top). Use this on the
    /// bottom rail of a TatamiRoom so the gleaming line frames the contents
    /// from above.
    var inverted: Bool = false

    var body: some View {
        let topColor = inverted ? shadow : gold
        let bottomColor = inverted ? gold : shadow
        let stops: [Gradient.Stop] = [
            .init(color: topColor.opacity(opacity), location: 0),
            .init(color: topColor.opacity(opacity), location: 1.0/3.0),
            .init(color: .clear, location: 1.0/3.0),
            .init(color: .clear, location: 2.0/3.0),
            .init(color: bottomColor.opacity(opacity), location: 2.0/3.0),
            .init(color: bottomColor.opacity(opacity), location: 1)
        ]
        let gradient = LinearGradient(
            stops: stops,
            startPoint: orientation == .horizontal ? .top : .leading,
            endPoint: orientation == .horizontal ? .bottom : .trailing
        )
        Rectangle()
            .fill(gradient)
            .frame(
                width: orientation == .vertical ? 3 : nil,
                height: orientation == .horizontal ? 3 : nil
            )
            .allowsHitTesting(false)
    }
}

#Preview("FusumaRail") {
    VStack(spacing: 24) {
        FusumaRail(orientation: .horizontal)
        FusumaRail(orientation: .horizontal, inverted: true)
        HStack { FusumaRail(orientation: .vertical).frame(height: 80); Spacer() }
    }
    .padding(40)
    .background(Color.ikeruSurface)
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build and commit**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
git add Ikeru/Views/Shared/Theme/Tatami/FusumaRail.swift Ikeru.xcodeproj
git commit -m "feat(tatami): add FusumaRail (paired-hairline rail)"
```

Expected build: `** BUILD SUCCEEDED **`.

### Task 1d: Add `SumiCornerFrame.swift`

- [ ] **Step 1: Write the file**

Path: `Ikeru/Views/Shared/Theme/Tatami/SumiCornerFrame.swift`

```swift
import SwiftUI

// MARK: - SumiCornerFrame
//
// Four sharp ink-brushed L-marks at the corners of the host view. Replaces
// rounded-corner radius — the Tatami direction insists on 0px corner radius
// and uses sumi marks to do the visual softening that radius normally does.
//
// Apply via the `.sumiCorners(...)` modifier; corners are drawn as overlays
// so the host view's intrinsic size is unchanged.

struct SumiCornerFrame: ViewModifier {
    var color: Color = .ikeruPrimaryAccent
    var size: CGFloat = 10
    var weight: CGFloat = 1.5
    var inset: CGFloat = -2 // sits slightly outside the rect, like a real brush

    func body(content: Content) -> some View {
        content.overlay {
            ZStack {
                cornerPath(corner: .topLeading)
                cornerPath(corner: .topTrailing)
                cornerPath(corner: .bottomTrailing)
                cornerPath(corner: .bottomLeading)
            }
            .allowsHitTesting(false)
        }
    }

    private enum Corner { case topLeading, topTrailing, bottomTrailing, bottomLeading }

    private func cornerPath(corner: Corner) -> some View {
        Path { p in
            switch corner {
            case .topLeading:
                p.move(to: CGPoint(x: 0, y: size))
                p.addLine(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: size, y: 0))
            case .topTrailing:
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: size, y: 0))
                p.addLine(to: CGPoint(x: size, y: size))
            case .bottomTrailing:
                p.move(to: CGPoint(x: size, y: 0))
                p.addLine(to: CGPoint(x: size, y: size))
                p.addLine(to: CGPoint(x: 0, y: size))
            case .bottomLeading:
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: 0, y: size))
                p.addLine(to: CGPoint(x: size, y: size))
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: weight, lineCap: .square))
        .frame(width: size, height: size)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(for: corner))
        .padding(corner == .topLeading || corner == .topTrailing
                 ? .top : .bottom, inset)
        .padding(corner == .topLeading || corner == .bottomLeading
                 ? .leading : .trailing, inset)
    }

    private func alignment(for corner: Corner) -> Alignment {
        switch corner {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomTrailing: return .bottomTrailing
        case .bottomLeading: return .bottomLeading
        }
    }
}

extension View {
    func sumiCorners(
        color: Color = .ikeruPrimaryAccent,
        size: CGFloat = 10,
        weight: CGFloat = 1.5,
        inset: CGFloat = -2
    ) -> some View {
        modifier(SumiCornerFrame(color: color, size: size, weight: weight, inset: inset))
    }
}

#Preview("SumiCornerFrame") {
    VStack(spacing: 24) {
        Rectangle()
            .fill(Color.ikeruSurface)
            .frame(width: 200, height: 100)
            .sumiCorners(color: .ikeruPrimaryAccent)
        Rectangle()
            .fill(Color.ikeruSurface)
            .frame(width: 200, height: 100)
            .sumiCorners(color: TatamiTokens.goldDim, size: 6, weight: 1.2)
    }
    .padding(40)
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build and commit**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
git add Ikeru/Views/Shared/Theme/Tatami/SumiCornerFrame.swift Ikeru.xcodeproj
git commit -m "feat(tatami): add SumiCornerFrame modifier"
```

### Task 1e: Add `MonCrest.swift` + tests

- [ ] **Step 1: Write the failing test**

Path: `IkeruTests/MonCrestTests.swift`

```swift
import Testing
import SwiftUI
@testable import Ikeru

struct MonCrestTests {
    @Test("All four mon kinds render a non-empty path inside the bounds")
    func allKindsRender() {
        let rect = CGRect(x: 0, y: 0, width: 24, height: 24)
        for kind in MonKind.allCases {
            let path = MonCrestShape(kind: kind).path(in: rect)
            #expect(!path.isEmpty, "Mon \(kind) produced an empty path")
            #expect(rect.insetBy(dx: -1, dy: -1).contains(path.boundingRect),
                    "Mon \(kind) escapes its bounds")
        }
    }
}
```

- [ ] **Step 2: Run test, verify it fails (because `MonCrestShape` doesn't exist yet)**

```bash
xcodebuild test -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:IkeruTests/MonCrestTests -quiet 2>&1 | tail -10
```

Expected: build error — "Cannot find 'MonCrestShape' in scope".

- [ ] **Step 3: Write `MonCrest.swift`**

Path: `Ikeru/Views/Shared/Theme/Tatami/MonCrest.swift`

```swift
import SwiftUI

// MARK: - MonCrest
//
// Four geometric Japanese family-crest variants:
// - asanoha (hemp-leaf, 6-point star inside circle)
// - genji (4-fold cross inside circle)
// - kikkou (hexagon)
// - maru (simple ring)
//
// Used as deck identifiers, tab-bar active markers, status indicators.
// Replaces colored dots and SF Symbols.

struct MonCrest: View {
    let kind: MonKind
    var size: CGFloat = 14
    var color: Color = .ikeruPrimaryAccent
    var lineWidth: CGFloat? = nil  // defaults to size * 0.066

    var body: some View {
        MonCrestShape(kind: kind)
            .stroke(color, lineWidth: lineWidth ?? max(0.6, size * 0.066))
            .frame(width: size, height: size)
    }
}

struct MonCrestShape: Shape {
    let kind: MonKind

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) * 0.46
        var p = Path()

        switch kind {
        case .asanoha:
            p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            for i in 0..<6 {
                let a = (Double(i) * .pi / 3) - .pi / 2
                let endpoint = CGPoint(x: c.x + cos(a) * r * 0.88,
                                        y: c.y + sin(a) * r * 0.88)
                p.move(to: c)
                p.addLine(to: endpoint)
            }

        case .genji:
            p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            p.move(to: CGPoint(x: c.x, y: c.y - r))
            p.addLine(to: CGPoint(x: c.x, y: c.y + r))
            p.move(to: CGPoint(x: c.x - r, y: c.y))
            p.addLine(to: CGPoint(x: c.x + r, y: c.y))

        case .kikkou:
            for i in 0..<6 {
                let a = Double(i) * .pi / 3
                let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()

        case .maru:
            let inner = r * 0.85
            p.addEllipse(in: CGRect(x: c.x - inner, y: c.y - inner,
                                     width: inner * 2, height: inner * 2))
        }
        return p
    }
}

#Preview("MonCrest") {
    HStack(spacing: 24) {
        ForEach(MonKind.allCases, id: \.self) { kind in
            VStack {
                MonCrest(kind: kind, size: 32, color: .ikeruPrimaryAccent)
                Text(kind.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
    .padding(40)
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 4: Run test, verify it passes**

```bash
xcodebuild test -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:IkeruTests/MonCrestTests -quiet 2>&1 | tail -5
```

Expected: `Test Suite 'MonCrestTests' passed`.

- [ ] **Step 5: Commit**

```bash
git add Ikeru/Views/Shared/Theme/Tatami/MonCrest.swift IkeruTests/MonCrestTests.swift Ikeru.xcodeproj
git commit -m "feat(tatami): add MonCrest with 4 family-crest variants"
```

### Task 1f: Add `HankoStamp.swift`

- [ ] **Step 1: Write the file**

Path: `Ikeru/Views/Shared/Theme/Tatami/HankoStamp.swift`

```swift
import SwiftUI

// MARK: - HankoStamp
//
// Vermilion clipped square containing a serif kanji. Used at most once per
// screen to mark the single most urgent thing — the only red in the entire
// UI. Slight clip-path irregularity is intentional: this has to read as a
// real ink seal impression, not a pristine button.

struct HankoStamp: View {
    let kanji: String
    var size: CGFloat = 32
    var opacity: Double = 0.95

    var body: some View {
        ZStack {
            // Slightly irregular ink seal — clip-path mimics the tiny
            // unevenness of pressed-stone seal contact with paper.
            HankoMaskShape()
                .fill(TatamiTokens.vermilion)
                .opacity(opacity)
                .overlay(
                    HankoMaskShape()
                        .stroke(.black.opacity(0.25), lineWidth: 0.6)
                        .blur(radius: 0.5)
                )
            Text(kanji)
                .font(.system(size: size * 0.55, weight: .bold, design: .serif))
                .foregroundStyle(Color(red: 0.961, green: 0.949, blue: 0.925)) // ikeru paper
        }
        .frame(width: size, height: size)
    }
}

private struct HankoMaskShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        // Tiny offsets each corner — irregularities of a stamp impression
        p.move(to: CGPoint(x: w * 0.02, y: 0))
        p.addLine(to: CGPoint(x: w * 0.98, y: h * 0.01))
        p.addLine(to: CGPoint(x: w, y: h * 0.97))
        p.addLine(to: CGPoint(x: w * 0.01, y: h * 0.99))
        p.closeSubpath()
        return p
    }
}

#Preview("HankoStamp") {
    HStack(spacing: 24) {
        HankoStamp(kanji: "急", size: 36)
        HankoStamp(kanji: "N5", size: 42)
        HankoStamp(kanji: "極", size: 28)
    }
    .padding(40)
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build and commit**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
git add Ikeru/Views/Shared/Theme/Tatami/HankoStamp.swift Ikeru.xcodeproj
git commit -m "feat(tatami): add HankoStamp (vermilion seal)"
```

### Task 1g: Add `BilingualLabel.swift`

- [ ] **Step 1: Write the file**

Path: `Ikeru/Views/Shared/Theme/Tatami/BilingualLabel.swift`

```swift
import SwiftUI

// MARK: - BilingualLabel
//
// The section-header pattern: optional mon + serif Japanese + middot +
// uppercase chrome label (EN or FR). Used everywhere a "TODAY", "DECKS",
// "SETTINGS"-style label lives in the current app.
//
// The Japanese half is fixed content (it's what the app teaches); the
// `chrome` parameter flows through localization so it switches with the
// app language.

struct BilingualLabel: View {
    let japanese: String
    /// The localized chrome label. Pass either a `LocalizedStringKey` (e.g.
    /// `"TODAY"`) so it auto-translates, or a literal `String` if the value
    /// is already localized at the call site.
    let chrome: LocalizedStringKey
    var mon: MonKind? = nil

    var body: some View {
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

#Preview("BilingualLabel") {
    VStack(alignment: .leading, spacing: 16) {
        BilingualLabel(japanese: "本日", chrome: "Today", mon: .asanoha)
        BilingualLabel(japanese: "稽古場", chrome: "Decks", mon: .kikkou)
        BilingualLabel(japanese: "進歩", chrome: "Progress")
    }
    .padding(40)
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build and commit**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
git add Ikeru/Views/Shared/Theme/Tatami/BilingualLabel.swift Ikeru.xcodeproj
git commit -m "feat(tatami): add BilingualLabel (JP · localized chrome)"
```

### Task 1h: Generate marble PNG assets

- [ ] **Step 1: Write the marble-generator HTML**

Path: `/tmp/marble-gen.html` (not committed)

```bash
cat > /tmp/marble-gen.html <<'HTML'
<!DOCTYPE html>
<html><head><style>
  body { margin: 0; padding: 0; background: #000; }
  .marble { width: 750px; height: 1624px; display: block; }
</style></head><body>
<svg id="m1" class="marble" preserveAspectRatio="xMidYMid slice">
  <defs>
    <filter id="n1"><feTurbulence type="fractalNoise" baseFrequency="0.012 0.025" numOctaves="3" seed="11"/><feColorMatrix values="0 0 0 0 0.04  0 0 0 0 0.04  0 0 0 0 0.06  0 0 0 0.55 0"/></filter>
    <radialGradient id="w1" cx="30%" cy="15%" r="75%">
      <stop offset="0%" stop-color="#1A1410"/><stop offset="55%" stop-color="#0E0C10"/><stop offset="100%" stop-color="#070709"/>
    </radialGradient>
    <linearGradient id="v1" x1="0" x2="1" y1="0" y2="1">
      <stop offset="0%" stop-color="#D4A574" stop-opacity="0"/><stop offset="40%" stop-color="#D4A574" stop-opacity="0.32"/>
      <stop offset="60%" stop-color="#E8C896" stop-opacity="0.4"/><stop offset="100%" stop-color="#8A6D4A" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <rect width="750" height="1624" fill="url(#w1)"/>
  <rect width="750" height="1624" filter="url(#n1)" opacity="0.7"/>
  <g stroke="url(#v1)" fill="none" stroke-linecap="round">
    <path d="M -50 360 Q 180 440 440 560 T 920 720" stroke-width="2.4" opacity="0.7"/>
    <path d="M 120 -40 Q 280 240 360 480 T 640 960" stroke-width="1.6" opacity="0.5"/>
    <path d="M 760 160 Q 640 440 480 640 T 160 1120" stroke-width="2.0" opacity="0.55"/>
    <path d="M -60 1240 Q 240 1200 480 1440 T 920 1680" stroke-width="1.8" opacity="0.6"/>
  </g>
</svg>
<!-- repeat with seeds 5, 3, 18, 7 for marble-2..5, varying gradient cx/cy -->
</body></html>
HTML
```

(For brevity, the actual file should contain 5 SVGs, one per marble. Use seeds: 11, 5, 3, 18, 7. Vary the radial-gradient `cx`/`cy` for vein direction variation.)

- [ ] **Step 2: Render each SVG to PNG via Playwright**

Use the already-installed Playwright instance. From a Node.js / Bash one-liner:

```bash
# Re-launch local server in a known dir
mkdir -p /tmp/marble-out
cp /tmp/marble-gen.html /tmp/marble-out/index.html
cd /tmp/marble-out && python3 -m http.server 8765 &
SERVER_PID=$!
sleep 1
# Now use Playwright via the MCP browser to navigate + screenshot each SVG.
# For each marble id m1..m5, navigate to localhost:8765, evaluate the SVG to a Blob, save as PNG at @1x/@2x/@3x.
# Concretely: take a 250x541 screenshot of #m1 (which is base @1x = 250x541; @2x = 500x1082; @3x = 750x1624).
# Save to: Ikeru/Assets.xcassets/Tatami/Marble/marble-1.imageset/marble-1{,_2x,_3x}.png
kill $SERVER_PID
```

Concretely: render each marble into the imageset folder. Below is one `Contents.json` template — same shape per imageset, just rename the file references:

Path: `Ikeru/Assets.xcassets/Tatami/Marble/marble-1.imageset/Contents.json`

```json
{
  "images" : [
    { "filename" : "marble-1.png",    "idiom" : "universal", "scale" : "1x" },
    { "filename" : "marble-1@2x.png", "idiom" : "universal", "scale" : "2x" },
    { "filename" : "marble-1@3x.png", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "preserves-vector-representation" : false, "template-rendering-intent" : "original" }
}
```

Repeat for marble-{2..5}.imageset/.

- [ ] **Step 3: Verify the assets in Xcode**

Open `Ikeru.xcodeproj`, navigate `Tatami/Marble/` in the asset catalog, confirm each imageset has 3 PNGs at @1x/@2x/@3x and renders as a dark marble texture.

- [ ] **Step 4: Commit**

```bash
git add Ikeru/Assets.xcassets/Tatami/
git commit -m "feat(tatami): add 5 baked marble PNG variants"
```

### Task 1i: Add `MarbleBackground.swift`

- [ ] **Step 1: Write the file**

Path: `Ikeru/Views/Shared/Theme/Tatami/MarbleBackground.swift`

```swift
import SwiftUI

// MARK: - MarbleBackground
//
// Picks a marble PNG variant by screen identifier. Five variants ship
// (`marble-1`..`marble-5`); the ID maps deterministically so the user sees
// the same marble on the same screen on every visit.
//
// Sits behind every screen as the first layer of the Tatami visual stack.

enum MarbleVariant: String, Sendable, CaseIterable {
    case home          = "marble-1"
    case session       = "marble-2"
    case summary       = "marble-3"
    case rpg           = "marble-4"
    case auxiliary     = "marble-5"  // Study, Companion, Settings, Tab-bar
}

struct MarbleBackground: View {
    let variant: MarbleVariant

    var body: some View {
        Image(variant.rawValue)
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

#Preview("MarbleBackground") {
    ZStack {
        MarbleBackground(variant: .home)
        VStack(spacing: 12) {
            Text("Home").foregroundStyle(.white)
            Text("(marble-1)").foregroundStyle(.white.opacity(0.5)).font(.caption)
        }
    }
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build and commit**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
git add Ikeru/Views/Shared/Theme/Tatami/MarbleBackground.swift Ikeru.xcodeproj
git commit -m "feat(tatami): add MarbleBackground variant picker"
```

### Task 1j: Add `ToriiFrame.swift`

- [ ] **Step 1: Write the file**

Path: `Ikeru/Views/Shared/Theme/Tatami/ToriiFrame.swift`

```swift
import SwiftUI

// MARK: - ToriiFrame
//
// 鳥居 (temple gate) frame. Two vertical pillars (hashira) topped by a
// horizontal kasagi crossbeam with a slight upward curve at each end, and
// a thinner nuki crossbeam below that. The host content (rank kanji)
// renders inside the negative space between the pillars.
//
// Used as the RPG profile rank crest. At sizes ≥ 80, the gate's
// architecture reads cleanly. Smaller crest uses keep `EnsoRankView`.

struct ToriiFrame<Content: View>: View {
    var color: Color = .ikeruPrimaryAccent
    var lineWidth: CGFloat = 4
    var dashed: Bool = false  // for the "next rank" teaser
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                ToriiShape()
                    .stroke(
                        color,
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: dashed ? [3, 4] : []
                        )
                    )
                content()
                    .frame(width: w * 0.55, height: h * 0.55)
                    .offset(y: h * 0.05) // sit slightly below the kasagi
            }
        }
    }
}

private struct ToriiShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        // Pillar geometry
        let pillarOffset = w * 0.12
        let leftX  = rect.minX + pillarOffset
        let rightX = rect.maxX - pillarOffset
        let pillarBottom = rect.minY + h * 0.95
        let pillarTop    = rect.minY + h * 0.30
        // Kasagi (top crossbeam) — slight upward sweep at each end
        let kasagiY      = rect.minY + h * 0.18
        let kasagiLeftX  = rect.minX + w * 0.04
        let kasagiRightX = rect.maxX - w * 0.04
        let kasagiTipY   = rect.minY + h * 0.08
        // Nuki (lower crossbeam, between kasagi and pillars)
        let nukiY        = rect.minY + h * 0.32
        let nukiLeftX    = rect.minX + w * 0.18
        let nukiRightX   = rect.maxX - w * 0.18

        // Left pillar
        p.move(to: CGPoint(x: leftX, y: pillarBottom))
        p.addLine(to: CGPoint(x: leftX, y: pillarTop))
        // Right pillar
        p.move(to: CGPoint(x: rightX, y: pillarBottom))
        p.addLine(to: CGPoint(x: rightX, y: pillarTop))
        // Kasagi — left tip up, then horizontal across, then right tip up
        p.move(to: CGPoint(x: kasagiLeftX, y: kasagiTipY))
        p.addQuadCurve(
            to: CGPoint(x: rect.midX, y: kasagiY),
            control: CGPoint(x: rect.minX + w * 0.25, y: kasagiY + 2)
        )
        p.addQuadCurve(
            to: CGPoint(x: kasagiRightX, y: kasagiTipY),
            control: CGPoint(x: rect.maxX - w * 0.25, y: kasagiY + 2)
        )
        // Nuki
        p.move(to: CGPoint(x: nukiLeftX, y: nukiY))
        p.addLine(to: CGPoint(x: nukiRightX, y: nukiY))

        return p
    }
}

#Preview("ToriiFrame") {
    HStack(spacing: 32) {
        ToriiFrame(color: .ikeruPrimaryAccent, lineWidth: 4) {
            Text("三")
                .font(.system(size: 38, weight: .light, design: .serif))
                .foregroundStyle(Color.ikeruPrimaryAccent)
        }
        .frame(width: 96, height: 96)

        ToriiFrame(color: TatamiTokens.goldDim, lineWidth: 2.5, dashed: true) {
            Text("四")
                .font(.system(size: 22, weight: .light, design: .serif))
                .foregroundStyle(TatamiTokens.goldDim)
        }
        .frame(width: 56, height: 56)
        .opacity(0.6)
    }
    .padding(40)
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build and commit**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
git add Ikeru/Views/Shared/Theme/Tatami/ToriiFrame.swift Ikeru.xcodeproj
git commit -m "feat(tatami): add ToriiFrame for RPG rank crest"
```

### Task 1k: Add `RPGRankCrest.swift`

- [ ] **Step 1: Write the file**

Path: `Ikeru/Views/Shared/Theme/Tatami/RPGRankCrest.swift`

```swift
import SwiftUI

// MARK: - RPGRankCrest
//
// Hero rank crest for the RPG profile. Wraps `ToriiFrame` with the rank
// kanji (大字: 一 二 三 …) centered between the pillars in a serif weight.
//
// Use only at sizes ≥ 80. For smaller rank glyphs (Home pill, hero rank
// row), keep `EnsoRankView` — the torii's architecture loses detail under
// 60pt and reads as noise.

struct RPGRankCrest: View {
    let level: Int
    var size: CGFloat = 96
    var dashed: Bool = false  // for the "next rank" teaser

    var body: some View {
        ToriiFrame(
            color: dashed ? TatamiTokens.goldDim : .ikeruPrimaryAccent,
            lineWidth: dashed ? 2.5 : 4,
            dashed: dashed
        ) {
            Text(rankKanji(level))
                .font(.system(size: size * 0.40, weight: .light, design: .serif))
                .foregroundStyle(dashed ? TatamiTokens.goldDim : Color.ikeruPrimaryAccent)
        }
        .frame(width: size, height: size)
    }

    private func rankKanji(_ n: Int) -> String {
        // Daiji (formal numerals) feel ceremonial enough for ranks. Falls
        // back to the ASCII numeral for ranks beyond the prepared range —
        // the glyph still reads inside the gate.
        let lookup: [Int: String] = [
            1: "一", 2: "二", 3: "三", 4: "四", 5: "五",
            6: "六", 7: "七", 8: "八", 9: "九", 10: "十"
        ]
        return lookup[n] ?? "\(n)"
    }
}

#Preview("RPGRankCrest") {
    HStack(spacing: 32) {
        RPGRankCrest(level: 3, size: 96)
        RPGRankCrest(level: 4, size: 56, dashed: true)
    }
    .padding(40)
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build and commit**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
git add Ikeru/Views/Shared/Theme/Tatami/RPGRankCrest.swift Ikeru.xcodeproj
git commit -m "feat(tatami): add RPGRankCrest (torii + rank kanji)"
```

### Task 1l: Add `TatamiRoom.swift`

- [ ] **Step 1: Write the file**

Path: `Ikeru/Views/Shared/Theme/Tatami/TatamiRoom.swift`

```swift
import SwiftUI

// MARK: - TatamiRoom
//
// The card-equivalent of the Tatami direction: solid fill (no rounded
// corners), top + bottom fusuma rails, and four sumi corners. Replaces
// `IkeruCard` everywhere in the per-screen restyle.
//
// Variants:
//   .standard — quiet ink fill, dim-gold rails and corners
//   .accent   — warmer fill (ink with a faint gold tint), full-gold rails
//   .glass    — translucent Liquid-Glass surface used SPARINGLY on hero
//               cards (Home hero, SRS card, JLPT estimate, RPG hero,
//               Conversation hero). Honors the design's "selective glass"
//               principle.

enum TatamiRoomVariant: Sendable {
    case standard
    case accent
    case glass     // accent + glass
}

struct TatamiRoomModifier: ViewModifier {
    let variant: TatamiRoomVariant
    let padding: EdgeInsets

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(roomBackground)
            .overlay(alignment: .top) { FusumaRail(gold: railGold, opacity: railOpacity) }
            .overlay(alignment: .bottom) { FusumaRail(gold: railGold, opacity: railOpacity, inverted: true) }
            .sumiCorners(color: cornerColor, size: 10, weight: 1.5)
    }

    @ViewBuilder
    private var roomBackground: some View {
        switch variant {
        case .standard:
            Rectangle().fill(Color(red: 0.102, green: 0.102, blue: 0.133)) // #1A1A22
        case .accent:
            LinearGradient(
                colors: [
                    Color(red: 0.122, green: 0.102, blue: 0.071),  // #1F1A12
                    Color(red: 0.102, green: 0.086, blue: 0.071)   // #1A1612
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .glass:
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.157, green: 0.118, blue: 0.071, opacity: 0.55),
                        Color(red: 0.110, green: 0.086, blue: 0.071, opacity: 0.45)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .background(.ultraThinMaterial)
            }
        }
    }

    private var railGold: Color {
        switch variant {
        case .standard: return TatamiTokens.goldDim
        case .accent, .glass: return .ikeruPrimaryAccent
        }
    }

    private var railOpacity: Double {
        switch variant {
        case .standard: return 0.7
        case .accent, .glass: return 1.0
        }
    }

    private var cornerColor: Color {
        switch variant {
        case .standard: return TatamiTokens.goldDim
        case .accent, .glass: return .ikeruPrimaryAccent
        }
    }
}

extension View {
    /// Wrap a view in a Tatami room (fusuma rails + sumi corners + solid fill).
    /// - Parameters:
    ///   - variant: visual treatment
    ///   - padding: inner padding (defaults to 18 on all sides)
    func tatamiRoom(
        _ variant: TatamiRoomVariant = .standard,
        padding: EdgeInsets = EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
    ) -> some View {
        modifier(TatamiRoomModifier(variant: variant, padding: padding))
    }

    /// Convenience: uniform padding.
    func tatamiRoom(
        _ variant: TatamiRoomVariant = .standard,
        padding: CGFloat
    ) -> some View {
        modifier(TatamiRoomModifier(
            variant: variant,
            padding: EdgeInsets(top: padding, leading: padding, bottom: padding, trailing: padding)
        ))
    }
}

#Preview("TatamiRoom") {
    ScrollView {
        VStack(spacing: 20) {
            Text("Standard").foregroundStyle(.white)
                .tatamiRoom(.standard)
            Text("Accent").foregroundStyle(.white)
                .tatamiRoom(.accent)
            Text("Glass").foregroundStyle(.white)
                .tatamiRoom(.glass)
        }
        .padding(20)
    }
    .background(MarbleBackground(variant: .home))
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build and commit**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
git add Ikeru/Views/Shared/Theme/Tatami/TatamiRoom.swift Ikeru.xcodeproj
git commit -m "feat(tatami): add TatamiRoom modifier (rails + sumi + solid fill)"
```

### Task 1m: End-of-Task-1 verification

- [ ] **Step 1: Run all tests**

```bash
xcodebuild test -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -15
```

Expected: all existing tests still pass; `MonCrestTests` is among them and passes.

- [ ] **Step 2: Visually verify previews in Xcode**

For each new file under `Ikeru/Views/Shared/Theme/Tatami/`, open the file in Xcode and click the `#Preview` icon. Confirm each preview renders without runtime errors and shows the component as described in the spec.

- [ ] **Step 3: No commit needed — Task 1 complete**

---

## Task 2: Localization scaffolding

**Files:**
- Create: `Ikeru/Localization/AppLocale.swift`
- Create: `Ikeru/Localization/Localizable.xcstrings`
- Create: `Ikeru/Localization/LanguagePickerView.swift`
- Create: `IkeruTests/AppLocaleTests.swift`
- Modify: `Ikeru.xcodeproj/project.pbxproj` (add `fr` to `knownRegions`)
- Modify: `Ikeru/Views/MainTabView.swift` (inject `\.locale`)

### Task 2a: Add `fr` to `knownRegions`

- [ ] **Step 1: Edit `project.pbxproj`**

Open `Ikeru.xcodeproj/project.pbxproj`, search for `knownRegions`. Replace:

```
			knownRegions = (
				Base,
				en,
			);
```

With:

```
			knownRegions = (
				Base,
				en,
				fr,
			);
```

- [ ] **Step 2: Build to confirm the project file is still valid**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Ikeru.xcodeproj/project.pbxproj
git commit -m "chore(i18n): add fr to knownRegions"
```

### Task 2b: Add `AppLocale.swift` with auto-detection rule + tests

- [ ] **Step 1: Write the failing test**

Path: `IkeruTests/AppLocaleTests.swift`

```swift
import Testing
import Foundation
@testable import Ikeru

struct AppLocaleTests {
    @Test("System preference picks French when device prefers any French variant")
    func systemPicksFrench() {
        let cases = ["fr", "fr-FR", "fr-CA", "fr-BE"]
        for variant in cases {
            let resolved = AppLocale.resolveSystem(preferredLanguages: [variant, "en-US"])
            #expect(resolved.identifier.hasPrefix("fr"),
                    "preferredLanguages = [\(variant)] should resolve to French")
        }
    }

    @Test("System preference falls back to English for non-French locales")
    func systemFallsBackToEnglish() {
        let cases = ["en", "en-US", "ja-JP", "de", "es-ES"]
        for variant in cases {
            let resolved = AppLocale.resolveSystem(preferredLanguages: [variant])
            #expect(resolved.identifier.hasPrefix("en"),
                    "preferredLanguages = [\(variant)] should resolve to English")
        }
    }

    @Test("Empty preferred languages defaults to English")
    func emptyDefaultsToEnglish() {
        let resolved = AppLocale.resolveSystem(preferredLanguages: [])
        #expect(resolved.identifier.hasPrefix("en"))
    }

    @Test("Preference 'en' overrides device locale")
    func enPreferenceOverrides() {
        let pref = LanguagePreference.en
        let resolved = AppLocale.resolve(preference: pref, preferredLanguages: ["fr-FR"])
        #expect(resolved.identifier.hasPrefix("en"))
    }

    @Test("Preference 'fr' overrides device locale")
    func frPreferenceOverrides() {
        let pref = LanguagePreference.fr
        let resolved = AppLocale.resolve(preference: pref, preferredLanguages: ["en-US"])
        #expect(resolved.identifier.hasPrefix("fr"))
    }
}
```

- [ ] **Step 2: Run test, verify it fails (`AppLocale` doesn't exist)**

```bash
xcodebuild test -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:IkeruTests/AppLocaleTests -quiet 2>&1 | tail -10
```

Expected: build error — "Cannot find 'AppLocale' in scope".

- [ ] **Step 3: Create the folder + write `AppLocale.swift`**

```bash
mkdir -p Ikeru/Localization
```

Path: `Ikeru/Localization/AppLocale.swift`

```swift
import SwiftUI
import Observation

// MARK: - LanguagePreference

enum LanguagePreference: String, Sendable, CaseIterable {
    case system  // auto-detect from device
    case en      // force English
    case fr      // force French
}

// MARK: - AppLocale
//
// Source of truth for the UI language. Reads `@AppStorage` and exposes a
// `currentLocale: Locale` to inject via `\.locale` at the root view. The
// auto-detection rule: if any of the device's preferred languages start
// with `"fr"`, default to French; otherwise English.

@Observable
final class AppLocale {
    static let storageKey = "ikeru.uiLanguage"

    private(set) var preference: LanguagePreference {
        didSet { UserDefaults.standard.set(preference.rawValue, forKey: Self.storageKey) }
    }

    init(preference: LanguagePreference? = nil) {
        if let preference {
            self.preference = preference
        } else if
            let raw = UserDefaults.standard.string(forKey: Self.storageKey),
            let stored = LanguagePreference(rawValue: raw)
        {
            self.preference = stored
        } else {
            self.preference = .system
        }
    }

    /// Update the preference and persist it.
    func setPreference(_ new: LanguagePreference) { preference = new }

    /// Resolve the locale to inject into `\.environment(\.locale, _)`.
    var currentLocale: Locale {
        Self.resolve(preference: preference, preferredLanguages: Locale.preferredLanguages)
    }

    // MARK: - Pure helpers (testable)

    /// Resolve a locale given a preference and the device's preferred-language list.
    static func resolve(preference: LanguagePreference, preferredLanguages: [String]) -> Locale {
        switch preference {
        case .en: return Locale(identifier: "en")
        case .fr: return Locale(identifier: "fr")
        case .system: return resolveSystem(preferredLanguages: preferredLanguages)
        }
    }

    /// Auto-detect rule: French if any preferred language begins with "fr",
    /// otherwise English. Used when the user's preference is `.system`.
    static func resolveSystem(preferredLanguages: [String]) -> Locale {
        if preferredLanguages.contains(where: { $0.lowercased().hasPrefix("fr") }) {
            return Locale(identifier: "fr")
        }
        return Locale(identifier: "en")
    }
}
```

- [ ] **Step 4: Run test, verify it passes**

```bash
xcodebuild test -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:IkeruTests/AppLocaleTests -quiet 2>&1 | tail -10
```

Expected: `Test Suite 'AppLocaleTests' passed`.

- [ ] **Step 5: Commit**

```bash
git add Ikeru/Localization/AppLocale.swift IkeruTests/AppLocaleTests.swift Ikeru.xcodeproj
git commit -m "feat(i18n): add AppLocale with auto-detection rule + tests"
```

### Task 2c: Create the empty String Catalog

- [ ] **Step 1: Add the catalog via Xcode**

In Xcode, right-click `Ikeru/Localization/` → **New File** → **String Catalog** → name `Localizable`. Add to the Ikeru target. Xcode creates `Ikeru/Localization/Localizable.xcstrings` with `en` as the source language.

In the catalog editor, click **Add Language → French**. The catalog now has EN + FR columns.

- [ ] **Step 2: Verify**

```bash
ls -la Ikeru/Localization/Localizable.xcstrings
```

Expected: file exists, ~200-500 bytes (mostly empty).

- [ ] **Step 3: Build to confirm the catalog is wired into the target**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Ikeru/Localization/Localizable.xcstrings Ikeru.xcodeproj
git commit -m "feat(i18n): add empty Localizable.xcstrings (en + fr)"
```

### Task 2d: Inject `\.locale` at the root view

- [ ] **Step 1: Modify `MainTabView.swift`**

Path: `Ikeru/Views/MainTabView.swift`

Find the line near the top of the struct:

```swift
@State private var presentAISettings = CommandLine.arguments.contains("-presentAISettings")
```

Add this line directly under it:

```swift
@State private var appLocale = AppLocale()
```

Find the line at the bottom of `body` that currently reads:

```swift
        .fullScreenCover(isPresented: $presentAISettings) {
```

(That's the very last modifier on the outermost `ZStack`.)

Insert this line **right above** that `.fullScreenCover`:

```swift
        .environment(\.locale, appLocale.currentLocale)
        .environment(appLocale)
```

Resulting structure of the modifier chain (for reference):

```swift
        .onAppear { ... }
        .onReceive(...) { ... }
        .onReceive(...) { ... }
        .sheet(isPresented: $showCompanionChat) { ... }
        .environment(\.locale, appLocale.currentLocale)
        .environment(appLocale)
        .fullScreenCover(isPresented: $presentAISettings) { ... }
```

- [ ] **Step 2: Build, verify**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Ikeru/Views/MainTabView.swift
git commit -m "feat(i18n): inject AppLocale into root view environment"
```

### Task 2e: Add `LanguagePickerView.swift`

- [ ] **Step 1: Write the file**

Path: `Ikeru/Localization/LanguagePickerView.swift`

```swift
import SwiftUI

// MARK: - LanguagePickerView
//
// Sheet presented from the Settings "言語 / Language" row. Three options
// (Auto / English / Français) — tap an option to set the preference; the
// `\.locale` environment update propagates immediately, so every visible
// `Text` re-renders without an app relaunch.
//
// Visual style matches the Tatami direction: tatami room with fusuma rows,
// hanko on the active row, kanji on the left of each label.

struct LanguagePickerView: View {
    @Environment(AppLocale.self) private var appLocale
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            MarbleBackground(variant: .auxiliary)

            VStack(alignment: .leading, spacing: 24) {
                header
                rows
                Spacer()
            }
            .padding(22)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Text("‹")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
            BilingualLabel(japanese: "言語", chrome: "Language")
            Spacer()
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            row(.system, japanese: "自動", english: "Auto")
            row(.en,     japanese: "英語", english: "English")
            row(.fr,     japanese: "仏語", english: "Français")
        }
        .tatamiRoom(.standard, padding: 0)
    }

    @ViewBuilder
    private func row(_ pref: LanguagePreference, japanese: String, english: String) -> some View {
        let isActive = appLocale.preference == pref
        Button {
            appLocale.setPreference(pref)
        } label: {
            HStack(spacing: 16) {
                Text(japanese)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .frame(width: 36, alignment: .leading)
                Text(english)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ikeruTextPrimary)
                Spacer()
                if isActive { HankoStamp(kanji: "選", size: 24) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(TatamiTokens.goldDim.opacity(0.2))
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview("LanguagePickerView") {
    LanguagePickerView()
        .environment(AppLocale(preference: .system))
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build and commit**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
git add Ikeru/Localization/LanguagePickerView.swift Ikeru.xcodeproj
git commit -m "feat(i18n): add LanguagePickerView (Auto/English/Français)"
```

### Task 2f: End-of-Task-2 verification

- [ ] **Step 1: All tests green**

```bash
xcodebuild test -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -15
```

Expected: every existing test plus `AppLocaleTests` pass.

- [ ] **Step 2: Manually verify in simulator**

Run the app on the iPhone 16 simulator. The catalog is empty so nothing visible should change yet — but the build must succeed and the app must launch.

---

## Task 3: Background swap (Marble)

**Files:**
- Modify: `Ikeru/Views/Shared/Theme/IkeruGlass.swift` (replace `IkeruScreenBackground` body)

The existing `IkeruScreenBackground` is referenced from many places. We swap its body to render the Tatami marble; consumers don't have to change.

### Task 3a: Replace `IkeruScreenBackground` body

- [ ] **Step 1: Read the existing implementation**

```bash
grep -n "IkeruScreenBackground" Ikeru/Views/Shared/Theme/IkeruGlass.swift
```

Open the file and locate the `IkeruScreenBackground` struct (around line 178).

- [ ] **Step 2: Modify the body**

Replace the existing struct body with:

```swift
public struct IkeruScreenBackground: View {
    /// Optional explicit variant. When nil, the Marble background uses
    /// `.auxiliary` — Home / Session / Summary / RPG screens override this
    /// by rendering their own `MarbleBackground` directly when they want a
    /// specific variant.
    let variant: MarbleVariant

    public init(variant: MarbleVariant = .auxiliary) {
        self.variant = variant
    }

    public var body: some View {
        ZStack {
            Color.ikeruBackground.ignoresSafeArea()
            MarbleBackground(variant: variant)
                .opacity(0.95)
        }
    }
}
```

(Preserve the rest of `IkeruGlass.swift` unchanged.)

- [ ] **Step 3: Build, verify**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. The app's background now shows marble veining on every screen.

- [ ] **Step 4: Run app on simulator and visually confirm**

Launch the app. Every screen should now sit on a marble texture instead of a flat dark.

- [ ] **Step 5: Commit**

```bash
git add Ikeru/Views/Shared/Theme/IkeruGlass.swift
git commit -m "feat(tatami): IkeruScreenBackground renders MarbleBackground"
```

---

## Task 4: Home screen Tatami pass + FR translations

**Files:**
- Modify: `Ikeru/Views/Home/HomeView.swift`
- Modify: `Ikeru/Localization/Localizable.xcstrings` (add Home strings + FR translations)

The Home screen has the most surface area. Restyle each section in order: top bar, hero proverb card, stats row, decks. Migrate every visible English string into the catalog with FR translations as it's touched.

### Task 4a: Set Home's marble variant

- [ ] **Step 1: Modify `HomeView.swift`**

Path: `Ikeru/Views/Home/HomeView.swift`

Find:

```swift
        ZStack {
            IkeruScreenBackground()
```

Replace with:

```swift
        ZStack {
            IkeruScreenBackground(variant: .home)
```

- [ ] **Step 2: Build, commit**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
git add Ikeru/Views/Home/HomeView.swift
git commit -m "feat(home): use marble-1 variant for Home screen"
```

### Task 4b: Restyle the Home top bar (status row + greeting)

- [ ] **Step 1: Replace the `topBar` function body**

Path: `Ikeru/Views/Home/HomeView.swift`

Find the existing `topBar(_ vm: HomeViewModel)` function (around line 117). Replace its body with:

```swift
    @ViewBuilder
    private func topBar(_ vm: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Serif kanji date row — sits where the SF status time bar lives
            HStack {
                Spacer()
                Text(serifJapaneseDate())
                    .font(.system(size: 11, weight: .regular, design: .serif))
                    .foregroundStyle(TatamiTokens.paperGhost)
                    .tracking(1)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeOfDayGreetingJP())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                        .tracking(2.4)
                        .textCase(.uppercase)

                    HStack(spacing: 0) {
                        Text(vm.displayName.isEmpty
                             ? String(localized: "Welcome")
                             : vm.displayName)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.ikeruTextPrimary)
                        Text("。")
                            .font(.system(size: 22, weight: .semibold, design: .serif))
                            .foregroundStyle(TatamiTokens.paperGhost)
                    }

                    if !equippedTitleName.isEmpty {
                        Text(equippedTitleName.uppercased())
                            .font(.ikeruMicro)
                            .ikeruTracking(.micro)
                            .foregroundStyle(Color.ikeruPrimaryAccent)
                    }
                }
                Spacer()
                levelPill(level: vm.level)
            }
        }
        .padding(.top, IkeruTheme.Spacing.xs)
    }

    /// Returns "四月二十九日 · 火" (Japanese serif kanji date).
    private func serifJapaneseDate() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日 · E"
        return f.string(from: Date())
    }

    /// Returns "こんばんは" / "おはよう" / "こんにちは" depending on the hour.
    private func timeOfDayGreetingJP() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<11: return "おはよう"
        case 11..<17: return "こんにちは"
        default: return "こんばんは"
        }
    }
```

(Note: the original `timeOfDayGreeting()` helper is no longer used by the new top bar. Leave it in place in case other code references it; we'll remove dead code in a later refactor pass.)

- [ ] **Step 2: Add the `Welcome` string to the catalog**

In Xcode, open `Localizable.xcstrings`. Search for "Welcome" — it should now appear automatically (Xcode's static-string scanner). Add the FR translation:

| Key | English | Français |
|---|---|---|
| `Welcome` | Welcome | Bienvenue |

- [ ] **Step 3: Build, verify**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Ikeru/Views/Home/HomeView.swift Ikeru/Localization/Localizable.xcstrings
git commit -m "feat(home): Tatami top bar with serif kanji date and JP greeting"
```

### Task 4c: Restyle the proverb hero into a Tatami glass room

- [ ] **Step 1: Replace `proverbHero(_:)`**

Path: `Ikeru/Views/Home/HomeView.swift`

Find `proverbHero(_ vm: HomeViewModel)`. Replace its **body** (the contents of `VStack` and the `.padding/.background/.clipShape/.shadow` chain) with the following — **keep the function signature**:

```swift
    @ViewBuilder
    private func proverbHero(_ vm: HomeViewModel) -> some View {
        let proverb = HomeProverb.dailyProverb(level: vm.level)
        let progress = Double(vm.xpInCurrentLevel) / Double(max(1, vm.xpRequiredForLevel))

        VStack(alignment: .leading, spacing: 14) {
            // Top row — bilingual "本日 · TODAY" + Hanko stamp when work is due
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    BilingualLabel(japanese: "本日", chrome: "Today", mon: nil)
                    Text(proverb.kanji)
                        .font(.system(size: 19, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ikeruTextPrimary)
                        .lineLimit(1)
                        .tracking(2)
                    Text(proverb.translation)
                        .font(.system(size: 11))
                        .italic()
                        .foregroundStyle(TatamiTokens.paperGhost)
                }
                Spacer()
                if vm.dueCardCount > 0 {
                    HankoStamp(kanji: "急", size: 36)
                }
            }

            // Due count — large serif numeral
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                SerifNumeral(vm.dueCardCount, size: 56, color: .ikeruTextPrimary)
                Text("CARDS DUE", comment: "Hero stat label on Home")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .tracking(1.4)
                    .textCase(.uppercase)
            }

            // Practice CTA — sharp gold, bilingual, sumi corners
            Button {
                startSession()
            } label: {
                HStack {
                    Spacer()
                    Text("稽古を始める · ")
                        .font(.system(size: 13, weight: .regular, design: .serif))
                    Text("BEGIN PRACTICE")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1.6)
                    Spacer()
                }
                .foregroundStyle(Color.ikeruBackground)
                .padding(.vertical, 14)
                .background(Color.ikeruPrimaryAccent)
                .sumiCorners(color: Color.ikeruBackground.opacity(0.6), size: 6, weight: 1.2, inset: -1)
            }
            .buttonStyle(.plain)

            // XP progress — fusuma rail with serif numerals
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    BilingualLabel(japanese: "経験", chrome: "Experience", mon: nil)
                    Spacer()
                    HStack(spacing: 0) {
                        SerifNumeral(vm.xpInCurrentLevel, size: 12,
                                     weight: .regular, color: .ikeruPrimaryAccent)
                        Text(" / ")
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(TatamiTokens.paperGhost)
                        SerifNumeral(vm.xpRequiredForLevel, size: 12,
                                     weight: .regular, color: TatamiTokens.paperGhost)
                    }
                }

                // Hairline fusuma progress
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(TatamiTokens.goldDim.opacity(0.3))
                        .frame(height: 1)
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.ikeruPrimaryAccent)
                            .frame(width: geo.size.width * progress, height: 1)
                            .shadow(color: .ikeruPrimaryAccent.opacity(0.6), radius: 3)
                    }
                    .frame(height: 1)
                }

                Text("\(vm.xpToNextLevel) XP to next rank")
                    .font(.system(size: 11))
                    .foregroundStyle(TatamiTokens.paperGhost)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .tatamiRoom(.glass, padding: 20)
    }
```

- [ ] **Step 2: Add the new strings to the catalog**

In Xcode, open `Localizable.xcstrings`. Add (or verify auto-extracted) these keys with FR translations:

| Key | English | Français |
|---|---|---|
| `CARDS DUE` | CARDS DUE | À RÉVISER |
| `BEGIN PRACTICE` | BEGIN PRACTICE | COMMENCER |
| `Today` | Today | Aujourd'hui |
| `Experience` | Experience | Expérience |
| `%lld XP to next rank` | %lld XP to next rank | %lld XP avant le grade suivant |

(For the "XP to next rank" string, this means changing the call site to use `String(localized:)` with formatting. Update the line in the new code:

```swift
                Text("\(vm.xpToNextLevel) XP to next rank")
```

to:

```swift
                Text("\(vm.xpToNextLevel) XP to next rank",
                     comment: "Subtle XP-remaining label on the Home hero")
```

so the string is picked up by the catalog scanner and gets a localized format. Xcode will surface it as `%lld XP to next rank` once it sees the interpolation.)

- [ ] **Step 3: Build, verify visually on simulator**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
```

Launch in simulator. Confirm: marble background, hero card has fusuma rails top/bottom, gold "稽古を始める · BEGIN PRACTICE" button is sharp-cornered with sumi corners. With FR system locale (Settings → General → Language → Français on the simulator), the EN-side labels read "AUJOURD'HUI", "COMMENCER", etc.

- [ ] **Step 4: Commit**

```bash
git add Ikeru/Views/Home/HomeView.swift Ikeru/Localization/Localizable.xcstrings
git commit -m "feat(home): Tatami proverb hero with hanko, serif numeral, sharp CTA"
```

### Task 4d: Restyle stats row + skill radar + decks list

- [ ] **Step 1: Replace `statsRow(_:)` body**

(Use the same pattern as Task 4c. Below is the replacement — install in place of the current `statsRow` and its `primaryStatCard`/`secondaryStatCard` helpers.)

Insert as the body of `statsRow`:

```swift
    @ViewBuilder
    private func statsRow(_ vm: HomeViewModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Learned (1.4× weight)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    MonCrest(kind: .asanoha, size: 11, color: .ikeruPrimaryAccent)
                    Text("LEARNED", comment: "Stat card label")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(TatamiTokens.paperGhost)
                        .tracking(1.4)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    SerifNumeral(vm.learnedCount, size: 32)
                    Text("kanji")
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(TatamiTokens.paperGhost)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tatamiRoom(.standard, padding: 14)
            .layoutPriority(1.4)

            // Streak
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    MonCrest(kind: .genji, size: 11, color: .ikeruPrimaryAccent)
                    Text("STREAK", comment: "Stat card label")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(TatamiTokens.paperGhost)
                        .tracking(1.4)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    SerifNumeral(vm.streakDays, size: 32)
                    Text("days")
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(TatamiTokens.paperGhost)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tatamiRoom(.standard, padding: 14)
        }
    }
```

(If `vm.learnedCount` or `vm.streakDays` doesn't exist on `HomeViewModel`, use the existing properties — search for `learned` and `streak` in `HomeViewModel.swift` and substitute the actual property names. **Do not** add new properties; the spec is zero functional change.)

- [ ] **Step 2: Add catalog entries**

| Key | English | Français |
|---|---|---|
| `LEARNED` | LEARNED | APPRIS |
| `STREAK` | STREAK | SÉRIE |

(Plus `kanji` and `days` — these are tiny English labels. `kanji` stays untranslated in FR per the translation discipline rule. `days` → `jours`.)

| Key | English | Français |
|---|---|---|
| `kanji` | kanji | kanji |
| `days` | days | jours |

- [ ] **Step 3: Replace decks list** (find `// Decks`-related block in `homeContent`):

Find the `sessionBreakdown` or equivalent decks rendering. If decks are shown via `IkeruCard` rows, replace with fusuma-railed rows:

```swift
    @ViewBuilder
    private func decksList(_ vm: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            BilingualLabel(japanese: "稽古場", chrome: "Decks", mon: .kikkou)
                .padding(.bottom, 10)

            ForEach(Array(vm.decks.enumerated()), id: \.offset) { index, deck in
                deckRow(deck, isFirst: index == 0)
            }
        }
    }

    @ViewBuilder
    private func deckRow(_ deck: HomeViewModel.DeckSummary, isFirst: Bool) -> some View {
        HStack(spacing: 12) {
            MonCrest(kind: monForDeck(deck), size: 16, color: .ikeruPrimaryAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text(deck.japaneseName.isEmpty ? deck.name : deck.japaneseName)
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(Color.ikeruTextPrimary)
                Text(deck.englishGloss ?? deck.name)
                    .font(.system(size: 11))
                    .foregroundStyle(TatamiTokens.paperGhost)
            }
            Spacer()
            SerifNumeral(deck.dueCount, size: 14, color: .ikeruPrimaryAccent)
            Text("›")
                .font(.system(size: 14))
                .foregroundStyle(TatamiTokens.goldDim)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .overlay(alignment: .top) {
            if isFirst {
                Rectangle()
                    .fill(TatamiTokens.goldDim.opacity(0.7))
                    .frame(height: 1)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.ikeruPrimaryAccent.opacity(0.3))
                .frame(height: 1)
        }
    }

    private func monForDeck(_ deck: HomeViewModel.DeckSummary) -> MonKind {
        // Stable per-deck identity. Hash the deck id for repeatable assignment.
        let kinds = MonKind.allCases
        let h = abs(deck.id.hashValue)
        return kinds[h % kinds.count]
    }
```

(If `HomeViewModel.DeckSummary` doesn't expose `japaneseName` / `englishGloss`, use a lookup table local to `HomeView`:

```swift
    private static let deckJapanese: [String: (jp: String, en: String)] = [
        "Hiragana": ("ひらがな", "Hiragana"),
        "Katakana": ("カタカナ", "Katakana"),
        "JLPT N5":  ("語彙 N5",   "JLPT N5 vocabulary")
    ]
```

and use `Self.deckJapanese[deck.name] ?? (deck.name, deck.name)` in `deckRow`. **Do not** modify `HomeViewModel` to add these properties.)

- [ ] **Step 4: Add catalog entries**

| Key | English | Français |
|---|---|---|
| `Decks` | Decks | Decks |

(`Decks` reads natively in French and matches the kanji 稽古場.)

- [ ] **Step 5: Build, run, commit**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
git add Ikeru/Views/Home/HomeView.swift Ikeru/Localization/Localizable.xcstrings
git commit -m "feat(home): Tatami stats row and fusuma deck rows"
```

### Task 4e: Update or remove `skillRadarCard` and `sessionBreakdown` in the same Tatami style

- [ ] **Step 1: Apply the same pattern**

Both cards use `IkeruGlassSurface` + rounded radius. Replace each card's `.padding/.background/.clipShape` with `.tatamiRoom(.standard, padding: 14)`. Keep the inner content unchanged — the visual upgrade is the surface, not the data.

For each `Text(...)` containing user-facing English (e.g., `"BALANCE"`, `"Your four winds"`, `"New"`, `"Review"`, `"Approx"`), wrap each one in `String(localized:)` with `comment:` and add to the catalog with FR.

- [ ] **Step 2: Catalog entries**

| Key | English | Français |
|---|---|---|
| `BALANCE` | BALANCE | ÉQUILIBRE |
| `Your four winds` | Your four winds | Tes quatre vents |
| `New` | New | Nouveaux |
| `Review` | Review | Révision |
| `Approx` | Approx | Approx. |
| `Reading` | Reading | Lecture |
| `Writing` | Writing | Écriture |
| `Listening` | Listening | Écoute |
| `Speaking` | Speaking | Parole |

- [ ] **Step 3: Build and commit**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
git add Ikeru/Views/Home/HomeView.swift Ikeru/Localization/Localizable.xcstrings
git commit -m "feat(home): Tatami skill radar + session breakdown rooms"
```

### Task 4f: End-of-Task-4 verification

- [ ] **Step 1: All tests still pass**

```bash
xcodebuild test -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -10
```

- [ ] **Step 2: Visual diff against the design**

Open `docs/design-review/tatami-section-home.png` (regenerate via the Playwright session if needed). Compare to the simulator render. Match: marble bg, hero card with fusuma rails, hanko top-right, sharp gold button, fusuma deck rows.

---

## Task 5: SRS Card review (Active Session)

**Files:**
- Modify: `Ikeru/Views/Learning/CardReview/SRSCardView.swift`
- Modify: `Ikeru/Views/Learning/CardReview/GradeButtonsView.swift`
- Modify: `Ikeru/Localization/Localizable.xcstrings`

### Task 5a: Set the session marble variant + restyle SRS card

- [ ] **Step 1: Modify `SRSCardView.swift` — outer ZStack**

Find the outer `ZStack` (or root view container). Replace the screen background with `IkeruScreenBackground(variant: .session)`:

```swift
            IkeruScreenBackground(variant: .session)
                .ignoresSafeArea()
```

- [ ] **Step 2: Restyle the kana card itself**

Locate the kana card's `VStack` (containing the large `Text(card.front)` etc.). Replace any `.ikeruCard()` modifier with:

```swift
            .padding(28)
            .frame(maxWidth: .infinity, minHeight: 360)
            .tatamiRoom(.glass, padding: EdgeInsets(top: 28, leading: 28, bottom: 28, trailing: 28))
```

The kana itself uses serif:

```swift
                Text(card.front)
                    .font(.system(size: 200, weight: .light, design: .serif))
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .shadow(color: .ikeruPrimaryAccent.opacity(0.25), radius: 32, y: 4)
```

Above the kana, add a small bilingual label:

```swift
                BilingualLabel(japanese: card.deckJapaneseName ?? "平仮名", chrome: "Hiragana")
                    .padding(.bottom, 8)
```

(Substitute the chrome label based on deck — match the existing logic. Use a switch on the deck if there's one, or pass it down from `CardReviewView`.)

- [ ] **Step 3: Replace the progress pill with a fusuma rail**

Locate the progress bar (`ZStack` with capsules or a `ProgressView` near the top). Replace its body with:

```swift
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(TatamiTokens.goldDim.opacity(0.3))
                    .frame(height: 3)
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.ikeruPrimaryAccent)
                        .frame(width: geo.size.width * progress, height: 1)
                        .shadow(color: .ikeruPrimaryAccent.opacity(0.6), radius: 6)
                }
                .frame(height: 3)
            }
            .padding(.horizontal, 22)
```

- [ ] **Step 4: Catalog entries for new strings**

| Key | English | Français |
|---|---|---|
| `Hiragana` | Hiragana | Hiragana |
| `Katakana` | Katakana | Katakana |
| `Kanji` | Kanji | Kanji |
| `Vocabulary` | Vocabulary | Vocabulaire |

- [ ] **Step 5: Build, commit**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
git add Ikeru/Views/Learning/CardReview/SRSCardView.swift Ikeru/Localization/Localizable.xcstrings
git commit -m "feat(session): Tatami SRS card with serif kana and fusuma progress"
```

### Task 5b: Restyle FSRS grade buttons with kanji headers

- [ ] **Step 1: Replace `GradeButtonsView.swift` body**

Path: `Ikeru/Views/Learning/CardReview/GradeButtonsView.swift`

Replace the current grid of grade buttons with:

```swift
import SwiftUI
import IkeruCore

struct GradeButtonsView: View {
    let onGrade: (CardGrade) -> Void
    let intervals: GradeIntervals  // existing model — see CardReview view-model

    private struct GradeSpec {
        let grade: CardGrade
        let kanji: String
        let label: LocalizedStringKey
        let color: Color
    }

    private var specs: [GradeSpec] {
        [
            .init(grade: .again, kanji: "又", label: "Again",
                  color: TatamiTokens.vermilion),
            .init(grade: .hard,  kanji: "難", label: "Hard",
                  color: Color(red: 0.627, green: 0.451, blue: 0.302)),
            .init(grade: .good,  kanji: "良", label: "Good",
                  color: .ikeruPrimaryAccent),
            .init(grade: .easy,  kanji: "易", label: "Easy",
                  color: Color(red: 0.616, green: 0.729, blue: 0.486))
        ]
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(specs, id: \.grade) { spec in
                Button {
                    onGrade(spec.grade)
                } label: {
                    VStack(spacing: 4) {
                        Text(spec.kanji)
                            .font(.system(size: 18, weight: .light, design: .serif))
                            .foregroundStyle(spec.color)
                            .padding(.bottom, 2)
                        Text(spec.label)
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(Color.ikeruTextPrimary)
                            .textCase(.uppercase)
                        SerifNumeral(intervals.label(for: spec.grade), size: 10,
                                     weight: .regular, color: TatamiTokens.paperGhost)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.102, green: 0.102, blue: 0.133))
                    .overlay(alignment: .top) {
                        Rectangle().fill(spec.color).frame(height: 1)
                    }
                    .sumiCorners(color: spec.color, size: 8, weight: 1.2, inset: -1)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

(`GradeIntervals` and `intervals.label(for:)` should already exist; if they don't, pass the FSRS interval string in directly — search the existing `GradeButtonsView` for how it gets the interval text and preserve that logic.)

- [ ] **Step 2: Catalog entries**

| Key | English | Français |
|---|---|---|
| `Again` | Again | Encore |
| `Hard` | Hard | Difficile |
| `Good` | Good | Bien |
| `Easy` | Easy | Facile |

- [ ] **Step 3: Build, run, commit**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
git add Ikeru/Views/Learning/CardReview/GradeButtonsView.swift Ikeru/Localization/Localizable.xcstrings
git commit -m "feat(session): Tatami FSRS buttons with kanji headers"
```

### Task 5c: Verify the session flow

- [ ] **Step 1: Manual test on simulator**

Launch a session from Home → start practice → tap reveal → tap grade. Confirm: marble bg, glass tatami card, large serif kana with warm shadow, FSRS row of 4 sharp tatami buttons each with a colored kanji header.

- [ ] **Step 2: All unit tests still pass**

```bash
xcodebuild test -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -10
```

---

## Task 6: Session Summary

**Files:**
- Modify: `Ikeru/Views/Session/SessionSummaryView.swift`
- Modify: `Ikeru/Localization/Localizable.xcstrings`

### Task 6a: Restyle the summary triumph header + 3-stat row + XP rail

- [ ] **Step 1: Replace `SessionSummaryView` body**

Path: `Ikeru/Views/Session/SessionSummaryView.swift`

Replace the root `body` with:

```swift
    var body: some View {
        ZStack {
            IkeruScreenBackground(variant: .summary)
                .ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    triumphHeader
                    heroStatRow
                    xpGainRail
                    splitCells
                    actions
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
    }

    private var triumphHeader: some View {
        VStack(spacing: 6) {
            Text("稽古終わり")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.ikeruPrimaryAccent)
                .tracking(3)
                .textCase(.uppercase)
            Text("Practice complete", comment: "Session summary headline")
                .font(.system(size: 32, weight: .light, design: .serif))
                .foregroundStyle(Color.ikeruTextPrimary)
            Text("七転び八起き · Fall seven, rise eight")
                .font(.system(size: 12))
                .italic()
                .foregroundStyle(TatamiTokens.paperGhost)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var heroStatRow: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                SerifNumeral(viewModel.cardsCount, size: 56, color: .ikeruPrimaryAccent)
                Text("CARDS", comment: "Summary stat label")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .tracking(1.6)
            }
            .frame(maxWidth: .infinity)

            verticalHairline

            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    SerifNumeral(viewModel.recallPercentage, size: 56, color: .ikeruPrimaryAccent)
                    Text("%")
                        .font(.system(size: 18, design: .serif))
                        .foregroundStyle(TatamiTokens.paperGhost)
                }
                Text("RECALL", comment: "Summary stat label")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .tracking(1.6)
            }
            .frame(maxWidth: .infinity)

            verticalHairline

            VStack(spacing: 6) {
                SerifNumeral(viewModel.timeString, size: 40, color: .ikeruPrimaryAccent)
                Text("TIME", comment: "Summary stat label")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .tracking(1.6)
            }
            .frame(maxWidth: .infinity)
        }
        .tatamiRoom(.glass, padding: 22)
    }

    private var verticalHairline: some View {
        Rectangle()
            .fill(TatamiTokens.goldDim.opacity(0.4))
            .frame(width: 1, height: 56)
    }

    private var xpGainRail: some View {
        VStack(spacing: 8) {
            HStack {
                MonCrest(kind: .asanoha, size: 14, color: .ikeruPrimaryAccent)
                Text("XP EARNED", comment: "Summary XP label")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .tracking(1.4)
                Spacer()
                SerifNumeral("+\(viewModel.xpEarned)", size: 18,
                             weight: .regular, color: .ikeruPrimaryAccent)
            }
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(TatamiTokens.goldDim.opacity(0.3))
                    .frame(height: 3)
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.ikeruPrimaryAccent)
                        .frame(width: geo.size.width * viewModel.xpProgress, height: 1)
                    Rectangle()
                        .fill(Color.ikeruPrimaryAccent)
                        .frame(width: geo.size.width * viewModel.xpGainProgress, height: 1)
                        .offset(x: geo.size.width * (viewModel.xpProgress - viewModel.xpGainProgress))
                        .shadow(color: .ikeruPrimaryAccent.opacity(0.8), radius: 6)
                }
                .frame(height: 3)
            }
            HStack {
                SerifNumeral(viewModel.rankLabelStart, size: 10, color: TatamiTokens.paperGhost)
                Spacer()
                SerifNumeral(viewModel.rankLabelEnd, size: 10, color: TatamiTokens.paperGhost)
            }
        }
        .tatamiRoom(.standard, padding: 18)
    }

    private var splitCells: some View {
        HStack(spacing: 10) {
            cell(label: "NEW LEARNED", count: viewModel.newCount,
                 color: Color(red: 0.616, green: 0.729, blue: 0.486),
                 mon: .maru)
            cell(label: "RE-LEARN", count: viewModel.relearnCount,
                 color: TatamiTokens.vermilion,
                 mon: .kikkou)
        }
    }

    @ViewBuilder
    private func cell(label: LocalizedStringKey, count: Int, color: Color, mon: MonKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                MonCrest(kind: mon, size: 11, color: color)
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(TatamiTokens.paperGhost)
                    .tracking(1.4)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                SerifNumeral(count, size: 28, color: color)
                Text("札")
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(TatamiTokens.paperGhost)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tatamiRoom(.standard, padding: 14)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button { onContinue() } label: {
                HStack {
                    Spacer()
                    Text("続ける · ")
                        .font(.system(size: 13, weight: .regular, design: .serif))
                    Text("CONTINUE", comment: "Summary primary CTA")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1.6)
                    Spacer()
                }
                .foregroundStyle(Color.ikeruBackground)
                .padding(.vertical, 14)
                .background(Color.ikeruPrimaryAccent)
                .sumiCorners(color: Color.ikeruBackground.opacity(0.6), size: 6, weight: 1.2, inset: -1)
            }
            .buttonStyle(.plain)

            Button { onReviewMistakes() } label: {
                Text("REVIEW MISTAKES", comment: "Summary secondary CTA")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .tracking(1.4)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }
```

(If `viewModel` doesn't expose `cardsCount`, `recallPercentage`, etc. yet, use whichever properties already exist on the existing `SessionSummaryView` and rename for clarity locally. Keep zero functional changes — read from existing fields only.)

- [ ] **Step 2: Catalog entries**

| Key | English | Français |
|---|---|---|
| `Practice complete` | Practice complete | Séance terminée |
| `CARDS` | CARDS | CARTES |
| `RECALL` | RECALL | RAPPEL |
| `TIME` | TIME | TEMPS |
| `XP EARNED` | XP EARNED | XP GAGNÉS |
| `NEW LEARNED` | NEW LEARNED | NOUVEAUX |
| `RE-LEARN` | RE-LEARN | À REVOIR |
| `CONTINUE` | CONTINUE | CONTINUER |
| `REVIEW MISTAKES` | REVIEW MISTAKES | REVOIR LES ERREURS |

- [ ] **Step 3: Build, manually trigger a session-end, commit**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
git add Ikeru/Views/Session/SessionSummaryView.swift Ikeru/Localization/Localizable.xcstrings
git commit -m "feat(summary): Tatami triumph + 3-numeral row + XP fusuma rail"
```

---

## Task 7: RPG Profile

**Files:**
- Modify: `Ikeru/Views/RPG/RPGProfileView.swift`
- Modify: `Ikeru/Localization/Localizable.xcstrings`

### Task 7a: Replace the rank crest with the torii frame

- [ ] **Step 1: Modify `RPGProfileView.swift`**

Find the existing rank-display block (likely uses `EnsoRankView` at large size). Replace with:

```swift
    @ViewBuilder
    private func rankCrest(_ vm: RPGProfileViewModel) -> some View {
        HStack(alignment: .center, spacing: 22) {
            RPGRankCrest(level: vm.level, size: 96)
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 4) {
                Text("第\(rankKanji(vm.level))段")
                    .font(.system(size: 22, weight: .light, design: .serif))
                    .foregroundStyle(Color.ikeruTextPrimary)
                Text(rankTitle(vm.level).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                    .tracking(2)
                HStack(spacing: 0) {
                    SerifNumeral(vm.xpInLevel, size: 12, color: TatamiTokens.paperGhost)
                    Text(" / ")
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(TatamiTokens.paperGhost)
                    SerifNumeral(vm.xpRequired, size: 12, color: TatamiTokens.paperGhost)
                    Text(" XP")
                        .font(.system(size: 12))
                        .foregroundStyle(TatamiTokens.paperGhost)
                }
                .padding(.top, 6)
                ZStack(alignment: .leading) {
                    Rectangle().fill(TatamiTokens.goldDim.opacity(0.2)).frame(height: 1)
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.ikeruPrimaryAccent)
                            .frame(width: geo.size.width * vm.xpProgress, height: 1)
                    }
                    .frame(height: 1)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .tatamiRoom(.glass, padding: 22)
    }

    private func rankKanji(_ n: Int) -> String {
        ["", "一","二","三","四","五","六","七","八","九","十"]
            .indices.contains(n) ? ["","一","二","三","四","五","六","七","八","九","十"][n] : "\(n)"
    }
```

- [ ] **Step 2: Replace achievements with hanko stamps**

Find the existing achievements block. Replace with:

```swift
    @ViewBuilder
    private func achievements(_ vm: RPGProfileViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            BilingualLabel(japanese: "勲章", chrome: "Achievements", mon: .asanoha)
            HStack(alignment: .top, spacing: 14) {
                ForEach(vm.achievements, id: \.id) { ach in
                    VStack(spacing: 6) {
                        if ach.earned {
                            HankoStamp(kanji: ach.kanji, size: 42)
                        } else {
                            Text(ach.kanji)
                                .font(.system(size: 22, weight: .light, design: .serif))
                                .foregroundStyle(TatamiTokens.paperGhost)
                                .frame(width: 42, height: 42)
                                .overlay(
                                    Rectangle()
                                        .strokeBorder(
                                            TatamiTokens.paperGhost,
                                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                                        )
                                )
                                .opacity(0.55)
                        }
                        Text(ach.label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(TatamiTokens.paperGhost)
                            .tracking(1)
                            .frame(maxWidth: 56)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .tatamiRoom(.standard, padding: 16)
    }
```

(`vm.achievements` model needs `.id`, `.kanji`, `.label`, `.earned`. If the existing model differs, **adapt this view code to it** — don't add new properties to `RPGProfileViewModel`.)

- [ ] **Step 3: Add the next-rank teaser using a dashed torii**

Below `achievements`:

```swift
    @ViewBuilder
    private func nextRank(_ vm: RPGProfileViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            BilingualLabel(japanese: "次の段", chrome: "Next rank", mon: .genji)
            HStack(spacing: 16) {
                RPGRankCrest(level: vm.level + 1, size: 56, dashed: true)
                    .frame(width: 56, height: 56)
                    .opacity(0.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text("第\(rankKanji(vm.level + 1))段 · \(rankTitle(vm.level + 1))")
                        .font(.system(size: 16, design: .serif))
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Text("\(vm.xpToNextRank) XP to advance",
                         comment: "RPG next rank caption")
                        .font(.system(size: 11))
                        .foregroundStyle(TatamiTokens.paperGhost)
                }
                Spacer(minLength: 0)
                SerifNumeral("\(vm.xpToNextRank) XP →", size: 11, color: .ikeruPrimaryAccent)
            }
        }
        .tatamiRoom(.standard, padding: 16)
    }
```

- [ ] **Step 4: Catalog entries**

| Key | English | Français |
|---|---|---|
| `Achievements` | Achievements | Distinctions |
| `Next rank` | Next rank | Prochain grade |
| `%lld XP to advance` | %lld XP to advance | %lld XP pour avancer |
| `Cards` | Cards | Cartes |
| `Streak` | Streak | Série |
| `Hours` | Hours | Heures |

- [ ] **Step 5: Build and commit**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
git add Ikeru/Views/RPG/RPGProfileView.swift Ikeru/Localization/Localizable.xcstrings
git commit -m "feat(rpg): Tatami torii rank crest, hanko achievements, next-rank teaser"
```

---

## Task 8: Study / Progress

**Files:**
- Modify: `Ikeru/Views/Home/ProgressDashboardView.swift`
- Modify: `Ikeru/Localization/Localizable.xcstrings`

### Task 8a: Restyle JLPT estimate hero + skill balance + decks

- [ ] **Step 1: Replace `body` of `ProgressDashboardView`**

```swift
    var body: some View {
        ZStack {
            IkeruScreenBackground(variant: .auxiliary)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    jlptHero
                    skillBalance
                    decks
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 140)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            BilingualLabel(japanese: "進歩", chrome: "Progress")
            HStack(spacing: 0) {
                Text("Your study", comment: "Study tab heading")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextPrimary)
                Text("。")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(TatamiTokens.paperGhost)
            }
        }
        .padding(.bottom, 6)
    }

    private var jlptHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    BilingualLabel(japanese: "推定", chrome: "JLPT estimate")
                    Text("Based on your last 90 reviews",
                         comment: "JLPT estimate sub-caption")
                        .font(.system(size: 12, design: .serif))
                        .italic()
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
                Spacer()
                HankoStamp(kanji: viewModel.jlptLevel, size: 42)
            }
            HStack(alignment: .firstTextBaseline) {
                SerifNumeral(viewModel.jlptPercent, size: 48)
                Text("%")
                    .font(.system(size: 12))
                    .foregroundStyle(TatamiTokens.paperGhost)
                    .tracking(1.4)
                Spacer()
                Text("READY FOR \(viewModel.jlptLevel)",
                     comment: "JLPT readiness label")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .tracking(1.2)
            }
            ZStack(alignment: .leading) {
                Rectangle().fill(TatamiTokens.goldDim.opacity(0.3)).frame(height: 3)
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.ikeruPrimaryAccent)
                        .frame(width: geo.size.width * viewModel.jlptProgress, height: 1)
                }
                .frame(height: 3)
            }
        }
        .tatamiRoom(.glass, padding: 22)
    }

    private var skillBalance: some View {
        VStack(alignment: .leading, spacing: 12) {
            BilingualLabel(japanese: "技能", chrome: "Skill balance", mon: .asanoha)
            VStack(spacing: 14) {
                ForEach(viewModel.skills, id: \.id) { skill in
                    HStack(spacing: 10) {
                        MonCrest(kind: skill.mon, size: 16, color: .ikeruPrimaryAccent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(skill.name.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.ikeruTextSecondary)
                                .tracking(1)
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color(red: 0.094, green: 0.094, blue: 0.122))
                                    .frame(height: 2)
                                GeometryReader { geo in
                                    Rectangle()
                                        .fill(Color.ikeruPrimaryAccent.opacity(0.85))
                                        .frame(width: geo.size.width * skill.progress, height: 2)
                                }
                                .frame(height: 2)
                            }
                        }
                        SerifNumeral(Int(skill.progress * 100), size: 14, color: .ikeruPrimaryAccent)
                    }
                }
            }
        }
        .tatamiRoom(.standard, padding: 20)
    }

    private var decks: some View {
        VStack(alignment: .leading, spacing: 0) {
            BilingualLabel(japanese: "稽古場", chrome: "Decks", mon: .kikkou)
                .padding(.bottom, 10)
            ForEach(Array(viewModel.decks.enumerated()), id: \.offset) { index, deck in
                deckRow(deck, isFirst: index == 0)
            }
        }
    }

    @ViewBuilder
    private func deckRow(_ deck: DeckSummary, isFirst: Bool) -> some View {
        HStack(spacing: 12) {
            MonCrest(kind: deck.mon, size: 16, color: .ikeruPrimaryAccent)
            VStack(alignment: .leading, spacing: 4) {
                Text(deck.japanese)
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(Color.ikeruTextPrimary)
                Text(deck.english)
                    .font(.system(size: 11))
                    .foregroundStyle(TatamiTokens.paperGhost)
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(red: 0.094, green: 0.094, blue: 0.122))
                        .frame(width: 80, height: 1)
                    Rectangle().fill(Color.ikeruPrimaryAccent.opacity(0.7))
                        .frame(width: 80 * deck.progress, height: 1)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                SerifNumeral(deck.learned, size: 14, color: .ikeruPrimaryAccent)
                Text("/\(deck.total)")
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(TatamiTokens.paperGhost)
            }
            Text("LEARNED")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(TatamiTokens.paperGhost)
                .tracking(1.2)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .overlay(alignment: .top) {
            if isFirst {
                Rectangle().fill(TatamiTokens.goldDim.opacity(0.7)).frame(height: 1)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.ikeruPrimaryAccent.opacity(0.3)).frame(height: 1)
        }
    }
```

(Use whatever data shape `ProgressDashboardViewModel` already exposes. If `viewModel.skills` has different fields than `id`/`name`/`progress`/`mon`, adapt the view code; do not modify the view model.)

- [ ] **Step 2: Catalog entries**

| Key | English | Français |
|---|---|---|
| `Progress` | Progress | Progrès |
| `Your study` | Your study | Tes études |
| `JLPT estimate` | JLPT estimate | Estimation JLPT |
| `Based on your last 90 reviews` | Based on your last 90 reviews | Calculé sur tes 90 dernières révisions |
| `READY FOR %@` | READY FOR %@ | PRÊT POUR %@ |
| `Skill balance` | Skill balance | Équilibre des compétences |

- [ ] **Step 3: Build, commit**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
git add Ikeru/Views/Home/ProgressDashboardView.swift Ikeru/Localization/Localizable.xcstrings
git commit -m "feat(study): Tatami JLPT hero + skill rooms + fusuma decks"
```

---

## Task 9: Conversation / Companion

**Files:**
- Modify: `Ikeru/Views/Learning/Conversation/CompanionTabView.swift`
- Modify: `Ikeru/Localization/Localizable.xcstrings`

### Task 9a: Restyle Sakura's hero card with sumi-bordered avatar

- [ ] **Step 1: Replace tutor card body**

```swift
    private var tutorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Rectangle().fill(LinearGradient(
                        colors: [
                            Color(red: 0.165, green: 0.133, blue: 0.102),
                            Color(red: 0.078, green: 0.067, blue: 0.051)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim, lineWidth: 1))
                    Text("桜")
                        .font(.system(size: 28, weight: .light, design: .serif))
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                }
                .frame(width: 64, height: 64)
                .sumiCorners(color: .ikeruPrimaryAccent, size: 8, weight: 1.2, inset: -1)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sakura")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Text("\"Patient. Specialty: keigo\"",
                         comment: "Sakura tutor description")
                        .font(.system(size: 11))
                        .italic()
                        .foregroundStyle(TatamiTokens.paperGhost)
                }
                Spacer()
                HStack(spacing: 6) {
                    MonCrest(kind: .maru, size: 10, color: Color(red: 0.616, green: 0.729, blue: 0.486))
                    Text("ONLINE", comment: "Tutor status")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.ikeruTextSecondary)
                        .tracking(1.2)
                }
            }
            Button { onBeginConversation() } label: {
                HStack {
                    Spacer()
                    Text("会話を始める · ")
                        .font(.system(size: 13, weight: .regular, design: .serif))
                    Text("BEGIN CONVERSATION", comment: "Companion CTA")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1.6)
                    Spacer()
                }
                .foregroundStyle(Color.ikeruBackground)
                .padding(.vertical, 14)
                .background(Color.ikeruPrimaryAccent)
                .sumiCorners(color: Color.ikeruBackground.opacity(0.6), size: 6, weight: 1.2, inset: -1)
            }
            .buttonStyle(.plain)
        }
        .tatamiRoom(.glass, padding: 20)
    }
```

- [ ] **Step 2: Restyle suggested topics + recent conversations**

```swift
    private var suggestedTopics: some View {
        VStack(alignment: .leading, spacing: 0) {
            BilingualLabel(japanese: "話題", chrome: "Suggested topics", mon: .genji)
                .padding(.bottom, 10)
            ForEach(Array(viewModel.suggestedTopics.enumerated()), id: \.offset) { index, topic in
                topicRow(topic, isFirst: index == 0)
            }
        }
    }

    @ViewBuilder
    private func topicRow(_ topic: ConversationTopic, isFirst: Bool) -> some View {
        Button {
            onTopicTap(topic)
        } label: {
            HStack(spacing: 12) {
                MonCrest(kind: topic.mon, size: 14, color: .ikeruPrimaryAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.japanese)
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Text(topic.english)
                        .font(.system(size: 11))
                        .foregroundStyle(TatamiTokens.paperGhost)
                }
                Spacer()
                Text(topic.jlptLevel)
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim, lineWidth: 1))
                Text("›")
                    .font(.system(size: 14))
                    .foregroundStyle(TatamiTokens.goldDim)
            }
            .padding(.vertical, 14).padding(.horizontal, 4)
            .overlay(alignment: .top) {
                if isFirst {
                    Rectangle().fill(TatamiTokens.goldDim.opacity(0.7)).frame(height: 1)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.ikeruPrimaryAccent.opacity(0.3)).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var recentConversations: some View {
        VStack(alignment: .leading, spacing: 10) {
            BilingualLabel(japanese: "履歴", chrome: "Recent conversations", mon: .kikkou)
            ForEach(viewModel.recent, id: \.id) { conv in
                HStack {
                    Text(conv.dateJP)
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(TatamiTokens.paperGhost)
                        .frame(minWidth: 40, alignment: .leading)
                    Text(conv.topic)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Spacer()
                    Text("\(conv.minutes)分")
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(TatamiTokens.paperGhost)
                }
                .padding(.vertical, 12).padding(.horizontal, 4)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(TatamiTokens.goldDim.opacity(0.2)).frame(height: 1)
                }
            }
        }
    }
```

(`ConversationTopic` and `viewModel.recent` shape: adapt to whatever exists in the current file. Do not change the view-model.)

- [ ] **Step 3: Catalog entries**

| Key | English | Français |
|---|---|---|
| `"Patient. Specialty: keigo"` | "Patient. Specialty: keigo" | "Patiente. Spécialité : keigo" |
| `ONLINE` | ONLINE | EN LIGNE |
| `BEGIN CONVERSATION` | BEGIN CONVERSATION | COMMENCER LA CONVERSATION |
| `Suggested topics` | Suggested topics | Sujets suggérés |
| `Recent conversations` | Recent conversations | Conversations récentes |

- [ ] **Step 4: Build and commit**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
git add Ikeru/Views/Learning/Conversation/CompanionTabView.swift Ikeru/Localization/Localizable.xcstrings
git commit -m "feat(companion): Tatami sumi-bordered Sakura cell + topic chips"
```

---

## Task 10: Settings

**Files:**
- Modify: `Ikeru/Views/Settings/SettingsView.swift`
- Modify: `Ikeru/Localization/Localizable.xcstrings`

### Task 10a: Tatami-fy settings rows + add language picker entry

- [ ] **Step 1: Replace `SettingsView` body**

```swift
    @State private var showingLanguagePicker = false

    var body: some View {
        ZStack {
            IkeruScreenBackground(variant: .auxiliary)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    practiceSection
                    memorySection
                    accountSection
                    aboutSection
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 140)
            }
        }
        .sheet(isPresented: $showingLanguagePicker) {
            LanguagePickerView()
                .presentationDetents([.medium])
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            BilingualLabel(japanese: "設定", chrome: "Settings")
            Text("Preferences", comment: "Settings heading")
                .font(.system(size: 28, weight: .light, design: .serif))
                .foregroundStyle(Color.ikeruTextPrimary)
        }
    }

    private var practiceSection: some View {
        section(label: ("稽古", "Practice"), mon: .asanoha) {
            settingRow(jp: "一日の目標", label: "Daily goal", value: "12 cards")
            settingRow(jp: "通知",       label: "Reminders",  value: "8:00 PM")
            settingRow(jp: "音声",       label: "Sound",      value: viewModel.sfxOn ? "On" : "Off")
        }
    }

    private var memorySection: some View {
        section(label: ("記憶", "Memory algorithm"), mon: .kikkou) {
            settingRow(jp: "FSRSパラメータ", label: "FSRS parameters", value: "Optimized")
            settingRow(jp: "保持率",         label: "Target retention", value: "90%")
            settingRow(jp: "最大間隔",       label: "Maximum interval", value: "36500d")
        }
    }

    private var accountSection: some View {
        section(label: ("勘定", "Account"), mon: .genji) {
            settingRow(jp: "プロフィール",     label: "Profile",     value: viewModel.profileName)
            settingRow(jp: "バックアップ",   label: "iCloud sync", value: viewModel.iCloudOn ? "On" : "Off")
            // Plan / Premium row intentionally omitted — does not exist in the app.
            languageRow
        }
    }

    private var aboutSection: some View {
        section(label: ("関連", "About"), mon: .maru) {
            settingRow(jp: "バージョン", label: "Version", value: viewModel.version)
            settingRow(jp: "利用規約",   label: "Terms",   value: "")
            settingRow(jp: "お問い合わせ", label: "Support", value: "")
        }
    }

    @ViewBuilder
    private func section(
        label: (jp: String, en: LocalizedStringKey),
        mon: MonKind,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            BilingualLabel(japanese: label.jp, chrome: label.en, mon: mon)
            VStack(spacing: 0) { content() }
                .tatamiRoom(.standard, padding: 0)
        }
    }

    @ViewBuilder
    private func settingRow(jp: String, label: LocalizedStringKey, value: String, action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 16) {
                Text(jp)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(TatamiTokens.paperGhost)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ikeruTextPrimary)
                Spacer()
                if !value.isEmpty {
                    Text(value)
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                }
                Text("›")
                    .font(.system(size: 14))
                    .foregroundStyle(TatamiTokens.goldDim)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(TatamiTokens.goldDim.opacity(0.2))
                    .frame(height: 1).padding(.horizontal, 16)
            }
        }
        .buttonStyle(.plain)
    }

    private var languageRow: some View {
        Button { showingLanguagePicker = true } label: {
            HStack(spacing: 16) {
                Text("言語")
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(TatamiTokens.paperGhost)
                Text("Language", comment: "Settings row label")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ikeruTextPrimary)
                Spacer()
                Text(currentLanguageLabel)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                Text("›")
                    .font(.system(size: 14))
                    .foregroundStyle(TatamiTokens.goldDim)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(TatamiTokens.goldDim.opacity(0.2))
                    .frame(height: 1).padding(.horizontal, 16)
            }
        }
        .buttonStyle(.plain)
    }

    @Environment(AppLocale.self) private var appLocale
    private var currentLanguageLabel: String {
        switch appLocale.preference {
        case .system: return String(localized: "Auto · English")
            // Note: this label is computed; if French is currently active, return "Auto · Français"
        case .en: return "English"
        case .fr: return "Français"
        }
    }
```

For the auto label to switch to "Auto · Français" when the resolved locale is FR, refine `currentLanguageLabel`:

```swift
    private var currentLanguageLabel: String {
        switch appLocale.preference {
        case .system:
            let lang = appLocale.currentLocale.language.languageCode?.identifier ?? "en"
            return lang == "fr"
                ? String(localized: "Auto · Français")
                : String(localized: "Auto · English")
        case .en: return "English"
        case .fr: return "Français"
        }
    }
```

- [ ] **Step 2: Catalog entries**

| Key | English | Français |
|---|---|---|
| `Settings` | Settings | Réglages |
| `Preferences` | Preferences | Préférences |
| `Practice` | Practice | Pratique |
| `Memory algorithm` | Memory algorithm | Algorithme de mémoire |
| `Account` | Account | Compte |
| `About` | About | À propos |
| `Daily goal` | Daily goal | Objectif quotidien |
| `Reminders` | Reminders | Rappels |
| `Sound` | Sound | Son |
| `FSRS parameters` | FSRS parameters | Paramètres FSRS |
| `Target retention` | Target retention | Taux de rétention cible |
| `Maximum interval` | Maximum interval | Intervalle maximum |
| `Profile` | Profile | Profil |
| `iCloud sync` | iCloud sync | Sync iCloud |
| `Language` | Language | Langue |
| `Auto · English` | Auto · English | Auto · Anglais |
| `Auto · Français` | Auto · Français | Auto · Français |
| `Version` | Version | Version |
| `Terms` | Terms | Conditions |
| `Support` | Support | Support |
| `On` | On | Activé |
| `Off` | Off | Désactivé |

- [ ] **Step 3: Build and commit**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
git add Ikeru/Views/Settings/SettingsView.swift Ikeru/Localization/Localizable.xcstrings
git commit -m "feat(settings): Tatami bilingual rows + Language picker entry"
```

---

## Task 11: Tab bar (kanji-only)

**Files:**
- Modify: `Ikeru/Views/Shared/Theme/IkeruTabBar.swift`
- Modify: `Ikeru/Views/MainTabView.swift` (only if `AppTab.icon` strings need updates — likely not, since the bar drives rendering)
- Modify: `Ikeru/Localization/Localizable.xcstrings`

### Task 11a: Replace tab cell rendering

- [ ] **Step 1: Read existing `IkeruTabBar.swift`**

```bash
grep -n "AppTab\|TabCell\|HStack\|VStack" Ikeru/Views/Shared/Theme/IkeruTabBar.swift | head -30
```

Identify the tab-cell view (the inner view that renders one tab's icon + label).

- [ ] **Step 2: Replace the cell with kanji-only rendering**

In `IkeruTabBar.swift`, define:

```swift
private struct TatamiTabCell: View {
    let tab: AppTab
    let isActive: Bool
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
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(isActive ? Color.ikeruPrimaryAccent : TatamiTokens.paperGhost)
                Text(englishLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isActive ? Color.ikeruTextSecondary : TatamiTokens.paperGhost)
                    .tracking(1.2)
                    .textCase(.uppercase)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var japaneseLabel: String {
        switch tab {
        case .home: return "稽古"
        case .study: return "辞書"
        case .companion: return "対話"
        case .rpg: return "段位"
        case .settings: return "設定"
        }
    }

    private var englishLabel: LocalizedStringKey {
        switch tab {
        case .home: return "Practice"
        case .study: return "Study"
        case .companion: return "Talk"
        case .rpg: return "Profile"
        case .settings: return "Settings"
        }
    }

    private var monKind: MonKind {
        switch tab {
        case .home: return .asanoha
        case .study: return .kikkou
        case .companion: return .genji
        case .rpg: return .maru
        case .settings: return .kikkou  // shares with Study but never both active at once
        }
    }
}
```

Then in the existing `IkeruTabBar` body, replace the per-tab loop with:

```swift
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                TatamiTabCell(
                    tab: tab,
                    isActive: selection == tab,
                    onTap: { withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        selection = tab
                    } }
                )
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 26)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            FusumaRail(opacity: 0.7)
        }
```

(Remove any existing icon rendering and pill-background-on-active styling.)

- [ ] **Step 2: Catalog entries (most already added)**

| Key | English | Français |
|---|---|---|
| `Practice` | Practice | Pratique |
| `Study` | Study | Étude |
| `Talk` | Talk | Parler |

(`Profile`, `Settings` already in catalog.)

- [ ] **Step 3: Build, run, manually check tab switching**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
```

Switch each tab → confirm:
- The kanji of the active tab is gold and has a mon above it.
- Inactive tabs are dim with no mon.
- All 5 tabs route to their existing screens.

- [ ] **Step 4: Commit**

```bash
git add Ikeru/Views/Shared/Theme/IkeruTabBar.swift Ikeru/Localization/Localizable.xcstrings
git commit -m "feat(tatami): kanji-only tab bar with mon active marker"
```

### Task 11b: End-of-build verification (test in EN and FR)

- [ ] **Step 1: All tests green**

```bash
xcodebuild test -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -15
```

Expected: every test passes.

- [ ] **Step 2: Manual EN/FR locale verification**

In the simulator, in the Ikeru Settings → 言語 / Language → switch between Auto / English / Français. Confirm:
- The change applies immediately, with no app relaunch.
- Every visible English string switches to its French translation.
- Japanese (kana, kanji, proverbs, deck names like ひらがな) stays the same in both languages.

- [ ] **Step 3: Verify the catalog has no "Needs Review" entries**

Open `Localizable.xcstrings` in Xcode → filter by "Needs Review". Resolve every flagged entry by either confirming the translation or correcting it. Save.

```bash
git diff --stat Ikeru/Localization/Localizable.xcstrings
git add Ikeru/Localization/Localizable.xcstrings
git commit -m "chore(i18n): finalize translations and clear Needs-Review flags" || true
```

(The `|| true` covers the case where there's nothing left to commit.)

- [ ] **Step 4: Final build, install on simulator**

```bash
xcodebuild -project Ikeru.xcodeproj -scheme Ikeru -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. Confirm the app installs and launches on the iPhone 16 simulator.

- [ ] **Step 5: STOP. Report to user.**

Output to the user:

> Tatami direction implementation is complete and the app is installable on the iPhone 16 simulator. Build is green and all tests pass. Both EN and FR locales render correctly. **Ready for MobAI testing on your physical iPhone — please give the green-light when you want me to start the device walkthrough.**

**Do not** invoke any MobAI tool until the user explicitly approves it.

---

## Self-review checklist

After completing every task, verify against the spec:

**Spec coverage:**
- [ ] Marble background (5 PNG variants, deterministic-per-screen mapping) — Task 1h, 1i, 3
- [ ] Fusuma rails on every card-equivalent — Task 1c, used inside `TatamiRoom`
- [ ] Sumi corners on every card-equivalent — Task 1d, used inside `TatamiRoom`
- [ ] Mon crests (4 kinds) on deck identifiers, status, tab-bar active marker — Task 1e, used in Tasks 4, 5, 6, 7, 8, 9, 11
- [ ] Hanko stamps once per screen on urgent items — Task 1f, used in Home (急), Study (N5/N4 etc.), RPG (achievements), Settings language picker (選)
- [ ] Torii frame on RPG profile big crest — Task 1j, 1k, used in Task 7
- [ ] Ensō stays on small Home pill / hero rank-row — verified in Task 4 (existing `EnsoRankView` reused in `levelPill`)
- [ ] All numerals in Noto Serif JP — `SerifNumeral` used everywhere (Task 1b)
- [ ] Bilingual JP·EN labels on chrome — `BilingualLabel` (Task 1g) used everywhere
- [ ] Status-bar serif kanji date — Task 4b
- [ ] Sharp gold "稽古を始める · BEGIN PRACTICE" CTA shape — Task 4c
- [ ] FSRS buttons with kanji headers — Task 5b
- [ ] Tab bar kanji-only with mon active marker — Task 11a
- [ ] No Plan/Premium row in Settings — confirmed omitted in Task 10
- [ ] EN/FR with auto-detection — Task 2b
- [ ] Settings language picker — Task 2e + Task 10a
- [ ] All view-models untouched — every per-screen task says "do not modify view-model"
- [ ] All tests still green — verified end of every task
- [ ] No MobAI run — final step says STOP

**Placeholder scan:** Search the plan for "TBD", "TODO", "implement later" — no occurrences. ✓

**Type consistency:** `MonKind`, `MarbleVariant`, `LanguagePreference`, `TatamiRoomVariant` defined once; method signatures consistent across tasks (e.g., `RPGRankCrest(level:size:dashed:)` matches usage in Task 7). ✓

If any task touches a property the view-model doesn't expose, the task says "use whatever exists; do not add new properties". This keeps zero functional change. ✓

---

## Notes for the implementer

- Each new file must be added to the Ikeru target in Xcode before its commit. If your `.pbxproj` uses synchronized folder references (Xcode 15.3+), simply dropping a `.swift` file into a tracked folder is enough. Otherwise, drag-add the file in Xcode's project navigator.
- All `Text(localized:)` and `Text("Foo", comment: "...")` calls automatically appear in `Localizable.xcstrings` once you build. If a key doesn't show up, build the project once with the catalog open.
- Frequent commits are expected — every step ends with one. If a step is large enough that the commit feels too coarse, split it. Granularity errs on the side of more commits.
- Do not refactor unrelated code while implementing this plan. Keep diffs surgical.
