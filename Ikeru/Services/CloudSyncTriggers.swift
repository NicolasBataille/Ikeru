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

    /// The ONE `AnonymousIdentityManager` instance `sharedCoordinator(...)`
    /// wires into `CloudSyncCoordinator` below — see `sharedIdentityManager`'s
    /// doc comment (lot 3, Mineur #7 remediation) for why every Apple-linking
    /// call site (`SettingsView`, `AppleSignInFlow`) must go through THIS
    /// instance rather than constructing a fresh `AnonymousIdentityManager()`
    /// of their own. Built once, here, at singleton construction — same
    /// lifetime as `coordinator`.
    private let identityManager = AnonymousIdentityManager()

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
        let created = CloudSyncCoordinator(modelContainer: modelContainer, identity: identityManager)
        coordinator = created
        return created
    }

    /// The SAME `AnonymousIdentityManager` instance `sharedCoordinator(...)`
    /// wires into `CloudSyncCoordinator` — Apple-linking call sites
    /// (`SettingsView`'s Sign in with Apple row, `AppleSignInFlow`) must
    /// obtain their identity manager from here, never from a freshly
    /// constructed `AnonymousIdentityManager()` (lot 3, Mineur #7
    /// remediation).
    ///
    /// `AnonymousIdentityManager` caches its loaded `SyncSession` in memory
    /// (`cachedSession`, up to ~1h before its own freshness check forces a
    /// reload) — two independent instances therefore do NOT observe each
    /// other's writes until that cache naturally expires. Before this fix, a
    /// tap on "Sign in with Apple" built its own `AnonymousIdentityManager()`,
    /// linked the Apple identity through IT, and persisted the new session to
    /// the Keychain — but `CloudSyncCoordinator`'s own, separate manager
    /// instance kept serving its already-cached (old) anonymous session for
    /// up to an hour, so the very next `syncNow()` (foreground trigger,
    /// network regain, or the toggle itself) still pushed to the OLD
    /// account. It converged eventually — the Keychain write was correct —
    /// but "eventually" here meant up to an hour of the learner's fresh
    /// progress silently going to the wrong place. Sharing one instance
    /// means the coordinator sees the freshly linked session on its very
    /// next call, same process, no cache staleness window at all.
    public var sharedIdentityManager: AnonymousIdentityManager { identityManager }

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
