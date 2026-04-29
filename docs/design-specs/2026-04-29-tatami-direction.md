# Tatami Direction — Implementation Spec

**Branch:** `design/wabi-refinements`
**Date:** 2026-04-29
**Source:** Claude Design package
`Ikeru - iOS Japanese Learning App - Design Review-handoff.tar.gz`
(`api.anthropic.com/v1/design/h/39Kk1M_sA10ln3AE9ez0PA`),
specifically `project/Ikeru Tatami Direction.html` and `tatami-screens.jsx`.

---

## Goal

Apply the **Tatami** visual vocabulary across every screen of Ikeru without
changing a single piece of functional behavior. The Tatami direction is the
final design landing point from the iterative review chat: same dark+gold
palette, same scannable card layouts, same one-tap practice flow — but
expressed in a vocabulary built from real Japanese architectural and graphic
precedents (tatami proportions, fusuma sliding-door rails, mon family crests,
sumi ink corners, vermilion hanko stamps).

Out of scope:
- FSRS scheduling, AI providers, vocab tracking, navigation, data models, view
  models — **zero functional change**.
- The premium "Plan" row in Settings — confirmed not in the app.
- The Companion floating avatar overlay — kept as-is.

## Why this direction

Quoted from the chat (intent the design assistant landed on):

> "The previous wabi-sabi directions failed because they sacrificed
> scannability for atmosphere — too much whitespace, too much vertical text,
> too few affordances. This direction inverts that trade-off: structurally,
> it's almost identical to the current Ikeru. Visually, it speaks a vocabulary
> nobody else owns."

The five primitives are reused on every screen, so the cost of learning the
vocabulary amortizes across the entire app instead of decorating one screen.

## The five primitives

| # | Primitive | Replaces | Spec |
|---|---|---|---|
| 1 | **Marble background** — warm dark base + thin gold veins | flat `#0A0A0F` background | Pre-baked PNGs, **5 variants** (one per mon kind, plus a fifth for tab-bar / overlay surfaces) cycled per-screen for visual variety. SwiftUI does not have `feTurbulence`; baking matches how shōji / tatami are made physically. |
| 2 | **Fusuma rail** — paired hairlines (gold 1px / 1px gap / shadow 1px), 3px tall | rounded-corner `1px` borders | Top and bottom of every card-equivalent surface. Comes from sliding-door rail joinery. Use **everywhere a 1px border would normally go.** |
| 3 | **Sumi corner** — sharp ink-brushed L-marks at four corners | rounded-corner radius | Default L-length 10px, weight 1.5px, gold (`#D4A574`) on accent surfaces, dim-gold (`#8A6D4A`) on quiet ones. **Sharp 0px radius** on the rectangle the marks frame. |
| 4 | **Mon crest** — 4 geometric family marks (asanoha, genji, kikkou, maru) | colored dots and SF-Symbol-style icons | Used as deck identifiers, status indicators, tab-bar active markers, section-header glyphs. Each deck/skill gets a stable mon for app-wide visual identity. |
| 5 | **Hanko stamp** — vermilion (`#C73E33`) clipped square containing a kanji | red badges, warning dots, exclamation points | **Once per screen, max.** Slight irregularity (clip-path) is intentional — it has to read as a real seal impression. The only red in the entire UI. |

Plus three typographic moves used throughout:

- **All numerals in Noto Serif JP** (counts, percentages, time, XP). Single font
  family makes the UI feel coherent in a way nothing else does.
- **Bilingual JP·EN labels** for all chrome — section headers (本日 · TODAY,
  稽古場 · DECKS), buttons (稽古を始める · BEGIN PRACTICE), settings rows
  (一日の目標 / Daily goal). The Japanese reads as the formal name; English is
  the gloss.
- **Status-bar date in serif kanji** (四月二十九日 · 火) replacing the system
  date.

## What the current branch already aligns with

`design/wabi-refinements` has gotten ~30% of the way there. These stay:

- `EnsoRankView` — used at small sizes (Home pill, Home rank row).
- `KintsugiHairline`, `MountainGlyph` — already on-brand for Tatami.
- `SegmentedXPBarView` — segmented ticks read as "carved" not "smeared".
- `IkeruLogo` (Calligraphic Taper variant B) — matches the design.
- `CornerTicks` — close to Sumi Corner. Will be replaced by a sharper sibling
  (see below) but the original stays for any non-Tatami surface.

