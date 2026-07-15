import Testing
import Foundation
@testable import Ikeru

/// Coverage for remediation ITEM B — the conservative store-recovery
/// move-aside logic. Exercises `StoreRecovery` with real temporary
/// directories (pure Foundation, no `ModelContainer` involved) so the
/// path-shuffling behaviour is verified without ever touching the app's real
/// Application Support store.
@Suite("StoreRecovery")
struct StoreRecoveryTests {

    /// A fresh, unique scratch directory per test, cleaned up afterwards.
    private func scratchDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("moveStoreAside preserves the whole file set and clears the original location")
    func moveStoreAsidePreservesFiles() throws {
        let scratch = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        // Named-configuration layout: the store files sit DIRECTLY in the
        // Application Support root (here: scratch), no per-bundle subdir.
        let storeURL = scratch.appendingPathComponent("Ikeru.store")
        let walURL = scratch.appendingPathComponent("Ikeru.store-wal")
        let shmURL = scratch.appendingPathComponent("Ikeru.store-shm")
        try Data("original store bytes".utf8).write(to: storeURL)
        try Data("wal bytes".utf8).write(to: walURL)
        try Data("shm bytes".utf8).write(to: shmURL)
        // An unrelated neighbour that must NOT be swept up by recovery.
        let unrelated = scratch.appendingPathComponent("unrelated.txt")
        try Data("leave me".utf8).write(to: unrelated)

        let destination = try StoreRecovery.moveStoreAside(
            storeURL: storeURL,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let recoveryDir = try #require(destination)

        // Nothing was deleted — all three files exist, byte-identical, at the new location.
        let recoveredStore = try Data(contentsOf: recoveryDir.appendingPathComponent("Ikeru.store"))
        let recoveredWal = try Data(contentsOf: recoveryDir.appendingPathComponent("Ikeru.store-wal"))
        let recoveredShm = try Data(contentsOf: recoveryDir.appendingPathComponent("Ikeru.store-shm"))
        #expect(String(data: recoveredStore, encoding: .utf8) == "original store bytes")
        #expect(String(data: recoveredWal, encoding: .utf8) == "wal bytes")
        #expect(String(data: recoveredShm, encoding: .utf8) == "shm bytes")

        // The original store files are gone from their old location (fresh
        // container can create a new store), but the unrelated neighbour and
        // the parent directory itself are untouched.
        #expect(!FileManager.default.fileExists(atPath: storeURL.path))
        #expect(!FileManager.default.fileExists(atPath: walURL.path))
        #expect(!FileManager.default.fileExists(atPath: shmURL.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))

        // The recovery directory is a SIBLING of the store file (inside the
        // same parent), not nested anywhere surprising.
        #expect(recoveryDir.deletingLastPathComponent().path == scratch.path)
    }

    @Test("moveStoreAside returns nil when no store files exist yet (fresh install)")
    func moveStoreAsideNilOnMissingStore() throws {
        let scratch = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let storeURL = scratch.appendingPathComponent("Ikeru.store")
        #expect(!FileManager.default.fileExists(atPath: storeURL.path))

        let destination = try StoreRecovery.moveStoreAside(storeURL: storeURL)
        #expect(destination == nil)

        // No recovery directory was created for nothing.
        let contents = try FileManager.default.contentsOfDirectory(atPath: scratch.path)
        #expect(contents.isEmpty)
    }

    @Test("existingStoreFiles finds only the store's own file set")
    func existingStoreFilesScoping() throws {
        let scratch = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let storeURL = scratch.appendingPathComponent("Ikeru.store")
        try Data("s".utf8).write(to: storeURL)
        try Data("w".utf8).write(to: scratch.appendingPathComponent("Ikeru.store-wal"))
        try Data("x".utf8).write(to: scratch.appendingPathComponent("Other.store"))

        let files = StoreRecovery.existingStoreFiles(for: storeURL)
        let names = Set(files.map(\.lastPathComponent))
        #expect(names == ["Ikeru.store", "Ikeru.store-wal"])
    }

    @Test("recoveryDestination names a timestamped sibling with no raw colons")
    func recoveryDestinationNaming() {
        let storeURL = URL(fileURLWithPath: "/tmp/Application Support/Ikeru.store")
        let destination = StoreRecovery.recoveryDestination(
            near: storeURL,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(destination.deletingLastPathComponent().path == storeURL.deletingLastPathComponent().path)
        #expect(destination.lastPathComponent.hasPrefix("IkeruStore-recovery-"))
        #expect(!destination.lastPathComponent.contains(":"))
    }

    @Test("two recoveries at different times never collide on the same destination")
    func recoveryDestinationIsTimeDependent() {
        let storeURL = URL(fileURLWithPath: "/tmp/Application Support/Ikeru.store")
        let first = StoreRecovery.recoveryDestination(
            near: storeURL, now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let second = StoreRecovery.recoveryDestination(
            near: storeURL, now: Date(timeIntervalSince1970: 1_700_000_060)
        )
        #expect(first != second)
    }
}

// MARK: - StoreRecoveryNotice

@Suite("StoreRecoveryNotice")
struct StoreRecoveryNoticeTests {

    @Test("isPending is false until markPending is called, then true, then acknowledged clears it")
    func pendingLifecycle() throws {
        let suiteName = "com.ikeru.tests.storerecoverynotice.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(!StoreRecoveryNotice.isPending(defaults: defaults))

        let recoveryDir = URL(fileURLWithPath: "/tmp/IkeruStore-recovery-test")
        StoreRecoveryNotice.markPending(recoveryDirectory: recoveryDir, defaults: defaults)

        #expect(StoreRecoveryNotice.isPending(defaults: defaults))
        #expect(StoreRecoveryNotice.recoveryPath(defaults: defaults) == recoveryDir.path)

        StoreRecoveryNotice.acknowledge(defaults: defaults)
        #expect(!StoreRecoveryNotice.isPending(defaults: defaults))
    }
}
