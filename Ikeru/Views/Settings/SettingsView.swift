import SwiftUI
import IkeruCore
import os

// MARK: - SettingsView

struct SettingsView: View {

    @Environment(\.profileViewModel) private var profileViewModel
    @State private var editingName: String = ""
    @State private var isEditingName = false
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

    // MARK: - Actions

    private func saveName() {
        guard isNameValid else { return }
        Logger.ui.info("Updating display name from settings")
        profileViewModel?.updateDisplayName(editingName)
        isEditingName = false
    }
}

// MARK: - Preview

#Preview("SettingsView") {
    NavigationStack {
        SettingsView()
    }
    .preferredColorScheme(.dark)
}