## What changes on the existing branch

| Current | Tatami | Why |
|---|---|---|
| `IkeruScreenBackground` (flat dark + slight gradient) | `IkeruScreenBackground` with marble variant | Marble is the Tatami signature — has to be on every screen. |
| `IkeruCard` (rounded glass, radius 18-24, white-tint) | `TatamiRoom` (sharp 0px radius, solid fill, fusuma rails, sumi corners) | The design explicitly rejects glassmorphism and rounded corners for cards. |
| `IkeruTabBar` (SF Symbols + EN labels) | Same bar, kanji + EN labels, mon active marker, **no icons** | Per the design's *"the kanji is the headline; English is the gloss"* principle. |
| FSRS grade buttons (rounded, color-tinted) | Sharp tatami buttons with **kanji header** (又/難/良/易) + sumi corners + interval below | Higher semantic payload, less chrome. Same 4-button layout, same FSRS interaction. |
| RPG Profile rank crest (planned ensō) | **Torii (鳥居) frame** around the level kanji | User decision: temple gate carries similar cultural weight to ensō, more architectural at hero size (size ≥ 80). Tiny ensō stays on Home pill (size ≤ 30). |

## Per-screen change map

All of these keep their `*ViewModel`, navigation, gestures, and data flow.
Only the SwiftUI `body` of each view gets re-composed with the new primitives.

### Home (`HomeView.swift`)
- Marble background.
- Status row gets a serif-kanji date (四月二十九日 · 火).
- Welcome row keeps name + greeting + small ensō pill.
- Hero proverb card → tatami room with `Hanko 急` top-right when due > 0,
  serif numeral for due count, sharp gold "稽古を始める · BEGIN PRACTICE"
  button with sumi corners.
- Stats row: 2 tatami rooms (Learned, Streak) with mon (asanoha, genji),
  serif numerals, JP counter (kanji 札, 連).
- Decks list: fusuma-railed rows (not cards), each with a stable mon and
  Japanese deck name + EN gloss.
- Skill radar card kept; restyled to a tatami room with hairline progress bars.
- Session preview keeps all 3 cells; restyled to tatami row.

### Active Session — Card Question (`SRSCardView.swift`)
- Marble background.
- Top counter in serif Japanese style (`1 / 5`), elapsed time in serif
  kanji-monospace.
- Progress is a fusuma rail with a gold inset, not a pill.
- Card is a glass tatami room — large kana centered, soft warm `textShadow`
  glow so the kana reads as the focal mat. Hint/Skip get mon (maru, genji)
  not chevrons.

### Active Session — Card Answer (`SRSCardView.swift`)
- Same shell as Question.
- Revealed: serif kana + romaji (28pt, gold, 4px tracking) + small caps gloss.
- FSRS buttons: 4 sharp-corner cells with **kanji header** (又, 難, 良, 易),
  EN label small caps, interval below in serif. Top hairline + 2 sumi corners
  in the rating color (vermilion, amber-brown, gold, moss).

### Session Summary (`SessionSummaryView.swift`)
- Marble background.
- "稽古終わり" kicker + `Practice complete` h1 + proverb subtitle.
- Hero stat row: 3 large serif numerals (Cards · Recall · Time) divided by
  vertical gold hairlines. **Replaces emoji confetti and exclamation point.**
- XP gain → fusuma rail with bright "new gain" segment glowing.
- New vs Re-learn → 2 compact tatami cells side by side (mon-coded green and
  vermilion), JP counter (札).
- Sharp gold "続ける · CONTINUE" + secondary "Review mistakes" text button.

### RPG Profile (`RPGProfileView.swift`)
- Marble background.
- Hero rank crest: **torii (鳥居) frame** around the level kanji (大字: 一, 二,
  三 …). Temple-gate pillars + crossbeam around the central serif kanji.
  Replaces the planned ensō-only treatment.
