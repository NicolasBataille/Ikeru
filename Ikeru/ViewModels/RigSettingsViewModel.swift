import Foundation
import IkeruCore
import Observation
import SwiftData
import os

// MARK: - RigSettingsViewModel
//
// Drives the "Local Rig" section of `AISettingsView` and the "Asset Cache"
// section of `SettingsView`. Holds:
//   - the current `RigSettings` (URL + token) loaded from `RigSettingsStore`
//   - the `/health` probe result, refreshed on demand
//   - the `AssetCache.Stats` snapshot for the cache UI
//   - the user-facing edit buffers for the URL and token fields
//
// All persistence goes through `RigSettingsStore` and `AssetCache` — this
// view-model holds no state of its own that survives a logout.

@Observable
@MainActor
public final class RigSettingsViewModel {

    // MARK: - Inputs

    public var urlInput: String = ""
    public var tokenInput: String = ""
    public var isProbing: Bool = false
    public private(set) var probedHealth: RigHealth?
    public private(set) var probeError: String?
    public private(set) var stats: AssetCache.Stats?
    public private(set) var quotaBytes: Int

    // MARK: - Dependencies

    @ObservationIgnored
    private let store: RigSettingsStore
    @ObservationIgnored
    private let cache: AssetCache

    // MARK: - Init

    public init(store: RigSettingsStore = RigSettingsStore(), cache: AssetCache) {
        self.store = store
        self.cache = cache
        self.quotaBytes = cache.configuration.quotaBytes

        if let existing = store.load() {
            self.urlInput = existing.baseURL.absoluteString
            self.tokenInput = existing.sharedToken
        }
        refreshStats()
    }

    // MARK: - Actions

    public func save() throws {
        guard let url = URL(string: urlInput.trimmingCharacters(in: .whitespacesAndNewlines)),
              !url.absoluteString.isEmpty else {
            throw RigSettingsError.invalidURL
        }
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw RigSettingsError.missingToken
        }
        let settings = RigSettings(baseURL: url, sharedToken: token)
        try store.save(settings)
    }

    public func clear() throws {
        try store.clear()
        urlInput = ""
        tokenInput = ""
        probedHealth = nil
        probeError = nil
    }

    public func probe() async {
        isProbing = true
        defer { isProbing = false }

        guard let url = URL(string: urlInput.trimmingCharacters(in: .whitespacesAndNewlines)),
              !url.absoluteString.isEmpty else {
            probeError = "Invalid URL"
            return
        }
        let settings = RigSettings(
            baseURL: url,
            sharedToken: tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let client = RigClient(configuration: settings)
        do {
            probedHealth = try await client.health()
            probeError = nil
        } catch {
            probedHealth = nil
            probeError = describe(error)
            Logger.rig.warning("Rig probe failed: \(self.probeError ?? "unknown")")
        }
    }

    // MARK: - Cache management

    public func refreshStats() {
        stats = cache.stats()
    }

    public func updateQuota(_ bytes: Int) {
        cache.updateQuota(bytes)
        quotaBytes = cache.configuration.quotaBytes
        refreshStats()
    }

    public func clearAllAssets() {
        cache.clearAll()
        refreshStats()
    }

    public func clearStaleAssets(olderThan days: Int) {
        cache.clearStale(olderThan: TimeInterval(days * 24 * 60 * 60))
        refreshStats()
    }

    // MARK: - Helpers

    private func describe(_ error: Error) -> String {
        if let rig = error as? RigError {
            switch rig {
            case .unauthorized: return "Unauthorized — check the shared token"
            case .notFound: return "Endpoint not found — is the URL correct?"
            case .timeout: return "Timed out — is the rig running?"
            case .network: return "Network error — is your iPhone on the same LAN?"
            case .invalidURL, .missingToken, .invalidResponse, .notReady, .httpStatus:
                return String(describing: rig)
            }
        }
        return error.localizedDescription
    }
}

public enum RigSettingsError: Error, Sendable {
    case invalidURL
    case missingToken
}
