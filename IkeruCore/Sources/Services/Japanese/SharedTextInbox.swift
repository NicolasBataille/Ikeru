import Foundation
import os

// MARK: - SharedTextInbox

/// Hand-off between the share extension and the app: one pending text, waiting
/// in the shared App Group container.
///
/// ## Why a drop box rather than a direct jump
///
/// A share extension cannot reliably open its host app on iOS. The tricks that
/// appear to work walk the responder chain to find a `UIApplication` and are
/// both undocumented and a review risk. So the extension **writes**, the app
/// **reads** on activation, and the learner sees « un texte t'attend » the next
/// time they open Ikeru. Slower than a jump by exactly the time it takes to tap
/// the icon, and it cannot break.
///
/// ## One slot, last write wins
///
/// Deliberately not a queue. Sharing three articles then opening the app once
/// would face the learner with a backlog to triage — the exact review-debt
/// feeling the whole feature is built to avoid. The most recent share is the
/// one they meant; a queue would be a to-do list nobody asked for.
///
/// The text is **consumed** on read: `take()` returns it and clears the slot, so
/// re-opening the app does not offer the same text again forever.
public struct SharedTextInbox: Sendable {

    /// The App Group both targets already share (widget, app, and now the share
    /// extension). Declared in each target's entitlements.
    public static let appGroup = "group.com.ikeru.shared"

    private static let key = "sharedText.pending"
    private static let dateKey = "sharedText.receivedAt"

    // `UserDefaults` n'est pas `Sendable` pour le compilateur, mais l'est en
    // pratique (documenté thread-safe par Apple). L'annotation est portée ici
    // plutôt que de retirer `Sendable` du type : la boîte doit pouvoir
    // traverser les frontières d'acteur, c'est tout son objet.
    private nonisolated(unsafe) let defaults: UserDefaults?

    /// - Parameter suiteName: overridable so tests never touch the real group.
    public init(suiteName: String = SharedTextInbox.appGroup) {
        self.defaults = UserDefaults(suiteName: suiteName)
        if defaults == nil {
            Logger.content.error("App Group \(suiteName) unavailable — shared text will be dropped")
        }
    }

    /// Whether a text is waiting. Cheap enough to ask on every activation.
    public var hasPending: Bool {
        guard let text = defaults?.string(forKey: Self.key) else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// When the waiting text arrived, if any.
    public var receivedAt: Date? {
        guard hasPending else { return nil }
        let stamp = defaults?.double(forKey: Self.dateKey) ?? 0
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// Stores a shared text, replacing whatever was waiting.
    ///
    /// Whitespace-only input is refused rather than stored: a share sheet fired
    /// by accident should not make the app announce that a text is waiting.
    @discardableResult
    public func deposit(_ text: String, at date: Date = Date()) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let defaults else { return false }
        defaults.set(text, forKey: Self.key)
        defaults.set(date.timeIntervalSince1970, forKey: Self.dateKey)
        return true
    }

    /// Returns the waiting text **and clears the slot**.
    public func take() -> String? {
        guard let defaults, let text = defaults.string(forKey: Self.key),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        defaults.removeObject(forKey: Self.key)
        defaults.removeObject(forKey: Self.dateKey)
        return text
    }

    /// Drops the waiting text without reading it — « non, pas maintenant ».
    public func discard() {
        defaults?.removeObject(forKey: Self.key)
        defaults?.removeObject(forKey: Self.dateKey)
    }
}
