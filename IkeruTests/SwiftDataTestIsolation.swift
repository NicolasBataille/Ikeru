import Testing

// MARK: - SwiftDataIsolated

/// Serializes every test carrying this trait against every OTHER test that
/// also carries it, ACROSS suite boundaries.
///
/// Swift Testing's built-in `.serialized` trait only serializes tests
/// *within* the one suite it's attached to — it does not create a global
/// barrier against unrelated suites running at the same time. That's
/// documented behavior, confirmed on the Swift Forums:
/// https://forums.swift.org/t/running-tests-serially-or-in-parallel/72935
/// ("a test from `Suite1` *and* `Suite2` can still run in parallel").
///
/// Why this trait exists (GAP-10, 2026-08-15): running the app test
/// target's SwiftData-backed suites under `xcodebuild test` (Swift Testing
/// hosted via XCTest, which parallelizes suites by default — unlike
/// `swift test --no-parallel`, there is no CLI flag to disable that for an
/// xcodebuild-hosted run) reliably crashes the whole test runner. Measured:
/// a full `-only-testing:IkeruTests` run produced 25 SIGTRAPs across one
/// invocation. Every crash report's faulting thread bottoms out in
/// `libswiftCore.dylib _assertionFailure` called from opaque `SwiftData`
/// frames (EXC_BREAKPOINT); the 4 occurrences where the simulator's
/// unified log captured the process's stderr before it died all show the
/// identical message:
///
///   SwiftData/BackingData.swift:940: Fatal error: Never access a full
///   future backing data - PersistentIdentifier(id: ...managedObjectID(...
///   <x-coredata://AAAAAAAA.../RPGState/p1>)) with Optional(BBBBBBBB...)
///
/// The two UUIDs differ — the `PersistentIdentifier` belongs to one
/// in-memory `ModelContainer`'s Core Data store while the fault handler
/// believes a DIFFERENT container's store is current. That is
/// cross-container contamination: SwiftData's process-global backing-data
/// bookkeeping is not safe against two independent in-memory containers
/// being exercised concurrently in the same process. This is the same
/// family of bug CLAUDE.md already documents for `IkeruCore`'s
/// versioned-schema migration suites (a poisoned process-global
/// entity↔class cache) — different trigger, same "SwiftData + concurrent
/// containers in one process" root cause.
///
/// `.serialized(for: *)` — Swift Testing's own unbounded-dependency SPI,
/// which shares one process-wide serializer across every suite that
/// declares it — would fix this for free, but is unusable here: the system
/// `Testing.framework` Xcode ships only exposes its public
/// `.swiftinterface` (no private interface), so `@_spi(Experimental) import
/// Testing` compiles with "will not include any SPI symbols" and
/// `.serialized(for: *)` fails with "cannot call value of non-function
/// type 'ParallelizationTrait'". Confirmed by trying it directly before
/// writing this trait. Hence the hand-rolled equivalent below: a single
/// actor-backed mutex, applied to every SwiftData-backed suite.
struct SwiftDataIsolated: SuiteTrait, TestTrait, TestScoping {
    // `SuiteTrait.isRecursive` defaults to `false` — a suite trait then wraps
    // ONE lock acquisition around the whole suite's run, but the tests inside
    // that suite are still scheduled by Swift Testing's own concurrency and
    // are not individually serialized against each other (confirmed by
    // testing: with the default, ProfileViewModelTests's 18 tests kept
    // racing and crashing even with this trait applied). `true` makes the
    // testing library call `provideScope` once per contained test function
    // instead of once for the suite, so every test individually acquires
    // `SwiftDataTestLock` — true one-at-a-time execution, both within a
    // suite and across every other suite carrying this trait.
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await SwiftDataTestLock.shared.run(function)
    }
}

extension Trait where Self == SwiftDataIsolated {
    /// Apply to a `@Suite` that builds a SwiftData `ModelContainer`. See
    /// `SwiftDataIsolated`'s doc comment for why this exists instead of the
    /// built-in `.serialized`.
    static var swiftDataIsolated: Self { Self() }
}

// MARK: - SwiftDataTestLock

/// A simple async mutex: at most one `run` body executes at a time,
/// process-wide, across all callers. Backs `SwiftDataIsolated`.
actor SwiftDataTestLock {
    static let shared = SwiftDataTestLock()

    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        do {
            let result = try await body()
            release()
            return result
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard waiters.isEmpty else {
            waiters.removeFirst().resume()
            return
        }
        isBusy = false
    }
}
