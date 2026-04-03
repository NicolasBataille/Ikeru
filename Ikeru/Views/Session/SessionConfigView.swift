import SwiftUI
import SwiftData
import IkeruCore
import os

// MARK: - SessionConfigView

/// Session configuration screen where users pick a duration, see a preview of
/// the session composition, and start an adaptive session.
///
/// Automatically detects muted volume and shows a silent mode banner when
/// audio exercises will be excluded.
struct SessionConfigView: View {

    var configViewModel: SessionConfigViewModel
    let onStartSession: (SessionConfig) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: IkeruTheme.Spacing.lg) {
                headerSection
                timePickerSection
                silentModeBanner
                previewSection
                startButton
            }
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .padding(.vertical, IkeruTheme.Spacing.lg)
        }
        .background(Color.ikeruBackground)
        .task {
            await configViewModel.onAppear()
        }
        .onDisappear {
            configViewModel.onDisappear()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Text("Configure Session")
                .font(.system(size: IkeruTheme.Typography.Size.heading1, weight: .bold))
                .foregroundStyle(.white)

            Text("Choose how much time you have")
                .font(.system(size: IkeruTheme.Typography.Size.body))
                .foregroundStyle(Color.ikeruTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Time Picker

    @ViewBuilder
    private var timePickerSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            Text("Duration")
                .font(.system(size: IkeruTheme.Typography.Size.heading3, weight: .semibold))
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: IkeruTheme.Spacing.sm) {
                    ForEach(configViewModel.timePresets, id: \.minutes) { preset in
                        timePresetButton(label: preset.label, minutes: preset.minutes)
                    }
                }
                .padding(.horizontal, IkeruTheme.Spacing.xs)
            }
        }
    }

    @ViewBuilder
    private func timePresetButton(label: String, minutes: Int) -> some View {
        let isSelected = configViewModel.selectedMinutes == minutes

        Button {
            Task {
                await configViewModel.selectTime(minutes)
            }
        } label: {
            VStack(spacing: IkeruTheme.Spacing.xs) {
                Text(label)
                    .font(.system(size: IkeruTheme.Typography.Size.stats, weight: .medium))

                Text("\(minutes)m")
                    .font(.system(size: IkeruTheme.Typography.Size.caption))
            }
            .frame(minWidth: 64, minHeight: 56)
            .foregroundStyle(isSelected ? .white : Color.ikeruTextSecondary)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
                        .fill(Color.ikeruPrimaryAccent)
                } else {
                    RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
                        .fill(Color.ikeruSurface)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm))
        }
        .animation(.easeInOut(duration: IkeruTheme.Animation.quickDuration), value: isSelected)
    }

    // MARK: - Silent Mode Banner

    @ViewBuilder
    private var silentModeBanner: some View {
        if configViewModel.isMuted {
            HStack(spacing: IkeruTheme.Spacing.sm) {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: IkeruTheme.Typography.Size.body))

                Text("Audio exercises excluded")
                    .font(.system(size: IkeruTheme.Typography.Size.stats))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, IkeruTheme.Spacing.sm)
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .background(Color.ikeruSecondaryAccent.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm))
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(
                .easeInOut(duration: IkeruTheme.Animation.standardDuration),
                value: configViewModel.isMuted
            )
        }
    }

    // MARK: - Preview Section

    @ViewBuilder
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            Text("Session Preview")
                .font(.system(size: IkeruTheme.Typography.Size.heading3, weight: .semibold))
                .foregroundStyle(.white)

            if configViewModel.previewLoading {
                ProgressView()
                    .tint(Color.ikeruPrimaryAccent)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                SessionPreviewCard(preview: configViewModel.preview)
            }

            durationTierHint
        }
    }

    @ViewBuilder
    private var durationTierHint: some View {
        let duration = SessionDuration.from(minutes: configViewModel.selectedMinutes)
        let hint: String = switch duration {
        case .micro: "Micro session: SRS reviews only"
        case .short: "Short session: SRS + one skill exercise"
        case .standard: "Standard session: mixed skill exercises"
        case .focused: "Focused session: all skills represented"
        }

        Text(hint)
            .font(.system(size: IkeruTheme.Typography.Size.caption))
            .foregroundStyle(Color.ikeruTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Start Button

    @ViewBuilder
    private var startButton: some View {
        Button {
            let config = configViewModel.buildConfig()
            onStartSession(config)
        } label: {
            Text("Start Session")
                .frame(maxWidth: .infinity)
        }
        .ikeruButtonStyle(.primary)
        .padding(.top, IkeruTheme.Spacing.sm)
    }
}

// MARK: - Preview

#Preview("Session Config View") {
    let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let repo = CardRepository(modelContainer: container)
    let planner = PlannerService(cardRepository: repo)
    let mockVolume = MockVolumeDetector(volume: 0.5)
    let vm = SessionConfigViewModel(
        volumeDetector: mockVolume,
        plannerService: planner
    )

    SessionConfigView(configViewModel: vm) { sessionConfig in
        print("Start session with config: \(sessionConfig)")
    }
    .preferredColorScheme(.dark)
}
