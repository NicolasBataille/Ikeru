import Testing
import Foundation
@testable import Ikeru
@testable import IkeruCore

// MARK: - RigJobsViewModelTests
//
// Story 7.5 Task 7 — exercises the polling/refresh/retry/cancel surface of
// `RigJobsViewModel` against an in-memory mock that conforms to
// `RigJobsClient`.

@Suite("RigJobsViewModel")
@MainActor
struct RigJobsViewModelTests {

    // MARK: - Mock

    final class MockRigJobsClient: RigJobsClient, @unchecked Sendable {
        var records: [String: RigJobRecord] = [:]
        var enqueueResult: String = "new-id"
        var enqueueCallCount = 0
        var cancelCallCount = 0
        var lastCancelledId: String?
        var lastEnqueued: RigJobRequest?
        var statusError: Error?

        func jobStatus(_ id: String) async throws -> RigJobRecord {
            if let statusError { throw statusError }
            guard let record = records[id] else {
                throw RigError.notFound
            }
            return record
        }

        func enqueueJob(_ job: RigJobRequest) async throws -> String {
            enqueueCallCount += 1
            lastEnqueued = job
            let id = enqueueResult
            records[id] = RigJobRecord(
                id: id,
                type: job.type,
                status: "queued",
                params: job.params,
                createdAt: Date(),
                startedAt: nil,
                finishedAt: nil,
                assetPath: nil,
                error: nil
            )
            return id
        }

        func cancel(_ id: String) async throws {
            cancelCallCount += 1
            lastCancelledId = id
            records.removeValue(forKey: id)
        }
    }

    // MARK: - Helpers

    private func makeRecord(
        id: String,
        type: String = "tts",
        status: String = "queued",
        createdAt: Date = Date(),
        error: String? = nil
    ) -> RigJobRecord {
        RigJobRecord(
            id: id,
            type: type,
            status: status,
            params: ["text": .string("hello \(id)"), "speaker_id": .int(3)],
            createdAt: createdAt,
            startedAt: nil,
            finishedAt: nil,
            assetPath: nil,
            error: error
        )
    }

    // MARK: - Tests

    @Test("refresh populates jobs from the mock, sorted createdAt desc")
    func refreshPopulatesJobs() async {
        let mock = MockRigJobsClient()
        let now = Date()
        mock.records["a"] = makeRecord(id: "a", createdAt: now.addingTimeInterval(-10))
        mock.records["b"] = makeRecord(id: "b", createdAt: now)

        let vm = RigJobsViewModel(client: mock)
        vm.track(["a", "b"])

        await vm.refresh()

        #expect(vm.jobs.count == 2)
        #expect(vm.jobs.first?.id == "b")
        #expect(vm.jobs.last?.id == "a")
        #expect(vm.errorMessage == nil)
        #expect(vm.isRefreshing == false)
    }

    @Test("cancel removes the job and calls the client")
    func cancelRemovesJob() async {
        let mock = MockRigJobsClient()
        let record = makeRecord(id: "x", status: "running")
        mock.records["x"] = record

        let vm = RigJobsViewModel(client: mock)
        vm.track("x")
        await vm.refresh()
        #expect(vm.jobs.count == 1)

        await vm.cancel(record)

        #expect(mock.cancelCallCount == 1)
        #expect(mock.lastCancelledId == "x")
        #expect(vm.jobs.isEmpty)
    }

    @Test("retry re-enqueues with same params and updates the list")
    func retryReenqueues() async {
        let mock = MockRigJobsClient()
        let failed = makeRecord(id: "old", status: "error", error: "boom")
        mock.records["old"] = failed
        mock.enqueueResult = "fresh"

        let vm = RigJobsViewModel(client: mock)
        vm.track("old")
        await vm.refresh()

        await vm.retry(failed)

        #expect(mock.enqueueCallCount == 1)
        #expect(mock.lastEnqueued?.type == "tts")
        if case .string(let text) = mock.lastEnqueued?.params["text"] {
            #expect(text == "hello old")
        } else {
            Issue.record("retry should re-send the original text param")
        }
        #expect(vm.jobs.contains { $0.id == "fresh" })
        #expect(!vm.jobs.contains { $0.id == "old" })
    }

    @Test("status errors are surfaced via errorMessage without crashing")
    func statusErrorIsSurfaced() async {
        let mock = MockRigJobsClient()
        mock.statusError = RigError.unauthorized

        let vm = RigJobsViewModel(client: mock)
        vm.track("anything")

        await vm.refresh()

        #expect(vm.jobs.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test("startPolling and stopPolling do not crash and refresh at least once")
    func pollingLifecycle() async throws {
        let mock = MockRigJobsClient()
        mock.records["p"] = makeRecord(id: "p")

        let vm = RigJobsViewModel(client: mock, pollInterval: .milliseconds(20))
        vm.track("p")

        vm.startPolling()

        // Deterministic wait: yield until the first refresh populates jobs, or
        // time out after 1 second of real time.
        let deadline = Date().addingTimeInterval(1.0)
        while vm.jobs.isEmpty && Date() < deadline {
            await Task.yield()
        }

        vm.stopPolling()

        #expect(vm.jobs.contains { $0.id == "p" })
    }
}
