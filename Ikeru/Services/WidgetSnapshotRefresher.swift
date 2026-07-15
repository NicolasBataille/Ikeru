import Foundation
import SwiftData
import WidgetKit
import IkeruCore
import os

/// Recomputes the shared widget snapshot (`WidgetSnapshotStore`, in `Shared/`)
/// from the active profile's current state and asks WidgetKit to reload every
/// timeline. Called from the only two places the data the widgets render
/// (due count, level, last-study date) can change: end of a study session
/// (`SessionViewModel.finalizeSession`) and app foreground/launch
/// (`IkeruApp`).
@MainActor
enum WidgetSnapshotRefresher {

    /// Minimum interval between non-forced refreshes. scenePhase flips to
    /// `.active` on every app switch — without this, frequent switching burns
    /// redundant due-card queries and WidgetKit's per-day reload budget.
    private static let debounceInterval: TimeInterval = 60
    private static var lastRefresh: Date?

    /// No-op if there is no active profile / RPG state yet (e.g. before the
    /// user has completed onboarding) — the widgets keep showing their
    /// placeholder fallback in that case.
    ///
    /// - Parameter force: bypasses the debounce — used at session end, where
    ///   the due count has definitely changed and must be written.
    static func refresh(modelContainer: ModelContainer, force: Bool = false) async {
        if !force, let last = lastRefresh, Date().timeIntervalSince(last) < debounceInterval {
            return
        }
        lastRefresh = Date()

        let context = modelContainer.mainContext
        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else { return }

        let repository = CardRepository(modelContainer: modelContainer)
        let dueCount = await repository.dueCards(before: Date()).count

        WidgetSnapshotStore.write(
            dueCount: dueCount,
            level: state.level,
            lastStudyDate: state.lastSessionDate
        )
        WidgetCenter.shared.reloadAllTimelines()
        Logger.ui.info(
            "widget.snapshot.refreshed dueCount=\(dueCount, privacy: .public) level=\(state.level, privacy: .public)"
        )
    }
}
