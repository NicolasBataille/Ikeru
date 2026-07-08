import SwiftUI
import UIKit
import IkeruCore

// MARK: - Premium Typography

extension Font {

    // MARK: - Display (hero moments — layout-sized, NOT scaled)

    /// Massive display text (56pt, ultra-light, tight tracking) — layout-sized, fixed.
    static var ikeruDisplayLarge: Font {
        .system(size: IkeruTheme.Typography.Size.displayLarge, weight: .ultraLight, design: .default)
    }

    /// Compact display (36pt, regular) — layout-sized, fixed.
    static var ikeruDisplaySmall: Font {
        .system(size: IkeruTheme.Typography.Size.displaySmall, weight: .regular, design: .default)
    }

    // MARK: - Kanji (Noto Serif JP)

    /// Hero kanji (96pt, Noto Serif JP Bold) — layout-sized, fixed.
    static var kanjiHero: Font {
        .custom(
            IkeruTheme.Typography.FontFamily.kanjiSerif,
            size: IkeruTheme.Typography.Size.kanjiHero
        )
    }

    /// Standard kanji display (64pt) — layout-sized, fixed.
    static var kanjiDisplay: Font {
        .custom(
            IkeruTheme.Typography.FontFamily.kanjiSerif,
            size: IkeruTheme.Typography.Size.kanjiDisplay
        )
    }

    /// Medium kanji (40pt) — layout-sized, fixed.
    static var kanjiMedium: Font {
        .custom(
            IkeruTheme.Typography.FontFamily.kanjiSerif,
            size: IkeruTheme.Typography.Size.kanjiMedium
        )
    }

    /// Inline kanji within text (24pt) — scales with Dynamic Type (.title2 band).
    static var kanjiInline: Font {
        .custom(
            IkeruTheme.Typography.FontFamily.kanjiSerif,
            size: IkeruTheme.Typography.Size.kanjiInline,
            relativeTo: .title2
        )
    }

    // MARK: - Headings (scalable)

    /// Heading 1 (32pt, semibold, tight) — scales with Dynamic Type (.title band).
    static var ikeruHeading1: Font {
        Font(UIFontMetrics(forTextStyle: .title1).scaledFont(
            for: UIFont.systemFont(ofSize: IkeruTheme.Typography.Size.heading1, weight: .semibold)
        ))
    }

    /// Heading 2 (24pt, medium) — scales with Dynamic Type (.title2 band).
    static var ikeruHeading2: Font {
        Font(UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: UIFont.systemFont(ofSize: IkeruTheme.Typography.Size.heading2, weight: .medium)
        ))
    }

    /// Heading 3 (19pt, medium) — scales with Dynamic Type (.title3 band).
    static var ikeruHeading3: Font {
        Font(UIFontMetrics(forTextStyle: .title3).scaledFont(
            for: UIFont.systemFont(ofSize: IkeruTheme.Typography.Size.heading3, weight: .medium)
        ))
    }

    // MARK: - Body (scalable)

    /// Large body text (17pt regular) — scales with Dynamic Type (.body band).
    static var ikeruBodyLarge: Font {
        Font(UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.systemFont(ofSize: IkeruTheme.Typography.Size.bodyLarge, weight: .regular)
        ))
    }

    /// Body text (15pt regular) — scales with Dynamic Type (.body band).
    static var ikeruBody: Font {
        Font(UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: UIFont.systemFont(ofSize: IkeruTheme.Typography.Size.body, weight: .regular)
        ))
    }

    // MARK: - Caption / Micro (scalable)

    /// Caption (12pt medium) — scales with Dynamic Type (.caption2 band).
    static var ikeruCaption: Font {
        Font(UIFontMetrics(forTextStyle: .caption2).scaledFont(
            for: UIFont.systemFont(ofSize: IkeruTheme.Typography.Size.caption, weight: .medium)
        ))
    }

    /// Micro label (11pt semibold uppercase) — scales with Dynamic Type (.caption2 band).
    static var ikeruMicro: Font {
        Font(UIFontMetrics(forTextStyle: .caption2).scaledFont(
            for: UIFont.systemFont(ofSize: IkeruTheme.Typography.Size.micro, weight: .semibold)
        ))
    }

    // MARK: - Mono (stats / numbers, scalable)

    /// Stats display (14pt mono medium) — scales with Dynamic Type (.footnote band).
    static var ikeruStats: Font {
        Font(UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: UIFont.monospacedSystemFont(ofSize: IkeruTheme.Typography.Size.stats, weight: .medium)
        ))
    }

    /// Large stats (24pt mono regular — for hero numbers) — scales with Dynamic Type (.body band).
    static var ikeruStatsLarge: Font {
        Font(UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.monospacedSystemFont(ofSize: 24, weight: .regular)
        ))
    }
}

// MARK: - ikeruScaledFont helper

/// ViewModifier that scales a custom-size system font with Dynamic Type.
private struct IkeruScaledFontModifier: ViewModifier {
    let weight: Font.Weight
    let design: Font.Design

    @ScaledMetric var scaledSize: CGFloat

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo textStyle: Font.TextStyle) {
        self.weight = weight
        self.design = design
        self._scaledSize = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: scaledSize, weight: weight, design: design))
    }
}

extension View {
    /// Apply a system font that scales with Dynamic Type.
    ///
    /// Preserves the exact base size at the default text-size setting.
    /// Choose `relativeTo` by size band:
    /// - ≤12 → `.caption2`
    /// - 13–14 → `.caption`
    /// - 15–17 → `.body` (default)
    /// - 18–21 → `.title3`
    /// - 22–27 → `.title2`
    /// - ≥28 → `.title`
    func ikeruScaledFont(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> some View {
        modifier(IkeruScaledFontModifier(size: size, weight: weight, design: design, relativeTo: textStyle))
    }

    // MARK: - Tracking modifier

    /// Apply premium typography tracking based on content type.
    func ikeruTracking(_ kind: IkeruTrackingKind) -> some View {
        self.tracking(kind.value)
    }
}

// MARK: - Tracking kinds

enum IkeruTrackingKind {
    case display
    case heading
    case body
    case caption
    case micro

    var value: CGFloat {
        switch self {
        case .display: return IkeruTheme.Typography.Tracking.display
        case .heading: return IkeruTheme.Typography.Tracking.heading
        case .body: return IkeruTheme.Typography.Tracking.body
        case .caption: return IkeruTheme.Typography.Tracking.caption
        case .micro: return IkeruTheme.Typography.Tracking.micro
        }
    }
}
