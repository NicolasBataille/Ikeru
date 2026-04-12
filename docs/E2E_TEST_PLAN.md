# Ikeru — End-to-End Test Plan

> Exhaustive UI test plan covering every screen, every feature, every interaction.
> Each scenario is independent and can be executed in isolation.
> Status legend: ⬜ pending · 🟢 pass · 🟡 partial · 🔴 fail · 🚫 blocked

---

## How to apply these tests

> **Do not run tests blindly. Read this section before starting any suite.**

### Prerequisites

1. **Xcode 26.4** with iOS 26.4 + watchOS 26.4 SDKs installed (Settings → Components)
2. **Physical iPhone** paired with the Mac for haptic, audio, mic, and Live Activity tests — the simulator cannot validate these
3. **Apple Watch** (Series 8+) paired for Suite 11
4. **iCloud account** signed in on the device for Suite 7.D and Suite 15.6
5. **Test Apple Developer Team** (free Personal Team is enough) selected on the `Ikeru` and `IkeruWidget` targets

### Build & install

```bash
# Simulator (no signing)
xcodebuild -project Ikeru.xcodeproj \
  -scheme Ikeru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build

# Real device (signed) — use Xcode GUI Cmd+R after selecting your team
```

After the build, install on the booted simulator:

```bash
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Ikeru-*/Build/Products/Debug-iphonesimulator/Ikeru.app -maxdepth 0 | head -1)
xcrun simctl install booted "$APP_PATH"
```

### Launch arguments (development helpers)

The app supports launch arguments to bypass setup and reach any screen quickly:

| Argument | Effect |
|----------|--------|
| `-skipOnboarding` | Auto-creates a profile named "Nico" if none exists |
| `-startTab=N` | Pre-selects a tab on launch (0=Home, 1=Study, 2=Companion, 3=RPG, 4=Settings) |
| `-autoStartSession` | Immediately starts a session after the home view loads |
| `-mockProfile` | **DEBUG only.** Seeds a fixture profile with rich RPG state and a card deck. Combine with the scalar overrides below. No-op if a profile already exists. |
| `-mockLevel=N` | Sets RPG level to `N` (mid-bar XP within that level). Defaults to 5. |
| `-mockDue=N` | Creates `N` cards with `dueDate <= now`. Defaults to 12. |
| `-mockMastered=N` | Creates `N` cards with `interval=365` (mastered). Defaults to 40. |
| `-mockLootboxes=N` | Adds `N` unopened lootboxes to the inventory. Defaults to 1. |
| `-mockInventory=N` | Adds `N` rotating-rarity loot items to the inventory. Defaults to 4. |
| `-mockGreeting=morning\|afternoon\|evening\|night` | Overrides `HomeView.timeOfDayGreeting()` regardless of device time. |
| `-e2eMode` | Sets `AppEnvironment.isE2EMode = true`. Reserved for future deterministic-rendering opt-ins (mesh drift freeze, AI stubbing, RNG seeding). |

Examples:

```bash
# Land directly on the RPG tab with a default profile
xcrun simctl launch booted com.ikeru.app -skipOnboarding -startTab=3

# Skip onboarding and dive straight into a session
xcrun simctl launch booted com.ikeru.app -skipOnboarding -autoStartSession

# Seed a mid-level profile to validate ranks, palettes, stats, and lootboxes in one shot
xcrun simctl launch booted com.ikeru.app \
  -mockProfile -mockLevel=15 -mockDue=25 -mockMastered=120 \
  -mockLootboxes=3 -mockInventory=4 -mockGreeting=morning

# Validate Master rank + kintsugi palette
xcrun simctl launch booted com.ikeru.app -mockProfile -mockLevel=30 -mockMastered=2000
```

To add a new launch argument, edit `Ikeru/Support/AppEnvironment.swift` (parsing) and either
`Ikeru/Support/TestFixtures.swift` (data seeding), `Ikeru/App/IkeruApp.swift`
(`initializeProfileViewModel`), or `Ikeru/Views/MainTabView.swift` (the `selectedTab` initializer).

### Reset state between suites

```bash
# Wipe the app entirely (SwiftData store + Keychain + UserDefaults)
xcrun simctl uninstall booted com.ikeru.app

# Or reset the entire simulator
xcrun simctl erase booted
```

For real devices: delete the app from the Home Screen, then reinstall via Xcode.

### Capturing evidence

```bash
# PNG screenshot
xcrun simctl io booted screenshot /tmp/ikeru-suite-X-test-Y.png

# QuickTime screen recording (real device): cmd+R from QuickTime → New Movie Recording
# Simulator recording:
xcrun simctl io booted recordVideo --codec=hevc /tmp/ikeru-suite-X.mov
# Stop with Ctrl+C
```

Save artifacts in `tests/evidence/<date>/<suite>/<test-id>.png|.mov` and reference them in
test report PRs.

### Conventions

