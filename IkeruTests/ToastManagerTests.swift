import Testing
@testable import Ikeru

@Suite("ToastManager")
@MainActor
struct ToastManagerTests {

    @Test("Initially has no toast")
    func initiallyNoToast() {
        let manager = ToastManager()
        #expect(manager.currentToast == nil)
    }

    @Test("Show info creates info toast")
    func showInfoCreatesInfoToast() {
        let manager = ToastManager()
        manager.showInfo("Test message")
        #expect(manager.currentToast != nil)
        #expect(manager.currentToast?.message == "Test message")
        #expect(manager.currentToast?.type == .info)
    }

    @Test("Show error creates error toast")
    func showErrorCreatesErrorToast() {
        let manager = ToastManager()
        manager.showError("Error occurred")
        #expect(manager.currentToast != nil)
        #expect(manager.currentToast?.message == "Error occurred")
        #expect(manager.currentToast?.type == .error)
    }

    @Test("Dismiss clears current toast")
    func dismissClearsToast() {
        let manager = ToastManager()
        manager.showInfo("Test")
        manager.dismiss()
        #expect(manager.currentToast == nil)
    }

    @Test("New toast replaces previous toast")
    func newToastReplacesPrevious() {
        let manager = ToastManager()
        manager.showInfo("First")
        manager.showError("Second")
        #expect(manager.currentToast?.message == "Second")
        #expect(manager.currentToast?.type == .error)
    }
}
