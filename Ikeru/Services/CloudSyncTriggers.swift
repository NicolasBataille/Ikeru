import Foundation
import Network
import SwiftData
import IkeruCore
import os

/// Wires the cloud-sync push triggers from
/// `docs/design-specs/2026-08-10-cloud-sync-design.md` §5.2 onto real
/// app-lifecycle events. `CloudSyncCoordinator.syncNow()` already owns every
/// policy decision that matters here — the opt-in consent gate and the
/// `minSyncInterval` throttle — so this type is nothing but call sites: it
/// decides *when* to ask, never *whether* a push actually happens. Nothing
/// here can make a network call `syncNow()` itself would refuse.
///
/// Two of the spec's three triggers are wired end-to-end from this lot:
/// - **Foreground** — `triggerForegroundSync()`, called from `IkeruApp`'s
///   `onChange(of: scenePhase)` when the new phase is `.active`.
/// - **Network regain** — the `NWPathMonitor` below, which fires only on an
///   unavailable → available transition, never on every path update (an
///   already-online interface change would otherwise re-trigger constantly).
///
/// The third — **session end** — is NOT wired by this lot. Its real hook is
/// `SessionRPGPersistence.finalize(...)` at
/// `Ikeru/ViewModels/Session/SessionRPGPersistence.swift:246`, which already
/// calls `WidgetSnapshotRefresher.refresh(...)` at the session's true
/// persistence point — but that file lives in `Ikeru/ViewModels/Session/`,
/// outside this lot's file perimeter (`Ikeru/Services/` and
/// `IkeruApp.swift` only). `triggerSessionEndSync()` is provided below,
/// pre-emptively, so wiring it later is a single added call at that
/// call site, not a new type — but as of this lot it has **no caller** and
/// does not fire.
@MainActor
public final class CloudSyncTriggers {

    public static let shared = CloudSyncTriggers()

    private var coordinator: CloudSyncCoordinator?
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.ikeru.cloudSync.pathMonitor")
    /// Previous path state, so the network-regain trigger fires only on the
    /// unavailable → available edge, never on every `pathUpdateHandler` call.
    private var wasPathUnavailable = false

    private init() {}

    /// Call once, early in app launch, once the `ModelContainer` exists.
    /// Builds the coordinator and starts the network monitor. Safe to call
    /// more than once — later calls are no-ops.
    public func start(modelContainer: ModelContainer) {
        _ = sharedCoordinator(modelContainer: modelContainer)
        startNetworkMonitorIfNeeded()
    }

    /// Returns the ONE shared `CloudSyncCoordinator`, building it on first
    /// call if `start(modelContainer:)` hasn't run yet. This is now the
    /// only way any part of the app obtains a coordinator — `SettingsView`
    /// calls this too (post-review fix for a duplicate-`ReviewLog` bug: two
    /// independently-constructed coordinators over the same
    /// `ModelContainer` each ran their own `SyncPullActor`, and the
    /// `UserDefaults`-based throttle in `CloudSyncCoordinator.syncNow()` is
    /// a read-then-write across two different actor instances — not atomic,
    /// and never intended as a cross-instance mutex). Returning the SAME
    /// instance to every caller means `CloudSyncCoordinator`'s own
    /// `isSyncing` reentrance guard (actor-isolated, genuinely atomic) is
    /// the only anti-reentrance mechanism that has to work — there is no
    /// second instance left for it to fail to protect against.
    public func sharedCoordinator(modelContainer: ModelContainer) -> CloudSyncCoordinator {
        if let coordinator { return coordinator }
        let created = CloudSyncCoordinator(modelContainer: modelContainer)
        coordinator = created
        return created
    }

    // MARK: - Trigger: foreground

    /// Call from `onChange(of: scenePhase)` when the new phase is `.active`.
    public func triggerForegroundSync() {
        fireSync(reason: "foreground")
    }

    // MARK: - Trigger: session end (provided, not yet called — see type doc)

    /// Call at the true end of a learning session. Not invoked anywhere in
    /// this lot; see the type doc comment for the hook this is meant for.
    public func triggerSessionEndSync() {
        fireSync(reason: "session-end")
    }

    // MARK: - Trigger: network regain

    private func startNetworkMonitorIfNeeded() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let isSatisfied = path.status == .satisfied
            Task { @MainActor in
                self?.handlePathUpdate(isSatisfied: isSatisfied)
            }
        }
        monitor.start(queue: monitorQueue)
        pathMonitor = monitor
    }

    private func handlePathUpdate(isSatisfied: Bool) {
        defer { wasPathUnavailable = !isSatisfied }
        guard isSatisfied, wasPathUnavailable else { return }
        fireSync(reason: "network-regained")
    }

    // MARK: - Shared push

    /// Detached so no caller — scenePhase change, path-monitor callback, or
    /// (once wired) session end — ever waits on network I/O on a rendering
    /// path. Never bypasses `syncNow()`'s own consent/throttle checks.
    private func fireSync(reason: String) {
        guard let coordinator else { return }
        Logger.sync.debug("Cloud sync trigger fired: \(reason, privacy: .public)")
        Task.detached(priority: .utility) {
            await coordinator.syncNow()
        }
    }
}
