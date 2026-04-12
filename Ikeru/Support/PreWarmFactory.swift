import Foundation
import SwiftData
import IkeruCore
import os

/// Factory + cache that wires the real `PreWarmService` from the app-level
/// dependencies (model container, asset cache, rig client/settings).
///
/// Lifecycle:
/// - A single `PreWarmService` instance is cached on the main actor for the
///   lifetime of the process. Subsequent calls to `make(...)` return the same
///   actor instance so its in-memory throttle state (`lastCallAt`) survives
///   across BG-task invocations, manual "Pre-warm now" taps, etc.
/// - The cached instance is invalidated and rebuilt when either the
///   `AssetCache` or the resolved `RigSettings` changes identity/value, which
///   happens e.g. after the user re-configures the rig in Settings.
/// - Keychain reads happen on the main actor; if the keychain is locked
///   (immediately after a cold reboot, before the user has unlocked the
///   device) `RigSettingsStore().load()` returns `nil` and we log+return nil
///   so the caller can skip this invocation and try again later. The next
///   `make(...)` call will retry the keychain read from scratch.
@MainActor
enum PreWarmFactory {

    private static var cached: PreWarmService?
    private static var cachedAssetCacheID: ObjectIdentifier?
    private static var cachedRigSettings: RigSettings?

    /// Build (or return the cached) `PreWarmService` from currently available
    /// app dependencies. Returns `nil` if any required dependency is missing
    /// or the keychain is currently locked.
    static func make(
        modelContainer: ModelContainer,
        assetCache: AssetCache?
    ) -> PreWarmService? {
        guard let assetCache else {
            Logger.cache.warning("PreWarmFactory: asset cache not initialised")
            return nil
        }

        // Keychain-locked-after-reboot scenario: before the user first
        // unlocks the device, protected keychain items are unreadable and
        // `RigSettingsStore().load()` returns `nil`. We treat that the same
        // as "not configured yet" — log a warning and bail. The caller
        // retries on a later tick.
        guard let rigSettings = RigSettingsStore().load() else {
            Logger.cache.warning("PreWarm: rig settings unavailable, cannot pre-warm (Keychain locked or not configured)")
            return nil
        }

        guard rigSettings.isConfigured else {
            Logger.cache.warning("PreWarmFactory: rig settings not configured")
            return nil
        }

        let assetCacheID = ObjectIdentifier(assetCache)
        if let cached,
           cachedAssetCacheID == assetCacheID,
           cachedRigSettings == rigSettings {
            return cached
        }

        let service = PreWarmService.makeDefault(
            modelContainer: modelContainer,
            assetCache: assetCache,
            rigSettings: rigSettings
        )
        cached = service
        cachedAssetCacheID = assetCacheID
        cachedRigSettings = rigSettings
        return service
    }
}
