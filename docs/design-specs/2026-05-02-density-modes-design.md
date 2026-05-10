# Density Modes & Beginner-First UI — Design Spec

**Date:** 2026-05-02
**Branch:** design/wabi-refinements (continuation)
**Author:** Nico
**Status:** Approved — ready for implementation plan

---

## Problem

The current Tatami refresh gives the app a strong, distinctive identity but reads as **kanji-saturated chrome** for anyone who isn't already comfortable with Japanese. Tab bar, headers, chips, section labels, drill UI — all use kanji glyphs as primary text with FR/EN demoted to small captions or accessibility labels. For a learning app whose primary audience is **people who don't yet read Japanese fluently**, the navigation language being Japanese is backwards: the chrome itself becomes a friction surface before the learner has touched any content.

Symptoms:

- Beginners see "段位 / 道 / 力 / 又 / 財" before they can read any of those characters.
- Information density is high — every surface carries a serif kanji glyph + a mon crest + small caps + a hairline. Reads as "supercharged" rather than calm.
- Onboarding through first-week reading has zero affordance from the chrome itself.

We do not want to throw away the Tatami language — it's earned, distinctive, and our north star for advanced surfaces. The ask is to make Tatami **a destination the user grows into**, not the entry door.

## Goals

- New users land in a UI whose chrome is legible without Japanese knowledge.
- Existing users keep the Tatami chrome they're used to (no regression).
- Tatami chrome is reachable as an explicit, suggested mode, not the only mode.
- Add the missing iOS-pager affordance to the learning tabs (swipe between Étude / Accueil / Rang).
- Replace the current binary tab indicator with a fluid, brand-aligned selector animation.

## Non-Goals

- Not a re-skin of card content. Drill faces, kana cards, vocab faces, RPG card titles in lootboxes — all stay Japanese-first. This spec is about **chrome**, plus reading-aid defaults.
- Not changing the app locale system (FR ↔ EN). The density toggle is orthogonal to locale.
- Not a redesign of Sakura's chat surface. The toggle only sets sensible defaults for Sakura's existing pronunciation/kana toggles; the chat UI itself doesn't change.
- Not a new icon kit. We use SF Symbols.

## Approach Overview

Introduce a single user-facing setting — **Interface Tatami** — with two states:

- **Beginner mode** (default for new accounts): SF-Symbol icons + FR/EN labels in chrome, furigana visible by default, romaji visible on vocab cards by default, glossary popovers expanded by default, mnemonics rendered in the user's locale, Sakura's reading aids defaulted ON.
- **Tatami mode** (current state, opt-in): kanji-first chrome (current Tatami styling), furigana off by default, no romaji on vocab cards, glossary popovers collapsed by default, mnemonics in JP, Sakura's reading aids defaulted OFF.

The toggle sets defaults, not hard locks. Per-card / per-message overrides that already exist (e.g., the kana toggle in Sakura, furigana switch in vocab review) remain user-controllable on top of the default.

Layered onto this: a redesigned tab bar with SF Symbols + FR/EN labels and a sliding kintsugi-gold rail indicator, and full-pane horizontal swipe across the three learning tabs.

## Architecture

### `DisplayMode` model

```swift
public enum DisplayMode: String, Codable, CaseIterable, Sendable {
    case beginner   // default for new accounts
    case tatami     // opt-in / earned
}
```

Lives in `IkeruCore/Sources/Models/Display/DisplayMode.swift`.

### `DisplayModePreference` repository

Profile-scoped (matches the existing pattern with `ActiveProfileResolver` / `CardRepository`). Backed by UserDefaults keyed `display.mode.<profileID>`. Exposes:

```swift
public protocol DisplayModePreferenceRepository {
    func current() -> DisplayMode
    func set(_ mode: DisplayMode)
    var publisher: AnyPublisher<DisplayMode, Never> { get }
}
```

