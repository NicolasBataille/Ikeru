import Testing
import Foundation
@testable import IkeruCore

@Suite("LocalGPUProvider")
struct LocalGPUProviderTests {

    // MARK: - Provider Properties

    @Test("Provider name is LocalGPU")
    func providerName() {
        let provider = LocalGPUProvider()
        #expect(provider.name == "LocalGPU")
    }

    @Test("Provider tier is localGPU")
    func providerTier() {
        let provider = LocalGPUProvider()
        #expect(provider.tier == .localGPU)
    }

    // MARK: - Availability (mock-based)

    @Test("Provider is unavailable when no service discovered")
    func unavailableWithoutService() async {
        let discovery = MockBonjourDiscovery(endpoint: nil)
        let provider = LocalGPUProvider(bonjourDiscovery: discovery)
        let available = await provider.isAvailable
        #expect(available == false)
    }

    @Test("Provider is available when service discovered")
    func availableWithService() async {
        let discovery = MockBonjourDiscovery(
            endpoint: BonjourEndpoint(host: "192.168.1.100", port: 8080)
        )
        let provider = LocalGPUProvider(bonjourDiscovery: discovery)
        let available = await provider.isAvailable
        #expect(available == true)
    }

    // MARK: - Generation with mock

    @Test("Successful generation returns response")
    func successfulGeneration() async throws {
        let discovery = MockBonjourDiscovery(
            endpoint: BonjourEndpoint(host: "192.168.1.100", port: 8080)
        )
        let mockSession = MockURLSessionProvider(
            responseData: localGPUSuccessJSON,
            statusCode: 200
        )
        let provider = LocalGPUProvider(
            bonjourDiscovery: discovery,
            urlSession: mockSession
        )
        let prompt = AIPrompt(
            systemPrompt: "Process batch",
            userMessage: "Generate mnemonics for these 50 kanji",
            complexity: .batch
        )
        let response = try await provider.generate(prompt: prompt)
        #expect(response.content == "Batch results here.")
        #expect(response.tier == .localGPU)
    }

    @Test("No endpoint throws providerUnavailable")
    func noEndpoint() async {
        let discovery = MockBonjourDiscovery(endpoint: nil)
        let provider = LocalGPUProvider(bonjourDiscovery: discovery)
        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .batch
        )
        do {
            _ = try await provider.generate(prompt: prompt)
            Issue.record("Expected providerUnavailable error")
        } catch let error as AIError {
            if case .providerUnavailable(let tier) = error {
                #expect(tier == .localGPU)
            } else {
                Issue.record("Expected providerUnavailable, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Server error throws invalidResponse")
    func serverError() async {
        let discovery = MockBonjourDiscovery(
            endpoint: BonjourEndpoint(host: "192.168.1.100", port: 8080)
        )
        let mockSession = MockURLSessionProvider(
            responseData: Data("error".utf8),
            statusCode: 500
        )
        let provider = LocalGPUProvider(
            bonjourDiscovery: discovery,
            urlSession: mockSession
        )
        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .batch
        )
        do {
            _ = try await provider.generate(prompt: prompt)
            Issue.record("Expected invalidResponse error")
        } catch let error as AIError {
            if case .invalidResponse = error {
                // passes
            } else {
                Issue.record("Expected invalidResponse, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Network error throws networkError")
    func networkError() async {
        let discovery = MockBonjourDiscovery(
            endpoint: BonjourEndpoint(host: "192.168.1.100", port: 8080)
        )
        let mockSession = MockURLSessionProvider(
            error: URLError(.cannotConnectToHost)
        )
        let provider = LocalGPUProvider(
            bonjourDiscovery: discovery,
            urlSession: mockSession
        )
        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .batch
        )
        do {
            _ = try await provider.generate(prompt: prompt)
            Issue.record("Expected networkError")
        } catch let error as AIError {
            if case .networkError = error {
                // passes
            } else {
                Issue.record("Expected networkError, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Test Data

    private var localGPUSuccessJSON: Data {
        Data("""
        {
            "text": "Batch results here.",
            "tokens": 150
        }
        """.utf8)
    }
}
