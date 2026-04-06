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

    private var isNameValid: Bool {
        !editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            ScrollView {
                VStack(spacing: IkeruTheme.Spacing.xl) {
                    topBar

                    profileSection
                    profileManagementSection
                    notificationsSection
                    backupSection
                    aiProvidersSection
                    attributionSection

                    Spacer(minLength: 200)
                }
                .padding(.horizontal, IkeruTheme.Spacing.md)
                .padding(.top, IkeruTheme.Spacing.lg)
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
        .confirmationDialog(
            "Delete Profile?",
            isPresented: Binding(
                get: { profileToDelete != nil },
                set: { if !$0 { profileToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let profile = profileToDelete {
                Button("Delete \(profile.displayName)", role: .destructive) {
                    profileViewModel?.deleteProfile(profile)
                    profileToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                profileToDelete = nil
            }
        } message: {
            Text("This will permanently delete the profile and all its learning data.")
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
