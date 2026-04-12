import Foundation
import CryptoKit
import SwiftData
import os

// MARK: - AssetCache
//
// Content-addressed local cache for binary assets fetched from the rig server.
//
// Layout on disk:
//   <Caches>/ikeru-assets/<hash[:2]>/<hash>.<ext>
//
// The two-character prefix directory keeps any single folder from growing past
// a few hundred files even if the cache hits its quota.
//
// Eviction is LRU based on `AssetManifest.lastAccessedAt`, triggered either:
//   - manually via `evictIfNeeded()` (e.g. on app launch)
//   - synchronously inside `store()` if the new asset would push the total
//     over the configured quota
//
// All disk operations are synchronous because they're tiny — even on a slow
// device, writing a 14 KB opus file is sub-millisecond.

public final class AssetCache: @unchecked Sendable {

    // MARK: - Configuration

    public struct Configuration: Sendable {
        public var quotaBytes: Int
        public var rootDirectory: URL

        public init(quotaBytes: Int, rootDirectory: URL) {
            self.quotaBytes = quotaBytes
            self.rootDirectory = rootDirectory
        }

        public static let defaultQuotaBytes: Int = 500 * 1024 * 1024 // 500 MB

        /// Default cache rooted at `<Caches>/ikeru-assets`.
        public static func `default`(quotaBytes: Int = defaultQuotaBytes) -> Configuration {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            return Configuration(
                quotaBytes: quotaBytes,
                rootDirectory: caches.appendingPathComponent("ikeru-assets", isDirectory: true)
            )
        }
    }

    // MARK: - Properties

    public private(set) var configuration: Configuration

    private let modelContainer: ModelContainer
    private let fileManager: FileManager

    public init(
        configuration: Configuration = .default(),
        modelContainer: ModelContainer,
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.modelContainer = modelContainer
        self.fileManager = fileManager
        try? fileManager.createDirectory(
            at: configuration.rootDirectory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Public configuration mutation

    public func updateQuota(_ bytes: Int) {
        configuration.quotaBytes = max(50 * 1024 * 1024, bytes) // never below 50 MB
        evictIfNeeded()
    }

    // MARK: - Hashing

    /// Stable content hash from a stable string seed (caller decides what to hash).
    public static func hash(of seed: String) -> String {
        let data = Data(seed.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined().prefix(32).lowercased()
    }

    // MARK: - Read

    public func contains(hash: String) -> Bool {
        fileManager.fileExists(atPath: location(for: hash, type: .audioOpus).path)
            || fileManager.fileExists(atPath: location(for: hash, type: .imagePng).path)
            || fileManager.fileExists(atPath: location(for: hash, type: .textPlain).path)
    }

    /// Returns a local file URL for a cached asset and touches its `lastAccessedAt`.
    public func read(hash: String, type: AssetType) -> URL? {
        let url = location(for: hash, type: type)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        touch(hash: hash)
        return url
    }

    // MARK: - Write

    /// Stores the given binary data, creates or updates the manifest entry,
    /// then runs eviction if the total now exceeds quota.
    @discardableResult
    public func store(
        hash: String,
        type: AssetType,
        data: Data,
        sourceText: String? = nil
    ) throws -> URL {
        let url = location(for: hash, type: type)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)

        let context = ModelContext(modelContainer)
        let manifests = (try? context.fetch(FetchDescriptor<AssetManifest>())) ?? []
        if let existing = manifests.first(where: { $0.hash == hash }) {
            existing.sizeBytes = data.count
            existing.lastAccessedAt = Date()
            existing.sourceText = sourceText ?? existing.sourceText
        } else {
            let manifest = AssetManifest(
                hash: hash,
                type: type,
                sizeBytes: data.count,
                sourceText: sourceText
            )
            context.insert(manifest)
        }
        try context.save()

        evictIfNeeded()
        return url
    }

    // MARK: - Eviction

    /// Removes the oldest manifest entries (and their files) until the total
    /// is back under quota.
    public func evictIfNeeded() {
        let context = ModelContext(modelContainer)
        guard let unsorted = try? context.fetch(FetchDescriptor<AssetManifest>()) else { return }
        let manifests = unsorted.sorted { $0.lastAccessedAt < $1.lastAccessedAt }

        var total = manifests.reduce(0) { $0 + $1.sizeBytes }
        guard total > configuration.quotaBytes else { return }

        for manifest in manifests {
            if total <= configuration.quotaBytes { break }
            let url = location(for: manifest.hash, type: manifest.type)
            try? fileManager.removeItem(at: url)
            context.delete(manifest)
            total -= manifest.sizeBytes
            Logger.cache.info("Evicted asset \(manifest.hash) (\(manifest.sizeBytes) bytes)")
        }
        try? context.save()
    }

    /// Clears every cached asset and every manifest row.
    public func clearAll() {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<AssetManifest>()
        if let manifests = try? context.fetch(descriptor) {
            for manifest in manifests {
                let url = location(for: manifest.hash, type: manifest.type)
                try? fileManager.removeItem(at: url)
                context.delete(manifest)
            }
            try? context.save()
        }
        // Also remove any orphan files left behind by interrupted writes
        try? fileManager.removeItem(at: configuration.rootDirectory)
        try? fileManager.createDirectory(
            at: configuration.rootDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Removes manifest entries older than `olderThan` (last accessed).
    public func clearStale(olderThan: TimeInterval) {
        let cutoff = Date().addingTimeInterval(-olderThan)
        let context = ModelContext(modelContainer)
        guard let manifests = try? context.fetch(FetchDescriptor<AssetManifest>()) else { return }
        let stale = manifests.filter { $0.lastAccessedAt < cutoff }
        for manifest in stale {
            let url = location(for: manifest.hash, type: manifest.type)
            try? fileManager.removeItem(at: url)
            context.delete(manifest)
        }
        try? context.save()
    }

    // MARK: - Stats

    public struct Stats: Sendable {
        public let totalBytes: Int
        public let entryCount: Int
        public let breakdown: [AssetType: Int]
    }

    public func stats() -> Stats {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<AssetManifest>()
        let manifests = (try? context.fetch(descriptor)) ?? []
        var total = 0
        var breakdown: [AssetType: Int] = [:]
        for manifest in manifests {
            total += manifest.sizeBytes
            breakdown[manifest.type, default: 0] += manifest.sizeBytes
        }
        return Stats(totalBytes: total, entryCount: manifests.count, breakdown: breakdown)
    }

    // MARK: - Internals

    private func touch(hash: String) {
        let context = ModelContext(modelContainer)
        guard let manifests = try? context.fetch(FetchDescriptor<AssetManifest>()) else { return }
        if let manifest = manifests.first(where: { $0.hash == hash }) {
            manifest.lastAccessedAt = Date()
            try? context.save()
        }
    }

    private func location(for hash: String, type: AssetType) -> URL {
        let prefix = String(hash.prefix(2))
        return configuration.rootDirectory
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent("\(hash).\(type.fileExtension)")
    }
}

// MARK: - os.Logger extension

extension Logger {
    /// Subsystem-scoped logger for the asset cache.
    public static let cache = Logger(subsystem: "com.ikeru.app", category: "cache")
}
