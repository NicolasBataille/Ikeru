import Foundation
import SwiftData
import os

// MARK: - PreWarmService
//
// Background pre-warmer for SRS-due audio. Queries the card repository for
// cards due within a window, computes the rig audio cache hash for each
// front, and enqueues TTS jobs only for cache misses. Throttled to at most
// 50 enqueues per call and one successful call per hour.
//
// All collaborators are injected via small Sendable protocols so tests can
// substitute fakes without touching SwiftData, the network, or the disk.

// MARK: - Collaborator protocols

public protocol PreWarmCardSource: Sendable {
    /// Returns the front text of every card due before `date`.
    ///
    /// Ordering contract: implementations MUST return fronts sorted by the
    /// underlying card `dueDate` in ascending order, so that overdue cards
    /// (oldest first) are pre-warmed before cards due later. `PreWarmService`
    /// relies on this order when capping the per-call batch.
    func dueCards(before date: Date) async -> [String]
}

public protocol PreWarmCacheLookup: Sendable {
    func contains(hash: String) -> Bool
}

public protocol PreWarmEnqueuer: Sendable {
    func enqueue(text: String, speaker: Int) async throws
}

// MARK: - Default adapters

public struct CardRepositoryPreWarmSource: PreWarmCardSource {
    private let repository: CardRepository

    public init(repository: CardRepository) {
        self.repository = repository
    }

    public func dueCards(before date: Date) async -> [String] {
        let cards = await repository.dueCards(before: date)
        return cards.sorted { $0.dueDate < $1.dueDate }.map(\.front)
    }
}

public struct AssetCachePreWarmLookup: PreWarmCacheLookup {
    private let cache: AssetCache

    public init(cache: AssetCache) {
        self.cache = cache
    }

    public func contains(hash: String) -> Bool {
        cache.contains(hash: hash)
    }
}

public struct RigClientPreWarmEnqueuer: PreWarmEnqueuer {
    private let client: RigClient

    public init(client: RigClient) {
        self.client = client
    }

    public func enqueue(text: String, speaker: Int) async throws {
        _ = try await client.enqueueJob(.tts(text: text, speaker: speaker))
    }
}

// MARK: - PreWarmService

public actor PreWarmService {

    /// Maximum jobs enqueued per `enqueueUpcomingDueAudio` invocation.
    public static let maxJobsPerCall = 50

    /// Minimum interval between two successful (non-throttled) calls.
    public static let minimumCallInterval: TimeInterval = 60 * 60 // 1 hour

    /// Default voicevox speaker used when computing cache hashes and TTS jobs.
    public static let defaultSpeaker = 3

    private let cardSource: any PreWarmCardSource
    private let cacheLookup: any PreWarmCacheLookup
    private let enqueuer: any PreWarmEnqueuer
    private let clock: @Sendable () -> Date

    private var lastCallAt: Date?

    public init(
        cardSource: any PreWarmCardSource,
        cacheLookup: any PreWarmCacheLookup,
        enqueuer: any PreWarmEnqueuer,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.cardSource = cardSource
        self.cacheLookup = cacheLookup
        self.enqueuer = enqueuer
        self.clock = clock
    }

    /// Convenience init that wires the production adapters around the
    /// concrete repository, cache, and rig client.
    public init(
        repository: CardRepository,
        cache: AssetCache,
        client: RigClient,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(
            cardSource: CardRepositoryPreWarmSource(repository: repository),
            cacheLookup: AssetCachePreWarmLookup(cache: cache),
            enqueuer: RigClientPreWarmEnqueuer(client: client),
            clock: clock
        )
    }

    /// Queries due cards within `[now, now + window]`, skips cache hits,
    /// and enqueues TTS jobs for misses up to the per-call cap.
    /// No-ops if called within `minimumCallInterval` of the previous run.
    public func enqueueUpcomingDueAudio(window: TimeInterval) async throws {
        let now = clock()

        if let last = lastCallAt, now.timeIntervalSince(last) < Self.minimumCallInterval {
            Logger.cache.info("PreWarm: throttled (last call within 1h)")
            return
        }

        let horizon = now.addingTimeInterval(window)
        let fronts = await cardSource.dueCards(before: horizon)
        let total = fronts.count

        var misses = 0
        var enqueued = 0

        for text in fronts {
            try Task.checkCancellation()
            if enqueued >= Self.maxJobsPerCall { break }

            let hash = RigAudioCoordinator.makeHash(
                text: text,
                speaker: Self.defaultSpeaker
            )
            if cacheLookup.contains(hash: hash) {
                continue
            }
            misses += 1

            do {
                try await enqueuer.enqueue(text: text, speaker: Self.defaultSpeaker)
                enqueued += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Logger.cache.error("PreWarm: enqueue failed for \(text.prefix(20), privacy: .private): \(String(describing: error))")
            }
        }

        if enqueued > 0 {
            lastCallAt = now
            Logger.cache.info("PreWarm: \(enqueued)/\(misses)/\(total) jobs enqueued")
        } else {
            Logger.cache.debug("PreWarm: nothing to enqueue, throttle not armed")
        }
    }

    // MARK: - Factory

    /// Builds a `PreWarmService` wired to production dependencies.
    /// Used by the app layer (`PreWarmFactory`) as the single integration seam.
    public static func makeDefault(
        modelContainer: ModelContainer,
        assetCache: AssetCache,
        rigSettings: RigSettings
    ) -> PreWarmService {
        let repository = CardRepository(modelContainer: modelContainer)
        let client = RigClient(configuration: rigSettings)
        return PreWarmService(
            repository: repository,
            cache: assetCache,
            client: client
        )
    }

    // MARK: - Test helpers

    /// Exposed for tests that want to inspect the throttle state.
    public func lastCallTimestamp() -> Date? { lastCallAt }
}
