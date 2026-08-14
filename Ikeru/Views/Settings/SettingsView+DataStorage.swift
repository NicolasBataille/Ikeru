import SwiftUI
import IkeruCore

// Split out of `SettingsView.swift`, which had grown past SwiftLint's
// 1800-line hard ceiling. This sub-page is reached from the "Data &
// Storage" row and owns nothing the parent screen needs — the only
// coupling is the initialiser below, which the parent fills in.
// Same one-file-per-sub-page shape as `AISettingsView.swift`.

// MARK: - Sub-page: Data & Storage Settings

struct DataStorageSettingsView: View {

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
