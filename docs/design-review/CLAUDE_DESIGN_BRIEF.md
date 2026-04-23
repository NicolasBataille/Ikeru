# Ikeru — Design Review Brief for Claude Design

## What is Ikeru?

Ikeru is a premium iOS app for learning Japanese. It uses spaced repetition (FSRS algorithm) with an RPG gamification layer — XP, levels, loot drops, equipped cosmetics. Built in SwiftUI, dark-mode only, targeting iPhone.

**Design philosophy**: Wabi-sabi — imperfect, weathered, quiet beauty. Negative space as a design element. Subtle warmth over saturated brightness. Movement through stillness — animations are calm and purposeful.

---

## Design System Tokens

### Colors (hex)
- **Background**: `#0A0A0F` (sumi/ink black)
- **Background elevated**: `#12121A`
- **Surface**: `#18181F` (raised)
- **Surface elevated**: `#1F1F28`
- **Primary accent**: `#D4A574` (warm gold / kintsugi)
- **Secondary accent**: `#E8B4B8` (sakura / powdered pink)
- **Tertiary accent**: `#7A8471` (matcha / sage green)
- **Success**: `#8FBCA0` (moss)
- **Warning**: `#E0A062` (amber)
- **Danger**: `#C97064` (terracotta)
- **Text primary**: `#F5F2EC` (washi paper — warm white, never pure)
- **Text secondary**: `#B8B5B0`
- **Text tertiary**: `#7A7770`

### Rarity colors (for RPG loot)
- Common: `#8A8780`
- Rare: `#6B92B5`
- Epic: `#9580B5`
- Legendary: `#D4A574`

### Typography
- System: SF Pro, SF Mono
- Kanji: NotoSerifJP-Bold / Medium
- Display sizes: 56 / 44 / 36
- Kanji hero: 96pt, display: 64pt
- Body: 15pt, caption: 12pt, micro: 11pt
- Tracking: display -1.2, heading -0.6, body -0.2, micro +0.8

### Spacing
- xs: 6, sm: 10, md: 16, lg: 24, xl: 36, xxl: 56

### Radius
- sm: 12, md: 18, lg: 24, xl: 32, full: 9999 (capsule)

### Surfaces
- Glass surfaces: white at 6% fill, 12% stroke, 18% highlight
- Cards: elevated shadow (black 45%, radius 24, y 8)
- Glow: gold 25%, radius 32 (for XP bar, loot)

### Animations
- Snappy spring: 0.28 response, 0.86 damping
- Smooth spring: 0.45 response, 0.92 damping
- Bouncy spring: 0.55 response, 0.72 damping

---

## Screen Inventory (14 screenshots attached)

### 01_home.png — Home screen
Greeting ("Good evening, Nico"), level pill top-right, hero card with level/proverb/XP bar, 3 stat cards (Due/Learned/Lootboxes), "Begin Session" primary CTA. Floating tab bar at bottom.

### 02_study.png — Study / Library tab
Card library browser. Not yet fully populated on fresh account.

### 03_conversation.png — Conversation tab
AI conversation companion for Japanese practice.

### 04_rpg_profile.png — RPG Profile (empty)
Level display, shield icon, XP bar, stat pills (reviews/items/attrs), skill profile with locked/unlocked attributes.

### 05-07_settings.png — Settings (3 parts)
Profile section, notifications, backup/export, AI providers, asset cache, attribution. Uses glass cards + section headers.

### 08_session_card_review.png — Card review (question)
Full-screen session. Progress bar + card count at top. Large kana character centered on glass card. "Show answer" primary button.

### 09_card_answer_revealed.png — Card review (answer)
Answer shown below the question. 4 grade buttons: Again (terracotta), Hard (amber), Good (gold), Easy (moss).

### 10-11_session_summary.png — Session complete
"Session Complete" hero with checkmark. Stats grid: new items, XP earned, level, duration. Loot earned callout. "Done" button.

### 12_home_post_session.png — Home after session
Same as 01 but with updated stats after a session.

### 13_rpg_profile_with_items.png — RPG Profile with progression
Shows 5 reviews, 5 items, 60/102 XP bar filled, 2 unlocked attributes (Reading, Writing), locked attributes at Lv.3/5/10/15.

### 14_rpg_inventory.png — Inventory with loot
"Treasures" section with rarity-grouped grid. Shows 5 "First Steps" (rare) badges with blue tint and leaf icon on glass tiles.

---

## What I want feedback on

1. **Overall visual coherence** — does the wabi-sabi/glass aesthetic hold together across all screens? Any screen that feels inconsistent?

2. **Home screen hierarchy** — the hero card dominates but the stat cards below feel small. Is the information architecture right?

3. **Card review experience** — the kana on the dark card feels isolated. Should there be more context, visual richness, or is the minimal approach correct for focus?

4. **RPG Profile** — the level display + XP bar + attributes list. Does the progression feel rewarding visually? The inventory grid (14_rpg_inventory) shows repeated "First Steps" badges — how to make a collection of cosmetics feel like a trophy cabinet rather than a dump?

5. **Session summary** — clean grid of stats. Too sparse? Should there be more celebration/animation guidance?

6. **Settings** — functional but long. Any structural improvements?

7. **Tab bar** — floating glass style at bottom. 5 tabs (Home, Study, Conversation, RPG, Settings). Too many? Icon clarity?

8. **Typography & spacing** — is the generous negative space working or does it feel empty on smaller screens?

9. **Color palette** — the gold/sakura/matcha trio. Does it feel premium or muddy?

10. **New feature coming**: a "hold-to-confirm" destructive action button (76pt capsule pill, danger fill sweeping left-to-right with progressive haptic). Does the concept fit the aesthetic?

---

## Constraints
- iOS only, iPhone, dark mode only
- No paid design tools (no Figma Pro)
- SwiftUI native — no web views
- Wabi-sabi philosophy must be preserved — no neon, no gamification theatre
