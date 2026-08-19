import Foundation

/// How a text got into the app.
///
/// The two doors lead to the same experience downstream — the vision is
/// explicit that « la porte d'entrée ne change rien à la suite » — so this is
/// recorded for the reading journal and for honesty about what was OCR'd, not
/// to branch behaviour.
public enum ImportSource: String, Sendable, Codable, CaseIterable, Identifiable {

    /// Pasted or typed by the learner. Zero friction, zero permission.
    case paste

    /// Recognised from a photo, then corrected by the learner if needed.
    case photo

    public var id: String { rawValue }

    /// Catalogue key, rendered by the view layer.
    ///
    /// A key rather than a string: `String(localized:)` inside IkeruCore
    /// resolves the wrong bundle and ignores the app's `AppLocale` override.
    /// See CLAUDE.md — this bit us before.
    public var labelKey: String {
        switch self {
        case .paste: "import.source.paste"
        case .photo: "import.source.photo"
        }
    }

    public var icon: String {
        switch self {
        case .paste: "doc.on.clipboard"
        case .photo: "camera"
        }
    }
}
