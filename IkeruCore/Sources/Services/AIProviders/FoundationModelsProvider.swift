import Foundation
import os

// MARK: - FoundationModelsProvider

/// On-device AI provider using Apple FoundationModels framework (iOS 26+).
/// Falls back gracefully on older devices by returning isAvailable = false.
public final class FoundationModelsProvider: AIProvider, @unchecked Sendable {

    public let name = "FoundationModels"
    public let tier = AITier.onDevice

    public init() {}

    public var isAvailable: Bool {
        get async {
            #if canImport(FoundationModels)
            if #available(iOS 26, macOS 26, *) {
                return OnDeviceModelSession.isSupported
            }
            #endif
            return false
        }
    }

    public func generate(prompt: AIPrompt) async throws -> AIResponse {
        let start = ContinuousClock.now

        guard await isAvailable else {
            Logger.ai.warning("FoundationModels not available on this device")
            throw AIError.providerUnavailable(.onDevice)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            return try await generateWithFoundationModels(prompt: prompt, start: start)
        }
        #endif

        throw AIError.providerUnavailable(.onDevice)
    }

    #if canImport(FoundationModels)
    @available(iOS 26, macOS 26, *)
    private func generateWithFoundationModels(
        prompt: AIPrompt,
        start: ContinuousClock.Instant
    ) async throws -> AIResponse {
        do {
            let session = OnDeviceModelSession(instructions: prompt.systemPrompt)
            let result = try await session.respond(to: prompt.userMessage)
            let elapsed = ContinuousClock.now - start
            let latencyMs = Int(elapsed.components.seconds * 1000
                + elapsed.components.attoseconds / 1_000_000_000_000_000)

            Logger.ai.info("FoundationModels generated response in \(latencyMs)ms")
            return AIResponse(
                content: result,
                tier: .onDevice,
                latencyMs: latencyMs
            )
        } catch {
            Logger.ai.error("FoundationModels generation failed: \(error)")
            throw AIError.providerUnavailable(.onDevice)
        }
    }
    #endif
}

// MARK: - FoundationModels Session Wrapper

/// Thin wrapper around Apple FoundationModels for conditional compilation.
#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, macOS 26, *)
private struct OnDeviceModelSession {

    static var isSupported: Bool {
        SystemLanguageModel.default.isAvailable
    }

    private let session: LanguageModelSession

    init(instructions: String) {
        self.session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: instructions
        )
    }

    func respond(to message: String) async throws -> String {
        let response = try await session.respond(to: message)
        return String(describing: response)
    }
}
#endif

// MARK: - MockFoundationModelsProvider

/// Mock provider for testing without a real device.
public final class MockFoundationModelsProvider: AIProvider, @unchecked Sendable {

    public let name = "FoundationModels"
    public let tier = AITier.onDevice

    private let available: Bool
    private let responseContent: String

    public init(available: Bool, responseContent: String) {
        self.available = available
        self.responseContent = responseContent
    }

    public var isAvailable: Bool {
        get async { available }
    }

    public func generate(prompt: AIPrompt) async throws -> AIResponse {
        guard available else {
            throw AIError.providerUnavailable(.onDevice)
        }

        return AIResponse(
            content: responseContent,
            tier: .onDevice,
            latencyMs: 50
        )
    }
}