- **Device baseline:** iPhone 17 Pro running iOS 26.4 simulator. Also run a real-device pass for any test marked **(real device)**: anything haptic, audio, mic, Watch, Live Activity, Dynamic Island, StandBy, Spotlight, push notifications, iCloud, or biometric.
- **Fresh profile per suite:** uninstall + reinstall before each suite unless the suite explicitly depends on a prior one. Use `-skipOnboarding` to skip Suite 1 when re-running unrelated suites.
- **Run order:** Suites can be run in any order *except* Suite 0 must precede everything (smoke), and Suites 8 and 9 should run together (session → summary depends on state).
- **One scenario at a time:** never batch multiple scenarios in a single observation — one tester action, one verification, one capture.
- **Pass criteria:** a scenario passes only if every "Expected" bullet is met. Partial = 🟡, regression = 🔴.
- **Reproduction:** every 🔴 test must produce a minimal repro: device, OS, build hash, launch args, screenshot/video, and console log. File as a GitHub issue with the test ID in the title.
- **Status tracking:** maintain `tests/results/<build-hash>.md` mirroring this document with the current status. Don't edit this template — copy it.
- **Accessibility pass:** after a clean functional pass, run Suite 13 with VoiceOver, Dynamic Type at largest, Reduce Motion, and Reduce Transparency all enabled separately and together.
- **Localization pass:** Suite 14 should be run last because it requires switching device locale.
- **Dark mode only:** the app is dark-mode-first (no light mode currently); verify in dark only.
- **Network:** for each suite, run once on Wi-Fi and once in airplane mode unless a scenario explicitly requires connectivity. Offline failures must be graceful.
- **Performance budget:** every screen transition should feel <16ms (60fps). Use Instruments → Animation Hitches if a frame drop is suspected.
- **Time mocking:** for time-dependent tests (greetings, reminders, weekly check-in, DST), use `xcrun simctl status_bar booted override --time "HH:mm"` for visual mocks, and edit the device's date manually for logic.
- **Scope flags:** when a scenario references a backend or AI integration that hasn't shipped yet, mark as 🚫 with a reason — never silently skip.

### Reporting template

Each test result should include:

```markdown
### Suite X — Test X.Y
- **Status:** 🟢 / 🟡 / 🔴 / 🚫
- **Build:** <git short hash>
- **Device:** iPhone 17 Pro · iOS 26.4 · simulator
- **Launch args:** `-skipOnboarding -startTab=0`
- **Steps performed:** (verbatim from this document)
- **Observed:** (what actually happened)
- **Evidence:** ![screenshot](evidence/2026-04-06/suite-X/test-Y.png)
- **Notes:** (anything unusual)
- **Repro:** (only if failed) — minimal steps to reproduce
```

### When to update this document

- A new screen or feature ships → add a new suite section
- A scenario becomes obsolete → strike through, do not delete (preserve history)
- Coverage gaps found in a 🔴 → add the missing scenario(s) to the relevant suite
- Never edit a scenario after a 🟢 unless the underlying behavior has actually changed

---

## Suite 0 — Smoke / Bootstrap

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 0.1 | Cold launch from fresh install | Delete app, launch | Splash → onboarding NameEntryView appears under 2s |
| 0.2 | Cold launch with existing profile | Force-quit, relaunch | Skips onboarding, lands on HomeView |
| 0.3 | Background → foreground | Send to background 30s, resume | App restores to last screen with no state loss |
| 0.4 | Memory warning | Trigger via Debug menu | App survives, no crashes, state intact |
| 0.5 | Rotate device | Rotate landscape | UI remains in portrait (locked) per Info.plist |
| 0.6 | Low battery / power saving | Enable | Animations remain functional, no broken state |
| 0.7 | Offline launch | Airplane mode, launch | Full app available, AI features show offline indicator |
| 0.8 | First-launch permission prompts | Allow notifications + speech + mic | All grants persist and app continues |

---

## Suite 1 — Onboarding (NameEntryView + OnboardingTourView)

### 1.A NameEntryView

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 1.1 | Hero animations | Open name entry | Kanji 中 fades + slides up with spring; "YOUR JOURNEY BEGINS" eyebrow visible |
| 1.2 | Name field auto-focus | Wait 0.5s | Keyboard appears, cursor in field |
| 1.3 | Continue disabled when empty | Inspect button | Button at 0.45 opacity, scale 0.98 |
| 1.4 | Continue enables on input | Type "T" | Button springs to full opacity + scale 1.0 |
| 1.5 | Submit via keyboard return | Tap Continue on keyboard | Profile created, OnboardingTourView appears |
| 1.6 | Submit via button | Tap "Continue →" | Same as 1.5 |
| 1.7 | Whitespace-only name | Type "   ", check button | Button stays disabled |
| 1.8 | Long name (50+ chars) | Type long string | Field truncates gracefully, doesn't overflow |
| 1.9 | Special characters | Type "日本語 / Nico-san!" | Accepts and persists |
| 1.10 | Cancel/back gesture | Swipe down on sheet | Sheet stays (no dismissal — onboarding required) |

### 1.B OnboardingTourView

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 1.11 | Page 1 — 道 michi | Inspect | Gold gradient kanji, "Your Journey", subtitle, description |
| 1.12 | Page 2 — 友 tomo | Swipe left | Animates with spring, page indicator morphs |
| 1.13 | Page 3 — 始 hajime | Swipe again | "Start Learning" button appears |
| 1.14 | Page indicator | Inspect | Active dot expands to capsule shape with gold gradient |
| 1.15 | Backward swipe | From page 3, swipe right | Goes back to page 2 |
| 1.16 | Start Learning button | Tap on page 3 | Tour dismisses, lands on HomeView |
| 1.17 | Companion explanation | On page 2 | Mentions adaptive AI without overpromising |

---

## Suite 2 — Home tab (HomeView + MeshHeroView)

### 2.A Top bar

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 2.1 | Greeting time-of-day | Mock 5am, 1pm, 6pm, 11pm | Shows "Good morning/afternoon/evening/night" |
| 2.2 | Display name | After onboarding | Top bar shows entered name in DisplaySmall |
| 2.3 | Level pill | Inspect | Flame icon + "1 lvl" in glass capsule |
| 2.4 | High level pill | Mock level 99 | "99 lvl" still fits, glass renders correctly |