A concrete `UserDefaultsDisplayModePreferenceRepository` reads the active profile id from `ActiveProfileResolver` on each call. On profile switch, the publisher republishes the new profile's value.

### Environment propagation

```swift
private struct DisplayModeKey: EnvironmentKey {
    static let defaultValue: DisplayMode = .beginner
}

extension EnvironmentValues {
    var displayMode: DisplayMode { ... }
}
```

`MainTabView` injects the current value via `.environment(\.displayMode, mode)` after subscribing to the repository's publisher. All chrome modifiers read this environment value rather than the repository directly.

### Mode-aware chrome modifiers

Three primary modifier families need mode awareness:

1. **`BilingualLabel`** — already exists. Extend with `.densityAware()` so `BilingualLabel(japanese: "力", chrome: "Attributes", mon: .kikkou)` renders:
   - In `.beginner`: "Attributes" as primary, kanji as small dim suffix `力 chikara` at 70% opacity.
   - In `.tatami`: kanji as primary (current behavior).

2. **`tatamiStatChip` / RPG chips** — currently use kanji glyph + EN caps. In Beginner: replace kanji glyph with SF Symbol (e.g., `arrow.triangle.2.circlepath` for reviews, `cube.fill` for items, `bolt.fill` for attributes), EN caps stay. In Tatami: current rendering (又/財/力 + caps).

3. **Section headers** in `RPGProfileView`, `ProgressDashboardView`, `SettingsView`, etc. — use `BilingualLabel` so they pick up densityAware behavior automatically.

### Reading-aid defaults

Existing user-facing toggles whose **defaults** depend on `displayMode`:

| Surface | Beginner default | Tatami default |
|---|---|---|
| Vocab card romaji visibility | visible | hidden |
| Vocab card furigana | visible | hidden |
| Glossary popover expanded state | expanded | collapsed |
| Mnemonic rendering language | locale (FR/EN) | JP |
| Sakura: pronunciation overlay | on | off |
| Sakura: kana fallback overlay | on | off |
| Onboarding tour copy | locale-only | locale + JP gloss |

Each surface reads `@Environment(\.displayMode)` and its existing user-toggle store; the toggle store holds an explicit "user-overridden" flag so the mode default doesn't clobber an explicit choice.

### `IkeruTabBar` redesign

Drop kanji-as-primary. Each tab cell becomes:

```
[ SF Symbol, 22pt ]
[ Localized label, 11pt semibold, ~10pt baseline gap ]
```

Tab → SF Symbol mapping:

| Tab | SF Symbol | EN label | FR label |
|---|---|---|---|
| Étude | `book.fill` | Study | Étude |
| Chat | `bubble.left.and.bubble.right.fill` | Chat | Chat |
| Accueil | `house.fill` | Home | Accueil |
| Rang | `rosette` | Rank | Rang |
| Réglages | `gearshape.fill` | Settings | Réglages |

**Selector** — a single `Capsule()`-ish thin rail (4pt tall, 28pt wide centered under each tab cell) drawn with the kintsugi gold gradient, animated with `matchedGeometryEffect` so it slides between tabs on selection change. The rail emits a soft outer glow (8pt radius, 0.55 alpha gold). Tab transitions use `.spring(response: 0.4, dampingFraction: 0.78)`.

**Tatami mode override** — when `displayMode == .tatami`, `IkeruTabBar` falls back to the current kanji-only rendering (道 話 家 段 設 / 17pt serif glyphs, no labels). The rail stays — it's mode-agnostic.

### Swipe-paged learning tabs

`MainTabView` currently uses a vanilla `TabView` with a custom tab bar overlay. Restructure as:

```swift
ZStack(alignment: .bottom) {
    PagedLearningStack(
        selection: $selection,
        screens: [.etude, .accueil, .rang]
    )
    .matchedGeometrySource(...)

    // Chat and Réglages remain modal/overlay tabs activated by tap
    // — they appear via state-based `fullScreenCover` or a `Group` switch.

    IkeruTabBar(selection: $selection, ...)
}
```

