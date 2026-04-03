import Testing
import Foundation
@testable import Ikeru
@testable import IkeruCore

// MARK: - Mock AI Provider for ViewModel Tests

private final class MockAIProvider: AIProvider, @unchecked Sendable {
    let name = "MockProvider"
    var available: Bool = true
    var responseText: String = "はい、元気です！"
    var shouldThrow: Error?

    func isAvailable() async -> Bool { available }

    func generate(_ request: AIRequest) async throws -> AIResponse {
        if let error = shouldThrow {
            throw error
        }
        return AIResponse(text: responseText, providerName: name)
    }
}

// MARK: - Mock Speech Delegate

private final class MockSpeechDelegate: SpeechRecognitionDelegate, @unchecked Sendable {
    var isListening = false
    var lastCompletion: (@Sendable (SpeechResult) -> Void)?

    func startListening(completion: @escaping @Sendable (SpeechResult) -> Void) {
        isListening = true
        lastCompletion = completion
    }

    func stopListening() {
        isListening = false
    }
}

// MARK: - ConversationViewModel Tests

@Suite("ConversationViewModel")
@MainActor
struct ConversationViewModelTests {

    private func makeViewModel(
        available: Bool = true,
        responseText: String = "はい！",
        shouldThrow: Error? = nil,
        jlptLevel: JLPTLevel = .n5,
        speechDelegate: SpeechRecognitionDelegate? = nil
    ) -> (ConversationViewModel, MockAIProvider) {
        let provider = MockAIProvider()
        provider.available = available
        provider.responseText = responseText
        provider.shouldThrow = shouldThrow

        let router = AIRouterService(providers: [provider])
        let service = ConversationService(aiRouter: router, timeoutSeconds: 5.0)
        let vm = ConversationViewModel(
            conversationService: service,
            jlptLevel: jlptLevel,
            speechDelegate: speechDelegate
        )
        return (vm, provider)
    }

    @Test("Initial state is correct")
    func initialState() {
        let (vm, _) = makeViewModel()

        #expect(vm.messages.isEmpty)
        #expect(vm.inputText.isEmpty)
        #expect(vm.isLoading == false)
        #expect(vm.isVoiceActive == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.showWelcome == true)
        #expect(vm.canSend == false)
    }

    @Test("canSend is true with non-empty text")
    func canSendWithText() {
        let (vm, _) = makeViewModel()
        vm.inputText = "hello"

        #expect(vm.canSend == true)
    }

    @Test("canSend is false with whitespace only")
    func canSendWhitespace() {
        let (vm, _) = makeViewModel()
        vm.inputText = "   "

        #expect(vm.canSend == false)
    }

    @Test("Sends message and appends response")
    func sendMessage() async {
        let (vm, _) = makeViewModel(responseText: "こんにちは！")
        vm.inputText = "Hello"

        await vm.sendMessage()

        #expect(vm.messages.count == 2)
        #expect(vm.messages[0].role == .user)
        #expect(vm.messages[0].content == "Hello")
        #expect(vm.messages[1].role == .assistant)
        #expect(vm.messages[1].content == "こんにちは！")
        #expect(vm.inputText.isEmpty)
        #expect(vm.isLoading == false)
    }

    @Test("Send with text parameter")
    func sendMessageWithText() async {
        let (vm, _) = makeViewModel(responseText: "はい！")

        await vm.sendMessage("テスト")

        #expect(vm.messages.count == 2)
        #expect(vm.messages[0].content == "テスト")
    }

    @Test("Does not send empty message")
    func doesNotSendEmpty() async {
        let (vm, _) = makeViewModel()
        vm.inputText = ""

        await vm.sendMessage()

        #expect(vm.messages.isEmpty)
    }

    @Test("Handles provider error gracefully")
    func handlesError() async {
        let (vm, _) = makeViewModel(shouldThrow: AIProviderError.networkError("test"))
        vm.inputText = "hello"

        await vm.sendMessage()

        #expect(vm.messages.count == 1) // Only user message
        #expect(vm.errorMessage != nil)
        #expect(vm.isLoading == false)
    }

    @Test("Handles unavailable error")
    func handlesUnavailable() async {
        let (vm, _) = makeViewModel(available: false)
        vm.inputText = "hello"

        await vm.sendMessage()

        #expect(vm.errorMessage != nil)
    }

    @Test("Handles timeout error")
    func handlesTimeout() async {
        let (vm, _) = makeViewModel(shouldThrow: AIProviderError.timeout)
        vm.inputText = "hello"

        await vm.sendMessage()

        #expect(vm.errorMessage?.contains("too long") == true)
    }

    @Test("Handles rate limit error")
    func handlesRateLimit() async {
        let (vm, _) = makeViewModel(shouldThrow: AIProviderError.rateLimited)
        vm.inputText = "hello"

        await vm.sendMessage()

        #expect(vm.errorMessage?.contains("wait") == true)
    }

    @Test("Clear conversation resets state")
    func clearConversation() async {
        let (vm, _) = makeViewModel(responseText: "hi")
        vm.inputText = "test"
        await vm.sendMessage()

        vm.clearConversation()

        #expect(vm.messages.isEmpty)
        #expect(vm.errorMessage == nil)
        #expect(vm.showWelcome == true)
    }

    @Test("JLPT level is preserved")
    func jlptLevel() {
        let (vm, _) = makeViewModel(jlptLevel: .n3)
        #expect(vm.jlptLevel == .n3)
    }

    @Test("onAppear checks AI availability")
    func onAppearAvailability() async {
        let (vm, _) = makeViewModel(available: true)

        await vm.onAppear()

        #expect(vm.isAIAvailable == true)
    }

    @Test("onAppear detects unavailable AI")
    func onAppearUnavailable() async {
        let (vm, _) = makeViewModel(available: false)

        await vm.onAppear()

        #expect(vm.isAIAvailable == false)
    }

    @Test("Voice toggle without delegate shows error")
    func voiceToggleNoDelegate() {
        let (vm, _) = makeViewModel()

        vm.toggleVoiceInput()

        #expect(vm.isVoiceActive == false)
        #expect(vm.errorMessage != nil)
    }

    @Test("Voice toggle with delegate activates")
    func voiceToggleWithDelegate() {
        let delegate = MockSpeechDelegate()
        let (vm, _) = makeViewModel(speechDelegate: delegate)

        vm.toggleVoiceInput()

        #expect(vm.isVoiceActive == true)
        #expect(delegate.isListening == true)
    }

    @Test("Voice stop deactivates")
    func voiceStop() {
        let delegate = MockSpeechDelegate()
        let (vm, _) = makeViewModel(speechDelegate: delegate)

        vm.startVoiceInput()
        vm.stopVoiceInput()

        #expect(vm.isVoiceActive == false)
        #expect(delegate.isListening == false)
    }
}
