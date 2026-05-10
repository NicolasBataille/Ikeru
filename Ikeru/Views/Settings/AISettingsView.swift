import SwiftUI
import IkeruCore
import os

// MARK: - AISettingsView
//
// Single screen for managing every AI provider Ikeru can talk to.
//
// Five free providers (FoundationModels + Gemini + OpenRouter + Groq + Cerebras + GitHub Models)
// share the same paste-API-key UX. Claude is shown last and labelled as paid because Anthropic
// closed third-party subscription auth on 2026-04-04.
//
// All keys live in the Keychain via `KeychainHelper`. The view never holds the key value
// after a save — the SecureField clears immediately and the source of truth is the Keychain.

struct AISettingsView: View {

    @Environment(\.aiRouterService) private var aiRouterService

    @State private var inputs: [String: String] = [:]
    @State private var configured: Set<String> = []
    @State private var foundationModelsAvailable = false
    @State private var localGPUStatus: LocalGPUDiscoveryStatus = .notFound
    @State private var showingSaveConfirmation = false
    @State private var saveMessage = ""
    @State private var rigViewModel: RigSettingsViewModel?

    @Environment(\.assetCache) private var assetCache

    private let keychainStore: any KeychainStore

    init(keychainStore: any KeychainStore = KeychainHelper()) {
        self.keychainStore = keychainStore
    }

    // MARK: - Provider catalogue (single source of truth)

    private static let recommendedProviders: [CloudProviderEntry] = [
        CloudProviderEntry(
            id: "gemini",
            title: "Gemini",
            subtitle: "Google AI Studio · Free tier · Recommended first provider",
            keychainKey: KeychainKeys.geminiAPIKey,
            signupURL: URL(string: "https://aistudio.google.com/apikey")!
        ),
    ]

    private static let advancedProviders: [CloudProviderEntry] = [
        CloudProviderEntry(
            id: "openrouter",
            title: "OpenRouter",
            subtitle: "Multi-model gateway · Free Llama/DeepSeek/Qwen",
            keychainKey: KeychainKeys.openRouterAPIKey,
            signupURL: URL(string: "https://openrouter.ai/keys")!
        ),
        CloudProviderEntry(
            id: "groq",
            title: "Groq",
            subtitle: "Llama 3.3 70B · Sub-second latency · Free tier",
            keychainKey: KeychainKeys.groqAPIKey,
            signupURL: URL(string: "https://console.groq.com/keys")!
        ),
        CloudProviderEntry(
            id: "cerebras",
            title: "Cerebras",
            subtitle: "Llama 3.3 70B · Wafer-scale silicon · Free tier",
            keychainKey: KeychainKeys.cerebrasAPIKey,
            signupURL: URL(string: "https://cloud.cerebras.ai")!
        ),
        CloudProviderEntry(
            id: "github",
            title: "GitHub Models",
            subtitle: "Llama / Phi / Mistral via your GitHub PAT",
            keychainKey: KeychainKeys.githubModelsAPIKey,
            signupURL: URL(string: "https://github.com/settings/personal-access-tokens")!
        ),
    ]

    private static let allCloudProviders: [CloudProviderEntry] = recommendedProviders + advancedProviders

    private static let claudeProvider = CloudProviderEntry(
        id: "claude",
        title: "Claude (Paid · optional)",
        subtitle: "Anthropic API key — billed pay-as-you-go, NOT covered by your Pro/Max sub",
        keychainKey: KeychainKeys.claudeAPIKey,
        signupURL: URL(string: "https://console.anthropic.com/settings/keys")!
    )

