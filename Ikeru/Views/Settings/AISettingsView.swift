import SwiftUI
import IkeruCore
import os

// MARK: - AISettingsView

struct AISettingsView: View {

    @Environment(\.aiRouterService) private var aiRouterService
    @State private var geminiKey: String = ""
    @State private var claudeToken: String = ""
    @State private var geminiConfigured = false
    @State private var claudeConfigured = false
    @State private var foundationModelsAvailable = false
    @State private var localGPUStatus: LocalGPUDiscoveryStatus = .notFound
    @State private var showingSaveConfirmation = false
    @State private var saveMessage = ""

    private let keychainStore: any KeychainStore

    init(keychainStore: any KeychainStore = KeychainHelper()) {
        self.keychainStore = keychainStore
    }

    var body: some View {
        ZStack {
            Color.ikeruBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: IkeruTheme.Spacing.lg) {
                    foundationModelsSection
                    geminiSection
                    claudeSection
                    localGPUSection
                }
                .padding(IkeruTheme.Spacing.md)
            }
        }
        .navigationTitle("AI Providers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            loadExistingConfiguration()
            localGPUStatus = .searching
            await checkProviderStatuses()
        }
        .overlay {
            if showingSaveConfirmation {
                saveConfirmationToast
            }
        }
    }

    // MARK: - FoundationModels Section

    private var foundationModelsSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            sectionHeader("On-Device AI")

            HStack {
                VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
                    Text("Apple FoundationModels")
                        .font(.ikeruBody)
                        .foregroundStyle(.white)

                    Text("On-device AI for simple tasks. No API key needed.")
                        .font(.ikeruCaption)
                        .foregroundStyle(.ikeruTextSecondary)
                }

                Spacer()

                statusDot(available: foundationModelsAvailable)
            }
        }
        .ikeruCard(.standard)
    }

    // MARK: - Gemini Section

    private var geminiSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            sectionHeader("Gemini (Free Tier)")

            HStack {
                Text("API Key")
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruTextSecondary)

                Spacer()

                statusDot(available: geminiConfigured)
            }

            SecureField("Enter Gemini API key", text: $geminiKey)
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

            HStack(spacing: IkeruTheme.Spacing.sm) {
                Button {
                    saveGeminiKey()
                } label: {
                    Text("Save")
                        .font(.ikeruCaption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, IkeruTheme.Spacing.md)
                        .padding(.vertical, IkeruTheme.Spacing.sm)
                        .background(Color.ikeruPrimaryAccent)
                        .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm))
                }
                .disabled(geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if geminiConfigured {
                    Button {
                        deleteGeminiKey()
                    } label: {
                        Text("Remove")
                            .font(.ikeruCaption)
                            .foregroundStyle(.ikeruSecondaryAccent)
                            .padding(.horizontal, IkeruTheme.Spacing.md)
                            .padding(.vertical, IkeruTheme.Spacing.sm)
                    }
                }
            }
        }
        .ikeruCard(.standard)
    }

    // MARK: - Claude Section

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            sectionHeader("Claude (Subscription)")

            HStack {
                Text("Session Token")
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruTextSecondary)

                Spacer()

                statusDot(available: claudeConfigured)
            }

            SecureField("Enter Claude session token", text: $claudeToken)
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

            HStack(spacing: IkeruTheme.Spacing.sm) {
                Button {
                    saveClaudeToken()
                } label: {
                    Text("Save")
                        .font(.ikeruCaption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, IkeruTheme.Spacing.md)
                        .padding(.vertical, IkeruTheme.Spacing.sm)
                        .background(Color.ikeruPrimaryAccent)
                        .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm))
                }
                .disabled(claudeToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if claudeConfigured {
                    Button {
                        deleteClaudeToken()
                    } label: {
                        Text("Remove")
                            .font(.ikeruCaption)
                            .foregroundStyle(.ikeruSecondaryAccent)
                            .padding(.horizontal, IkeruTheme.Spacing.md)
                            .padding(.vertical, IkeruTheme.Spacing.sm)
                    }
                }
            }
        }
        .ikeruCard(.standard)
    }

    // MARK: - LocalGPU Section

    private var localGPUSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            sectionHeader("Local GPU (RTX 5090)")

            HStack {
                VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
                    Text("Bonjour Discovery")
                        .font(.ikeruBody)
                        .foregroundStyle(.white)

                    Text(localGPUStatusText)
                        .font(.ikeruCaption)
                        .foregroundStyle(.ikeruTextSecondary)
                }

                Spacer()

                localGPUStatusIndicator
            }
        }
        .ikeruCard(.standard)
    }

    // MARK: - Shared Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.ikeruHeading3)
            .foregroundStyle(.ikeruTextSecondary)
            .padding(.leading, IkeruTheme.Spacing.xs)
    }

    private func statusDot(available: Bool) -> some View {
        Circle()
            .fill(available ? Color.ikeruSuccess : Color.gray.opacity(0.5))
            .frame(width: 10, height: 10)
    }

    @ViewBuilder
    private var localGPUStatusIndicator: some View {
        switch localGPUStatus {
        case .found:
            statusDot(available: true)
        case .searching:
            ProgressView()
                .scaleEffect(0.7)
        case .notFound:
            statusDot(available: false)
        }
    }

    private var localGPUStatusText: String {
        switch localGPUStatus {
        case .found:
            return "GPU server found on local network"
        case .searching:
            return "Searching for GPU server..."
        case .notFound:
            return "No GPU server found on local network"
        }
    }

    private var saveConfirmationToast: some View {
        VStack {
            Spacer()
            Text(saveMessage)
                .font(.ikeruCaption)
                .foregroundStyle(.white)
                .padding(IkeruTheme.Spacing.md)
                .background(Color.ikeruSurface)
                .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm))
                .padding(.bottom, IkeruTheme.Spacing.xl)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: IkeruTheme.Animation.quickDuration), value: showingSaveConfirmation)
    }

    // MARK: - Actions

    private func loadExistingConfiguration() {
        do {
            geminiConfigured = (try keychainStore.load(key: KeychainKeys.geminiAPIKey)) != nil
            claudeConfigured = (try keychainStore.load(key: KeychainKeys.claudeSessionToken)) != nil
        } catch {
            Logger.ai.error("Failed to check Keychain configuration: \(error)")
        }
    }

    private func checkProviderStatuses() async {
        await aiRouterService?.refreshTierStatuses()

        if let statuses = aiRouterService?.tierStatuses {
            foundationModelsAvailable = statuses[.onDevice] == .available
            if statuses[.localGPU] == .available {
                localGPUStatus = .found
            }
        }
    }

    private func saveGeminiKey() {
        let trimmedKey = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        do {
            try keychainStore.save(key: KeychainKeys.geminiAPIKey, value: trimmedKey)
            geminiConfigured = true
            geminiKey = ""
            showSaveConfirmation("Gemini API key saved")
            Logger.ai.info("Gemini API key saved to Keychain")
        } catch {
            Logger.ai.error("Failed to save Gemini API key")
            showSaveConfirmation("Failed to save API key")
        }
    }

    private func deleteGeminiKey() {
        do {
            try keychainStore.delete(key: KeychainKeys.geminiAPIKey)
            geminiConfigured = false
            showSaveConfirmation("Gemini API key removed")
            Logger.ai.info("Gemini API key removed from Keychain")
        } catch {
            Logger.ai.error("Failed to delete Gemini API key")
        }
    }

    private func saveClaudeToken() {
        let trimmedToken = claudeToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { return }

        do {
            try keychainStore.save(key: KeychainKeys.claudeSessionToken, value: trimmedToken)
            claudeConfigured = true
            claudeToken = ""
            showSaveConfirmation("Claude session token saved")
            Logger.ai.info("Claude session token saved to Keychain")
        } catch {
            Logger.ai.error("Failed to save Claude session token")
            showSaveConfirmation("Failed to save session token")
        }
    }

    private func deleteClaudeToken() {
        do {
            try keychainStore.delete(key: KeychainKeys.claudeSessionToken)
            claudeConfigured = false
            showSaveConfirmation("Claude session token removed")
            Logger.ai.info("Claude session token removed from Keychain")
        } catch {
            Logger.ai.error("Failed to delete Claude session token")
        }
    }

    private func showSaveConfirmation(_ message: String) {
        saveMessage = message
        showingSaveConfirmation = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showingSaveConfirmation = false
        }
    }
}

// MARK: - LocalGPU Discovery Status

private enum LocalGPUDiscoveryStatus {
    case found
    case searching
    case notFound
}

// MARK: - Environment Key for AIRouterService

struct AIRouterServiceKey: EnvironmentKey {
    static let defaultValue: AIRouterService? = nil
}

extension EnvironmentValues {
    var aiRouterService: AIRouterService? {
        get { self[AIRouterServiceKey.self] }
        set { self[AIRouterServiceKey.self] = newValue }
    }
}

// MARK: - Preview

#Preview("AI Settings") {
    NavigationStack {
        AISettingsView()
    }
    .preferredColorScheme(.dark)
}