### 2.B Mesh hero panel

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 2.5 | Mesh animation | Watch for 8s | Slow drift, no flickering |
| 2.6 | Rank: Apprentice | Level 1-4 | Shows "Apprentice" |
| 2.7 | Rank: Student | Level 5-9 | Shows "Student" |
| 2.8 | Rank: Adept | Level 10-14 | Shows "Adept" |
| 2.9 | Rank: Practitioner | Level 15-19 | Shows "Practitioner" |
| 2.10 | Rank: Wayfarer | Level 20-24 | Shows "Wayfarer" |
| 2.11 | Rank: Sensei | Level 25-29 | Shows "Sensei" |
| 2.12 | Rank: Master | Level 30+ | Shows "Master" |
| 2.13 | Aphorism rotation | Different levels | 七転八起 / 一期一会 / etc. cycle stably |
| 2.14 | XP bar fill | Various XP | Gradient fill, gold glow shadow |
| 2.15 | XP bar at 0 | Fresh profile | Minimum 5% width visible |
| 2.16 | XP bar at 100% | Just before level up | Full width fill |
| 2.17 | Achievement chip | Mock recent achievement | Glass capsule with sparkles + text |
| 2.18 | No achievement | Fresh profile | Chip absent |
| 2.19 | Color palette levels 1-9 | Inspect | Twilight blue mesh |
| 2.20 | Color palette levels 10-19 | Inspect | Matcha green mesh |
| 2.21 | Color palette levels 20-29 | Inspect | Dusk gold mesh |
| 2.22 | Color palette level 30+ | Inspect | Kintsugi gold mesh |

### 2.C Stats row

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 2.23 | Due cards = 0 | Fresh profile | Shows "0" + "DUE" eyebrow |
| 2.24 | Due cards > 0 | Mock 25 due | Shows "25" with numericText transition |
| 2.25 | Learned count | Mock 150 learned | Shows "150" + "LEARNED" |
| 2.26 | Lootboxes | Mock 3 unopened | Shows "3" + "LOOTBOXES" |
| 2.27 | Tap interaction | Tap a stat card | Should react with scale (or be flat — verify intent) |
| 2.28 | Number animation | Change a stat | Smooth `numericText` transition |

### 2.D Primary action

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 2.29 | Begin Session button | Tap | Opens ActiveSessionView fullScreenCover |
| 2.30 | Session preview text | Inspect | "~N min · M reviews" or "Start a session..." |
| 2.31 | Haptic feedback | Tap with device | Medium impact felt |
| 2.32 | Button press scale | Touch down | Scales to 0.97, shadow shrinks |

### 2.E Quiet state

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 2.33 | All caught up pill | Due = 0 | "All caught up — enjoy the calm" with checkmark |
| 2.34 | Pill hidden when due > 0 | Mock 5 due | Pill not visible |

### 2.F Refresh

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 2.35 | Refresh on return | Switch tab → return | loadData() runs, stats update |
| 2.36 | Refresh after session | Complete session | Due count decreases, XP bar grows |

---

## Suite 3 — Custom tab bar (IkeruTabBar)

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 3.1 | Initial tab | Launch | Home highlighted by default with gold capsule indicator |
| 3.2 | Tap Study tab | Tap | Indicator morphs to 2nd position with spring; haptic selection |
| 3.3 | Tap Companion | Tap | Indicator morphs; companion icon highlighted |
| 3.4 | Tap RPG | Tap | Same |
| 3.5 | Tap Settings | Tap | Same |
| 3.6 | Rapid taps | Tap 5 tabs in 2s | No animation glitches, no crash |
| 3.7 | Tab content cross-fade | Switch tabs | Content scales/fades; spring animation, no flash |
| 3.8 | Glass background | Inspect | Ultra-thin material with edge highlight + border |
| 3.9 | Floating shadow | Inspect | Soft drop shadow under tab bar |
| 3.10 | Safe area respect | Phone with notch | Tab bar floats above home indicator |
| 3.11 | Keyboard interaction | Open name field in settings | Tab bar hides or stays based on `.ignoresSafeArea(.keyboard)` |
| 3.12 | Selected icon weight | Selected vs unselected | Selected uses semibold + filled symbol; unselected regular + outline |
| 3.13 | Re-tap selected tab | Tap home twice | Pops to root navigation if applicable |

---

## Suite 4 — Study tab (ProgressDashboardView)

### 4.A Top bar
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 4.1 | "YOUR PATH / Progress" header | Open tab | Eyebrow + display title visible |

### 4.B JLPT estimate card
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 4.2 | Fresh profile | Inspect | "N5" + "0% mastered" + "0/100 items" |
| 4.3 | Mid progress | Mock 50 cards mastered | Bar half full, percent updates |
| 4.4 | Beyond N1 | Mock 2000+ | Shows "N1" capped at 100% |
| 4.5 | Bar animation | Update value | Smooth spring transition |

### 4.C Skill balance radar
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 4.6 | Initial radar | Fresh profile | All 4 axes at 0%, polygon at center |
| 4.7 | Reading dominant | Mock 80% reading | Polygon expands toward Reading axis |
| 4.8 | All skills equal | Mock 50% all | Symmetric polygon |
| 4.9 | Color coding | Inspect | Reading blue, Writing matcha, Listening gold, Speaking terracotta |
| 4.10 | Touch interaction | Tap a corner | Highlights or shows tooltip (verify intent) |

