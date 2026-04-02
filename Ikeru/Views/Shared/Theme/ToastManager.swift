import SwiftUI
import IkeruCore
import os

// MARK: - Toast Type

public enum ToastType: Sendable {
    case info
    case error
}

// MARK: - Toast Item

public struct ToastItem: Identifiable, Sendable {
    public let id = UUID()
    public let message: String
    public let type: ToastType

    public init(message: String, type: ToastType) {
        self.message = message
        self.type = type
    }
}

// MARK: - ToastManager

@MainActor
@Observable
public final class ToastManager {

    public var currentToast: ToastItem?

    private var dismissTask: Task<Void, Never>?

    public init() {}

    // MARK: - Show Toast

    public func showInfo(_ message: String) {
        Logger.ui.info("Toast info: \(message)")
        dismissTask?.cancel()
        currentToast = ToastItem(message: message, type: .info)

        dismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self.dismiss()
        }
    }

    public func showError(_ message: String) {
        Logger.ui.error("Toast error: \(message)")
        dismissTask?.cancel()
        currentToast = ToastItem(message: message, type: .error)
        // Error toasts persist until manually dismissed
    }

    // MARK: - Dismiss

    public func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        currentToast = nil
    }
}

// MARK: - Environment Key

private struct ToastManagerKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue = ToastManager()
}

extension EnvironmentValues {
    public var toastManager: ToastManager {
        get { self[ToastManagerKey.self] }
        set { self[ToastManagerKey.self] = newValue }
    }
}
