import Foundation
import SwiftData
import os

// MARK: - MnemonicResult

/// The result of a mnemonic generation request.
public struct MnemonicResult: Sendable {
    /// The generated mnemonic text.
    public let text: String

    /// Which AI tier produced the mnemonic.
    public let tier: AITier

    public init(text: String, tier: AITier) {
        self.text = text
        self.tier = tier
    }
}

// MARK: - MnemonicProvider Protocol

/// Provides AI-generated mnemonics for kanji characters with caching.
public protocol MnemonicProvider: Sendable {
    /// Generate a mnemonic for a kanji character. Returns cached result if available.
    /// - Parameters:
    ///   - character: The kanji character (e.g., "日").
    ///   - radicals: Radical meanings that compose the kanji.
    ///   - readings: On/kun readings for context.
    /// - Returns: A mnemonic result with the generated text and AI tier used.
    func generateMnemonic(
        for character: String,
        radicals: [String],
        readings: [String]
    ) async throws -> MnemonicResult

    /// Retrieve a cached mnemonic for a character, if one exists.
    /// - Parameter character: The kanji character.
    /// - Returns: The cached mnemonic text, or nil if not cached.
    func cachedMnemonic(for character: String) async -> String?

    /// Clear the cached mnemonic for a character.
    /// - Parameter character: The kanji character.
    func clearCache(for character: String) async throws
}

// MARK: - MnemonicService

/// AI-powered mnemonic generation with SwiftData caching.
///
/// Checks the local SwiftData cache before calling the AI router.
/// Generated mnemonics are persisted so subsequent views of the same
/// kanji load instantly without an AI round-trip.
@MainActor
public final class MnemonicService: MnemonicProvider {

    // MARK: - Dependencies

    private let aiRouter: AIRouterService
    private let modelContainer: ModelContainer

    // MARK: - Init

    /// - Parameters:
    ///   - aiRouter: The AI router for generating mnemonics.
    ///   - modelContainer: SwiftData container for cache persistence.
    public init(aiRouter: AIRouterService, modelContainer: ModelContainer) {
        self.aiRouter = aiRouter
        self.modelContainer = modelContainer
    }

    // MARK: - MnemonicProvider

    public func generateMnemonic(
        for character: String,
        radicals: [String],
        readings: [String]
    ) async throws -> MnemonicResult {
        // Check cache first
        if let entry = await cachedEntry(for: character) {
            Logger.ai.info("Mnemonic cache hit for '\(character)'")
            let tier = AITier(rawValue: Int(entry.tierUsed) ?? 0) ?? .onDevice
            return MnemonicResult(text: entry.mnemonic, tier: tier)
        }

        Logger.ai.info("Mnemonic cache miss for '\(character)' — generating via AI")

        let prompt = buildPrompt(character: character, radicals: radicals, readings: readings)
        let response = try await aiRouter.generate(prompt: prompt)

        let mnemonicText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !mnemonicText.isEmpty else {
            throw MnemonicGenerationError.emptyResponse
        }

        persistToCache(character: character, mnemonic: mnemonicText, tier: response.tier)

        Logger.ai.info("Mnemonic generated for '\(character)' via tier \(response.tier.rawValue) in \(response.latencyMs)ms")

        return MnemonicResult(text: mnemonicText, tier: response.tier)
    }

    public func cachedMnemonic(for character: String) async -> String? {
        cachedEntry(for: character)?.mnemonic
    }

    /// Retrieves the full cache entry for a character, if one exists.
    private func cachedEntry(for character: String) -> MnemonicCache? {
        let context = modelContainer.mainContext
        let predicate = #Predicate<MnemonicCache> { $0.character == character }
        var descriptor = FetchDescriptor<MnemonicCache>(predicate: predicate)
        descriptor.fetchLimit = 1

        do {
            return try context.fetch(descriptor).first
        } catch {
            Logger.ai.warning("Failed to fetch cached mnemonic for '\(character)': \(error)")
            return nil
        }
    }

    public func clearCache(for character: String) async throws {
        let context = modelContainer.mainContext
        let predicate = #Predicate<MnemonicCache> { $0.character == character }
        let descriptor = FetchDescriptor<MnemonicCache>(predicate: predicate)

        let results = try context.fetch(descriptor)
        for entry in results {
            context.delete(entry)
        }
        try context.save()

        Logger.ai.info("Cleared mnemonic cache for '\(character)'")
    }

    // MARK: - Private

    private func buildPrompt(
        character: String,
        radicals: [String],
        readings: [String]
    ) -> AIPrompt {
        let systemPrompt = """
        You are a Japanese language learning assistant. Generate a memorable, vivid mnemonic \
        to help the learner remember this kanji. Use the radical components as building blocks \
        for a short story or visual image. Keep the mnemonic concise (2-3 sentences max). \
        Do not include the kanji character itself in the mnemonic. \
        Respond with only the mnemonic text, no labels or formatting.
        """

        let radicalsDescription = radicals.isEmpty
            ? "unknown"
            : radicals.joined(separator: ", ")

        let readingsDescription = readings.isEmpty
            ? "unknown"
            : readings.joined(separator: ", ")

        let userMessage = """
        Kanji: \(character)
        Radicals: \(radicalsDescription)
        Readings: \(readingsDescription)
        """

        return AIPrompt(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            context: [
                "character": character,
                "radicals": radicalsDescription,
                "readings": readingsDescription,
            ],
            complexity: .simple
        )
    }

    private func persistToCache(character: String, mnemonic: String, tier: AITier) {
        let context = modelContainer.mainContext
        // Upsert: update existing entry or insert new one
        let predicate = #Predicate<MnemonicCache> { $0.character == character }
        var descriptor = FetchDescriptor<MnemonicCache>(predicate: predicate)
        descriptor.fetchLimit = 1

        do {
            if let existing = try context.fetch(descriptor).first {
                existing.mnemonic = mnemonic
                existing.tierUsed = String(tier.rawValue)
                existing.generatedAt = Date()
            } else {
                let entry = MnemonicCache(
                    character: character,
                    mnemonic: mnemonic,
                    tierUsed: String(tier.rawValue)
                )
                context.insert(entry)
            }
            try context.save()
        } catch {
            Logger.ai.error("Failed to persist mnemonic cache for '\(character)': \(error)")
        }
    }
}

// MARK: - MnemonicGenerationError

public enum MnemonicGenerationError: Error, LocalizedError {
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .emptyResponse:
            "AI returned an empty mnemonic response."
        }
    }
}
