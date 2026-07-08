# Ikeru Design Rig

A zero-build HTML/CSS harness that mimics how Ikeru renders on an iPhone, so UI/UX work can be
designed, reviewed, and screenshotted **on the web** — including by AI agents that have no iOS
simulator. It is a **design tool, not a web app**: no framework, no bundler, no app logic, never
shipped to users.

## Why this exists

The app is SwiftUI-only and stays that way (see `docs/reviews/2026-07-08-remediation-plan.md`,
"Decision" section). But design iteration was previously blind for anyone without a Mac + simulator.
The rig closes that loop:

```
design/iterate here (HTML/CSS) → node design-rig/screenshot.mjs → review PNGs in design-rig/shots/
      → human approves → port the approved design to SwiftUI → keep the rig page as the design spec
```

## Layout

- `css/tokens.css` — design tokens transcribed from `IkeruCore/Sources/Theme/IkeruTheme.swift` and
  `Ikeru/Views/Shared/Theme/Tatami/TatamiTokens.swift`. **The Swift files are the source of truth**;
  each CSS custom property cites its Swift origin. If a token changes in Swift, update it here.
- `css/device.css` — iPhone chrome: 393×852 pt viewport, Dynamic Island, status bar, home indicator,
  safe-area padding, dark surround.
- `css/components.css` — mirrors of the Tatami component set (cards, glass, buttons, kintsugi
  hairline, hanko, mon crests, bilingual labels, serif numerals, XP bars, tab bar, toasts, enso ring).
- `screens/*.html` — one page per app screen, composed from the components with believable data.
- `js/rig.js` — injects the shared device frame and the screen-switcher nav (outside the frame).
- `screenshot.mjs` — Playwright renderer: `node design-rig/screenshot.mjs [screen ...]` →
  `shots/<screen>.png` (2x scale). Requires Chromium via Playwright (`PLAYWRIGHT_BROWSERS_PATH` or a
  local install); falls back to `/opt/pw-browsers/chromium`.
- `shots/` — rendered PNGs (gitignored except when intentionally committed for a review).

## Fidelity limits (accepted)

- System font stack approximates SF Pro; kanji use the real bundled Noto Serif JP TTFs
  (`../Ikeru/Resources/Fonts/`).
- No native blur/material physics, no haptics, no gesture feel — those still need the
  TestFlight/device loop. The rig removes blindness on layout, hierarchy, color, and typography.

## Adding a screen

1. Copy an existing page in `screens/`, keep the `<head>` includes and the `data-screen` attribute.
2. Compose from `components.css` classes; put screen-specific rules in a `<style>` block on the page.
3. Use real Japanese text and believable data — no lorem ipsum.
4. `node design-rig/screenshot.mjs yourscreen`, review the PNG, iterate.
