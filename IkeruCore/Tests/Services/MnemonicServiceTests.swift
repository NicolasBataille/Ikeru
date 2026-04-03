import Testing
import Foundation
import SwiftData
@testable import IkeruCore

@Suite("MnemonicService")
struct MnemonicServiceTests {

    // MARK: - Helpers

    /// Creates an in-memory ModelContainer for testing.
    private func makeModelContainer() throws -> ModelContainer {
        let schema = Schema([MnemonicCache.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Creates a MnemonicService with a mock AI router.
    @MainActor
    private func makeService(
        responseContent: String = "A vivid mnemonic about the sun.",
        responseAvailable: Bool = true,
        responseError: AIError? = nil,
        modelContainer: ModelContainer? = nil
    ) throws -> (MnemonicService, ModelContainer) {
        let container = try modelContainer ?? makeModelContainer()

        let mockProvider = ConfigurableMockAIProvider(
            content: responseContent,
            available: responseAvailable,
            error: responseError
        )

        let router = AIRouterService(
            onDeviceProvider: mockProvider,
            geminiProvider: ConfigurableMockAIProvider(content: "", available: false),
            claudeProvider: ConfigurableMockAIProvider(content: "", available: false),
            localGPUProvider: ConfigurableMockAIProvider(content: "", available: false),
            networkChecker: MockNetworkChecker(online: false)
        )

        let service = MnemonicService(aiRouter: router, modelContainer: container)
        return (service, container)
    }

    /// Pre-populates the cache with a mnemonic entry.
    @MainActor
    private func seedCache(
        container: ModelContainer,
        character: String,
        mnemonic: String,
        tierUsed: String = "onDevice"
    ) {
        let context = ModelContext(container)
        let entry = MnemonicCache(character: character, mnemonic: mnemonic, tierUsed: tierUsed)
        context.insert(entry)
        try? context.save()
    }

    // MARK: - Cache Miss

    @Test("Cache miss triggers AI generation and caches result")
    @MainActor
    func cacheMissTriggersGeneration() async throws {
        let expectedMnemonic = "The sun rises over the mountain."
        let (service, container) = try makeService(responseContent: expectedMnemonic)

        let result = try await service.generateMnemonic(
            for: "日",
            radicals: ["sun"],
            readings: ["にち", "ひ"]
        )

        #expect(result.text == expectedMnemonic)
        #expect(result.tier == .onDevice)

        // Verify it was cached
        let cached = await service.cachedMnemonic(for: "日")
        #expect(cached == expectedMnemonic)
    }

    // MARK: - Cache Hit

    @Test("Cache hit returns cached mnemonic without AI call")
    @MainActor
    func cacheHitReturnsCached() async throws {
        let cachedText = "A pre-existing mnemonic."
        let container = try makeModelContainer()
        seedCache(container: container, character: "月", mnemonic: cachedText)

        let (service, _) = try makeService(
            responseContent: "This should NOT be returned.",
            modelContainer: container
        )

        let result = try await service.generateMnemonic(
            for: "月",
            radicals: ["moon"],
            readings: ["げつ", "つき"]
        )

        #expect(result.text == cachedText)
    }

    // MARK: - Cached Mnemonic Lookup

    @Test("cachedMnemonic returns nil when no cache entry exists")
    @MainActor
    func cachedMnemonicReturnsNilForMiss() async throws {
        let (service, _) = try makeService()
        let cached = await service.cachedMnemonic(for: "火")
        #expect(cached == nil)
    }

    @Test("cachedMnemonic returns text when cache entry exists")
    @MainActor
    func cachedMnemonicReturnsTextForHit() async throws {
        let container = try makeModelContainer()
        seedCache(container: container, character: "水", mnemonic: "Water flows downhill.")

        let (service, _) = try makeService(modelContainer: container)
        let cached = await service.cachedMnemonic(for: "水")
        #expect(cached == "Water flows downhill.")
    }

    // MARK: - Clear Cache

    @Test("clearCache removes cached mnemonic and allows fresh generation")
    @MainActor
    func clearCacheRemovesEntry() async throws {
        let container = try makeModelContainer()
        seedCache(container: container, character: "木", mnemonic: "Old mnemonic.")

        let freshMnemonic = "A brand new mnemonic about a tree."
        let (service, _) = try makeService(
            responseContent: freshMnemonic,
            modelContainer: container
        )

        // Verify cache has the old entry
        let cachedBefore = await service.cachedMnemonic(for: "木")
        #expect(cachedBefore == "Old mnemonic.")

        // Clear cache
        try await service.clearCache(for: "木")

        // Verify cache is empty
        let cachedAfter = await service.cachedMnemonic(for: "木")
        #expect(cachedAfter == nil)

        // Generate fresh — should call AI
        let result = try await service.generateMnemonic(
            for: "木",
            radicals: ["tree"],
            readings: ["もく", "き"]
        )
        #expect(result.text == freshMnemonic)
    }

    // MARK: - AI Error Propagation

    @Test("AI generation failure propagates error")
    @MainActor
    func aiFailurePropagatesError() async throws {
        let mockProvider = ConfigurableMockAIProvider(
            content: "",
            available: false,
            error: nil
        )

        let container = try makeModelContainer()
        let router = AIRouterService(
            onDeviceProvider: mockProvider,
            geminiProvider: ConfigurableMockAIProvider(content: "", available: false),
            claudeProvider: ConfigurableMockAIProvider(content: "", available: false),
            localGPUProvider: ConfigurableMockAIProvider(content: "", available: false),
            networkChecker: MockNetworkChecker(online: false)
        )

        let service = MnemonicService(aiRouter: router, modelContainer: container)

        do {
            _ = try await service.generateMnemonic(
                for: "金",
                radicals: ["metal"],
                readings: ["きん", "かね"]
            )
            Issue.record("Expected error to be thrown")
        } catch {
            // Expected — all providers are unavailable
        }
    }

    // MARK: - Whitespace Trimming

    @Test("Generated mnemonic is trimmed of whitespace")
    @MainActor
    func mnemonicIsTrimmed() async throws {
        let (service, _) = try makeService(responseContent: "  A mnemonic with spaces.  \n")

        let result = try await service.generateMnemonic(
            for: "土",
            radicals: ["earth"],
            readings: ["ど", "つち"]
        )

        #expect(result.text == "A mnemonic with spaces.")
    }
}

// MARK: - Test Doubles

/// A configurable mock AI provider for testing MnemonicService.
private final class ConfigurableMockAIProvider: AIProvider, @unchecked Sendable {

    let name: String = "MockProvider"
    let tier: AITier = .onDevice
    private let content: String
    private let _available: Bool
    private let _error: AIError?

    init(content: String, available: Bool = true, error: AIError? = nil) {
        self.content = content
        self._available = available
        self._error = error
    }

    var isAvailable: Bool {
        get async { _available }
    }

    func generate(prompt: AIPrompt) async throws -> AIResponse {
        if let error = _error {
            throw error
        }
        return AIResponse(content: content, tier: .onDevice, latencyMs: 10)
    }
}
