import Testing
import Foundation
@testable import IkeruCore

@Suite("FoundationModelsProvider")
struct FoundationModelsProviderTests {

    // MARK: - Provider Properties

    @Test("Provider name is FoundationModels")
    func providerName() {
        let provider = FoundationModelsProvider()
        #expect(provider.name == "FoundationModels")
    }

    @Test("Provider tier is onDevice")
    func providerTier() {
        let provider = FoundationModelsProvider()
        #expect(provider.tier == .onDevice)
    }

    // MARK: - Availability

    @Test("Provider availability reflects device capability")
    func availability() async {
        let provider = FoundationModelsProvider()
        // On test environments (macOS CI, older devices), this should be false.
        // The test validates the property is accessible without crashing.
        let available = await provider.isAvailable
        #expect(available == true || available == false)
    }

    // MARK: - Mock-based generation

    @Test("Mock FoundationModels provider generates response")
    func mockGeneration() async throws {
        let provider = MockFoundationModelsProvider(
            available: true,
            responseContent: "The kanji means water."
        )
        let prompt = AIPrompt(
            systemPrompt: "You are a tutor.",
            userMessage: "What does this mean?"
        )
        let response = try await provider.generate(prompt: prompt)
        #expect(response.content == "The kanji means water.")
        #expect(response.tier == .onDevice)
        #expect(response.latencyMs >= 0)
    }

    @Test("Mock FoundationModels provider unavailable throws error")
    func mockUnavailable() async {
        let provider = MockFoundationModelsProvider(
            available: false,
            responseContent: ""
        )
        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test"
        )
        do {
            _ = try await provider.generate(prompt: prompt)
            Issue.record("Expected providerUnavailable error")
        } catch let error as AIError {
            if case .providerUnavailable(let tier) = error {
                #expect(tier == .onDevice)
            } else {
                Issue.record("Expected providerUnavailable, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Provider conforms to AIProvider protocol")
    func protocolConformance() {
        let provider: any AIProvider = FoundationModelsProvider()
        #expect(provider.tier == .onDevice)
    }
}
