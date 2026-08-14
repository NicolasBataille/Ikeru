import SwiftUI
import Combine
import IkeruCore
import os

// MARK: - SettingsView
//
// Tatami-styled Preferences screen. Bilingual section headers (Japanese
// kanji + EN/FR chrome label), tatami rooms grouping rows, paper-ghost
// kanji + serif gold values + dim-gold chevrons, and a 1px hairline
// divider between rows. Every functional surface from earlier revisions
// is preserved — only the visual envelope changes.

struct SettingsView: View {

    // MARK: Environment

    @Environment(\.profileViewModel) private var profileViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.assetCache) private var assetCache
    @Environment(\.toastManager) private var toastManager
    @Environment(AppLocale.self) private var appLocale
    @Environment(\.displayMode) private var displayMode

    // MARK: Editing state

    @State private var editingName: String = ""
    @State private var isEditingName = false
    @FocusState private var isNameFieldFocused: Bool

    // MARK: Reminders

    @AppStorage("ikeru.reviewReminder.enabled") private var reviewReminderEnabled = false
    @AppStorage("ikeru.reviewReminder.hour") private var reviewReminderHour = 9
    @AppStorage("ikeru.weeklyCheckIn.enabled") private var weeklyCheckInEnabled = false
    @AppStorage("ikeru.weeklyCheckIn.day") private var weeklyCheckInDay = 1
    @AppStorage("ikeru.weeklyCheckIn.hour") private var weeklyCheckInHour = 10

    // MARK: Daily term

    @AppStorage(DailyTermSettings.enabledKey) private var dailyTermEnabled: Bool = false
    @AppStorage(DailyTermSettings.hourKey) private var dailyTermHour: Int = DailyTermSettings.defaultHour
    @AppStorage(DailyTermSettings.minuteKey) private var dailyTermMinute: Int = DailyTermSettings.defaultMinute

    // MARK: Backup

    @StateObject private var backupManager = CloudBackupManager()
    @State private var showRestoreConfirmation = false
    @State private var showExportShare = false
    @State private var exportURL: URL?

    // MARK: Cloud backup (Supabase, lot 4 — opt-in, user-facing; pull/merge
    // added in lot 2)
    //
    // `CloudSyncCoordinator` is IkeruCore's cloud backup (design spec
    // `docs/design-specs/2026-08-10-cloud-sync-design.md`, distinct from
    // the dormant CloudKit path above). Off by default — nothing leaves the
    // device until this toggle is turned on. This screen no longer
    // constructs its own coordinator: `CloudSyncTriggers.shared` (wired
    // from `IkeruApp` for the foreground/network-regain triggers) is the
    // ONE shared instance, and `cloudSyncCoordinatorInstance()` below just
    // asks it for that same instance — two independently-built coordinators
    // over the same `ModelContainer` used to be able to run overlapping
    // pulls and double-insert a `ReviewLog` (post-review fix; see
    // `CloudSyncTriggers.sharedCoordinator(modelContainer:)`).
    @AppStorage(CloudSyncPreferences.consentDefaultsKey) private var cloudSyncConsentEnabled = false
    @AppStorage(CloudSyncPreferences.lastSuccessDefaultsKey) private var cloudSyncLastSuccessEpoch: Double = 0
    @AppStorage(CloudSyncPreferences.lastAttemptDefaultsKey) private var cloudSyncLastAttemptEpoch: Double = 0
    /// Diagnostic message from the most recent failed attempt (see
    /// `SyncConsentStore.lastErrorMessage()`'s doc comment — not localized
    /// UI copy, never shown verbatim). Read here only to check for
    /// `CloudSyncCoordinator.pullFailureMessagePrefix`, which distinguishes
    /// "push succeeded, pull failed this cycle" from a full sync failure —
    /// see `cloudSyncStatusValue`.
    @AppStorage(CloudSyncPreferences.lastErrorDefaultsKey) private var cloudSyncLastError: String = ""
    @State private var isDeletingCloudData = false
    @State private var showDeleteCloudDataConfirmation = false

    // MARK: Profile management

    @State private var showNewProfile = false
    @State private var newProfileName = ""
    @State private var profileToDelete: UserProfile?

    // MARK: Cache & rig

    @State private var cacheStats: AssetCache.Stats?
    @State private var cacheQuotaMB: Double = 500
    @State private var showClearAllAlert = false
    @AppStorage(IkeruApp.preWarmEnabledKey) private var preWarmEnabled: Bool = true
    @AppStorage(IkeruApp.preWarmNotifyKey) private var preWarmNotify: Bool = false
    @State private var isPreWarming = false

    // MARK: Conversation

    @AppStorage("ikeru.furigana.enabled") private var furiganaEnabled = true
    @AppStorage("ikeru.furigana.userTouched") private var furiganaUserTouched = false

    // MARK: Audio autoplay (SRSCardView reads the same key)

    @AppStorage("ikeru.audio.autoplay") private var isAudioAutoplayEnabled = true

    // MARK: Language picker

    @State private var showingLanguagePicker = false

    // MARK: Computed

    private var isNameValid: Bool {
        !editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var iCloudStatusValue: LocalizedStringKey {
        if backupManager.isBackingUp || backupManager.isRestoring { return "Syncing" }
        if backupManager.lastBackupDate != nil { return "On" }
        return "Off"
    }

    /// Honest cloud-backup status ("never backed up / up to date / backup
    /// pending", never a bare error, never the word "sync"). Reads the same
    /// `UserDefaults` keys `CloudSyncCoordinator` writes on every attempt —
    /// `@AppStorage` re-renders this automatically even though the
    /// coordinator writes from a background actor, since both go through
    /// the same `UserDefaults.standard` keys declared in
    /// `CloudSyncPreferences`.
    ///
    /// A successful push with a FAILED pull this cycle is its own state
    /// (`pullFailedThisCycle` below), distinct from plain "up to date"
    /// (CRITICAL fix — this used to be indistinguishable: a broken pull
    /// left this row claiming everything was fine, indefinitely, because
    /// the coordinator wiped the error slot on every successful push
    /// regardless of the pull outcome). A pull that DID succeed but left
    /// some rows stuck or permanently abandoned (a poison row — see
    /// `SyncPullActor`'s poison-row policy) is a THIRD, calmer state
    /// (`pullDegradedThisCycle`) — the point E/F/G observability fix: this
    /// used to be computed and surfaced nowhere, so a table quietly stuck
    /// forever was invisible from Settings. The label stays deliberately
    /// calm in every case: the backup itself did succeed, so none of these
    /// must read as an error.
    private var cloudSyncStatusValue: LocalizedStringKey {
        guard cloudSyncConsentEnabled else { return "Off" }
        if cloudSyncLastSuccessEpoch > 0 {
            if pullFailedThisCycle { return "Backed up, will retry" }
            if pullDegradedThisCycle { return "Backed up, restore incomplete" }
            return "Up to date"
        }
        if cloudSyncLastAttemptEpoch > 0 { return "Backup pending" }
        return "Never backed up"
    }

    /// Whether the most recently recorded error is specifically a pull
    /// failure from an otherwise-successful sync cycle — see
    /// `CloudSyncCoordinator.pullFailureMessagePrefix`'s doc comment for why
    /// this is encoded as a prefix on the shared error string rather than a
    /// second `UserDefaults` key.
    private var pullFailedThisCycle: Bool {
        cloudSyncLastError.hasPrefix(CloudSyncCoordinator.pullFailureMessagePrefix)
    }

    /// Whether the most recently recorded error is specifically the
    /// "pull succeeded but left some rows stuck or permanently abandoned"
    /// state — see `CloudSyncCoordinator.pullDegradedMessagePrefix`'s doc
    /// comment. Mutually exclusive with `pullFailedThisCycle`: the
    /// coordinator only ever writes one prefix (or none) per cycle.
    private var pullDegradedThisCycle: Bool {
        cloudSyncLastError.hasPrefix(CloudSyncCoordinator.pullDegradedMessagePrefix)
    }

    /// Whether backup has been turned on at least once. Derived from
    /// existing state rather than a separate "ever enabled" flag: consent
    /// currently on, or a past attempt/success recorded, both only happen
    /// after the toggle was flipped on at some point. Gates the "delete my
    /// data from the server" row — before this is true there is nothing on
    /// the server to erase. All three signals get reset together on a
    /// successful deletion (`deleteCloudDataFromServer`), so this goes
    /// false again once the server side is actually empty.
    private var hasEverBackedUp: Bool {
        cloudSyncConsentEnabled || cloudSyncLastSuccessEpoch > 0 || cloudSyncLastAttemptEpoch > 0
    }

    /// Furigana's effective value — what conversations actually render, not
    /// necessarily what's stored. When the user has never touched the toggle,
    /// the effective value is derived from the display mode (ReadingAidResolver),
    /// not from `furiganaEnabled`. Settings must always show the effective
    /// value, or the row lies about what's on screen.
    private var effectiveFuriganaEnabled: Bool {
        ReadingAidResolver(
            mode: displayMode,
            userTouched: furiganaUserTouched,
            storedValue: furiganaEnabled
        ).effective
    }

    private var furiganaStatusValue: LocalizedStringKey {
        effectiveFuriganaEnabled ? "On" : "Off"
    }

    private var preWarmStatusValue: LocalizedStringKey {
        preWarmEnabled ? "On" : "Off"
    }

    private var appVersionValue: String {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "1.0"
        let build = (info?["CFBundleVersion"] as? String) ?? "1"
        return "\(version) (\(build))"
    }

    private var currentLanguageLabel: LocalizedStringKey {
        switch appLocale.preference {
        case .system:
            let lang = appLocale.currentLocale.language.languageCode?.identifier ?? "en"
            return lang == "fr" ? "Auto · Français" : "Auto · English"
        case .en: return "English"
        case .fr: return "Français"
        }
    }

    private var profileNameValue: String {
        profileViewModel?.displayName ?? ""
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            IkeruScreenBackground(variant: .auxiliary)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    practiceSection
                    displaySection
                    accountSection
                    aiSection
                    dataStorageLinkSection
                    aboutSection
                    #if IKERU_DEV_TOOLS
                    devToolsLinkSection
                    #endif
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 140) // clear of the floating tab bar
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingLanguagePicker) {
            LanguagePickerView()
                .presentationDetents([.medium])
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showExportShare, onDismiss: {
            if let url = exportURL {
                DataExportManager().cleanup(url: url)
                exportURL = nil
            }
        }) {
            if let url = exportURL {
                ShareLink(item: url)
            }
        }
        .sheet(item: $profileToDelete) { profile in
            DeleteProfileSheet(
                profile: profile,
                onConfirm: {
                    // Clear the sheet's item BEFORE deleting: `deleteProfile` posts
                    // notifications synchronously as part of the save, and if
                    // `profileToDelete` were still non-nil when those land, `.sheet(item:)`
                    // could re-invoke this closure and rebuild `DeleteProfileSheet` against
                    // a profile already deleted from the model context. DeleteProfileSheet
                    // also no longer reads `profile.displayName` live (see its `displayName`
                    // capture) as a second layer of defense for re-renders during the
                    // dismiss animation.
                    profileToDelete = nil
                    profileViewModel?.deleteProfile(profile)
                },
                onCancel: { profileToDelete = nil }
            )
        }
        .alert("New Profile", isPresented: $showNewProfile) {
            TextField("Name", text: $newProfileName)
            Button("Create") {
                let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    profileViewModel?.createProfile(name: name)
                    profileViewModel?.loadProfile()
                    newProfileName = ""
                }
            }
            Button("Cancel", role: .cancel) { newProfileName = "" }
        }
        .confirmationDialog(
            "Restore Backup?",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                Task { await backupManager.restore(modelContainer: modelContext.container) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace all current data with the backup. This cannot be undone.")
        }
        .alert("Clear cache?", isPresented: $showClearAllAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear all", role: .destructive) {
                assetCache?.clearAll()
                cacheStats = assetCache?.stats()
            }
        } message: {
            Text("Removes every cached audio file and image. Assets will be regenerated on next use.")
        }
        .alert("Delete data from server?", isPresented: $showDeleteCloudDataConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteCloudDataFromServer()
            }
        } message: {
            Text("Permanently deletes your backed-up progress — profiles, cards, review history, and vocabulary — from the server. This cannot be undone. Data on this device stays untouched.")
        }
        .task {
            if CloudBackupManager.iCloudEnabled {
                await backupManager.checkLastBackup()
            }
            cacheStats = assetCache?.stats()
            if let cache = assetCache {
                cacheQuotaMB = Double(cache.configuration.quotaBytes) / 1_048_576.0
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            BilingualLabel(japanese: "設定", chrome: "Settings")
            Text("Preferences", comment: "Settings heading")
                .ikeruScaledFont(28, weight: .light, design: .serif, relativeTo: .title)
                .foregroundStyle(Color.ikeruTextPrimary)
        }
    }

    // MARK: - Section: 稽古 / Practice

    private var practiceSection: some View {
        section(label: ("稽古", "Practice"), mon: .asanoha) {
            reminderToggleRow(
                jp: "通知",
                label: "Reminders",
                isOn: $reviewReminderEnabled,
                onToggleChange: { enabled in
                    updateReviewReminder(enabled: enabled)
                },
                trailing: {
                    if reviewReminderEnabled {
                        AnyView(
                            inlineHourPicker(
                                selected: $reviewReminderHour,
                                onChange: { newValue in
                                    Task {
                                        await NotificationManager.shared.scheduleReviewReminder(
                                            hour: newValue
                                        )
                                    }
                                }
                            )
                        )
                    } else {
                        AnyView(
                            Text("Off")
                                .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                                .foregroundStyle(TatamiTokens.paperGhost)
                        )
                    }
                }
            )
            reminderToggleRow(
                jp: "週次振り返り",
                label: "Weekly check-in",
                isOn: $weeklyCheckInEnabled,
                onToggleChange: { enabled in
                    updateWeeklyCheckIn(enabled: enabled)
                },
                trailing: {
                    if weeklyCheckInEnabled {
                        AnyView(
                            HStack(spacing: 8) {
                                inlineWeekdayPicker(
                                    selected: $weeklyCheckInDay,
                                    onChange: { newDay in
                                        Task {
                                            await NotificationManager.shared.scheduleWeeklyCheckIn(
                                                weekday: newDay,
                                                hour: weeklyCheckInHour
                                            )
                                        }
                                    }
                                )
                                inlineHourPicker(
                                    selected: $weeklyCheckInHour,
                                    onChange: { newValue in
                                        Task {
                                            await NotificationManager.shared.scheduleWeeklyCheckIn(
                                                weekday: weeklyCheckInDay,
                                                hour: newValue
                                            )
                                        }
                                    }
                                )
                            }
                        )
                    } else {
                        AnyView(
                            Text("Off")
                                .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                                .foregroundStyle(TatamiTokens.paperGhost)
                        )
                    }
                }
            )
            reminderToggleRow(
                jp: "今日の言葉",
                label: "Term of the day",
                isOn: $dailyTermEnabled,
                onToggleChange: { enabled in
                    updateDailyTermReminder(enabled: enabled)
                },
                trailing: {
                    if dailyTermEnabled {
                        AnyView(
                            Text(formattedTime(dailyTermHour, dailyTermMinute))
                                .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                                .foregroundStyle(Color.ikeruPrimaryAccent)
                        )
                    } else {
                        AnyView(
                            Text("Off")
                                .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                                .foregroundStyle(TatamiTokens.paperGhost)
                        )
                    }
                }
            )
            VStack(alignment: .leading, spacing: 4) {
                settingRow(
                    jp: "振り仮名",
                    label: "Furigana",
                    value: localizedString(furiganaStatusValue),
                    showChevron: false
                ) {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        // Tapping always fixes the setting explicitly — from
                        // here on the stored value is the effective value.
                        furiganaEnabled = !effectiveFuriganaEnabled
                        furiganaUserTouched = true
                    }
                }
                if !furiganaUserTouched {
                    Text("Follows display mode", comment: "Furigana subtitle shown only when the toggle above isn't user-set — its value follows the current display mode, not a stored preference.")
                        .ikeruScaledFont(11, relativeTo: .caption2)
                        .foregroundStyle(TatamiTokens.paperGhost)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }

            settingRow(
                jp: "自動再生",
                label: "Audio autoplay",
                value: isAudioAutoplayEnabled ? String(localized: "On") : String(localized: "Off"),
                showChevron: false
            ) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    isAudioAutoplayEnabled.toggle()
                }
            }

            retentionRow
        }
    }

    // MARK: Retention target (FSRS desiredRetention)

    private static let retentionOptions: [Double] = [0.80, 0.85, 0.90, 0.95]

    private var desiredRetentionValue: String {
        let retention = profileViewModel?.currentProfile?.settings.desiredRetention ?? 0.9
        return String(format: "%.0f%%", retention * 100)
    }

    private var retentionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                ForEach(Self.retentionOptions, id: \.self) { option in
                    Button(String(format: "%.0f%%", option * 100)) {
                        profileViewModel?.updateDesiredRetention(option)
                    }
                }
            } label: {
                rowChrome(
                    jp: "定着率",
                    label: "Retention target",
                    value: desiredRetentionValue,
                    showChevron: false
                )
            }
            .buttonStyle(.plain)
            Text("Higher means better recall, but more daily reviews", comment: "Retention target explainer")
                .ikeruScaledFont(11, relativeTo: .caption2)
                .foregroundStyle(TatamiTokens.paperGhost)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }

    // MARK: - Section: 表示 / Display

    @Environment(\.displayModeRepository) private var displayModeRepo

    /// `displayMode` (declared above, `@Environment(\.displayMode)`) is the
    /// single source of truth here — it is kept live by `MainTabView`, which
    /// re-reads the repository both on an explicit toggle (`repo.publisher`)
    /// *and* on a profile switch/create/delete (`.displayModeDidChange`,
    /// posted by `ProfileViewModel`). A previous revision mirrored
    /// `repo.publisher` into a local `@State` here instead; that mirror only
    /// caught the toggle case and went stale across a profile change inside
    /// this very screen (the Tatami-leak bug) — removed in favour of the
    /// environment value, which both call sites keep fresh.
    private var displaySection: some View {
        section(label: ("表示", "Display"), mon: .kikkou) {
            if let repo = displayModeRepo {
                DisplayModeToggleRow(repository: repo)
                TatamiEligibilityRow(
                    modelContainer: modelContext.container,
                    activeProfileID: { ActiveProfileResolver.activeProfileID() },
                    displayMode: displayMode
                )
            }
        }
    }

    // MARK: - Section: アカウント / Account

    private var accountSection: some View {
        section(label: ("アカウント", "Account"), mon: .genji) {
            settingRow(
                jp: "プロフィール",
                label: "Profile",
                value: profileNameValue,
                showChevron: false
            ) {
                editingName = profileNameValue
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    isEditingName = true
                }
                isNameFieldFocused = true
            }

            if isEditingName {
                inlineNameEditor
            }

            // Profile switcher (multi-profile support).
            if let profiles = profileViewModel?.allProfiles, profiles.count > 1 {
                ForEach(profiles, id: \.id) { profile in
                    profileSwitchRow(profile)
                }
            }

            settingRow(
                jp: "プロフィール追加",
                label: "Add profile",
                value: ""
            ) {
                showNewProfile = true
            }

            if CloudBackupManager.iCloudEnabled {
                settingRow(
                    jp: "バックアップ",
                    label: "iCloud sync",
                    value: localizedString(iCloudStatusValue)
                ) {
                    Task {
                        await backupManager.backup(modelContainer: modelContext.container)
                    }
                }

                settingRow(
                    jp: "復元",
                    label: "Restore from iCloud",
                    value: ""
                ) {
                    showRestoreConfirmation = true
                }
            }

            settingRow(
                jp: "書き出し",
                label: "Export data",
                value: ""
            ) {
                Task {
                    let manager = DataExportManager()
                    do {
                        let url = try await manager.exportData(modelContainer: modelContext.container)
                        exportURL = url
                        showExportShare = true
                    } catch {
                        Logger.ui.error("Data export failed: \(error.localizedDescription)")
                        toastManager.showError("Export failed: \(error.localizedDescription)")
                    }
                }
            }

            // Live for everyone as of lot 4 — no more `#if IKERU_DEV_TOOLS`
            // gate. That gate never actually protected TestFlight users
            // anyway: `IKERU_DEV_TOOLS` is active in Release too (see
            // CLAUDE.md), so it only hid the row from App Store review /
            // screenshots, not from real installs. `docs/privacy.html`
            // (section "Sauvegarde cloud (optionnelle)" / "Cloud backup
            // (optional)") and `PrivacyInfo.xcprivacy` were updated in this
            // same lot to describe exactly what this toggle sends.
            cloudBackupBlock

            // Plan / Premium row intentionally omitted — does not exist in the app.

            languageRow
        }
    }

    /// Toggle + inline honest status, an always-visible plain-language
    /// explainer, and — once backup has ever been turned on
    /// (`hasEverBackedUp`) — a destructive row to erase the server copy.
    /// This is a one-way backup with no restore path; the explainer says so
    /// in plain language rather than letting "cloud backup" imply more.
    private var cloudBackupBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            cloudSyncToggleRow
            // Status on its own full-width line rather than squeezed into the
            // row's trailing slot. That slot sits between two fixed-width
            // labels and the toggle, so there is almost no room left: French
            // statuses ("Jamais sauvegardé", and worse "Sauvegardé, nouvel
            // essai prévu") wrapped one character per line. Truncating them
            // instead would have been no better — the whole point of these
            // strings is to distinguish "backed up" from "backed up but the
            // restore side is failing", which a clipped string cannot do.
            if cloudSyncConsentEnabled {
                Text(cloudSyncStatusValue)
                    .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                    .padding(.horizontal, 16)
            }
            Text(
                "Backs up your progress to a server in Europe. No account is needed. Conversations with Sakura are not included. Restoring on a new device is not available yet.",
                comment: "Explanatory text shown under the cloud backup toggle in Settings, describing what the backup does and does not do"
            )
            .ikeruScaledFont(11, relativeTo: .caption2)
            .foregroundStyle(TatamiTokens.paperGhost)
            .padding(.horizontal, 16)
            .padding(.bottom, hasEverBackedUp ? 4 : 12)

            if hasEverBackedUp {
                deleteCloudDataRow
            }
        }
    }

    /// Just the toggle — cloud backup, lot 4. The status deliberately does
    /// NOT ride in this row's trailing slot (see `cloudBackupBlock`): its
    /// strings are full sentences, and this row has no width to spare.
    private var cloudSyncToggleRow: some View {
        reminderToggleRow(
            jp: "クラウド",
            label: "Cloud backup (beta)",
            isOn: $cloudSyncConsentEnabled,
            onToggleChange: { enabled in handleCloudSyncToggleChange(enabled) }
        ) {
            EmptyView()
        }
    }

    /// Destructive row, shown only once `hasEverBackedUp` is true — before
    /// that there is nothing on the server to erase and the row would be
    /// meaningless. Tapping only opens the confirmation alert; the actual
    /// deletion call is `deleteCloudDataFromServer()`, wired to that
    /// alert's destructive button below.
    private var deleteCloudDataRow: some View {
        Button {
            showDeleteCloudDataConfirmation = true
        } label: {
            HStack(spacing: 16) {
                Text("削除")
                    .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                    .foregroundStyle(TatamiTokens.paperGhost)
                Text("Delete my data from the server")
                    .ikeruScaledFont(13, relativeTo: .caption)
                    .foregroundStyle(Color.ikeruDanger)
                Spacer()
                if isDeletingCloudData {
                    ProgressView()
                        .tint(Color.ikeruDanger)
                } else {
                    Text("›")
                        .font(.system(size: 14))
                        .foregroundStyle(TatamiTokens.goldDim)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDeletingCloudData)
    }

    /// Returns the SAME `CloudSyncCoordinator` instance every other trigger
    /// site uses — `CloudSyncTriggers.shared.sharedCoordinator(modelContainer:)`,
    /// not a locally-built one. Building a second instance here used to let
    /// this toggle's push race a foreground/network-regain push from
    /// `CloudSyncTriggers`, with nothing but a non-atomic `UserDefaults`
    /// read-then-write between two different actors standing in for a real
    /// mutex — see that method's doc comment for the duplicate-`ReviewLog`
    /// failure mode this closes.
    private func cloudSyncCoordinatorInstance() -> CloudSyncCoordinator {
        CloudSyncTriggers.shared.sharedCoordinator(modelContainer: modelContext.container)
    }

    /// Turning ON records consent AND triggers the first push immediately
    /// (fire-and-forget background `Task` — no loading screen, per the
    /// design spec's local-first rule). Turning OFF only records consent
    /// (and resets pull cursors — see `CloudSyncCoordinator.setConsent`'s
    /// doc comment); no network call follows. This is only ONE of several
    /// call sites for `CloudSyncCoordinator.syncNow()` — `CloudSyncTriggers`
    /// also fires it on foreground and network-regain, which is exactly why
    /// this now shares that type's single coordinator instance instead of
    /// building its own (see `cloudSyncCoordinatorInstance()`).
    private func handleCloudSyncToggleChange(_ enabled: Bool) {
        let coordinator = cloudSyncCoordinatorInstance()
        Task {
            await coordinator.setConsent(enabled)
            if enabled {
                await coordinator.syncNow()
            }
        }
    }

    /// Erases the learner's data on the server (`CloudDataDeletionService`,
    /// built in `IkeruCore` for this same lot). On success, also turns
    /// backup off locally and zeroes the displayed timestamps — otherwise
    /// the app would keep trying to push to an identity that was just
    /// wiped server-side, and the status row would keep claiming "up to
    /// date" about data that no longer exists. On failure, nothing local
    /// changes: consent stays as it was, no timestamp is touched, and the
    /// toast names the failure instead of silently pretending it worked.
    private func deleteCloudDataFromServer() {
        isDeletingCloudData = true
        Task {
            do {
                try await CloudDataDeletionService(modelContainer: modelContext.container).deleteAllCloudData()
                isDeletingCloudData = false
                cloudSyncConsentEnabled = false
                cloudSyncLastSuccessEpoch = 0
                cloudSyncLastAttemptEpoch = 0
                // A stale "pull-failed"/"pull-degraded" error string must
                // not outlive an account wipe: `CloudDataDeletionService`
                // already resets the pull cursor and skip-tracker state —
                // but that's LOCAL `UserDefaults` bookkeeping, not
                // something that happens "server-side" (the server side of
                // this is just the deleted rows themselves) — and this
                // row's own status display has its own error slot that
                // must not keep pointing at a failure from an identity
                // that no longer exists.
                cloudSyncLastError = ""
                // The success path used to be entirely silent, which reads
                // as "nothing happened" for an action whose whole point is
                // that something irreversible did.
                toastManager.showInfo(
                    String(localized: "Your data has been deleted from the server")
                )
            } catch {
                isDeletingCloudData = false
                // The technical description goes to the log, not to the
                // learner: `CloudDeletionError` is not `LocalizedError`, so
                // `localizedDescription` renders as
                // "The operation couldn't be completed. (IkeruCore.CloudDeletionError error 1.)"
                // — noise that also leaks a type name into the UI. What the
                // learner needs is the one fact that changes their next
                // action: nothing was deleted, so try again.
                Logger.ui.error("Cloud data deletion failed: \(error.localizedDescription)")
                toastManager.showError(
                    String(localized: "Couldn't delete your data from the server. Nothing was deleted — check your connection and try again.")
                )
            }
        }
    }

    private var inlineNameEditor: some View {
        HStack(spacing: 12) {
            TextField("Your name", text: $editingName)
                .ikeruScaledFont(14, design: .serif, relativeTo: .body)
                .foregroundStyle(Color.ikeruTextPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.ikeruBackground.opacity(0.55))
                .sumiCorners(
                    color: Color.ikeruPrimaryAccent,
                    size: 6,
                    weight: 1.0,
                    inset: -1
                )
                .focused($isNameFieldFocused)
                .submitLabel(.done)
                .onSubmit { saveName() }

            Button {
                saveName()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.ikeruPrimaryAccent)
            }
            .disabled(!isNameValid)
            .opacity(isNameValid ? 1.0 : 0.4)

            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    isEditingName = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.ikeruTextTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TatamiTokens.goldDim.opacity(0.2))
                .frame(height: 1).padding(.horizontal, 16)
        }
    }

    /// One row per profile in the switcher list. Tapping the name/label area
    /// switches to that profile (no-op when it's already current); the trash
    /// icon opens `DeleteProfileSheet` for that profile — including the
    /// *active* one, which `ProfileViewModel.deleteProfile` handles by
    /// switching to whichever profile remains.
    ///
    /// This used to be a single row-wide `Button` with `.swipeActions` for
    /// delete. `.swipeActions` only does anything inside a `List` row — this
    /// screen builds its rows in a plain `VStack` inside a `ScrollView`, so
    /// the modifier was silently inert: no swipe gesture was ever attached,
    /// which is exactly the "no way to delete a profile" gap the review
    /// flagged. Replaced with an always-visible, always-functional icon
    /// button (two sibling tap targets, not nested — nesting a `Button`
    /// inside a `Button`'s label doesn't work in SwiftUI).
    @ViewBuilder
    private func profileSwitchRow(_ profile: UserProfile) -> some View {
        let isCurrent = profile.id == profileViewModel?.currentProfile?.id
        HStack(spacing: 12) {
            Button {
                guard !isCurrent else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    profileViewModel?.switchProfile(to: profile)
                }
            } label: {
                HStack(spacing: 16) {
                    Text("︙")
                        .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                        .foregroundStyle(TatamiTokens.paperGhost)
                    Text(profile.displayName)
                        .ikeruScaledFont(13, relativeTo: .caption)
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Spacer()
                    if isCurrent {
                        Text("Active", comment: "Active profile indicator")
                            .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(Color.ikeruPrimaryAccent)
                    } else {
                        Text("Switch", comment: "Switch profile action")
                            .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(Color.ikeruPrimaryAccent)
                        Text("›")
                            .font(.system(size: 14))
                            .foregroundStyle(TatamiTokens.goldDim)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isCurrent)

            Button {
                profileToDelete = profile
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.ikeruDanger)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Delete profile", comment: "Accessibility label for the per-profile delete icon button in Settings"))
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TatamiTokens.goldDim.opacity(0.2))
                .frame(height: 1).padding(.horizontal, 16)
        }
    }

    private var languageRow: some View {
        Button { showingLanguagePicker = true } label: {
            HStack(spacing: 16) {
                Text("言語")
                    .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                    .foregroundStyle(TatamiTokens.paperGhost)
                Text("Language", comment: "Settings row label")
                    .ikeruScaledFont(13, relativeTo: .caption)
                    .foregroundStyle(Color.ikeruTextPrimary)
                Spacer()
                Text(currentLanguageLabel)
                    .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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

    // MARK: - Section: 知能 / AI providers

    private var aiSection: some View {
        section(label: ("知能", "AI providers"), mon: .kikkou) {
            NavigationLink {
                AISettingsView()
            } label: {
                rowChrome(
                    jp: "プロバイダ",
                    label: "AI providers",
                    value: ""
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Section link: データ / Data & Storage (sub-page)

    private var dataStorageLinkSection: some View {
        section(label: ("データ", "Data & Storage"), mon: .maru) {
            NavigationLink {
                DataStorageSettingsView(
                    cacheStats: cacheStats,
                    cacheQuotaMB: cacheQuotaMB,
                    preWarmEnabled: $preWarmEnabled,
                    preWarmNotify: $preWarmNotify,
                    isPreWarming: $isPreWarming,
                    onClearCache: {
                        assetCache?.clearAll()
                        cacheStats = assetCache?.stats()
                    },
                    onPreWarmNow: runPreWarmNow,
                    makeRigClient: makeRigClient
                )
            } label: {
                rowChrome(
                    jp: "保管",
                    label: "Cache & pre-warm",
                    value: cacheUsageValue
                )
            }
            .buttonStyle(.plain)
        }
    }

    #if IKERU_DEV_TOOLS
    // MARK: - Section link: 開発 / Dev tools (sub-page)

    private var devToolsLinkSection: some View {
        section(label: ("開発", "Dev tools"), mon: .maru) {
            NavigationLink {
                DevToolsSettingsView()
            } label: {
                rowChrome(
                    jp: "開発",
                    label: "Developer tools",
                    value: ""
                )
            }
            .buttonStyle(.plain)
        }
    }
    #endif

    // MARK: - Cache usage (used by dataStorageLinkSection value display)

    private var cacheUsageValue: String {
        guard let stats = cacheStats else { return "" }
        let usedMB = Double(stats.totalBytes) / 1_048_576.0
        return String(format: "%.0f / %.0f MB", usedMB, cacheQuotaMB)
    }

    // MARK: - Section: 情報 / About

    private var aboutSection: some View {
        section(label: ("情報", "About"), mon: .maru) {
            settingRow(jp: "バージョン", label: "Version", value: appVersionValue)

            settingRow(jp: "案内", label: "Tour.Settings.Replay", value: "") {
                NotificationCenter.default.post(name: .replayFeatureTour, object: nil)
            }

            NavigationLink {
                AttributionView()
            } label: {
                rowChrome(
                    jp: "謝辞",
                    label: "Attribution",
                    value: ""
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private func saveName() {
        guard isNameValid else { return }
        Logger.ui.info("Updating display name from settings")
        profileViewModel?.updateDisplayName(editingName)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            isEditingName = false
        }
    }

    private func updateReviewReminder(enabled: Bool) {
        if enabled {
            Task {
                let authorized = await NotificationManager.shared.requestAuthorization()
                if authorized {
                    await NotificationManager.shared.scheduleReviewReminder(
                        hour: reviewReminderHour
                    )
                } else {
                    reviewReminderEnabled = false
                }
            }
        } else {
            NotificationManager.shared.cancelReviewReminders()
        }
    }

    private func updateDailyTermReminder(enabled: Bool) {
        if enabled {
            Task {
                let authorized = await NotificationManager.shared.requestAuthorization()
                if authorized {
                    await NotificationManager.shared.scheduleDailyTermReminder(
                        hour: dailyTermHour,
                        minute: dailyTermMinute
                    )
                } else {
                    dailyTermEnabled = false
                }
            }
        } else {
            NotificationManager.shared.cancelDailyTermReminder()
        }
    }

    private func formattedTime(_ hour: Int, _ minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    private func updateWeeklyCheckIn(enabled: Bool) {
        if enabled {
            Task {
                let authorized = await NotificationManager.shared.requestAuthorization()
                if authorized {
                    await NotificationManager.shared.scheduleWeeklyCheckIn(
                        weekday: weeklyCheckInDay,
                        hour: weeklyCheckInHour
                    )
                } else {
                    weeklyCheckInEnabled = false
                }
            }
        } else {
            NotificationManager.shared.cancelWeeklyCheckIn()
        }
    }

    private func makeRigClient() -> RigClient? {
        guard let settings = RigSettingsStore().load(), settings.isConfigured else {
            return nil
        }
        return RigClient(configuration: settings)
    }

    private func runPreWarmNow() {
        guard !isPreWarming else { return }
        guard let service = PreWarmFactory.make(
            modelContainer: modelContext.container,
            assetCache: assetCache
        ) else {
            toastManager.showError("Pre-warm unavailable: cache not ready")
            return
        }
        isPreWarming = true
        toastManager.showInfo("Pre-warming started")
        Logger.cache.info("Manual pre-warm triggered from Settings")
        Task { @MainActor in
            defer { isPreWarming = false }
            do {
                try await service.enqueueUpcomingDueAudio(window: 86_400)
                Logger.cache.info("Manual pre-warm done")
                toastManager.showInfo("Pre-warm queued")
                if preWarmNotify {
                    await PreWarmNotifier.notifyBatchFinished()
                }
            } catch is CancellationError {
                // Silently ignore cancellation.
            } catch {
                Logger.cache.warning("Manual pre-warm failed: \(error.localizedDescription)")
                toastManager.showError("Pre-warm failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Row primitives
//
// Extracted from the main `SettingsView` body to keep `type_body_length`
// under SwiftLint's threshold. `private` members declared here remain
// visible to `SettingsView`'s own body because Swift's access control for
// `private` is file-scoped, not declaration-scoped — any extension of the
// same type in the same file shares access (SE-0169).

extension SettingsView {

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

    /// Tappable row. Pass `action: nil` for an informational (read-only) row.
    @ViewBuilder
    private func settingRow(
        jp: String,
        label: LocalizedStringKey,
        value: String,
        showChevron: Bool = true,
        action: (() -> Void)? = nil
    ) -> some View {
        Button {
            action?()
        } label: {
            rowChrome(jp: jp, label: label, value: value, showChevron: showChevron)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    /// Settings row with a custom Tatami on/off toggle on the right and
    /// an optional inline trailing block (value-pickers shown only when
    /// enabled). Toggle is the source of truth for ON/OFF; tap on inner
    /// menu values opens their respective pickers without firing toggle.
    private func reminderToggleRow<Trailing: View>(
        jp: String,
        label: LocalizedStringKey,
        isOn: Binding<Bool>,
        onToggleChange: @escaping (Bool) -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            Text(jp)
                .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                .foregroundStyle(TatamiTokens.paperGhost)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(label)
                .ikeruScaledFont(13, relativeTo: .caption)
                .foregroundStyle(Color.ikeruTextPrimary)
                .lineLimit(1)
                .layoutPriority(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 4)
            if isOn.wrappedValue {
                trailing()
                    // Safety net: the two labels and the toggle are all
                    // fixed-width, so whatever little room is left here can
                    // collapse to a few points. Without this, a trailing
                    // string long enough (a French status, an hour with a
                    // long weekday) wraps one character per line instead of
                    // truncating — which is how it shipped and how it looked.
                    .lineLimit(1)
                    .padding(.trailing, 4)
            }
            TatamiToggle(isOn: isOn, onChange: onToggleChange)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TatamiTokens.goldDim.opacity(0.2))
                .frame(height: 1).padding(.horizontal, 16)
        }
    }

    /// Inline hour menu — gold value + small ▾ hint that the cell opens a
    /// list. Tap reveals a native menu of 24 hours.
    private func inlineHourPicker(
        selected: Binding<Int>,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        Menu {
            ForEach(0..<24, id: \.self) { h in
                Button(String(format: "%02d:00", h)) {
                    selected.wrappedValue = h
                    onChange(h)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(String(format: "%02d:00", selected.wrappedValue))
                    .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                Text("\u{25BE}") // ▾
                    .font(.system(size: 9))
                    .foregroundStyle(TatamiTokens.goldDim)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// Inline weekday menu (1=Sunday … 7=Saturday). Localized short names
    /// inline on the cell (Mon/Tue/… or Lun./Mar./…), full names inside
    /// the dropdown. Same ▾ list-hint as `inlineHourPicker`.
    private func inlineWeekdayPicker(
        selected: Binding<Int>,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        Menu {
            ForEach(1...7, id: \.self) { d in
                Button(weekdayName(d)) {
                    selected.wrappedValue = d
                    onChange(d)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(shortWeekdayName(selected.wrappedValue))
                    .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                Text("\u{25BE}") // ▾
                    .font(.system(size: 9))
                    .foregroundStyle(TatamiTokens.goldDim)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// Full localized weekday name (used inside the menu list, where space
    /// allows the longer form: "Monday", "lundi", …).
    private func weekdayName(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let symbols = formatter.weekdaySymbols ?? []
        let idx = max(1, min(7, weekday)) - 1
        return symbols[idx].capitalized
    }

    /// Short localized weekday name (e.g. "Mon", "Lun.").
    private func shortWeekdayName(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let symbols = formatter.shortWeekdaySymbols ?? []
        let idx = max(1, min(7, weekday)) - 1
        return symbols[idx].capitalized
    }

    /// Bilingual + serif gold value + dim-gold chevron + 1px hairline divider.
    @ViewBuilder
    private func rowChrome(
        jp: String,
        label: LocalizedStringKey,
        value: String,
        showChevron: Bool = true
    ) -> some View {
        HStack(spacing: 16) {
            Text(jp)
                .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                .foregroundStyle(TatamiTokens.paperGhost)
            Text(label)
                .ikeruScaledFont(13, relativeTo: .caption)
                .foregroundStyle(Color.ikeruTextPrimary)
            Spacer()
            if !value.isEmpty {
                Text(value)
                    .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
            }
            // Toggle-style rows (e.g. Furigana) show their On/Off value, not a
            // chevron — a chevron there falsely signals navigation.
            if showChevron {
                Text("›")
                    .font(.system(size: 14))
                    .foregroundStyle(TatamiTokens.goldDim)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TatamiTokens.goldDim.opacity(0.2))
                .frame(height: 1).padding(.horizontal, 16)
        }
    }

    /// Resolve a `LocalizedStringKey` to its current locale-rendered string.
    /// Used when we need the *value* slot to participate in localization but
    /// the row primitive expects a `String`.
    private func localizedString(_ key: LocalizedStringKey) -> String {
        // String(localized:) expects a String key; pull the literal out.
        let mirror = Mirror(reflecting: key)
        if let key = mirror.children.first(where: { $0.label == "key" })?.value as? String {
            return String(localized: String.LocalizationValue(key))
        }
        return ""
    }
}

// MARK: - Sub-page: Data & Storage Settings

private struct DataStorageSettingsView: View {

    let cacheStats: AssetCache.Stats?
    let cacheQuotaMB: Double
    @Binding var preWarmEnabled: Bool
    @Binding var preWarmNotify: Bool
    @Binding var isPreWarming: Bool
    let onClearCache: () -> Void
    let onPreWarmNow: () -> Void
    let makeRigClient: () -> RigClient?

    @State private var showClearAllAlert = false
    @Environment(\.toastManager) private var toastManager

    var body: some View {
        ZStack {
            IkeruScreenBackground(variant: .auxiliary)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        BilingualLabel(japanese: "データ", chrome: "Data & Storage")
                        Text("Cache & Pre-warm", comment: "Data & Storage subpage heading")
                            .ikeruScaledFont(28, weight: .light, design: .serif, relativeTo: .title)
                            .foregroundStyle(Color.ikeruTextPrimary)
                    }

                    storageContentSection
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 60)
            }
        }
        .navigationTitle("Data & Storage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .alert("Clear cache?", isPresented: $showClearAllAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear all", role: .destructive) {
                onClearCache()
            }
        } message: {
            Text("Removes every cached audio file and image. Assets will be regenerated on next use.")
        }
    }

    private var cacheUsageValue: String {
        guard let stats = cacheStats else { return "" }
        let usedMB = Double(stats.totalBytes) / 1_048_576.0
        return String(format: "%.0f / %.0f MB", usedMB, cacheQuotaMB)
    }

    private var preWarmStatusValue: LocalizedStringKey {
        preWarmEnabled ? "On" : "Off"
    }

    private var storageContentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            BilingualLabel(japanese: "データ", chrome: "Storage", mon: .maru)
            VStack(spacing: 0) {
                storageRow(
                    jp: "資産キャッシュ",
                    label: "Asset cache",
                    value: cacheUsageValue
                ) { showClearAllAlert = true }

                storageToggleRow(
                    jp: "予熱",
                    label: "Pre-warm audio",
                    value: preWarmEnabled ? String(localized: "On") : String(localized: "Off")
                ) {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        preWarmEnabled.toggle()
                    }
                }

                storageToggleRow(
                    jp: "予熱通知",
                    label: "Pre-warm notifications",
                    value: preWarmNotify ? String(localized: "On") : String(localized: "Off")
                ) {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        preWarmNotify.toggle()
                    }
                }

                storageRow(
                    jp: "今すぐ予熱",
                    label: "Pre-warm now",
                    value: isPreWarming ? String(localized: "Working") : ""
                ) { onPreWarmNow() }

                NavigationLink {
                    if let client = makeRigClient() {
                        RigJobsView(client: client)
                    } else {
                        Text("Configure rig first in AI Providers")
                            .font(.ikeruCaption)
                            .foregroundStyle(Color.ikeruTextSecondary)
                            .padding()
                    }
                } label: {
                    storageChrome(jp: "ジョブ", label: "Rig jobs", value: "")
                }
                .buttonStyle(.plain)
            }
            .tatamiRoom(.standard, padding: 0)
        }
    }

    @ViewBuilder
    private func storageRow(jp: String, label: LocalizedStringKey, value: String, action: (() -> Void)? = nil) -> some View {
        Button { action?() } label: {
            storageChrome(jp: jp, label: label, value: value)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    @ViewBuilder
    private func storageToggleRow(jp: String, label: LocalizedStringKey, value: String, action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            storageChrome(jp: jp, label: label, value: value)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func storageChrome(jp: String, label: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 16) {
            Text(jp)
                .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                .foregroundStyle(TatamiTokens.paperGhost)
            Text(label)
                .ikeruScaledFont(13, relativeTo: .caption)
                .foregroundStyle(Color.ikeruTextPrimary)
            Spacer()
            if !value.isEmpty {
                Text(value)
                    .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
}

// MARK: - Sub-page: Dev Tools Settings

#if IKERU_DEV_TOOLS
private struct DevToolsSettingsView: View {

    @Environment(\.profileViewModel) private var profileViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.assetCache) private var assetCache

    @State private var devSeedLevel: Double = 15
    @State private var devSeedDue: Double = 20
    @State private var devSeedMastered: Double = 120
    @State private var devShowResetConfirm = false
    @State private var devShowSeedConfirm = false
    @State private var devLastAction: String = ""

    var body: some View {
        ZStack {
            IkeruScreenBackground(variant: .auxiliary)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        BilingualLabel(japanese: "開発", chrome: "Dev tools")
                        Text("Developer Tools", comment: "Dev tools subpage heading")
                            .ikeruScaledFont(28, weight: .light, design: .serif, relativeTo: .title)
                            .foregroundStyle(Color.ikeruTextPrimary)
                    }

                    devSection
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 60)
            }
        }
        .navigationTitle("Dev tools")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .alert("Reset profile?", isPresented: $devShowResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Wipe", role: .destructive) {
                guard let vm = profileViewModel else { return }
                TestFixtures.wipeAll(context: modelContext, profileVM: vm)
                devLastAction = "✓ Profile wiped — relaunch to see onboarding"
            }
        } message: {
            Text("Deletes every profile, RPG state, card, vocab encounter. Onboarding triggers on next cold launch.")
        }
    }

    private var devSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            BilingualLabel(japanese: "開発", chrome: "Dev tools", mon: .maru)
            VStack(spacing: 0) {
                devSeedRow
                Rectangle().fill(TatamiTokens.goldDim.opacity(0.2)).frame(height: 1)
                devActionRow(jp: "削除", label: "Wipe profile",    value: "destructive") { devShowResetConfirm = true }
                devActionRow(jp: "昇段", label: "Force level-up",  value: "next") {
                    TestFixtures.grantLevelUp(context: modelContext)
                    devLastAction = "✓ XP bumped past next grade"
                }
                devActionRow(jp: "資産", label: "Clear asset cache", value: "purge") {
                    assetCache?.clearAll()
                    devLastAction = "✓ Asset cache cleared"
                }
                devActionRow(jp: "情報", label: "Build info",       value: devBuildInfo, action: nil)

                if !devLastAction.isEmpty {
                    Text(devLastAction)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.ikeruSuccess)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
            .tatamiRoom(.standard, padding: 0)
        }
    }

    @ViewBuilder
    private func devActionRow(jp: String, label: LocalizedStringKey, value: String, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            HStack(spacing: 16) {
                Text(jp)
                    .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                    .foregroundStyle(TatamiTokens.paperGhost)
                Text(label)
                    .ikeruScaledFont(13, relativeTo: .caption)
                    .foregroundStyle(Color.ikeruTextPrimary)
                Spacer()
                if !value.isEmpty {
                    Text(value)
                        .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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
        .disabled(action == nil)
    }

    private var devSeedRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Seed fixture profile")
                    .ikeruScaledFont(13, relativeTo: .caption)
                    .foregroundStyle(Color.ikeruTextPrimary)
                Spacer()
                Button {
                    devShowSeedConfirm = true
                } label: {
                    Text("Seed")
                        .ikeruScaledFont(12, weight: .semibold, relativeTo: .caption2)
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.ikeruPrimaryAccent.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                // Same destructive-confirmation motif as "Wipe profile"
                // (`devShowResetConfirm` above): this used to replace every
                // card, the RPG state, and the chat log for the current
                // profile with no confirmation — a real risk since
                // IKERU_DEV_TOOLS ships in Release/TestFlight builds.
                .alert("Reseed profile?", isPresented: $devShowSeedConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Seed", role: .destructive) {
                        guard let vm = profileViewModel else { return }
                        TestFixtures.wipeAndSeed(
                            context: modelContext,
                            profileVM: vm,
                            level: Int(devSeedLevel),
                            dueCount: Int(devSeedDue),
                            masteredCount: Int(devSeedMastered)
                        )
                        devLastAction = "✓ Seeded: lvl \(Int(devSeedLevel)), \(Int(devSeedDue)) due, \(Int(devSeedMastered)) mastered"
                    }
                } message: {
                    Text("Deletes every card, the RPG state, and the chat log for the current profile, then replaces them with fixture data.")
                }
            }

            devSlider(label: "Level",     value: $devSeedLevel,     range: 1...30,   step: 1)
            devSlider(label: "Due",       value: $devSeedDue,       range: 0...50,   step: 5)
            devSlider(label: "Mastered",  value: $devSeedMastered,  range: 0...200,  step: 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func devSlider(
        label: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(TatamiTokens.paperGhost)
                .frame(width: 70, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .tint(Color.ikeruPrimaryAccent)
            Text("\(Int(value.wrappedValue))")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.ikeruTextPrimary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private var devBuildInfo: String {
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let bid = bundle.bundleIdentifier ?? "?"
        return "\(version) (\(build)) · \(bid)"
    }
}
#endif

// MARK: - Preview

#Preview("SettingsView") {
    NavigationStack {
        SettingsView()
            .environment(AppLocale(preference: .system))
    }
    .preferredColorScheme(.dark)
}
