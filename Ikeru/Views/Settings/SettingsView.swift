import SwiftUI
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

    // MARK: Editing state

    @State private var editingName: String = ""
    @State private var isEditingName = false
    @FocusState private var isNameFieldFocused: Bool

    // MARK: Reminders

    @State private var reviewReminderEnabled = false
    @State private var reviewReminderHour = 9
    @State private var weeklyCheckInEnabled = false
    @State private var weeklyCheckInDay = 1
    @State private var weeklyCheckInHour = 10

    // MARK: Backup

    @StateObject private var backupManager = CloudBackupManager()
    @State private var showRestoreConfirmation = false
    @State private var showExportShare = false
    @State private var exportURL: URL?

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

    private var furiganaStatusValue: LocalizedStringKey {
        furiganaEnabled ? "On" : "Off"
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
                    memorySection
                    accountSection
                    aiSection
                    storageSection
                    aboutSection
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
                    profileViewModel?.deleteProfile(profile)
                    profileToDelete = nil
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
        .task {
            await backupManager.checkLastBackup()
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
                .font(.system(size: 28, weight: .light, design: .serif))
                .foregroundStyle(Color.ikeruTextPrimary)
        }
    }

    // MARK: - Section: 稽古 / Practice

    private var practiceSection: some View {
        section(label: ("稽古", "Practice"), mon: .asanoha) {
            settingRow(
                jp: "一日の目標",
                label: "Daily goal",
                value: "12 cards"
            )
            settingRow(
                jp: "通知",
                label: "Reminders",
                value: reviewReminderEnabled
                    ? "\(reviewReminderHour):00"
                    : String(localized: "Off")
            ) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    reviewReminderEnabled.toggle()
                }
                updateReviewReminder(enabled: reviewReminderEnabled)
            }
            settingRow(
                jp: "週次振り返り",
                label: "Weekly check-in",
                value: weeklyCheckInEnabled
                    ? "\(weeklyCheckInHour):00"
                    : String(localized: "Off")
            ) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    weeklyCheckInEnabled.toggle()
                }
                updateWeeklyCheckIn(enabled: weeklyCheckInEnabled)
            }
            settingRow(
                jp: "音声",
                label: "Sound",
                value: String(localized: "On")
            )
            settingRow(
                jp: "振り仮名",
                label: "Furigana",
                value: localizedString(furiganaStatusValue)
            ) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    furiganaEnabled.toggle()
                }
            }
        }
    }

    // MARK: - Section: 記憶 / Memory algorithm

    private var memorySection: some View {
        section(label: ("記憶", "Memory algorithm"), mon: .kikkou) {
            settingRow(jp: "FSRSパラメータ", label: "FSRS parameters", value: "Optimized")
            settingRow(jp: "保持率",         label: "Target retention", value: "90%")
            settingRow(jp: "最大間隔",       label: "Maximum interval", value: "36500d")
        }
    }

    // MARK: - Section: 勘定 / Account

    private var accountSection: some View {
        section(label: ("勘定", "Account"), mon: .genji) {
            settingRow(
                jp: "プロフィール",
                label: "Profile",
                value: profileNameValue
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

            settingRow(
                jp: "書き出し",
                label: "Export data",
                value: ""
            ) {
                Task {
                    let manager = DataExportManager()
                    if let url = try? await manager.exportData(modelContainer: modelContext.container) {
                        exportURL = url
                        showExportShare = true
                    }
                }
            }

            // Plan / Premium row intentionally omitted — does not exist in the app.

            languageRow
        }
    }

    private var inlineNameEditor: some View {
        HStack(spacing: 12) {
            TextField("Your name", text: $editingName)
                .font(.system(size: 14, design: .serif))
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

    @ViewBuilder
    private func profileSwitchRow(_ profile: UserProfile) -> some View {
        let isCurrent = profile.id == profileViewModel?.currentProfile?.id
        Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                profileViewModel?.switchProfile(to: profile)
            }
        } label: {
            HStack(spacing: 16) {
                Text("︙")
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(TatamiTokens.paperGhost)
                Text(profile.displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ikeruTextPrimary)
                Spacer()
                if isCurrent {
                    Text("Active", comment: "Active profile indicator")
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                } else {
                    Text("Switch", comment: "Switch profile action")
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(Color.ikeruPrimaryAccent)
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
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            if !isCurrent {
                Button(role: .destructive) {
                    profileToDelete = profile
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
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

    // MARK: - Section: 倉庫 / Storage (asset cache + local rig)

    private var storageSection: some View {
        section(label: ("倉庫", "Storage"), mon: .maru) {
            settingRow(
                jp: "資産キャッシュ",
                label: "Asset cache",
                value: cacheUsageValue
            ) {
                showClearAllAlert = true
            }

            settingRow(
                jp: "予熱",
                label: "Pre-warm audio",
                value: localizedString(preWarmStatusValue)
            ) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    preWarmEnabled.toggle()
                }
            }

            settingRow(
                jp: "予熱通知",
                label: "Pre-warm notifications",
                value: preWarmNotify ? String(localized: "On") : String(localized: "Off")
            ) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    preWarmNotify.toggle()
                }
            }

            settingRow(
                jp: "今すぐ予熱",
                label: "Pre-warm now",
                value: isPreWarming ? String(localized: "Working") : ""
            ) {
                runPreWarmNow()
            }

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
                rowChrome(
                    jp: "ジョブ",
                    label: "Rig jobs",
                    value: ""
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var cacheUsageValue: String {
        guard let stats = cacheStats else { return "" }
        let usedMB = Double(stats.totalBytes) / 1_048_576.0
        return String(format: "%.0f / %.0f MB", usedMB, cacheQuotaMB)
    }

    // MARK: - Section: 関連 / About

    private var aboutSection: some View {
        section(label: ("関連", "About"), mon: .maru) {
            settingRow(jp: "バージョン", label: "Version", value: appVersionValue)
            settingRow(jp: "利用規約",   label: "Terms",   value: "")
            settingRow(jp: "お問い合わせ", label: "Support", value: "")

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

    // MARK: - Row primitives

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
        action: (() -> Void)? = nil
    ) -> some View {
        Button {
            action?()
        } label: {
            rowChrome(jp: jp, label: label, value: value)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    /// Bilingual + serif gold value + dim-gold chevron + 1px hairline divider.
    @ViewBuilder
    private func rowChrome(
        jp: String,
        label: LocalizedStringKey,
        value: String
    ) -> some View {
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

// MARK: - Preview

#Preview("SettingsView") {
    NavigationStack {
        SettingsView()
            .environment(AppLocale(preference: .system))
    }
    .preferredColorScheme(.dark)
}
