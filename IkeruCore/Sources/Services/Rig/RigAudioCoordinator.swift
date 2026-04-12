import Foundation
import os

// MARK: - RigAudioCoordinator
//
// High-level API on top of `RigClient` + `AssetCache` for the audio use case.
//
// Workflow for `audioForText("食べる")`:
//   1. Compute the deterministic hash for `(tts, voicevox-default, speaker_id, text)`
//   2. If the cache already has the asset → return its local URL immediately
//   3. Otherwise enqueue a TTS job on the rig and poll until done
//   4. Download the asset bytes, store them in the cache, return the local URL
//
// If the rig is not configured or unreachable, throws `RigError.notFound` —
// callers can fall back to `AVSpeechSynthesizer` so the user always hears
// *something*, even if quality is degraded.

public actor RigAudioCoordinator {

    public static let voicevoxVersion = "voicevox-v0.21"

    private let client: RigClient
    private let cache: AssetCache
    private let pollIntervals: [Duration]
    private let maxWait: Duration

    public init(
        client: RigClient,
        cache: AssetCache,
        pollIntervals: [Duration] = [
            .milliseconds(200),
            .milliseconds(500),
            .seconds(1),
            .seconds(2),
        ],
        maxWait: Duration = .seconds(30)
    ) {
        self.client = client
        self.cache = cache
        self.pollIntervals = pollIntervals
        self.maxWait = maxWait
    }

    /// Returns a playable local file URL for the given Japanese text.
    public func audioForText(
        _ text: String,
        speaker: Int = 3
    ) async throws -> URL {
        let hash = Self.makeHash(text: text, speaker: speaker)

        if let cached = cache.read(hash: hash, type: .audioOpus) {
            Logger.rig.info("RigAudioCoordinator cache hit for \(hash)")
            return cached
        }

        Logger.rig.info("RigAudioCoordinator cache miss — enqueueing TTS job for \(text.prefix(20))")
        let jobId = try await client.enqueueJob(.tts(text: text, speaker: speaker))
        let final = try await waitForCompletion(jobId: jobId)

        guard final.isDone else {
            throw RigError.invalidResponse
        }

        let data = try await client.fetchAsset(jobId)
        let url = try cache.store(
            hash: hash,
            type: .audioOpus,
            data: data,
            sourceText: text
        )
        return url
    }

    // MARK: - Hashing

    public static func makeHash(text: String, speaker: Int) -> String {
        let seed = "tts|\(voicevoxVersion)|speaker=\(speaker)|\(text)"
        return AssetCache.hash(of: seed)
    }

    // MARK: - Polling

    private func waitForCompletion(jobId: String) async throws -> RigJobRecord {
        let deadline = ContinuousClock.now + maxWait
        var attempt = 0
        while ContinuousClock.now < deadline {
            let interval = pollIntervals[min(attempt, pollIntervals.count - 1)]
            try? await Task.sleep(for: interval)
            attempt += 1

            let record = try await client.jobStatus(jobId)
            if record.isTerminal {
                return record
            }
        }
        throw RigError.timeout
    }
}
