import SwiftUI
import SwiftData

// Split out of `SettingsView.swift` for the same reason as
// `SettingsView+DataStorage.swift`: the file had crossed SwiftLint's
// 1800-line hard ceiling.
//
// The whole file stays behind `#if IKERU_DEV_TOOLS` exactly as it was
// inline — see CLAUDE.md ("Outils développeur en TestFlight") for how
// that flag is removed before App Store submission.

// MARK: - Sub-page: Dev Tools Settings

#if IKERU_DEV_TOOLS
struct DevToolsSettingsView: View {

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
                // The `value:` column is padded so it lines up down the rows.
                // SwiftLint's `comma` rule reads that padding as a violation.
                // It always did — but this code sat inline in SettingsView.swift
                // on lines no PR had touched, and the strict pass only judges
                // touched lines, so nobody ever saw it. Moving the file makes
                // every line "new". The alignment is deliberate; it stays.
                // swiftlint:disable comma
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
                // swiftlint:enable comma

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

            // Aligned columns again — same reason as the block above.
            // swiftlint:disable comma
            devSlider(label: "Level",     value: $devSeedLevel,     range: 1...30,   step: 1)
            devSlider(label: "Due",       value: $devSeedDue,       range: 0...50,   step: 5)
            devSlider(label: "Mastered",  value: $devSeedMastered,  range: 0...200,  step: 10)
            // swiftlint:enable comma
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