### 4.D Forecast / Monthly snapshots
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 4.11 | 7-day forecast bars | Inspect | One bar per day with cards-due count |
| 4.12 | Monthly history | 6 months | Shows last 6 months mastered + accuracy |
| 4.13 | Empty months | Fresh profile | Bars at 0, no errors |

---

## Suite 5 — Companion tab (CompanionTabView + ConversationView)

### 5.A Empty state
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 5.1 | Meet Sakura header | First open | Header + chat icons + "Your Japanese conversation partner" + "Level: n5" |
| 5.2 | Suggested messages | Inspect | "こんにちは!", "今日は何をしましたか?", "Hello! I'm learning Japanese." as glass pills |
| 5.3 | Tap a suggestion | Tap one | Inserts text into input field or sends directly |

### 5.B Sending messages
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 5.4 | Type and send | "konnichiwa" + send | User bubble appears, AI loading indicator, then assistant bubble |
| 5.5 | Voice input | Tap mic, speak | Speech recognition transcribes, sends |
| 5.6 | Empty send blocked | Tap send empty | No message added |
| 5.7 | Long messages | Send 500 char | Wraps cleanly in bubble |
| 5.8 | Network failure | Airplane mode + send | Falls back to on-device or shows error |
| 5.9 | Rate limit | Send 10 fast | Graceful degradation |
| 5.10 | Inline kanji rendering | AI returns 漢字 | InlineKanjiView highlights kanji, tappable |
| 5.11 | Inline mnemonic | AI returns mnemonic block | InlineMnemonicView renders styled |
| 5.12 | Inline quiz | AI returns quiz | InlineQuizView shows interactive quiz |

### 5.C Companion floating avatar (CompanionAvatarView)
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 5.13 | Avatar visibility | On home tab | Avatar visible above tab bar |
| 5.14 | Avatar attention badge | Mock attention state | Pulsing badge appears |
| 5.15 | Tap avatar | Tap | Opens CompanionChatSheet (medium/large detents) |
| 5.16 | Sheet drag | Drag indicator | Resizes between detents |
| 5.17 | Avatar persists | Switch tabs | Avatar visible across all tabs (verify intent) |

### 5.D Leech intervention
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 5.18 | Leech detected | Fail same card 5x | Companion proactively offers help |
| 5.19 | Decline help | Dismiss intervention | Returns to session |

### 5.E Weekly check-in
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 5.20 | Weekly check-in trigger | Day-of-week match | Companion initiates check-in |
| 5.21 | Debate path | Disagree with planner | Companion adapts weights |
| 5.22 | Export insights | Tap "Export" | JSON file generated and shareable |

---

## Suite 6 — RPG tab (RPGProfileView)

### 6.A Hero panel
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 6.1 | "YOUR JOURNEY / RPG Profile" header | Open tab | Eyebrow + display title |
| 6.2 | Level + shield icon | Inspect | Big "1" with shield ornament |
| 6.3 | XP progress | Inspect | "Lv. 1 — 0/102 XP" with thin bar |
| 6.4 | Reviews counter | Inspect glass pill | "0 reviews" |
| 6.5 | Items counter | Inspect | "0 items" |
| 6.6 | Attrs counter | Inspect | "2 attrs" (initial Reading + Writing) |

### 6.B Attributes section
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 6.7 | Reading attribute | Inspect | Icon + "Reading" + "Kanji recognition..." description + bar |
| 6.8 | Writing attribute | Inspect | Same with pencil icon |
| 6.9 | Locked attributes | Inspect ??? rows | Greyed out, "Unlocks at Lv. N" |
| 6.10 | Unlock animation | Reach unlock level | Spring animation reveals new attribute |
| 6.11 | Bar fill | Mock progress | Bar fills proportionally |

### 6.C Inventory
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 6.12 | Empty inventory | Fresh profile | "No items yet" empty state |
| 6.13 | Add loot drops | Earn drops | Grid populates with rarity-tinted items |
| 6.14 | Tap item | Tap | Detail sheet with name + description |
| 6.15 | Rarity colors | Inspect | Common grey, rare blue, epic purple, legendary gold |

### 6.D Lootboxes
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 6.16 | No lootboxes | Empty | Hidden or "No challenges" |
| 6.17 | Earn lootbox | Complete 25 reviews | New lootbox card appears |
| 6.18 | Tap lootbox | Tap | LootBoxChallengeView opens |
| 6.19 | Challenge type kanji speed | Start | Quiz timer + 4 buttons |
| 6.20 | Correct answers | Answer 5/5 | LootBoxOpenView appears |
| 6.21 | Failed challenge | Run timer out | "Try again" appears |
| 6.22 | Retry challenge | Tap retry | Timer resets, new questions |
| 6.23 | Cancel single tap on retry | Multiple retries | No double timer (verified fix) |
| 6.24 | Open lootbox animation | Open | LootBoxOpenView particle burst |
| 6.25 | Reveal items | After open | LootRevealView shows each item with rarity glow |
| 6.26 | Empty items defensive | Force empty | Doesn't crash (uses placeholder) |
| 6.27 | Multi-item reveal | 3+ items | Sequential reveal with haptic crescendo |
| 6.28 | Save persistence | Open lootbox + force quit | Lootbox stays opened on relaunch |

### 6.E Level up
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 6.29 | LevelUpView trigger | Cross XP threshold | LevelUpView celebration appears |
| 6.30 | Animation | Watch | Number rolls, particles, haptic |
| 6.31 | Dismiss | Tap continue | Returns to previous screen |

