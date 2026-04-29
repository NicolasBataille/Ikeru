import SwiftUI

// MARK: - Tatami Tokens
//
// Tatami-specific colors that don't belong in `IkeruTheme.Colors` because
// they don't apply outside the Tatami visual vocabulary. Vermilion is the
// hanko-stamp red — used at most once per screen. Gold-dim is the lower-
// intensity sibling of `IkeruTheme.Colors.primaryAccent` used for hairline
// shadows in fusuma rails and inactive sumi corners.

enum TatamiTokens {
    // The single warm red of the entire UI. Used only on hanko stamps.
    static let vermilion = Color(red: 0.78, green: 0.243, blue: 0.20)   // #C73E33

    // Subdued gold, used for hairline shadows and quiet sumi marks.
    static let goldDim = Color(red: 0.541, green: 0.427, blue: 0.290)   // #8A6D4A

    // Paper-ghost — barely-visible labels.
    static let paperGhost = Color(red: 0.478, green: 0.467, blue: 0.439) // #7A7770
}

// MARK: - Mon Kind
//
// Four geometric family-crest patterns. Each kind has a stable identity
// across the app (Hiragana = maru, Katakana = genji, Vocabulary = asanoha,
// Listening = kikkou) so users learn to associate a deck with its crest.

enum MonKind: String, Sendable, CaseIterable {
    case asanoha   // hemp-leaf — 6-pointed star inside circle
    case genji     // genji-wheel — circle with cross
    case kikkou    // hexagon (tortoiseshell)
    case maru      // simple ring
}
