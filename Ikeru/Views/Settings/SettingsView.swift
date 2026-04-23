import SwiftUI
import IkeruCore
import os

// MARK: - SettingsView

struct SettingsView: View {

    @Environment(\.profileViewModel) private var profileViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var editingName: String = ""
    @State private var isEditingName = false
    @State private var reviewReminderEnabled = false
    @State private var reviewReminderHour = 9
    @State private var weeklyCheckInEnabled = false
    @State private var weeklyCheckInDay = 1
    @State private var weeklyCheckInHour = 10
    @StateObject private var backupManager = CloudBackupManager()
    @State private var showRestoreConfirmation = false
    @State private var showExportShare = false
    @State private var exportURL: URL?
    @State private var showNewProfile = false
    @State private var newProfileName = ""
    @State private var profileToDelete: UserProfile?
    @FocusState private var isNameFieldFocused: Bool
    @Environment(\.assetCache) private var assetCache
    @State private var cacheStats: AssetCache.Stats?
    @State private var cacheQuotaMB: Double = 500
    @State private var showClearAllAlert = false
    @Environment(\.toastManager) private var toastManager
    @AppStorage(IkeruApp.preWarmEnabledKey) private var preWarmEnabled: Bool = true
    @AppStorage(IkeruApp.preWarmNotifyKey) private var preWarmNotify: Bool = false
    @State private var isPreWarming = false