### 6.F Loot drop
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 6.32 | LootDropView trigger | Earn drop in session | Banner slides in |
| 6.33 | Auto-dismiss | Wait 3s | Slides out |
| 6.34 | Manual dismiss | Tap | Slides out immediately |
| 6.35 | View leaves before complete | Navigate away | No crash from orphan asyncAfter (verified fix) |

### 6.G XP bar
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 6.36 | XPBarView in hero | Inspect | Animates fills smoothly |
| 6.37 | XPGainView on grade | Grade card | "+10 XP" floats up and fades |

---

## Suite 7 — Settings tab (SettingsView + sub-screens)

### 7.A Profile section
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 7.1 | Display name shown | Inspect | Eyebrow + name in body large |
| 7.2 | Edit name | Tap pencil | Field appears with current name pre-filled |
| 7.3 | Save valid name | Type + checkmark | Persists, top bar updates |
| 7.4 | Cancel edit | Tap X | Reverts to view mode |
| 7.5 | Empty name save blocked | Clear + checkmark | Disabled |

### 7.B Profile management
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 7.6 | Profile list | With multiple profiles | Each in glass row |
| 7.7 | Active marker | Inspect | "ACTIVE" eyebrow + checkmark |
| 7.8 | Switch profile | Tap inactive profile | Switches active, reloads data |
| 7.9 | Add profile | Tap "+ Add Profile" | Alert appears |
| 7.10 | Create profile | Type name + Create | New row appears |
| 7.11 | Delete profile | Long-press / swipe | Confirmation alert |
| 7.12 | Cannot delete last | Single profile | Delete disabled or warning |
| 7.13 | Cancel delete | Tap Cancel | No change |

### 7.C Notifications
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 7.14 | Daily Review Reminder toggle on | Toggle | Permission prompt → schedules notification |
| 7.15 | Daily reminder time picker | Tap row | Time picker appears, saves choice |
| 7.16 | Daily reminder fires | Mock time | Local notification delivered |
| 7.17 | Disable reminder | Toggle off | Pending notification removed |
| 7.18 | Weekly check-in toggle | Toggle on | Permission + day picker + hour picker |
| 7.19 | Weekly fires | Mock weekday/hour | Notification delivered |
| 7.20 | Permission denied | Deny iOS prompt | Toggle reverts off, no crash |

### 7.D Backup section
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 7.21 | Backup status row | Inspect | Last backup date or "Never" |
| 7.22 | Backup button | Tap | If iCloud configured: shows progress, success toast |
| 7.23 | Backup w/o iCloud entitlement | Tap on simulator | "iCloud Unavailable" error, no crash (verified fix) |
| 7.24 | Backup unauthenticated | Sign out iCloud | Error: not signed in |
| 7.25 | Restore | Tap | Confirmation alert (destructive) |
| 7.26 | Restore success | Confirm | Loading → cards/RPG state restored |
| 7.27 | Restore failure | Mock failure | Error toast, original data intact |
| 7.28 | Export data | Tap export | DataExportManager creates folder, share sheet |
| 7.29 | Export contents | Inspect | cards.json, rpg.json, context.json, cards.csv |
| 7.30 | Export cleanup | Dismiss share sheet | Tmp dir deleted |

### 7.E AI providers
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 7.31 | AISettingsView | Tap row | Sub-screen with on-device/Gemini/Claude/local GPU rows |
| 7.32 | Tier statuses | Inspect | Each shows availability |
| 7.33 | On-device only | Toggle others off | Router uses only on-device |
| 7.34 | API key entry | Tap Gemini → enter key | Saved to Keychain (verify in settings) |
| 7.35 | Invalid key | Enter garbage | Test fails gracefully |
| 7.36 | Test connection | Tap test | Sends test prompt, shows latency |

### 7.F Attribution
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 7.37 | Open AttributionView | Tap row | Lists data sources (KanjiVG, Tatoeba, KANJIDIC, JMdict) |
| 7.38 | Each source license | Tap | Description visible |

---

## Suite 8 — Active session (ActiveSessionView + ExerciseTransitionContainer)

### 8.A Session lifecycle
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 8.1 | Start session from home | Tap Begin Session | Full screen cover slides up |
| 8.2 | Initial state | Inspect | Progress bar 0%, first exercise rendered |
| 8.3 | Timer counts up | Watch | Elapsed time increases per second |
| 8.4 | Estimated remaining | Watch | Decrements |
| 8.5 | Pause session | Background app | Timer pauses |
| 8.6 | Resume | Foreground | Timer resumes |
| 8.7 | End early via gesture | Swipe down to dismiss | Confirmation: keep partial progress |
| 8.8 | Session complete | Finish all | Auto-routes to SessionSummaryView |
| 8.9 | Live Activity | Start session on real device | Dynamic Island shows progress |

### 8.B SRS card review (SRSCardView + GradeButtonsView)
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 8.10 | Card front | Inspect | Hiragana/kanji centered, large kanji typography |
| 8.11 | Tap to reveal | Tap card | Flips to back / shows reading + meaning |
| 8.12 | Grade Again | Tap | Card schedules sooner, advances |
| 8.13 | Grade Hard | Tap | Different interval |
| 8.14 | Grade Good | Tap | Standard FSRS interval |
| 8.15 | Grade Easy | Tap | Longer interval |
| 8.16 | Swipe gradation | Swipe left/right/up/down | Maps to grade direction |
| 8.17 | XP gain animation | After grade | XPGainView shows "+N XP" |
| 8.18 | Streak tracking | Multiple consecutive correct | Streak count rises |
| 8.19 | Level-up mid-session | Cross threshold | LevelUpView interrupts |
| 8.20 | Loot drop mid-session | RNG | LootDropView appears |
| 8.21 | Lootbox milestone | After 25 reviews | Lootbox earned, shown in summary |