    var body: some View {
        ZStack {
            Color.ikeruBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: IkeruTheme.Spacing.lg) {
                    foundationModelsSection

                    sectionHeader("Recommended")

                    ForEach(Self.recommendedProviders) { entry in
                        cloudProviderSection(entry)
                    }

                    DisclosureGroup {
                        VStack(spacing: IkeruTheme.Spacing.lg) {
                            ForEach(Self.advancedProviders) { entry in
                                cloudProviderSection(entry)
                            }

                            cloudProviderSection(Self.claudeProvider)
                        }
                        .padding(.top, IkeruTheme.Spacing.sm)
                    } label: {
                        Text("Advanced")
                            .font(.ikeruHeading3)
                            .foregroundStyle(.ikeruTextSecondary)
                    }
                    .tint(.ikeruTextSecondary)

                    localRigSection
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
            if rigViewModel == nil, let cache = assetCache {
                rigViewModel = RigSettingsViewModel(cache: cache)
            }
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

                    Text("Runs on-device. No key, no network, no quota.")
                        .font(.ikeruCaption)
                        .foregroundStyle(.ikeruTextSecondary)
                }

                Spacer()

                statusDot(available: foundationModelsAvailable)
            }
        }
        .ikeruCard(.standard)
    }

    // MARK: - Generic Cloud Provider Section

    @ViewBuilder
    private func cloudProviderSection(_ entry: CloudProviderEntry) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
                    Text(entry.title)
                        .font(.ikeruHeading3)
                        .foregroundStyle(.ikeruTextSecondary)
                    Text(entry.subtitle)
                        .font(.ikeruCaption)
                        .foregroundStyle(.ikeruTextSecondary.opacity(0.7))
                }

                Spacer()

                statusDot(available: configured.contains(entry.id))
            }

            SecureField("Paste API key", text: bindingForInput(entry.id))
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

            HStack(spacing: IkeruTheme.Spacing.sm) {
                Button {
                    saveKey(for: entry)
                } label: {
                    Text("Save")
                        .font(.ikeruCaption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, IkeruTheme.Spacing.md)
                        .padding(.vertical, IkeruTheme.Spacing.sm)
                        .background(Color.ikeruPrimaryAccent)
                        .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm))
                }
                .disabled(currentInput(entry.id).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if configured.contains(entry.id) {
                    Button {
                        deleteKey(for: entry)
                    } label: {
                        Text("Remove")
                            .font(.ikeruCaption)
                            .foregroundStyle(.ikeruSecondaryAccent)
                            .padding(.horizontal, IkeruTheme.Spacing.md)
                            .padding(.vertical, IkeruTheme.Spacing.sm)
                    }
                }

                Spacer()

                Link(destination: entry.signupURL) {
                    HStack(spacing: 4) {
                        Text("Get free key")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruPrimaryAccent)
                }
            }
        }
        .ikeruCard(.standard)
    }

    // MARK: - Local Rig Section

    @ViewBuilder
    private var localRigSection: some View {
        if let vm = rigViewModel {
            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
                        Text("Local Rig")
                            .font(.ikeruHeading3)
                            .foregroundStyle(.ikeruTextSecondary)
                        Text("PC bridge for VOICEVOX TTS and future heavy models")
                            .font(.ikeruCaption)
                            .foregroundStyle(.ikeruTextSecondary.opacity(0.7))
                    }

                    Spacer()

                    if vm.isProbing {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        statusDot(available: vm.probedHealth?.status == "ok")
                    }
                }

                TextField("http://192.168.x.x:8787", text: bindingForRigURL(vm))
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
                    .keyboardType(.URL)
                    .autocorrectionDisabled()

                SecureField("Shared token", text: bindingForRigToken(vm))
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

                HStack(spacing: IkeruTheme.Spacing.sm) {
                    Button {
                        do {
                            try vm.save()
                            showSaveConfirmation("Rig settings saved")
                        } catch {
                            showSaveConfirmation("Save failed — check URL and token")
                        }
                    } label: {
                        Text("Save")
                            .font(.ikeruCaption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, IkeruTheme.Spacing.md)
                            .padding(.vertical, IkeruTheme.Spacing.sm)
                            .background(Color.ikeruPrimaryAccent)
                            .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm))
                    }

                    Button {
                        Task { await vm.probe() }
                    } label: {
                        Text("Test connection")
                            .font(.ikeruCaption)
                            .foregroundStyle(.ikeruPrimaryAccent)
                            .padding(.horizontal, IkeruTheme.Spacing.md)
                            .padding(.vertical, IkeruTheme.Spacing.sm)
                    }
                    .disabled(vm.urlInput.isEmpty)

                    Spacer()
                }

                if let health = vm.probedHealth {
                    Text("Connected · voicevox=\(health.voicevox) · gpu=\(health.gpu) · v\(health.version)")
                        .font(.ikeruCaption)
                        .foregroundStyle(.ikeruSuccess)
                } else if let error = vm.probeError {
                    Text(error)
                        .font(.ikeruCaption)
                        .foregroundStyle(.ikeruSecondaryAccent)
                }
            }
            .ikeruCard(.standard)
        }
    }

    private func bindingForRigURL(_ vm: RigSettingsViewModel) -> Binding<String> {
        Binding(
            get: { vm.urlInput },
            set: { vm.urlInput = $0 }
        )
    }

    private func bindingForRigToken(_ vm: RigSettingsViewModel) -> Binding<String> {
        Binding(
            get: { vm.tokenInput },
            set: { vm.tokenInput = $0 }
        )
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

    // MARK: - Bindings

    private func bindingForInput(_ id: String) -> Binding<String> {
        Binding(
            get: { inputs[id] ?? "" },
            set: { inputs[id] = $0 }
        )
    }

    private func currentInput(_ id: String) -> String {
        inputs[id] ?? ""
    }

    // MARK: - Actions

    private func loadExistingConfiguration() {
        var found: Set<String> = []
        for entry in Self.allCloudProviders + [Self.claudeProvider] {
            do {
                if let value = try keychainStore.load(key: entry.keychainKey), !value.isEmpty {
                    found.insert(entry.id)
                }
            } catch {
                Logger.ai.error("Failed to read Keychain for \(entry.title): \(error.localizedDescription)")
            }
        }
        configured = found
    }

    private func checkProviderStatuses() async {
        await aiRouterService?.refreshTierStatuses()

        if let statuses = aiRouterService?.tierStatuses {
            foundationModelsAvailable = statuses[.onDevice] == .available
            if statuses[.localGPU] == .available {
                localGPUStatus = .found
            } else {
                localGPUStatus = .notFound
            }
        }
    }

    private func saveKey(for entry: CloudProviderEntry) {
        let trimmed = currentInput(entry.id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try keychainStore.save(key: entry.keychainKey, value: trimmed)
            configured.insert(entry.id)
            inputs[entry.id] = ""
            showSaveConfirmation("\(entry.title) key saved")
            Logger.ai.info("\(entry.title) API key saved to Keychain")
        } catch {
            Logger.ai.error("Failed to save \(entry.title) API key: \(error.localizedDescription)")
            showSaveConfirmation("Failed to save \(entry.title) key")
        }
    }

    private func deleteKey(for entry: CloudProviderEntry) {
        do {
            try keychainStore.delete(key: entry.keychainKey)
            configured.remove(entry.id)
            showSaveConfirmation("\(entry.title) key removed")
            Logger.ai.info("\(entry.title) API key removed from Keychain")
        } catch {
            Logger.ai.error("Failed to delete \(entry.title) API key: \(error.localizedDescription)")
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

// MARK: - Cloud Provider Entry

private struct CloudProviderEntry: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let keychainKey: String
    let signupURL: URL
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

// MARK: - Environment Key for AssetCache

struct AssetCacheKey: EnvironmentKey {
    static let defaultValue: AssetCache? = nil
}

extension EnvironmentValues {
    var assetCache: AssetCache? {
        get { self[AssetCacheKey.self] }
        set { self[AssetCacheKey.self] = newValue }
    }
}