- Rank label `第三段 · APPRENTICE`, serif XP `340 / 520`, hairline progress.
- 3-stat row: tatami rooms with mon + serif numeral + JP counter (札, 連, 時).
- Achievements: row of hanko stamps with kanji (初, 七, 百, 千, 極). Earned →
  full vermilion hanko. Unearned → dashed-outline serif kanji at 35% opacity.
- Next rank teaser: dashed torii (or dashed enso) around the next kanji at
  50% opacity, "Reach X XP to advance" + delta XP.

### Study / Progress (`ProgressDashboardView.swift`)
- Marble background.
- JLPT estimate hero: tatami room, `Hanko N5` top-right, big serif percentage,
  hairline progress.
- Skill balance: 4 rows in one tatami room, mon per skill (Hiragana=maru,
  Katakana=genji, Vocabulary=asanoha, Listening=kikkou), serif numeral,
  hairline bar.
- Decks list: fusuma-railed rows, mon + JP+EN deck name + mini-progress
  hairline + serif `learned/total`.

### Conversation / Companion (`CompanionTabView.swift`)
- Marble background.
- Sakura's portrait: square sumi-bordered cell with the kanji 桜 in serif gold
  centered. Replaces the circular gradient avatar.
- Header card: tatami room with bilingual `Sakura、 your sensei。` h1, role
  blurb, sharp gold "会話を始める · BEGIN CONVERSATION".
- Suggested topics: fusuma-railed rows with JP+EN topic names, mon, JLPT
  level in a thin gold-bordered serif chip (looks like a stamp, not a pill).
- History: rows with Japanese date markers (昨日, 一昨日) leading each row,
  topic, duration in serif (`8分`).

### Settings (`SettingsView.swift`)
- Marble background.
- Back chevron + bilingual `設定 · SETTINGS` kicker.
- `Preferences` h1 in serif.
- 4 sections, each labeled with mon: 稽古 (Practice, asanoha), 記憶 (Memory,
  kikkou), 勘定 (Account, genji), 関連 (About, maru).
- Rows: bilingual title (`一日の目標 · Daily goal`), value in gold serif,
  chevron in dim gold.
- **NO Plan/Premium row.** Per user note: doesn't exist in the app.

### Tab bar (`IkeruTabBar.swift`, `MainTabView.swift`)
- 5 tabs: 稽古 / 辞書 / 対話 / 段位 / 設定 (Home / Study / Companion / RPG /
  Settings). Kanji + EN gloss, **no icons**. Mon active marker above the kanji.
- Top fusuma rail above the bar.
- Ultra-thin material backing kept (the only place glassmorphism stays — it
  matches iOS native nav patterns and the design uses it deliberately for
  the bar surface).

## New components to add

All under `Ikeru/Views/Shared/Theme/Tatami/` (new folder, keeps the existing
theme directory clean and makes the Tatami vocabulary discoverable as a unit):

| File | Purpose |
|---|---|
| `MarbleBackground.swift` | View that picks a marble PNG variant (deterministically by screen ID, or randomized once per session). |
| `FusumaRail.swift` | View that renders the paired-hairline rail. Horizontal and vertical orientations. |
| `SumiCornerFrame.swift` | ViewModifier that overlays four sumi corners with configurable size, weight, color. |
| `MonCrest.swift` | View with `kind: MonKind` enum (asanoha / genji / kikkou / maru). Renders the geometric SVG-equivalent paths in SwiftUI `Path`. |
| `HankoStamp.swift` | View with `kanji: String`, vermilion clipped square with serif kanji centered. Subtle inset shadow + irregular clip-path. |
| `ToriiFrame.swift` | View that renders a 鳥居 (temple gate) shape around its content. Used by `RPGRankCrest`. |
| `RPGRankCrest.swift` | Wrapper for the RPG profile hero crest — torii + serif kanji. Keeps `EnsoRankView` for small sizes. |
| `TatamiRoom.swift` | ViewModifier giving a view: solid fill + top/bottom fusuma rails + sumi corners + sharp 0px radius. Variants: `.standard`, `.accent` (gold-warmer), `.glass` (used sparingly — Liquid-Glass surface for hero cards only). |
| `TatamiTokens.swift` | Vermilion (`#C73E33`), gold-dim (`#8A6D4A`), and other Tatami-specific colors. Stays out of `IkeruTheme.Colors` so existing surfaces don't shift. |
| `BilingualLabel.swift` | Tiny helper for the JP · EN section-header pattern (mon + serif JP + middot + caps EN). |
| `SerifNumeral.swift` | Convenience for Noto Serif JP numerals at consistent weights/sizes. |