### 8.C Kanji study (KanjiStudyView + sub-views)
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 8.22 | KanjiDisplayView | Inspect | Large kanji with serif font |
| 8.23 | RadicalDecompositionView | Tap radicals | Each radical shown with meaning |
| 8.24 | ReadingsView | Inspect | On'yomi + kun'yomi listed |
| 8.25 | VocabularyExamplesView | Inspect | Example words with kana + meaning |
| 8.26 | MnemonicView | Inspect | AI-generated mnemonic, refresh button |
| 8.27 | Mnemonic generation | Tap regenerate | Spinner → new mnemonic |
| 8.28 | Mnemonic cache | Re-open same kanji | Loads from cache instantly |

### 8.D Vocabulary study (VocabularyStudyView)
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 8.29 | Word display | Inspect | Word + reading + meaning + JLPT level |
| 8.30 | Tatoeba example | Inspect | Sentence with translation |
| 8.31 | WordDefinitionView | Tap word inline | Sheet with definition |

### 8.E Grammar (GrammarPointView + FillInBlankExerciseView)
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 8.32 | Grammar explanation | Inspect | Title + concise explanation + examples |
| 8.33 | Fill in blank | Inspect | Sentence with blank, particle options |
| 8.34 | Correct answer | Tap correct | Glow + advance |
| 8.35 | Wrong answer | Tap wrong | Shake + reveal correct |

### 8.F Reading (ReadingPassageView)
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 8.36 | Passage display | Inspect | Long-form Japanese text, tap-to-translate |
| 8.37 | Tap unknown word | Tap | WordDefinitionView sheet |
| 8.38 | Comprehension question | Inspect | Multiple choice |

### 8.G Writing (StrokeOrderExerciseView + HandwritingExerciseView + SentenceConstructionView)
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 8.39 | Stroke order animation | Watch | Strokes draw in sequence |
| 8.40 | StrokeTracingView | Trace strokes | Real-time accuracy feedback |
| 8.41 | Stroke too off | Wrong direction | Hint indicator |
| 8.42 | HandwritingCanvasView | Draw kanji | On-device recognition |
| 8.43 | Recognition accuracy | Draw clean kanji | Recognized correctly |
| 8.44 | Bad drawing | Scribble | Rejected, allow retry |
| 8.45 | SentenceConstructionView | Drag chunks to form sentence | Validates correctly |

### 8.H Listening (ListeningExerciseView + ListeningPassageView)
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 8.46 | Audio playback | Tap play | Audio plays via AudioService |
| 8.47 | PlaybackRateSelector | Switch 0.5x/0.75x/1.0x/1.25x | Rate changes apply |
| 8.48 | Replay | Tap replay | Restarts |
| 8.49 | Audio interruption | Receive call mid-playback | Pauses, resumes after (verified handler) |
| 8.50 | Silent mode | Mute device | App detects via VolumeDetector, skips audio |
| 8.51 | Listening passage | Long form audio | Plays with text follow-along |
| 8.52 | Comprehension question | After audio | Multiple choice |

### 8.I Speaking (ShadowingExerciseView + PitchAccentView)
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 8.53 | Shadowing prompt | Tap listen | Hears native speaker |
| 8.54 | Shadowing record | Tap record | Mic permission, records 5s |
| 8.55 | Diff highlighting | Inspect result | DiffHighlightView shows mismatches |
| 8.56 | Pronunciation score | Inspect | 0-100 score |
| 8.57 | PitchAccentView | Inspect | Pitch contour graph |
| 8.58 | Pitch attempt | Speak word | Records and compares to target |
| 8.59 | Per-pattern accuracy | Multiple attempts | Tracks heiban/atamadaka/nakadaka/odaka |

### 8.J Session transitions
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 8.60 | ExerciseTransitionContainer | Between exercises | Smooth crossfade with slight scale |
| 8.61 | Transition with new skill | Skill change | Brief eyebrow shows new skill |
| 8.62 | Skip transition | Tap | Goes immediately to next |

### 8.K Progress bar (SessionProgressBar)
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 8.63 | Segmented bar | Inspect | One segment per exercise |
| 8.64 | Current segment | Active | White-gold gradient |
| 8.65 | Completed segments | Past | Gold gradient |
| 8.66 | Pending segments | Future | White 8% opacity |
| 8.67 | Time labels | Inspect | "0:00" elapsed, "-2:30" remaining |
| 8.68 | Skill icons row | < 12 exercises | Icons under each segment |
| 8.69 | Compact mode | > 12 exercises | "3/15" count instead of icons |

---

## Suite 9 — Session summary (SessionSummaryView)

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 9.1 | Hero number | Inspect | Big card count |
| 9.2 | Accuracy % | Inspect | Percentage with bar |
| 9.3 | XP gained | Inspect | Total + breakdown |
| 9.4 | Time spent | Inspect | Duration |
| 9.5 | Cards by skill | Inspect | Reading/Writing/Listening/Speaking distribution |
| 9.6 | Earned rewards | Loot drops | Listed |
| 9.7 | Earned lootbox | Lootbox earned | Card showing it |
| 9.8 | Continue button | Tap | Returns to home |
| 9.9 | End session button | Tap | Same |
| 9.10 | Share summary | Tap share (if exists) | Activity sheet |

---

