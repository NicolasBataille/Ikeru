import SwiftUI
import IkeruCore

// MARK: - Premium Typography

extension Font {

    // MARK: - Display (hero moments)

    /// Massive display text (56pt, ultra-light, tight tracking)
    static var ikeruDisplayLarge: Font {
        .system(size: IkeruTheme.Typography.Size.displayLarge, weight: .ultraLight, design: .default)
    }

    /// Large display (44pt, light)
    static var ikeruDisplayMedium: Font {
        .system(size: IkeruTheme.Typography.Size.displayMedium, weight: .light, design: .default)
    }

    /// Compact display (36pt, regular)
    static var ikeruDisplaySmall: Font {
        .system(size: IkeruTheme.Typography.Size.displaySmall, weight: .regular, design: .default)
    }

    // MARK: - Kanji (Noto Serif JP)

    /// Hero kanji (96pt, Noto Serif JP Bold)
    static var kanjiHero: Font {
        .custom(
            IkeruTheme.Typography.FontFamily.kanjiSerif,
            size: IkeruTheme.Typography.Size.kanjiHero
        )
    }

    /// Standard kanji display (64pt)
    static var kanjiDisplay: Font {
        .custom(
            IkeruTheme.Typography.FontFamily.kanjiSerif,
            size: IkeruTheme.Typography.Size.kanjiDisplay
        )
    }

    /// Medium kanji (40pt)
    static var kanjiMedium: Font {
        .custom(
            IkeruTheme.Typography.FontFamily.kanjiSerif,
            size: IkeruTheme.Typography.Size.kanjiMedium
        )
    }

    /// Inline kanji within text (24pt)
    static var kanjiInline: Font {
        .custom(
            IkeruTheme.Typography.FontFamily.kanjiSerif,
            size: IkeruTheme.Typography.Size.kanjiInline
        )
    }

    // MARK: - Headings

    /// Heading 1 (32pt, semibold, tight)
    static var ikeruHeading1: Font {
        .system(size: IkeruTheme.Typography.Size.heading1, weight: .semibold, design: .default)
    }

    /// Heading 2 (24pt, medium)
    static var ikeruHeading2: Font {
        .system(size: IkeruTheme.Typography.Size.heading2, weight: .medium, design: .default)
    }

    /// Heading 3 (19pt, medium)
    static var ikeruHeading3: Font {
        .system(size: IkeruTheme.Typography.Size.heading3, weight: .medium, design: .default)
    }

    // MARK: - Body

    /// Large body text (17pt regular)
    static var ikeruBodyLarge: Font {
        .system(size: IkeruTheme.Typography.Size.bodyLarge, weight: .regular)
    }

    /// Body text (15pt regular)
    static var ikeruBody: Font {
        .system(size: IkeruTheme.Typography.Size.body, weight: .regular)
    }

    /// Small body text (13pt regular)
    static var ikeruBodySmall: Font {
        .system(size: IkeruTheme.Typography.Size.bodySmall, weight: .regular)
    }

    // MARK: - Caption / Micro

    /// Caption (12pt medium)
    static var ikeruCaption: Font {
        .system(size: IkeruTheme.Typography.Size.caption, weight: .medium)
    }

    /// Micro label (11pt semibold uppercase)
    static var ikeruMicro: Font {
        .system(size: IkeruTheme.Typography.Size.micro, weight: .semibold)
    }

    // MARK: - Mono (stats / numbers)

    /// Stats display (14pt mono medium)
    static var ikeruStats: Font {
        .system(size: IkeruTheme.Typography.Size.stats, design: .monospaced)
            .weight(.medium)
    }

    /// Large stats (24pt mono regular — for hero numbers)
    static var ikeruStatsLarge: Font {
        .system(size: 24, design: .monospaced)
            .weight(.regular)
    }
}

// MARK: - Tracking modifier

extension View {
    /// Apply premium typography tracking based on content type.
    func ikeruTracking(_ kind: IkeruTrackingKind) -> some View {
        self.tracking(kind.value)
    }
}

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
