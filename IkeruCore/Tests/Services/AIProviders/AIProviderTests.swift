import Testing
import Foundation
@testable import IkeruCore

@Suite("AIProvider Protocol & Supporting Types")
struct AIProviderTests {

    // MARK: - AITier Enum

    @Test("AITier has four cases")
    func tierCaseCount() {
        let allTiers: [AITier] = [.onDevice, .gemini, .claude, .localGPU]
        #expect(allTiers.count == 4)
    }

    @Test("AITier priority order: onDevice < gemini < claude < localGPU")
    func tierOrdering() {
        #expect(AITier.onDevice < AITier.gemini)
        #expect(AITier.gemini < AITier.claude)
        #expect(AITier.claude < AITier.localGPU)
    }

    @Test("AITier conforms to Comparable")
    func tierComparable() {
        let sorted = [AITier.localGPU, AITier.onDevice, AITier.claude, AITier.gemini].sorted()
        #expect(sorted == [.onDevice, .gemini, .claude, .localGPU])
    }

    @Test("AITier conforms to Sendable")
    func tierSendable() {
        let tier: any Sendable = AITier.onDevice
        #expect(tier is AITier)
    }

    // MARK: - PromptComplexity Enum

    @Test("PromptComplexity has four cases")
    func complexityCaseCount() {
        let all: [PromptComplexity] = [.simple, .medium, .complex, .batch]
        #expect(all.count == 4)
    }

    // MARK: - AIPrompt Struct

    @Test("AIPrompt construction with all fields")
    func promptConstruction() {
        let prompt = AIPrompt(
            systemPrompt: "You are a Japanese tutor.",
            userMessage: "What does this kanji mean?",
            context: ["level": "N5", "recentErrors": "2"],
            complexity: .medium
        )
        #expect(prompt.systemPrompt == "You are a Japanese tutor.")
        #expect(prompt.userMessage == "What does this kanji mean?")
        #expect(prompt.context["level"] == "N5")
        #expect(prompt.complexity == .medium)
    }

    @Test("AIPrompt defaults complexity to simple")
    func promptDefaultComplexity() {
        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Hello"
        )
        #expect(prompt.complexity == .simple)
    }

    @Test("AIPrompt defaults context to empty")
    func promptDefaultContext() {
        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Hello"
        )
        #expect(prompt.context.isEmpty)
    }

    // MARK: - AIResponse Struct

    @Test("AIResponse construction with all fields")
    func responseConstruction() {
        let response = AIResponse(
            content: "This kanji means water.",
            tier: .gemini,
            latencyMs: 450,
            tokenCount: 12
        )
        #expect(response.content == "This kanji means water.")
        #expect(response.tier == .gemini)
        #expect(response.latencyMs == 450)
        #expect(response.tokenCount == 12)
    }

    @Test("AIResponse tokenCount is optional and defaults to nil")
    func responseOptionalTokenCount() {
        let response = AIResponse(
            content: "Answer",
            tier: .onDevice,
            latencyMs: 100
        )
        #expect(response.tokenCount == nil)
    }

    // MARK: - AIError Enum

    @Test("AIError providerUnavailable carries tier")
    func errorProviderUnavailable() {
        let error = AIError.providerUnavailable(.gemini)
        if case .providerUnavailable(let tier) = error {
            #expect(tier == .gemini)
        } else {
            Issue.record("Expected providerUnavailable")
        }
    }

    @Test("AIError timeout carries tier")
    func errorTimeout() {
        let error = AIError.timeout(.claude)
        if case .timeout(let tier) = error {
            #expect(tier == .claude)
        } else {
            Issue.record("Expected timeout")
        }
    }

    @Test("AIError rateLimited carries tier")
    func errorRateLimited() {
        let error = AIError.rateLimited(.gemini)
        if case .rateLimited(let tier) = error {
            #expect(tier == .gemini)
        } else {
            Issue.record("Expected rateLimited")
        }
    }

    @Test("AIError invalidResponse exists")
    func errorInvalidResponse() {
        let error = AIError.invalidResponse
        if case .invalidResponse = error {
            // passes
        } else {
            Issue.record("Expected invalidResponse")
        }
    }

    @Test("AIError networkError carries underlying error")
    func errorNetworkError() {
        let underlying = URLError(.notConnectedToInternet)
        let error = AIError.networkError(underlying)
        if case .networkError(let inner) = error {
            #expect(inner is URLError)
        } else {
            Issue.record("Expected networkError")
        }
    }

    @Test("AIError keyNotFound carries key name")
    func errorKeyNotFound() {
        let error = AIError.keyNotFound("com.ikeru.gemini-api-key")
        if case .keyNotFound(let key) = error {
            #expect(key == "com.ikeru.gemini-api-key")
        } else {
            Issue.record("Expected keyNotFound")
        }
    }

    @Test("AIError allProvidersExhausted exists")
    func errorAllProvidersExhausted() {
        let error = AIError.allProvidersExhausted
        if case .allProvidersExhausted = error {
            // passes
        } else {
            Issue.record("Expected allProvidersExhausted")
        }
    }

    // MARK: - ProviderStatus Enum

    @Test("ProviderStatus has three cases")
    func providerStatusCases() {
        let all: [ProviderStatus] = [.available, .unavailable, .degraded]
        #expect(all.count == 3)
    }
}