Marble PNG assets land in `Ikeru/Assets.xcassets/Tatami/Marble/`:
`marble-1.imageset` … `marble-5.imageset`, each ~150-300KB at @3x. Generated
locally with the same SVG turbulence params from `tokens.jsx` then exported.
Mapping is deterministic-per-screen so the user sees the same marble texture
for the same screen on every visit:
- Home → marble-1
- Card review (active session) → marble-2
- Session summary → marble-3
- RPG profile → marble-4
- Study, Companion, Settings, Tab-bar overlay → marble-5

## Build order

Each step ships independently — every commit leaves the app green and runnable:

1. **Foundations** — add the 11 new theme files above + 5 marble PNGs. Add
   `#Preview` for each component. No call sites changed yet.
2. **Background swap** — replace `IkeruScreenBackground` body with the marble
   variant.
3. **Home** — most-seen screen. Replace hero / stats / decks rendering with the
   Tatami composition. `HomeViewModel` untouched.
4. **Active Session (SRS Q/A)** — kana card + FSRS buttons.
5. **Session Summary**.
6. **RPG Profile** — including the new `ToriiFrame` + `RPGRankCrest`.
7. **Study / Progress**.
8. **Conversation / Companion**.
9. **Settings**.
10. **Tab bar** — last, because it's the most visible "this is a different app"
    moment and we want the inside to be ready first.

After step 10: build green → installable → **stop**, hand to the user for the
MobAI green-light before driving the device.

## Acceptance criteria

For each screen, success = the rendered SwiftUI matches the corresponding
right-side phone in the Tatami HTML on these axes:

- Color tokens (palette unchanged, vermilion only on hanko, gold-dim hairlines).
- Typography family (serif on numerals, kana, kanji, proverbs; system on EN
  chrome).
- No rounded corners on any card-equivalent surface.
- Fusuma rails appear top + bottom of every card-equivalent.
- Mon / hanko / sumi-corner / marble appear at the call sites listed in the
  per-screen change map.
- Tap targets unchanged (Apple HIG 44pt minimum on all rows / buttons).
- Functional behavior unchanged — every test in `IkeruTests/` continues to
  pass without modification.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Marble PNG visual seam at screen edges | All variants are designed to be edge-fade (radial vignette to ink at corners) and tile-tolerant. |
| Sharp 0px corners look "harsh" on iPhone (which expects rounded) | Sumi corners do the visual softening that radius normally does. Tested in design mockups; reads correctly at iPhone sizes. |
| Kanji-only tab bar discoverability for new users | EN gloss directly under the kanji on every tab. Same widths, same tap targets. The design's argument is that after one session the kanji become learned anchors. |
| Performance: 5 PNG assets per session | Each is ≤300KB, decoded once and held by SwiftUI's image cache. Marble background is one image-fill, no per-frame work. |
| Existing `IkeruCard` call sites that aren't in the per-screen map (e.g. loot box, level-up, onboarding) | They keep `IkeruCard` for now. Tatami-fy them in a follow-up after the user reviews the main flows. |

## Out of scope (explicitly)

- All view models, repositories, persistence, FSRS algorithm, AI providers,
  audio, kana data — untouched.
- Onboarding screens (`OnboardingTourView`, `AISetupView`, `NameEntryView`),
  loot reveal screens, level-up screen — kept on existing `IkeruCard` styling
  for this pass.
- Premium / Plan row — confirmed not in the app.
- The launch animation — not part of the Tatami direction.

## Testing plan

- `swift build` after each step (steps 1-10) — must succeed.
- `swift test` after each step — existing test suite must remain green.
- Manual visual diff on the simulator after each screen lands, comparing to
  the corresponding phone in `Ikeru Tatami Direction.html`.
- After step 10: install on the physical iPhone, **wait for user
  confirmation**, then run a MobAI session that walks through every flow
  (Home → start session → grade card → finish session → see summary →
  RPG profile → torii → study → companion → settings → back to home) and
  saves screenshots for side-by-side review.