    private var isNameValid: Bool {
        !editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: IkeruTheme.Spacing.xl) {
                    topBar

                    profileSection
                    profileManagementSection
                    conversationSection
                    notificationsSection
                    backupSection
                    aiProvidersSection
                    assetCacheSection
                    localRigSection
                    attributionSection
                }
                .padding(.horizontal, IkeruTheme.Spacing.md)
                .padding(.top, IkeruTheme.Spacing.lg)
                .padding(.bottom, 140) // clear of the floating tab bar
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PREFERENCES")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
            Text("Settings")
                .font(.ikeruDisplaySmall)
                .ikeruTracking(.display)
                .foregroundStyle(Color.ikeruTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            IkeruSectionHeader(title: "Profile", eyebrow: "Identity")
            displayNameRow
        }
        .ikeruCard(.standard)
    }

    @ViewBuilder
    private var displayNameRow: some View {
        if isEditingName {
            nameEditField
        } else {
            nameDisplayRow
        }
    }

    private var nameDisplayRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("DISPLAY NAME")
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(Color.ikeruTextTertiary)

                Text(profileViewModel?.displayName ?? "")
                    .font(.ikeruBodyLarge)
                    .foregroundStyle(Color.ikeruTextPrimary)
            }

            Spacer()

            Button {
                editingName = profileViewModel?.displayName ?? ""
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    isEditingName = true
                }
                isNameFieldFocused = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                    .padding(10)
                    .background {
                        Circle().fill(.ultraThinMaterial)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private var nameEditField: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            Text("DISPLAY NAME")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)

            HStack(spacing: IkeruTheme.Spacing.sm) {
                TextField("Your name", text: $editingName)
                    .font(.ikeruBody)
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .padding(.horizontal, IkeruTheme.Spacing.md)
                    .padding(.vertical, IkeruTheme.Spacing.sm)
                    .ikeruGlass(
                        cornerRadius: IkeruTheme.Radius.md,
                        tint: Color.ikeruPrimaryAccent,
                        tintOpacity: 0.05
                    )
                    .focused($isNameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { saveName() }

                Button {
                    saveName()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
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
                        .font(.system(size: 26))
                        .foregroundStyle(Color.ikeruTextTertiary)
                }
            }
        }
    }

    // MARK: - Profile Management Section

    private var profileManagementSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            IkeruSectionHeader(title: "Profiles", eyebrow: "Accounts")

            VStack(spacing: 0) {
                let profiles = profileViewModel?.allProfiles ?? []
                ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                    profileRow(profile)
                    if index < profiles.count - 1 {
                        IkeruDivider()
                    }
                }
            }

            Button {
                showNewProfile = true
            } label: {
                HStack(spacing: IkeruTheme.Spacing.sm) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Profile")
                }
            }
            .ikeruButtonStyle(.glassPill)
        }
        .ikeruCard(.standard)
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
            Button("Cancel", role: .cancel) {
                newProfileName = ""
            }
        }
        .sheet(item: $profileToDelete) { profile in
            DeleteProfileSheet(
                profile: profile,
                onConfirm: {
                    profileViewModel?.deleteProfile(profile)
                    profileToDelete = nil
                },
                onCancel: {
                    profileToDelete = nil
                }
            )
        }
    }

    @ViewBuilder
    private func profileRow(_ profile: UserProfile) -> some View {
        let isCurrent = profile.id == profileViewModel?.currentProfile?.id
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.ikeruBody)
                    .foregroundStyle(Color.ikeruTextPrimary)

                if isCurrent {
                    Text("ACTIVE")
                        .font(.ikeruMicro)
                        .ikeruTracking(.micro)
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                }
            }

            Spacer()

            if !isCurrent {
                Button("Switch") {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        profileViewModel?.switchProfile(to: profile)
                    }
                }
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruPrimaryAccent)

                if (profileViewModel?.allProfiles.count ?? 0) > 1 {
                    Button(role: .destructive) {
                        profileToDelete = profile
                    } label: {
                        Image(systemName: "trash")
                            .font(.ikeruCaption)
                            .foregroundStyle(Color.ikeruDanger)
                    }
                }
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color.ikeruPrimaryAccent)
            }
        }
        .padding(.vertical, IkeruTheme.Spacing.sm)
    }

    // MARK: - Backup Section

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            IkeruSectionHeader(title: "Data", eyebrow: "Backup & Export")

            VStack(spacing: 0) {
                glassRow(
                    icon: "icloud.and.arrow.up",
                    title: "Backup to iCloud",
                    subtitle: backupManager.isBackingUp ? "Backing up..." : nil
                ) {
                    Task {
                        await backupManager.backup(modelContainer: modelContext.container)
                    }
                }
                .disabled(backupManager.isBackingUp || backupManager.isRestoring)

                IkeruDivider()

                glassRow(
                    icon: "icloud.and.arrow.down",
                    title: "Restore from iCloud",
                    subtitle: backupManager.isRestoring ? "Restoring..." : nil
                ) {
                    showRestoreConfirmation = true
                }
                .disabled(backupManager.isBackingUp || backupManager.isRestoring)

                IkeruDivider()

                glassRow(
                    icon: "square.and.arrow.up",
                    title: "Export Data",
                    subtitle: nil
                ) {
                    Task {
                        let manager = DataExportManager()
                        if let url = try? await manager.exportData(modelContainer: modelContext.container) {
                            exportURL = url
                            showExportShare = true
                        }
                    }
                }
            }

            if let date = backupManager.lastBackupDate {
                Text("Last backup: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextTertiary)
            }

            if let error = backupManager.lastError {
                Text(error.localizedDescription)
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruDanger)
            }
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
        .ikeruCard(.standard)
        .confirmationDialog(
            "Restore Backup?",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                Task {
                    await backupManager.restore(modelContainer: modelContext.container)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace all current data with the backup. This cannot be undone.")
        }
        .task {
            await backupManager.checkLastBackup()
        }
    }

    private func glassRow(
        icon: String,
        title: String,
        subtitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: IkeruTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.ikeruBody)
                        .foregroundStyle(Color.ikeruTextPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.ikeruCaption)
                            .foregroundStyle(Color.ikeruTextSecondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, IkeruTheme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Conversation Section

    @AppStorage("ikeru.furigana.enabled") private var furiganaEnabled = true

    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            IkeruSectionHeader(title: "Conversation", eyebrow: "Learning")

            Toggle(isOn: $furiganaEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show pronunciation guides")
                        .font(.ikeruBody)
                        .foregroundStyle(.white)
                    Text("Display romaji and furigana above Japanese characters")
                        .font(.ikeruCaption)
                        .foregroundStyle(.ikeruTextSecondary)
                }
            }
            .tint(Color.ikeruPrimaryAccent)
        }
        .ikeruCard(.standard)
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            IkeruSectionHeader(title: "Notifications", eyebrow: "Reminders")

            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
                Toggle(isOn: $reviewReminderEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily Review Reminder")
                            .font(.ikeruBody)
                            .foregroundStyle(Color.ikeruTextPrimary)
                        Text("Get notified when cards are ready")
                            .font(.ikeruCaption)
                            .foregroundStyle(Color.ikeruTextSecondary)
                    }
                }
                .tint(Color.ikeruPrimaryAccent)
                .onChange(of: reviewReminderEnabled) { _, enabled in
                    updateReviewReminder(enabled: enabled)
                }

                if reviewReminderEnabled {
                    Picker("Time", selection: $reviewReminderHour) {
                        ForEach(6..<23) { hour in
                            Text("\(hour):00").tag(hour)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.ikeruPrimaryAccent)
                    .onChange(of: reviewReminderHour) { _, _ in
                        updateReviewReminder(enabled: true)
                    }
                }
            }
            .padding(.vertical, IkeruTheme.Spacing.xs)

            IkeruDivider()

            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
                Toggle(isOn: $weeklyCheckInEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weekly Check-In")
                            .font(.ikeruBody)
                            .foregroundStyle(Color.ikeruTextPrimary)
                        Text("Reflect on your progress")
                            .font(.ikeruCaption)
                            .foregroundStyle(Color.ikeruTextSecondary)
                    }
                }
                .tint(Color.ikeruPrimaryAccent)
                .onChange(of: weeklyCheckInEnabled) { _, enabled in
                    updateWeeklyCheckIn(enabled: enabled)
                }

                if weeklyCheckInEnabled {
                    HStack {
                        Picker("Day", selection: $weeklyCheckInDay) {
                            Text("Sun").tag(1)
                            Text("Mon").tag(2)
                            Text("Tue").tag(3)
                            Text("Wed").tag(4)
                            Text("Thu").tag(5)
                            Text("Fri").tag(6)
                            Text("Sat").tag(7)
                        }
                        .pickerStyle(.menu)
                        .tint(Color.ikeruPrimaryAccent)

                        Picker("Time", selection: $weeklyCheckInHour) {
                            ForEach(6..<23) { hour in
                                Text("\(hour):00").tag(hour)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.ikeruPrimaryAccent)
                    }
                    .onChange(of: weeklyCheckInDay) { _, _ in
                        updateWeeklyCheckIn(enabled: true)
                    }
                    .onChange(of: weeklyCheckInHour) { _, _ in
                        updateWeeklyCheckIn(enabled: true)
                    }
                }
            }
            .padding(.vertical, IkeruTheme.Spacing.xs)
        }
        .ikeruCard(.standard)
    }

    // MARK: - AI Providers Section

    private var aiProvidersSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            IkeruSectionHeader(title: "AI", eyebrow: "Providers")

            NavigationLink {
                AISettingsView()
            } label: {
                navRow(
                    title: "AI Providers",
                    subtitle: "Configure API keys and local GPU"
                )
            }
            .buttonStyle(.plain)
        }
        .ikeruCard(.standard)
    }

    // MARK: - Asset Cache Section

    @ViewBuilder
    private var assetCacheSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            IkeruSectionHeader(title: "Storage", eyebrow: "Asset cache")

            if let stats = cacheStats {
                let usedMB = Double(stats.totalBytes) / 1_048_576.0
                VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
                    Text(String(format: "%.1f MB / %.0f MB · %d entries", usedMB, cacheQuotaMB, stats.entryCount))
                        .font(.ikeruBody)
                        .foregroundStyle(.white)

                    ProgressView(value: usedMB, total: cacheQuotaMB)
                        .tint(Color.ikeruPrimaryAccent)
                }

                if !stats.breakdown.isEmpty {
                    let breakdown = stats.breakdown.map { "\($0.key.rawValue): \($0.value / 1024) KB" }
                        .sorted()
                        .joined(separator: " · ")
                    Text(breakdown)
                        .font(.ikeruCaption)
                        .foregroundStyle(.ikeruTextSecondary)
                }
            } else {
                Text("Cache not initialised")
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruTextSecondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Quota")
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruTextSecondary)
                Slider(value: $cacheQuotaMB, in: 200...2000, step: 100) {
                    Text("Quota")
                } onEditingChanged: { editing in
                    if !editing {
                        let bytes = Int(cacheQuotaMB) * 1_048_576
                        assetCache?.updateQuota(bytes)
                        cacheStats = assetCache?.stats()
                    }
                }
                .tint(Color.ikeruPrimaryAccent)
            }

            HStack(spacing: IkeruTheme.Spacing.sm) {
                Button {
                    showClearAllAlert = true
                } label: {
                    Text("Clear all")
                        .font(.ikeruCaption)
                        .foregroundStyle(.ikeruSecondaryAccent)
                        .padding(.horizontal, IkeruTheme.Spacing.md)
                        .padding(.vertical, IkeruTheme.Spacing.sm)
                }

                Button {
                    assetCache?.clearStale(olderThan: 30 * 24 * 60 * 60)
                    cacheStats = assetCache?.stats()
                } label: {
                    Text("Clear unused (30d)")
                        .font(.ikeruCaption)
                        .foregroundStyle(.ikeruPrimaryAccent)
                        .padding(.horizontal, IkeruTheme.Spacing.md)
                        .padding(.vertical, IkeruTheme.Spacing.sm)
                }

                Spacer()
            }
        }
        .ikeruCard(.standard)
        .task {
            cacheStats = assetCache?.stats()
            if let cache = assetCache {
                cacheQuotaMB = Double(cache.configuration.quotaBytes) / 1_048_576.0
            }
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
    }

    // MARK: - Local Rig Section (Story 7.5)

    private var localRigSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            IkeruSectionHeader(title: "Local Rig", eyebrow: "Pre-warming")

            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
                Toggle(isOn: $preWarmEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto pre-warm audio for upcoming reviews")
                            .font(.ikeruBody)
                            .foregroundStyle(Color.ikeruTextPrimary)
                        Text("Generates tomorrow's audio in the background")
                            .font(.ikeruCaption)
                            .foregroundStyle(Color.ikeruTextSecondary)
                    }
                }
                .tint(Color.ikeruPrimaryAccent)

                Toggle(isOn: $preWarmNotify) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notify when batch finishes")
                            .font(.ikeruBody)
                            .foregroundStyle(Color.ikeruTextPrimary)
                        Text("Local notification after each pre-warm pass")
                            .font(.ikeruCaption)
                            .foregroundStyle(Color.ikeruTextSecondary)
                    }
                }
                .tint(Color.ikeruPrimaryAccent)
            }
            .padding(.vertical, IkeruTheme.Spacing.xs)

            IkeruDivider()

            Button {
                runPreWarmNow()
            } label: {
                HStack(spacing: IkeruTheme.Spacing.sm) {
                    if isPreWarming {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "bolt.fill")
                    }
                    Text(isPreWarming ? "Pre-warming…" : "Pre-warm now")
                }
            }
            .ikeruButtonStyle(.glassPill)
            .disabled(isPreWarming)

            IkeruDivider()

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
                navRow(
                    title: "View jobs",
                    subtitle: "In-flight rig jobs"
                )
            }
            .buttonStyle(.plain)
        }
        .ikeruCard(.standard)
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

    // MARK: - Attribution Section

    private var attributionSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            IkeruSectionHeader(title: "About", eyebrow: "Credits")

            NavigationLink {
                AttributionView()
            } label: {
                navRow(
                    title: "Attribution",
                    subtitle: "Open-source credits"
                )
            }
            .buttonStyle(.plain)
        }
        .ikeruCard(.standard)
    }

    private func navRow(title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ikeruBody)
                    .foregroundStyle(Color.ikeruTextPrimary)
                Text(subtitle)
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ikeruTextTertiary)
        }
        .padding(.vertical, IkeruTheme.Spacing.xs)
        .contentShape(Rectangle())
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
}

// MARK: - Preview

#Preview("SettingsView") {
    NavigationStack {
        SettingsView()
    }
    .preferredColorScheme(.dark)
}
