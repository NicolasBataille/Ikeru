# Ikeru — Remaining Work

All 10 epics are implemented (code written). This file tracks what's needed before release.

## 1. Build Verification

- [ ] Accept Xcode license: `sudo xcodebuild -license`
- [ ] Open project in Xcode and build iOS target (Ikeru scheme)
- [ ] Build watchOS target (IkeruWatch scheme)
- [ ] Build Widget target (IkeruWidget scheme)
- [ ] Fix any compilation errors surfaced by Xcode

## 2. Pre-existing Issues

- [ ] Fix `SkillBalance` naming conflict — two structs with same name in `IkeruCore/Sources/Services/ProgressService.swift` and `IkeruCore/Sources/Models/Session/SkillBalance.swift`. Rename one.
- [ ] FoundationModels provider has `@available` issues on macOS — only affects CLI builds, but should add proper `#if canImport` guards

## 3. SwiftData Migration

New fields added to existing `@Model` classes require migration or DB reset:

- `RPGState`: added `attributesData`, `lootInventoryData`, `lootBoxesData`, `totalSessionsCompleted`
- `ProfileSettings`: added `reviewReminderEnabled`, `reviewReminderHour`, `weeklyCheckInEnabled`, `weeklyCheckInDay`, `weeklyCheckInHour`

Options:
- Add a `VersionedSchema` + `SchemaMigrationPlan` for production
- Or delete app data on device/simulator for dev (simplest during development)

## 4. Integration Wiring

These services are implemented but not yet called from the app lifecycle:

- [ ] `LiveActivityManager` — needs to be instantiated in `SessionViewModel` and called on `startSession()` / `gradeAndAdvance()` / `endSession()`
- [ ] `WatchConnectivityManager.activate()` — needs to be called from `IkeruApp.init()` or `.task {}` with the modelContainer
- [ ] `NotificationManager` — settings UI is wired but initial notification scheduling on app launch (from saved preferences) is missing
- [ ] `ShortcutsManager` — `Notification.Name.startQuizFromShortcut` / `.startReviewFromShortcut` need observers in `IkeruApp` or `MainTabView` to trigger sessions

## 5. Tests

- [ ] Run all IkeruCore tests: `swift test` (requires fixing SkillBalance conflict first)
- [ ] Run IkeruTests via Xcode (requires simulator)
- [ ] Fix any failing tests
- [ ] New test files to verify:
  - `LootRarityTests`, `LootItemTests`, `RPGAttributeTests`
  - `RPGRewardServiceTests`, `LootDropServiceTests`, `LootBoxServiceTests`
  - `WatchSyncServiceTests`, `KanaDataTests`

## 6. Code Review

- [ ] Run code review agent on Epic 7 changes (RPG system)
- [ ] Run code review agent on Epic 8 changes (Watch)
- [ ] Run code review agent on Epic 9 changes (iOS integration)
- [ ] Run code review agent on Epic 10 changes (data management)
- [ ] Security review on `CloudBackupManager` (CloudKit data handling)
- [ ] Security review on `DataExportManager` (no PII leak in exports)

## 7. UI Polish & Testing

- [ ] Run all SwiftUI previews in Xcode to verify layouts
- [ ] Test RPGProfileView on device — verify attribute bars, inventory grid, lootbox cards
- [ ] Test LootDropView animation timing on device
- [ ] Test LootRevealView particle burst + haptic crescendo on device
- [ ] Test MeshHeroView MeshGradient animation (requires iOS 18+ simulator)
- [ ] Test Watch quiz on Apple Watch simulator — verify <200ms interaction target
- [ ] Test haptic pitch accent patterns on physical Watch
- [ ] Test Dynamic Island compact/expanded layouts
- [ ] Test StandBy widget flashcard cycling
- [ ] Test notification delivery and positive framing text
- [ ] Test iCloud backup/restore round-trip
- [ ] Test data export JSON/CSV validity
- [ ] Test multi-profile creation, switching, and deletion

## 8. Missing Assets

- [ ] No Xcode project file updates — new Swift files may need to be added to the Xcode project if `project.yml` / xcodegen isn't run automatically
- [ ] Run `xcodegen generate` if using XcodeGen to regenerate the .xcodeproj from project.yml
- [ ] Watch app may need an Asset Catalog for app icon
- [ ] Widget needs `NSSupportsLiveActivities = YES` in Info.plist
- [ ] App needs `com.apple.developer.usernotifications` entitlement for notifications

## 9. Git

- [ ] Commit all Epic 7-10 changes
- [ ] Consider splitting into per-epic commits for cleaner history
