import SwiftUI
import IkeruCore
import os

// MARK: - SettingsView

struct SettingsView: View {

    @Environment(\.profileViewModel) private var profileViewModel
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
            Color.ikeruBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: IkeruTheme.Spacing.lg) {
                    profileSection
                    profileManagementSection
                    notificationsSection
                    backupSection
                    aiProvidersSection
                    attributionSection
                }
                .padding(IkeruTheme.Spacing.md)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            Text("Profile")
                .font(.ikeruHeading3)
                .foregroundStyle(.ikeruTextSecondary)
                .padding(.leading, IkeruTheme.Spacing.xs)

            displayNameRow
        }
        .ikeruCard(.standard)
    }

    // MARK: - Display Name Row

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
            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
                Text("Display Name")
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruTextSecondary)

                Text(profileViewModel?.displayName ?? "")
                    .font(.ikeruBody)
                    .foregroundStyle(.white)
            }

            Spacer()

            Button {
                editingName = profileViewModel?.displayName ?? ""
                isEditingName = true
                isNameFieldFocused = true
            } label: {
                Image(systemName: "pencil")
                    .font(.ikeruBody)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
            }
        }
    }

    private var nameEditField: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            Text("Display Name")
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)

            HStack(spacing: IkeruTheme.Spacing.sm) {
                TextField("Your name", text: $editingName)
                    .font(.ikeruBody)
                    .foregroundStyle(.white)
                    .padding(IkeruTheme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
                            .fill(Color.ikeruSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
                            .strokeBorder(Color.ikeruPrimaryAccent, lineWidth: 1)
                    )
                    .focused($isNameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        saveName()
                    }

                Button {
                    saveName()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                }
                .disabled(!isNameValid)
                .opacity(isNameValid ? 1.0 : 0.5)

                Button {
                    isEditingName = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.ikeruTextSecondary)
                }
            }
        }
    }

    // MARK: - Profile Management Section

    private var profileManagementSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            Text("Profiles")
                .font(.ikeruHeading3)
                .foregroundStyle(.ikeruTextSecondary)
                .padding(.leading, IkeruTheme.Spacing.xs)

            ForEach(profileViewModel?.allProfiles ?? [], id: \.id) { profile in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName)
                            .font(.ikeruBody)
                            .foregroundStyle(.white)

                        if profile.id == profileViewModel?.currentProfile?.id {
                            Text("Active")
                                .font(.ikeruCaption)
                                .foregroundStyle(Color.ikeruPrimaryAccent)
                        }
                    }

                    Spacer()

                    if profile.id != profileViewModel?.currentProfile?.id {
                        Button("Switch") {
                            profileViewModel?.switchProfile(to: profile)
                        }
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruPrimaryAccent)

                        if (profileViewModel?.allProfiles.count ?? 0) > 1 {
                            Button(role: .destructive) {
                                profileToDelete = profile
                            } label: {
                                Image(systemName: "trash")
                                    .font(.ikeruCaption)
                            }
                        }
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.ikeruPrimaryAccent)
                    }
                }
                .padding(.vertical, IkeruTheme.Spacing.xs)
            }

            Button {
                showNewProfile = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                    Text("Add Profile")
                        .font(.ikeruBody)
                        .foregroundStyle(.white)
                }
            }
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

    // MARK: - Backup Section

    @Environment(\.modelContext) private var modelContext

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            Text("Data")
                .font(.ikeruHeading3)
                .foregroundStyle(.ikeruTextSecondary)
                .padding(.leading, IkeruTheme.Spacing.xs)

            // Backup button
            Button {
                Task {
                    await backupManager.backup(modelContainer: modelContext.container)
                }
            } label: {
                HStack {
                    Image(systemName: "icloud.and.arrow.up")
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                    Text("Backup to iCloud")
                        .font(.ikeruBody)
                        .foregroundStyle(.white)
                    Spacer()
                    if backupManager.isBackingUp {
                        ProgressView()
                            .tint(.white)
                    }
                }
            }
            .disabled(backupManager.isBackingUp || backupManager.isRestoring)

            // Restore button
            Button {
                showRestoreConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "icloud.and.arrow.down")
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                    Text("Restore from iCloud")
                        .font(.ikeruBody)
                        .foregroundStyle(.white)
                    Spacer()
                    if backupManager.isRestoring {
                        ProgressView()
                            .tint(.white)
                    }
                }
            }
            .disabled(backupManager.isBackingUp || backupManager.isRestoring)

            // Last backup date
            if let date = backupManager.lastBackupDate {
                Text("Last backup: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruTextSecondary)
            }

            Divider()
                .background(.ikeruTextSecondary.opacity(0.3))

            // Export button
            Button {
                Task {
                    let manager = DataExportManager()
                    if let url = try? await manager.exportData(modelContainer: modelContext.container) {
                        exportURL = url
                        showExportShare = true
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                    Text("Export Data")
                        .font(.ikeruBody)
                        .foregroundStyle(.white)
                    Spacer()
                }
            }

            // Error display
            if let error = backupManager.lastError {
                Text(error.localizedDescription)
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruError)
            }
        }
        .sheet(isPresented: $showExportShare) {
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

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            Text("Notifications")
                .font(.ikeruHeading3)
                .foregroundStyle(.ikeruTextSecondary)
                .padding(.leading, IkeruTheme.Spacing.xs)

            // Review reminder toggle
            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
                Toggle(isOn: $reviewReminderEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily Review Reminder")
                            .font(.ikeruBody)
                            .foregroundStyle(.white)
                        Text("Get notified when cards are ready")
                            .font(.ikeruCaption)
                            .foregroundStyle(.ikeruTextSecondary)
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

            Divider()
                .background(.ikeruTextSecondary.opacity(0.3))

            // Weekly check-in toggle
            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
                Toggle(isOn: $weeklyCheckInEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weekly Check-In")
                            .font(.ikeruBody)
                            .foregroundStyle(.white)
                        Text("Reflect on your progress")
                            .font(.ikeruCaption)
                            .foregroundStyle(.ikeruTextSecondary)
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
        }
        .ikeruCard(.standard)
    }

    // MARK: - AI Providers Section

    private var aiProvidersSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            Text("AI")
                .font(.ikeruHeading3)
                .foregroundStyle(.ikeruTextSecondary)
                .padding(.leading, IkeruTheme.Spacing.xs)

            NavigationLink {
                AISettingsView()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
                        Text("AI Providers")
                            .font(.ikeruBody)
                            .foregroundStyle(.white)

                        Text("Configure API keys and local GPU")
                            .font(.ikeruCaption)
                            .foregroundStyle(.ikeruTextSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.ikeruCaption)
                        .foregroundStyle(.ikeruTextSecondary)
                }
            }
        }
        .ikeruCard(.standard)
    }

    // MARK: - Attribution Section

    private var attributionSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            Text("About")
                .font(.ikeruHeading3)
                .foregroundStyle(.ikeruTextSecondary)
                .padding(.leading, IkeruTheme.Spacing.xs)

            NavigationLink {
                AttributionView()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
                        Text("Attribution")
                            .font(.ikeruBody)
                            .foregroundStyle(.white)

                        Text("Open-source credits")
                            .font(.ikeruCaption)
                            .foregroundStyle(.ikeruTextSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.ikeruCaption)
                        .foregroundStyle(.ikeruTextSecondary)
                }
            }
        }
        .ikeruCard(.standard)
    }

    // MARK: - Actions

    private func saveName() {
        guard isNameValid else { return }
        Logger.ui.info("Updating display name from settings")
        profileViewModel?.updateDisplayName(editingName)
        isEditingName = false
    }

    private func updateReviewReminder(enabled: Bool) {
        if enabled {
            Task {
                let authorized = await NotificationManager.shared.requestAuthorization()
                if authorized {
                    NotificationManager.shared.scheduleReviewReminder(
                        hour: reviewReminderHour,
                        dueCardCount: 0
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
                    NotificationManager.shared.scheduleWeeklyCheckIn(
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
