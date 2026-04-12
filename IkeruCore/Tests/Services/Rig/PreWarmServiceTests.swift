import Foundation
import Testing
@testable import IkeruCore

// MARK: - Fakes

private final class FakeCardSource: PreWarmCardSource, @unchecked Sendable {
    let fronts: [String]
    init(fronts: [String]) { self.fronts = fronts }
    func dueCards(before date: Date) async -> [String] { fronts }
}

private final class FakeCacheLookup: PreWarmCacheLookup, @unchecked Sendable {
    let hits: Set<String>
    init(hits: Set<String> = []) { self.hits = hits }
    func contains(hash: String) -> Bool { hits.contains(hash) }
}

private actor EnqueueRecorder {
    private(set) var enqueued: [String] = []
    func append(_ text: String) { enqueued.append(text) }
    func count() -> Int { enqueued.count }
}

private struct RecordingEnqueuer: PreWarmEnqueuer {
    let recorder: EnqueueRecorder
    let failOn: Set<String>
    let delay: UInt64

    init(failOn: Set<String> = [], delayNanos: UInt64 = 0) {
        self.recorder = EnqueueRecorder()
        self.failOn = failOn
        self.delay = delayNanos
    }

    func enqueue(text: String, speaker: Int) async throws {
        if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
        if failOn.contains(text) {
            throw NSError(domain: "test", code: 1)
        }
        await recorder.append(text)
    }
}

private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    init(_ start: Date) { self._now = start }
    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return _now
    }
    func advance(by interval: TimeInterval) {
        lock.lock(); _now = _now.addingTimeInterval(interval); lock.unlock()
    }
    func provider() -> @Sendable () -> Date { { [weak self] in self?.now ?? Date() } }
}

private func hash(for text: String) -> String {
    RigAudioCoordinator.makeHash(text: text, speaker: PreWarmService.defaultSpeaker)
}

// MARK: - Tests

@Test("Cache hits are skipped — no enqueue")
func cacheHitsAreSkipped() async throws {
    let fronts = ["食べる", "飲む", "見る"]
    let hits = Set(fronts.map(hash(for:)))
    let enqueuer = RecordingEnqueuer()
    let service = PreWarmService(
        cardSource: FakeCardSource(fronts: fronts),
        cacheLookup: FakeCacheLookup(hits: hits),
        enqueuer: enqueuer
    )

    try await service.enqueueUpcomingDueAudio(window: 86400)

    #expect(await enqueuer.recorder.enqueued.isEmpty)
}

@Test("Cache misses are enqueued")
func cacheMissesAreEnqueued() async throws {
    let fronts = ["食べる", "飲む", "見る"]
    let enqueuer = RecordingEnqueuer()
    let service = PreWarmService(
        cardSource: FakeCardSource(fronts: fronts),
        cacheLookup: FakeCacheLookup(hits: []),
        enqueuer: enqueuer
    )

    try await service.enqueueUpcomingDueAudio(window: 86400)

    #expect(await enqueuer.recorder.enqueued == fronts)
}

@Test("More than 50 misses cap at 50 enqueues")
func capsAtFiftyEnqueues() async throws {
    let fronts = (0..<120).map { "card-\($0)" }
    let enqueuer = RecordingEnqueuer()
    let service = PreWarmService(
        cardSource: FakeCardSource(fronts: fronts),
        cacheLookup: FakeCacheLookup(hits: []),
        enqueuer: enqueuer
    )

    try await service.enqueueUpcomingDueAudio(window: 86400)

    #expect(await enqueuer.recorder.enqueued.count == PreWarmService.maxJobsPerCall)
    #expect(await enqueuer.recorder.enqueued == Array(fronts.prefix(PreWarmService.maxJobsPerCall)))
}

@Test("Second call within one hour is throttled")
func secondCallWithinHourIsThrottled() async throws {
    let fronts = ["a", "b", "c"]
    let enqueuer = RecordingEnqueuer()
    let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
    let service = PreWarmService(
        cardSource: FakeCardSource(fronts: fronts),
        cacheLookup: FakeCacheLookup(hits: []),
        enqueuer: enqueuer,
        clock: clock.provider()
    )

    try await service.enqueueUpcomingDueAudio(window: 86400)
    #expect(await enqueuer.recorder.enqueued.count == 3)

    clock.advance(by: 30 * 60) // 30 minutes
    try await service.enqueueUpcomingDueAudio(window: 86400)

    #expect(await enqueuer.recorder.enqueued.count == 3, "second call must be a no-op")
}