`PagedLearningStack` is a custom container:

- Holds the three learning destinations in an `HStack` of width `3 × screen.width`, offset by `-CGFloat(activeIndex) * width + dragOffset`.
- `DragGesture(minimumDistance: 12)` drives `dragOffset`. On `.onEnded`:
  - If `|translation| > width / 2` (or velocity > 600pt/s): commit to next/prev index.
  - Else: spring back to current index.
- Rubber-band at the boundary indices (multiply offset by 0.35 once it would push past the first/last page).
- The same `DragGesture` updates a `@Binding var railOffset: CGFloat` consumed by the tab bar so the kintsugi rail tracks the finger live (not snap-on-release).
- `MainTabView` switches its content container based on `selection`:
  - When `selection ∈ {étude, accueil, rang}`: render `PagedLearningStack` (the swipe pager).
  - When `selection ∈ {chat, réglages}`: render the destination view directly inside a non-paged container — no horizontal swipe binding on these screens.
  - The `IkeruTabBar` is rendered above both containers in either case, so the rail can still reflect any selection.
- Tapping Chat or Réglages thus enters via tab-bar tap only and does not participate in the page drag.

Pages other than the active one render a placeholder until they're within ±1 of active, to avoid pre-warming three full screens worth of data.

### Suggestion card on Accueil

`DisplayModeAdvancedThresholdMonitor` (struct, not @MainActor unless needed):

- Reads from existing repositories: `RPGState` for streak days, `CardRepository.totalReviews(profile:)`, `CardRepository.cardsAtMasteryOrAbove(.familiar, profile:)`.
- Emits `.eligible` once **all three** are true:
  - active streak ≥ 21 days **or** total active days ≥ 30
  - reviews completed ≥ 500
  - cards at mastery 慣 (`.familiar`) or higher ≥ 50
- Exposes a one-shot publisher that fires **once per profile**. Fired status persists in UserDefaults `display.mode.suggestionShown.<profileID>`.

`HomeView` subscribes; if eligible and not yet dismissed, renders the suggestion card pinned above the main content. Card has two CTAs:

- **"Essayer"** — calls `DisplayModePreference.set(.tatami)`, marks `suggestionShown = true`, dismisses.
- **"Plus tard" / ×** — marks `suggestionShown = true`, dismisses. Never shown again.

Card copy (FR primary, EN parallel via `Localizable.xcstrings`):

> **Tu lis maintenant le japonais avec aisance.**
> Active l'interface Tatami — kanji partout, romaji et traductions masqués par défaut. Un mode pour les apprenants confirmés. Ajustable à tout moment dans Réglages.
>
> [Essayer]   [Plus tard]

### Settings entry