## Suite 10 — Adaptive planner (PlannerService end-to-end)

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 10.1 | Empty deck | Fresh profile | Seeds beginner kana |
| 10.2 | Time-aware composition | 5 vs 30 min preference | Different exercise counts |
| 10.3 | Silent mode adaptation | VolumeDetector reports muted | No listening/speaking exercises |
| 10.4 | Skill balance enforcement | Heavy reading bias | Planner injects writing/listening |
| 10.5 | Difficulty progression | Beginner | Mostly new + easy reviews |
| 10.6 | Plateau detection | Many lapses | Eases up, more review |
| 10.7 | Performance budget | 500-card deck | Composes < 1000ms |
| 10.8 | Idempotency | Same state twice | Same composition |

---

## Suite 11 — Apple Watch (IkeruWatch)

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 11.1 | Watch app installs | Pair watch, install | App icon visible on watch |
| 11.2 | Kana quiz launch | Open watch app | Quiz appears |
| 11.3 | 4-choice answer | Tap correct | Haptic + advance |
| 11.4 | Wrong answer | Tap wrong | Haptic warning |
| 11.5 | Audio drill | Hear audio | Plays via watch speaker |
| 11.6 | Pitch accent haptics | Multi-mora word | Distinct haptic pattern per mora |
| 11.7 | Complications | Add to watch face | Shows level + due count |
| 11.8 | Connectivity sync | Earn XP on watch | iPhone receives via WatchConnectivity |
| 11.9 | Offline session | No iPhone reachable | Queues for sync |
| 11.10 | Sync after reconnect | Reconnect | Queue uploads |
| 11.11 | Watch session result wired | Complete watch quiz | iPhone XP increases (verified fix) |
| 11.12 | Conflict resolution | Edit on both devices | Last-write-wins per SyncConflictResolver |

---

## Suite 12 — System integration

### 12.A Live Activities (SessionLiveActivity)
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 12.1 | Activity starts | Begin session | Dynamic Island shows session widget |
| 12.2 | Update on grade | Grade card | Counts update in island |
| 12.3 | Activity ends on completion | Finish session | Activity dismisses with summary |
| 12.4 | End on early exit | Quit session | Activity dismisses |
| 12.5 | Lock screen widget | Lock device mid-session | Widget on lock screen |

### 12.B StandBy widget (StandByFlashcardWidget)
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 12.6 | Widget gallery | Add widget | Available in small/medium/large |
| 12.7 | StandBy mode | Enable StandBy | Cycles flashcards |
| 12.8 | Tap widget | Tap | Opens app |

### 12.C Siri shortcuts
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 12.9 | "Quiz me in Ikeru" | Say to Siri | Launches app, starts quiz |
| 12.10 | "Review Japanese in Ikeru" | Say | Launches review |
| 12.11 | Spotlight suggestion | Search "Ikeru" | App + shortcut suggestions |

### 12.D Push notifications
| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 12.12 | Daily reminder fires | At scheduled hour | Notification with calm copy |
| 12.13 | Tap reminder | Tap | Opens to home / starts session |
| 12.14 | Weekly check-in fires | At scheduled day/hour | Notification |
| 12.15 | Tap weekly | Tap | Opens companion check-in |
| 12.16 | Notifications disabled | Disable in iOS settings | Reschedule fails gracefully |

---

## Suite 13 — Accessibility

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 13.1 | VoiceOver — home | Enable, swipe | Every element labeled, in logical order |
| 13.2 | VoiceOver — session | Read flashcard | Announces front, back, grade options |
| 13.3 | VoiceOver — tab bar | Swipe tabs | Each tab labeled with selected state |
| 13.4 | Dynamic Type — XL | Set largest | All text scales without overflow |
| 13.5 | Reduce motion | Enable | Spring animations replaced with crossfades |
| 13.6 | Reduce transparency | Enable | Glass surfaces use solid fallback |
| 13.7 | Bold text | Enable | All system text bolds |
| 13.8 | Color contrast | Inspect | Text on glass meets WCAG AA |
| 13.9 | Switch Control | Enable | Navigable |
| 13.10 | Haptic strength | Reduce | Still feedback but less aggressive |

---

## Suite 14 — Localization

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 14.1 | English | Default | All copy in English |
| 14.2 | Japanese system locale | Switch | UI mixes English chrome + Japanese learning content |
| 14.3 | French system locale | Switch | Time-of-day greeting falls back, no broken strings |
| 14.4 | RTL pseudo-language | Set | Layout still readable (verify intent) |
| 14.5 | Date formats | Different locales | Forecast labels match locale |

---

## Suite 15 — Data integrity

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 15.1 | SwiftData migration | Update schema | App migrates without data loss |
| 15.2 | Schema rollback | Downgrade | App refuses or migrates back |
| 15.3 | Concurrent writes | Two views write same model | No corruption |
| 15.4 | Force-quit during session | Kill mid-grade | Last grade persists or reverts cleanly |
| 15.5 | Export round-trip | Export → wipe → import | Data restored exactly |
| 15.6 | iCloud round-trip | Backup → wipe → restore | Data restored exactly (with cards/reviews) |
| 15.7 | Profile isolation | Two profiles | Cards/RPG don't leak across |
| 15.8 | Mnemonic cache invalidation | Update kanji | Cache invalidates correctly |
| 15.9 | Companion chat history | Many messages | Pagination, no UI freeze |

---

