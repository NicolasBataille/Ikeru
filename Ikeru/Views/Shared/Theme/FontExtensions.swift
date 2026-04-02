import SwiftUI
import IkeruCore

// MARK: - Font Extensions for IkeruTheme

extension Font {

    // MARK: - Kanji Fonts (Noto Serif JP)

    /// Large hero kanji display (64pt, Noto Serif JP Bold)
    static var kanjiHero: Font {
        .custom(
            IkeruTheme.Typography.FontFamily.kanjiSerif,
            size: IkeruTheme.Typography.Size.kanjiHero
        )
    }

    /// Standard kanji display (48pt, Noto Serif JP Bold)
    static var kanjiDisplay: Font {
        .custom(
            IkeruTheme.Typography.FontFamily.kanjiSerif,
            size: IkeruTheme.Typography.Size.kanjiDisplay
        )
    }

    /// Medium kanji (32pt, Noto Serif JP Bold)
    static var kanjiMedium: Font {
        .custom(
            IkeruTheme.Typography.FontFamily.kanjiSerif,
            size: IkeruTheme.Typography.Size.kanjiMedium
        )
    }

    // MARK: - System Fonts (SF Pro)

    /// Heading 1 (28pt, SF Pro Bold)
    static var ikeruHeading1: Font {
        .system(size: IkeruTheme.Typography.Size.heading1, weight: .bold)
    }

    /// Heading 2 (22pt, SF Pro Semibold)
    static var ikeruHeading2: Font {
        .system(size: IkeruTheme.Typography.Size.heading2, weight: .semibold)
    }

    /// Heading 3 (18pt, SF Pro Semibold)
    static var ikeruHeading3: Font {
        .system(size: IkeruTheme.Typography.Size.heading3, weight: .semibold)
    }

    /// Body text (16pt, SF Pro Regular)
    static var ikeruBody: Font {
        .system(size: IkeruTheme.Typography.Size.body)
    }

    /// Caption text (13pt, SF Pro Regular)
    static var ikeruCaption: Font {
        .system(size: IkeruTheme.Typography.Size.caption)
    }

    // MARK: - Mono Fonts (SF Mono)

    /// Stats/numbers display (14pt, SF Mono Medium)
    static var ikeruStats: Font {
        .system(size: IkeruTheme.Typography.Size.stats, design: .monospaced)
            .weight(.medium)
    }
}