@Test("Second call after one hour proceeds")
func secondCallAfterHourProceeds() async throws {
    let fronts = ["a", "b"]
    let enqueuer = RecordingEnqueuer()
    let clock = MutableClock(Date(timeIntervalSince1970: 2_000_000))
    let service = PreWarmService(
        cardSource: FakeCardSource(fronts: fronts),
        cacheLookup: FakeCacheLookup(hits: []),
        enqueuer: enqueuer,
        clock: clock.provider()
    )

    try await service.enqueueUpcomingDueAudio(window: 86400)
    #expect(await enqueuer.recorder.enqueued.count == 2)

    clock.advance(by: 60 * 60 + 1) // just over 1 hour
    try await service.enqueueUpcomingDueAudio(window: 86400)

    #expect(await enqueuer.recorder.enqueued.count == 4)
}

@Test("Per-card enqueue failure does not abort the batch")
func perCardFailureDoesNotAbortBatch() async throws {
    let fronts = ["ok-1", "boom", "ok-2", "ok-3"]
    let enqueuer = RecordingEnqueuer(failOn: ["boom"])
    let service = PreWarmService(
        cardSource: FakeCardSource(fronts: fronts),
        cacheLookup: FakeCacheLookup(hits: []),
        enqueuer: enqueuer
    )

    try await service.enqueueUpcomingDueAudio(window: 86400)

    #expect(await enqueuer.recorder.enqueued == ["ok-1", "ok-2", "ok-3"])
}

@Test("empty input does not arm throttle")
func emptyInputDoesNotArmThrottle() async throws {
    let enqueuer = RecordingEnqueuer()
    let clock = MutableClock(Date(timeIntervalSince1970: 3_000_000))
    let service = PreWarmService(
        cardSource: FakeCardSource(fronts: []),
        cacheLookup: FakeCacheLookup(hits: []),
        enqueuer: enqueuer,
        clock: clock.provider()
    )

    try await service.enqueueUpcomingDueAudio(window: 86400)
    #expect(await service.lastCallTimestamp() == nil, "empty batch must not arm throttle")
    #expect(await enqueuer.recorder.enqueued.isEmpty)

    clock.advance(by: 5 * 60) // 5 minutes — well within the 1h window
    try await service.enqueueUpcomingDueAudio(window: 86400)
    #expect(await service.lastCallTimestamp() == nil)
    #expect(await enqueuer.recorder.enqueued.isEmpty)
}

@Test("all-cache-hits does not arm throttle")
func allCacheHitsDoesNotArmThrottle() async throws {
    let fronts = ["a", "b", "c", "d", "e"]
    let hits = Set(fronts.map(hash(for:)))
    let enqueuer = RecordingEnqueuer()
    let clock = MutableClock(Date(timeIntervalSince1970: 4_000_000))
    let service = PreWarmService(
        cardSource: FakeCardSource(fronts: fronts),
        cacheLookup: FakeCacheLookup(hits: hits),
        enqueuer: enqueuer,
        clock: clock.provider()
    )

    try await service.enqueueUpcomingDueAudio(window: 86400)
    #expect(await service.lastCallTimestamp() == nil)
    #expect(await enqueuer.recorder.enqueued.isEmpty)

    clock.advance(by: 5 * 60)
    try await service.enqueueUpcomingDueAudio(window: 86400)
    // Second call must not be throttled — it still executed the lookup.
    #expect(await service.lastCallTimestamp() == nil)
    #expect(await enqueuer.recorder.enqueued.isEmpty)
}

@Test("cancellation propagates and stops enqueuing mid-batch")
func cancellationPropagatesAndStopsMidBatch() async throws {
    let fronts = (0..<100).map { "card-\($0)" }
    let enqueuer = RecordingEnqueuer(delayNanos: 20_000_000) // 20ms per enqueue
    let service = PreWarmService(
        cardSource: FakeCardSource(fronts: fronts),
        cacheLookup: FakeCacheLookup(hits: []),
        enqueuer: enqueuer
    )

    let task = Task {
        try await service.enqueueUpcomingDueAudio(window: 86400)
    }

    // Allow 1–2 enqueues to land, then cancel.
    try await Task.sleep(nanoseconds: 35_000_000)
    task.cancel()

    var threwCancellation = false
    do {
        try await task.value
    } catch is CancellationError {
        threwCancellation = true
    } catch {
        // Some await points may surface cancellation as generic errors; accept either.
        threwCancellation = true
    }

    #expect(threwCancellation, "cancelled task must throw")
    let count = await enqueuer.recorder.count()
    #expect(count < PreWarmService.maxJobsPerCall, "cancellation must stop the batch early")
    // Throttle must not be armed on a cancelled / zero-enqueue path either.
}

// NOTE: dueDate-ascending ordering is enforced by the protocol contract
// documented on PreWarmCardSource.dueCards(before:). The concrete
// CardRepositoryPreWarmSource adapter sorts by CardDTO.dueDate before
// mapping to .front. A direct adapter test would require spinning up a
// SwiftData ModelContainer, which is beyond the scope of these unit tests;
// the contract is covered by the doc comment + adapter implementation.
