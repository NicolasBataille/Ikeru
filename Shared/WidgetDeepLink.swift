import Foundation

/// Deep-link URLs shared between `IkeruWidget` (which sets `.widgetURL`) and
/// the `Ikeru` app target (which handles them in `onOpenURL`). Kept as a
/// single shared constant so the two sides can't drift on the scheme/host.
enum WidgetDeepLink {
    /// Opens the app straight into a review session — posted by
    /// `IkeruApp.onOpenURL` as `.startReviewFromShortcut`, the same
    /// notification the "Review Japanese" Siri Shortcut already uses.
    static let review = URL(string: "ikeru://review")
}
