import SwiftUI
import IkeruCore
import os

// MARK: - SessionConfigViewModel

/// Drives the session configuration screen where users pick session duration,
/// see a preview of the session composition, and start an adaptive session.
///
/// Observes system volume to auto-toggle silent mode and recomputes the
/// session preview whenever time or mute state changes.
@MainActor
@Observable
public final class SessionConfigViewModel {

    // MARK: - User Selections

    /// Selected session duration in minutes.
    public var selectedMinutes: Int = 20 {
        didSet {
            guard oldValue != selectedMinutes else { return }
            previewInvalidated = true
        }
    }

    /// Whether the device volume is muted (auto-detected).
    public private(set) var isMuted: Bool = false

    // MARK: - Preview State

    /// The computed session preview for the current configuration.
    public private(set) var preview: SessionPreview = .empty

    /// Whether a preview computation is in progress.
    public private(set) var previewLoading: Bool = false

    // MARK: - Time Presets

    /// Available time presets for the picker.
    public let timePresets: [(label: String, minutes: Int)] = [
        ("Quick", 5),
        ("Short", 10),
        ("Standard", 20),
        ("Focused", 30),
        ("Deep", 45)
    ]

    // MARK: - Dependencies

    private let volumeDetector: VolumeDetecting
    private let plannerService: PlannerService

    /// Tracks whether the preview needs recomputation.
    private var previewInvalidated: Bool = false

    /// Tracks the last mute state to detect changes.
    private var lastMuteState: Bool = false

    // MARK: - Init

    public init(
        volumeDetector: VolumeDetecting,
        plannerService: PlannerService
    ) {
        self.volumeDetector = volumeDetector
        self.plannerService = plannerService
    }

    // MARK: - Lifecycle

    /// Called when the view appears. Starts volume monitoring and loads initial preview.
    public func onAppear() async {
        volumeDetector.startMonitoring()
        syncMuteState()
        await refreshPreview()
    }

    /// Called when the view disappears. Stops volume monitoring.
    public func onDisappear() {
        volumeDetector.stopMonitoring()
    }

    // MARK: - Actions

    /// Selects a time preset and refreshes the preview.
    /// - Parameter minutes: The number of minutes for the session.
    public func selectTime(_ minutes: Int) async {
        selectedMinutes = minutes
        await refreshPreview()
    }

    /// Builds a `SessionConfig` from the current user selections and detected state.
    /// - Returns: A session configuration snapshot ready for `PlannerService`.
    public func buildConfig() -> SessionConfig {
        syncMuteState()
        return SessionConfig(
            availableTimeMinutes: selectedMinutes,
            isSilentMode: isMuted
        )
    }

    /// Reloads the session preview using the current configuration.
    public func refreshPreview() async {
        syncMuteState()
        previewLoading = true
        defer { previewLoading = false }

        let config = buildConfig()
        let plan = await plannerService.composeAdaptiveSession(config: config)
        let totalExercises = plan.exercises.count

        var skillSplit: [SkillType: Double] = [:]
        if totalExercises > 0 {
            for (skill, count) in plan.exerciseBreakdown {
                skillSplit[skill] = Double(count) / Double(totalExercises)
            }
        }

        preview = SessionPreview(
            estimatedMinutes: plan.estimatedDurationMinutes,
            cardCount: totalExercises,
            exerciseBreakdown: plan.exerciseBreakdown,
            skillSplit: skillSplit
        )

        previewInvalidated = false

        Logger.ui.info(
            "Session preview refreshed: \(totalExercises) exercises, ~\(plan.estimatedDurationMinutes)min, muted=\(self.isMuted)"
        )
    }

    // MARK: - Private Helpers

    /// Syncs the mute state from the volume detector.
    private func syncMuteState() {
        let detectedMute = volumeDetector.isMuted
        if detectedMute != isMuted {
            isMuted = detectedMute
            Logger.audio.debug("Mute state synced: \(detectedMute)")
        }
    }
}
