#if canImport(Speech)
import Testing
import Foundation
@testable import IkeruCore

@Suite("SpeechRecognitionService")
struct SpeechRecognitionServiceTests {

    // MARK: - SpeechPermissionStatus Tests

    @Suite("SpeechPermissionStatus")
    struct PermissionStatusTests {

        @Test("All permission status cases are distinct")
        func distinctCases() {
            let cases: [SpeechPermissionStatus] = [
                .notDetermined, .authorized, .denied, .restricted, .unavailable
            ]
            #expect(Set(cases).count == 5)
        }

        @Test("Permission status supports equality")
        func equatable() {
            #expect(SpeechPermissionStatus.authorized == SpeechPermissionStatus.authorized)
            #expect(SpeechPermissionStatus.denied != SpeechPermissionStatus.authorized)
        }
    }

    // MARK: - SpeechRecognitionResult Tests

    @Suite("SpeechRecognitionResult")
    struct ResultTests {

        @Test("Result stores text and isFinal flag")
        func resultProperties() {
            let result = SpeechRecognitionResult(text: "こんにちは", isFinal: true)
            #expect(result.text == "こんにちは")
            #expect(result.isFinal == true)
        }

        @Test("Non-final result")
        func nonFinalResult() {
            let result = SpeechRecognitionResult(text: "こん", isFinal: false)
            #expect(result.text == "こん")
            #expect(result.isFinal == false)
        }

        @Test("Empty text result")
        func emptyResult() {
            let result = SpeechRecognitionResult(text: "", isFinal: true)
            #expect(result.text.isEmpty)
            #expect(result.isFinal == true)
        }

        @Test("Results support equality")
        func equatable() {
            let a = SpeechRecognitionResult(text: "ねこ", isFinal: true)
            let b = SpeechRecognitionResult(text: "ねこ", isFinal: true)
            let c = SpeechRecognitionResult(text: "いぬ", isFinal: true)
            #expect(a == b)
            #expect(a != c)
        }
    }

    // MARK: - SpeechRecognitionError Tests

    @Suite("SpeechRecognitionError")
    struct ErrorTests {

        @Test("Error cases are available")
        func errorCases() {
            let errors: [SpeechRecognitionError] = [
                .recognizerUnavailable,
                .audioEngineError,
                .permissionDenied
            ]
            #expect(errors.count == 3)
        }

        @Test("Errors conform to Error protocol")
        func conformsToError() {
            let error: Error = SpeechRecognitionError.recognizerUnavailable
            #expect(error is SpeechRecognitionError)
        }
    }

    // MARK: - Service Initialization Tests

    @Suite("Initialization")
    struct InitTests {

        @Test("Service initializes with default state")
        @MainActor
        func defaultState() {
            let service = SpeechRecognitionService()
            #expect(service.isRecording == false)
            #expect(service.recognizedText == "")
            #expect(service.permissionStatus == .notDetermined)
        }
    }
}

#endif
