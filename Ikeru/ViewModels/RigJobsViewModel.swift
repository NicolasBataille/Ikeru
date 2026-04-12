import Foundation
import IkeruCore
import Observation
import os

// MARK: - RigJobsClient
//
// Narrow protocol over `RigClient` so the view-model can be tested with a
// mock. The rig server (Story 7.3) does not currently expose a list-jobs
// endpoint, so the view-model maintains its own in-memory set of known
// job IDs and polls each via `jobStatus(_:)`.

public protocol RigJobsClient: Sendable {
    func jobStatus(_ id: String) async throws -> RigJobRecord
    func enqueueJob(_ job: RigJobRequest) async throws -> String
    func cancel(_ id: String) async throws
}

extension RigClient: RigJobsClient {}

// MARK: - RigJobsViewModel

@Observable
@MainActor
public final class RigJobsViewModel {

    // MARK: - Observable state

    public private(set) var jobs: [RigJobRecord] = []
    public private(set) var isRefreshing: Bool = false
    public var errorMessage: String?
    public private(set) var consecutiveFailures: Int = 0

    // MARK: - Dependencies

    @ObservationIgnored
    private let client: any RigJobsClient
    @ObservationIgnored
    private var trackedIds: Set<String> = []
    @ObservationIgnored
    private let taskHandle: TaskHandle = .init()
    @ObservationIgnored
    private let pollInterval: Duration

    /// Nonisolated holder so `deinit` can cancel without touching MainActor state.
    final class TaskHandle: @unchecked Sendable {
        var task: Task<Void, Never>?
        func cancel() { task?.cancel() }
    }

    // MARK: - Init

    public init(
        client: any RigJobsClient,
        pollInterval: Duration = .seconds(2)
    ) {
        self.client = client
        self.pollInterval = pollInterval
    }

    deinit {
        taskHandle.cancel()
    }

    // MARK: - Tracking

    /// Adds a job ID to the polled set. Used by other view-models that
    /// enqueue jobs (e.g. PreWarmService callers) so this view sees them.
    public func track(_ id: String) {
        trackedIds.insert(id)
    }

    public func track(_ ids: some Sequence<String>) {
        trackedIds.formUnion(ids)
    }

    // MARK: - Polling lifecycle

    public func startPolling() {
        guard taskHandle.task == nil else { return }
        let baseInterval = pollInterval
        taskHandle.task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let failures = await self?.consecutiveFailures ?? 0
                let delay = Self.backoffDelay(baseInterval: baseInterval, failures: failures)
                try? await Task.sleep(for: delay)
            }
        }
    }

    public func stopPolling() {
        taskHandle.cancel()
        taskHandle.task = nil
    }

    /// Exponential backoff: base interval on success, doubling on each failure
    /// up to a 60-second cap.
    private static func backoffDelay(baseInterval: Duration, failures: Int) -> Duration {
        guard failures > 0 else { return baseInterval }
        let baseSeconds = Double(baseInterval.components.seconds)
            + Double(baseInterval.components.attoseconds) / 1e18
        let scaled = baseSeconds * pow(2.0, Double(failures))
        let capped = min(scaled, 60.0)
        return .seconds(capped)
    }

    // MARK: - Actions

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        var fetched: [RigJobRecord] = []
        var firstError: Error?

        for id in trackedIds {
            do {
                let record = try await client.jobStatus(id)
                fetched.append(record)
            } catch {
                if firstError == nil { firstError = error }
                Logger.rig.warning("RigJobsViewModel jobStatus(\(id)) failed: \(error.localizedDescription)")
            }
        }

        jobs = fetched.sorted { $0.createdAt > $1.createdAt }

        if let firstError {
            errorMessage = describe(firstError)
            consecutiveFailures += 1
        } else {
            errorMessage = nil
            consecutiveFailures = 0
        }
    }

    public func cancel(_ job: RigJobRecord) async {
        do {
            try await client.cancel(job.id)
            trackedIds.remove(job.id)
            jobs.removeAll { $0.id == job.id }
        } catch {
            errorMessage = describe(error)
            Logger.rig.warning("RigJobsViewModel cancel(\(job.id)) failed")
        }
    }

    public func retry(_ job: RigJobRecord) async {
        let request = RigJobRequest(type: job.type, params: job.params)
        do {
            let newId = try await client.enqueueJob(request)
            trackedIds.remove(job.id)
            trackedIds.insert(newId)
            jobs.removeAll { $0.id == job.id }
            await refresh()
        } catch {
            errorMessage = describe(error)
            Logger.rig.warning("RigJobsViewModel retry(\(job.id)) failed")
        }
    }

    // MARK: - Helpers

    private func describe(_ error: Error) -> String {
        if let rig = error as? RigError {
            switch rig {
            case .unauthorized: return "Unauthorized — check the shared token"
            case .notFound: return "Job not found on rig"
            case .timeout: return "Timed out talking to rig"
            case .network: return "Network error reaching rig"
            case .invalidURL, .missingToken, .invalidResponse, .notReady, .httpStatus:
                return String(describing: rig)
            }
        }
        return error.localizedDescription
    }
}