## Suite 16 — Performance & memory

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 16.1 | App launch < 2s | Cold start | Time-to-interactive |
| 16.2 | Tab switch < 16ms | Instruments | No dropped frames |
| 16.3 | Session compose < 1000ms | 500 cards | Within budget |
| 16.4 | Card transition < 100ms | Grade card | Within FSRS NFR |
| 16.5 | Mesh gradient FPS | Watch hero 30s | 60fps sustained |
| 16.6 | Memory baseline | Idle home | < 100 MB |
| 16.7 | Memory after session | 50-card session | No leaks (verify Instruments) |
| 16.8 | Energy consumption | 30 min usage | Energy log in normal range |

---

## Suite 17 — Visual regression

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 17.1 | Snapshot — home idle | iPhone 17 Pro | Matches reference image |
| 17.2 | Snapshot — home with achievement | Mock | Matches |
| 17.3 | Snapshot — study tab | | Matches |
| 17.4 | Snapshot — companion | | Matches |
| 17.5 | Snapshot — RPG | | Matches |
| 17.6 | Snapshot — settings | | Matches |
| 17.7 | Snapshot — onboarding (each page) | | Matches |
| 17.8 | Snapshot — session card | | Matches |
| 17.9 | Snapshot — session summary | | Matches |
| 17.10 | Snapshot — lootbox open | | Matches |
| 17.11 | Snapshot — level up | | Matches |
| 17.12 | Snapshot — companion chat with messages | | Matches |
| 17.13 | Snapshot — settings expanded sections | | Matches |
| 17.14 | iPhone SE size class | Small device | Layout doesn't break |
| 17.15 | iPhone 17 Pro Max | Large device | Layout doesn't break |
| 17.16 | iPad (Designed for iPad) | iPad simulator | Renders correctly |

---

## Suite 18 — Edge cases & error states

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 18.1 | First launch with no permissions | Deny everything | App still functional |
| 18.2 | Disk full | Mock | Graceful error, no crash |
| 18.3 | iCloud full | Mock | Backup error, no crash |
| 18.4 | Corrupted SwiftData | Manually corrupt | Recovery prompt or fresh start |
| 18.5 | Empty card pool | No cards | Empty state across home/session |
| 18.6 | All cards burned | All mastered | Graduate state shown |
| 18.7 | Network timeout | Slow network | Fallback to next AI tier or on-device |
| 18.8 | All AI tiers fail | Mock all fail | "AI temporarily unavailable" |
| 18.9 | Companion offline | No network | On-device only mode indicator |
| 18.10 | Time zone change | Travel | Reminders re-anchor |
| 18.11 | DST change | Transition | Reminders fire at correct local time |
| 18.12 | System time skew | Set device clock back | FSRS doesn't break |
| 18.13 | Locale change mid-session | Switch | Session continues, UI re-localizes on restart |
| 18.14 | Low storage warning | Mock | Backup feature warns |

---

## Suite 19 — Security & privacy

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 19.1 | API keys in Keychain | Add Gemini key | Verify in Keychain Access, not UserDefaults |
| 19.2 | App backgrounds with sensitive screen | Background mid-edit | Snapshot doesn't reveal name field content (use redaction if needed) |
| 19.3 | Pasteboard not used for secrets | Use api key entry | No unintended pasteboard write |
| 19.4 | Export contents PII review | Inspect cards.json | No emails, no device identifiers |
| 19.5 | Backup contents PII review | Inspect snapshot | Uses device.model, not device.name (verified fix) |
| 19.6 | Crash logs scrubbed | Force crash | Crashlytics/OSLog don't contain user content |
| 19.7 | Speech recognition on-device | Test offline | Recognizes Japanese without network |
| 19.8 | Mnemonic generation prompt | Inspect | Doesn't include other user info |

---

## Suite 20 — Companion intelligence quality (pass/fail by judgment)

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 20.1 | Companion responds in Japanese | Send Japanese | Stays in Japanese at JLPT level |
| 20.2 | Level escalation | User uses higher-level grammar | Companion adapts up |
| 20.3 | Level de-escalation | User struggles | Companion simplifies |
| 20.4 | Companion remembers context | Multi-turn | Refers back to previous turns |
| 20.5 | Inappropriate content | Send harmful prompt | Refuses politely |
| 20.6 | Off-topic | Send unrelated question | Steers back to learning |
| 20.7 | Mistake celebration | Get something right after struggling | Notices + celebrates |
| 20.8 | Encouragement during failure | Multiple failures | Empathetic, not condescending |

---

## Test infrastructure tasks

- [ ] Create XCUITest target if not present (currently only IkeruTests unit suite)
- [ ] Add launch arguments framework: `-skipOnboarding`, `-startTab=N`, `-autoStartSession`, `-mockProfile=name`, `-mockLevel=N`, `-mockCards=N`
- [ ] Build a `TestDataSeeder` accessible from launch args to populate any state
- [ ] Add SwiftSnapshotTesting for visual regression suite (Suite 17)
- [ ] Set up CI pipeline: build → unit tests → snapshot tests → critical XCUITest path
- [ ] Document mock CloudKit recording for backup/restore tests
- [ ] Add accessibility audit script to fail CI if elements lack labels
- [ ] Configure Maestro or similar for cross-platform smoke flows on real devices

## Critical path (first tests to automate)

1. 0.1, 0.2 — launch & profile detection
2. 1.5, 1.16 — onboarding completion
3. 2.29, 8.1, 8.8, 9.8 — full session loop
4. 3.1–3.5 — tab navigation
5. 7.6, 7.8, 7.10 — multi-profile basics
6. 15.5, 15.6 — data export & restore round trip
7. 18.7, 18.8 — AI fallback resilience

These cover the spine of the app — if these break, nothing else matters.