New row inside the existing "Affichage" / "Display" section (creating that section if it doesn't already exist):

```
Interface Tatami            [ ◯ ]
Kanji partout, traductions masquées
```

Below the toggle, a small explainer line when off:
> Conçu pour les apprenants à l'aise avec le japonais.

When on:
> Pour revenir au mode beginner-friendly, désactive ici.

## Migration

- The migration is a **lazy, one-shot write** keyed off the absence of `display.mode.<profileID>` in UserDefaults.
- On first repository read after the update:
  - If the key exists → use stored value (subsequent flips persist normally).
  - If the key is missing **and** the profile's `createdAt` is before a hard-coded `densityModesReleaseDate` constant → write `.tatami` and persist. Existing users see no chrome change.
  - If the key is missing **and** the profile is newer than the release date → write `.beginner` and persist. New users land in beginner-first chrome.
- After the lazy write, the threshold monitor begins watching beginner-mode profiles silently.

## Localization

New strings (FR primary):

- Tab bar labels: Étude / Chat / Accueil / Rang / Réglages (already exist as `BilingualLabel.chrome` parameters; ensure xcstrings entries exist).
- "Interface Tatami" / "Tatami interface", subtitles, both states.
- Suggestion card title and body.
- Mnemonic locale-routing requires existing FR mnemonics; if a card has no FR mnemonic, fall back to EN, then JP last.

Out-of-scope locales for this spec: only FR and EN are currently shipped. JP UI locale is not covered here.

## Telemetry / Logging

- Log mode changes: `display.mode.changed` with `from`, `to`, `trigger` (`settings`, `suggestion`, `migration`).
- Log suggestion outcomes: `display.mode.suggestion.shown`, `display.mode.suggestion.accepted`, `display.mode.suggestion.dismissed`.
- All events profile-scoped so we can later answer "what % of accounts that crossed threshold accepted?"

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Existing Tatami users feel migration was forced when it actually wasn't | Migration only sets value; in-app banner: "Nouvelle interface Beginner disponible — tu es resté en Tatami" with a link to flip. Shown once. |
| Swipe gesture conflicts with horizontal scrollers inside learning tabs | Audit existing horizontal scrollers (if any) and add `.simultaneousGesture` opt-out so inner scroll wins inside its bounds. |
| Suggestion card looks like a paywall / upsell | Copy and styling explicitly avoid the language of upgrade — frame as "you've earned this" not "unlock". Card uses brand gold, not a CTA color. |
| Furigana-by-default impacts performance on long vocab lists | Furigana renderer already exists; render cost is per-row, not global. Profile if list-scroll FPS drops. |
| Mode-aware chrome doubles the testing surface | Snapshot tests per mode for tab bar, RPG profile, Home, Settings. ~10 new snapshots total. |

## Acceptance Criteria

- [ ] New profile → tab bar shows SF Symbols + FR labels, kintsugi rail under active tab.
- [ ] Existing profile → tab bar shows kanji-first chrome (current Tatami), kintsugi rail under active tab.
- [ ] Toggle in Settings → all chrome surfaces re-render to reflect new mode without app restart.
- [ ] Swiping right on Étude → arrives at Accueil; rail slides live with finger; spring-back works below halfway.
- [ ] Swiping past first or last learning tab → rubber-bands, never wraps.
- [ ] Tapping Chat or Réglages from Étude → modal/overlay transition, not page slide.
- [ ] Sakura chat opened in Beginner → pronunciation + kana toggles default on.
- [ ] Sakura chat opened in Tatami → both default off.
- [ ] Profile crossing threshold (21 streak + 500 reviews + 50 mastered) → suggestion card appears once on Accueil.
- [ ] Card "Plus tard" → never shown again for that profile.
- [ ] Card "Essayer" → mode flips, full UI re-renders, card dismissed.

## Testing Plan

- **Unit:** `DisplayMode` codable round-trip; `UserDefaultsDisplayModePreferenceRepository` profile-scoping; `DisplayModeAdvancedThresholdMonitor` gating with fixture data (each combo of three signals; only all-true triggers eligible).
- **Integration:** mode toggle flips environment value across `MainTabView` subtree; Sakura subscribes correctly; furigana visibility default flips with mode.
- **Snapshot:** tab bar (both modes), Accueil suggestion card, RPG chips (both modes), Settings row (both states).
- **Gesture / interaction:** XCUITest: drag from Étude → Accueil and Accueil → Rang and back; verify rail position keyed off page offset; verify Chat/Réglages tap-only.
- **Manual QA:** install over existing profile (verify Tatami preserved); install fresh (verify Beginner default); cross threshold via fixture (verify suggestion timing).

## Out of Scope (revisit later)

- Three-level density slider (Beginner / Intermediate / Advanced). If two modes prove too coarse after launch, this is the natural next step.
- A "preview Tatami" mode that flips the chrome for 60 seconds without committing — useful but additional complexity.
- Migration banner strings beyond FR/EN.
- Wraparound swipe (Rang → Étude). Considered, rejected: implies infinite carousel; conflicts with finite study loop semantics.

## Open Questions

None — all locked during brainstorm.
