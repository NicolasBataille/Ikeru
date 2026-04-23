import SwiftUI
import IkeruCore
import os

// MARK: - AISetupView

/// Onboarding step that offers a quick AI provider setup before entering the app.
/// If FoundationModels (iOS 26+) is available, the user sees a green checkmark and
/// can continue immediately. Otherwise, they're guided to paste a free Gemini key
/// or skip for now.
struct AISetupView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var foundationModelsAvailable = false
    @State private var geminiKey: String = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var saved = false

    private let keychainStore: any KeychainStore

    init(keychainStore: any KeychainStore = KeychainHelper()) {
        self.keychainStore = keychainStore
    }

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            VStack(spacing: 0) {
                Spacer()

                headerSection

                Spacer().frame(height: IkeruTheme.Spacing.xxl)

                if foundationModelsAvailable {
                    onDeviceReadySection
                } else {
                    geminiSetupSection
                }

                Spacer()

                bottomButtons

                Spacer().frame(height: IkeruTheme.Spacing.xxl)
            }
            .padding(.horizontal, IkeruTheme.Spacing.xl)
        }
        .task {
            await checkFoundationModels()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(hex: IkeruTheme.Colors.primaryAccent),
                            Color(hex: IkeruTheme.Colors.success)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("AI Setup")
                .font(.ikeruDisplaySmall)
                .ikeruTracking(.display)
                .foregroundStyle(Color.ikeruTextPrimary)

            Text("Sakura needs an AI provider to chat with you.")
                .font(.ikeruBody)
                .foregroundStyle(Color.ikeruTextSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - On-Device Ready

    private var onDeviceReadySection: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            HStack(spacing: IkeruTheme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.ikeruSuccess)

                Text("On-device AI ready")
                    .font(.ikeruBody)
                    .foregroundStyle(.white)
            }

            Text("Apple FoundationModels is available on your device. No setup required.")
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(IkeruTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.md)
                .fill(Color.ikeruSuccess.opacity(0.08))
                .strokeBorder(Color.ikeruSuccess.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Gemini Setup

    private var geminiSetupSection: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            Text("Set up a free Gemini key for AI features")
                .font(.ikeruBody)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                HStack(spacing: 4) {
                    Text("Get a free key from Google AI Studio")
                    Image(systemName: "arrow.up.right")
                }
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruPrimaryAccent)
            }

            SecureField("Paste Gemini API key", text: $geminiKey)
                .font(.ikeruBody)
                .foregroundStyle(.white)
                .padding(IkeruTheme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
                        .fill(Color.ikeruSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
                        .strokeBorder(Color.ikeruPrimaryAccent.opacity(0.3), lineWidth: 1)
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if saved {
                HStack(spacing: IkeruTheme.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.ikeruSuccess)
                    Text("Key saved")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruSuccess)
                }
            }

            if let error = saveError {
                Text(error)
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruSecondaryAccent)
            }
        }
        .padding(IkeruTheme.Spacing.lg)
        .ikeruCard(.standard)
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            if !foundationModelsAvailable && !saved {
                Button {
                    saveGeminiKey()
                } label: {
                    HStack(spacing: 10) {
                        Text("Save")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .ikeruButtonStyle(.primary)
                .disabled(geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }

            Button {
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Text(foundationModelsAvailable || saved ? "Continue" : "Skip for now")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .ikeruButtonStyle(foundationModelsAvailable || saved ? .primary : .ghost)
        }
    }

    // MARK: - Actions

    private func checkFoundationModels() async {
        let provider = FoundationModelsProvider()
        foundationModelsAvailable = await provider.isAvailable
    }

    private func saveGeminiKey() {
        let trimmed = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        saveError = nil

        do {
            try keychainStore.save(key: KeychainKeys.geminiAPIKey, value: trimmed)
            geminiKey = ""
            saved = true
            Logger.ai.info("Gemini API key saved during onboarding")
        } catch {
            saveError = "Failed to save key. Try again."
            Logger.ai.error("Onboarding Gemini key save failed: \(error.localizedDescription)")
        }

        isSaving = false
    }
}

// MARK: - Preview

#Preview("AI Setup — No FoundationModels") {
    AISetupView()
        .preferredColorScheme(.dark)
}
