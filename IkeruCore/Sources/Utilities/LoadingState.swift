import Foundation

/// Generic loading state for async operations.
/// Used throughout the app to track the lifecycle of async data loading.
public enum LoadingState<T: Sendable>: Sendable {
    /// No loading has been initiated.
    case idle

    /// Data is currently being loaded.
    case loading

    /// Data loaded successfully.
    case loaded(T)

    /// Loading failed with an error.
    case failed(Error)

    /// Whether the state is currently loading.
    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// The loaded value, if available.
    public var value: T? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    /// The error, if loading failed.
    public var error: Error? {
        if case .failed(let error) = self { return error }
        return nil
    }

    /// Whether the state is idle (no loading initiated).
    public var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    /// Whether the state is loaded with a value.
    public var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    /// Whether the state is failed.
    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
