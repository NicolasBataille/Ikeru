import Foundation

// MARK: - StoreRecovery

/// Pure, `FileManager`-injectable logic for recovering from a corrupted or
/// unopenable SwiftData store at app launch.
///
/// Conservative by design: nothing is ever deleted. The store's file set is
/// moved aside into a fresh, timestamped sibling directory so the app can
/// retry with an empty store while every byte of the user's original data is
/// preserved on-device for later export or support triage (see
/// `DataExportManager`).
///
/// Operates on the store's actual **file URL** (obtained from the same
/// `ModelConfiguration` the container opens — see
/// `IkeruApp.storeConfiguration(schema:)`), NOT a guessed directory: SwiftData
/// places the named `"Ikeru"` configuration's files (`Ikeru.store` plus its
/// `-shm`/`-wal`/`-journal` SQLite siblings) directly in Application Support,
/// not in a per-bundle subdirectory.
///
/// Kept as a standalone type — rather than inline in `IkeruApp.init` — purely
/// so the path-shuffling logic is unit-testable with an injected `FileManager`
/// and temporary directories, without needing a real `ModelContainer`.
enum StoreRecovery {

    /// SQLite sidecar suffixes that can accompany the main store file.
    private static let sidecarSuffixes = ["-shm", "-wal", "-journal"]

    /// ISO8601 with a filesystem-safe stamp (colons replaced with dashes —
    /// `:` is legal in HFS+/APFS filenames but awkward to read/select in
    /// Finder and in Console log lines).
    static func recoveryDestination(
        near storeURL: URL,
        now: Date = Date()
    ) -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: now).replacingOccurrences(of: ":", with: "-")
        return storeURL
            .deletingLastPathComponent()
            .appendingPathComponent("IkeruStore-recovery-\(stamp)", isDirectory: true)
    }

    /// Every file belonging to the store at `storeURL` that currently exists
    /// on disk: the main file plus any SQLite sidecars (`-shm`, `-wal`,
    /// `-journal`).
    static func existingStoreFiles(
        for storeURL: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        let candidates = [storeURL] + sidecarSuffixes.map { suffix in
            let sibling = storeURL.lastPathComponent + suffix
            return storeURL.deletingLastPathComponent().appendingPathComponent(sibling)
        }
        return candidates.filter { fileManager.fileExists(atPath: $0.path) }
    }

    /// Moves the store's file set aside (if any of it exists) into a fresh
    /// timestamped sibling directory computed by
    /// `recoveryDestination(near:now:)`, so a subsequent `ModelContainer`
    /// open can write a brand-new store at the original URL.
    ///
    /// - Returns: the recovery directory's URL when something was actually
    ///   preserved, or `nil` when no store files existed yet (e.g. a fresh
    ///   install whose container creation failed for an unrelated reason).
    /// - Throws: whatever `fileManager.createDirectory`/`moveItem` throws.
    ///   The caller is expected to treat a throw here as fatal — recovery
    ///   itself failing means the filesystem is in a state this code cannot
    ///   reason about further.
    @discardableResult
    static func moveStoreAside(
        storeURL: URL,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> URL? {
        let files = existingStoreFiles(for: storeURL, fileManager: fileManager)
        guard !files.isEmpty else { return nil }

        let destination = recoveryDestination(near: storeURL, now: now)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for file in files {
            try fileManager.moveItem(
                at: file,
                to: destination.appendingPathComponent(file.lastPathComponent)
            )
        }
        return destination
    }
}
