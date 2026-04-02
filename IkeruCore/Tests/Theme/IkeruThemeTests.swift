import Testing
@testable import IkeruCore

@Suite("IkeruTheme Design Tokens")
struct IkeruThemeTests {

    // MARK: - Colors

    @Suite("Colors")
    struct ColorsTests {

        @Test("Background color is dark navy")
        func background() {
            #expect(IkeruTheme.Colors.background == 0x1A1A2E)
        }

        @Test("Surface color is dark purple-gray")
        func surface() {
            #expect(IkeruTheme.Colors.surface == 0x252540)
        }

        @Test("Primary accent is amber")
        func primaryAccent() {
            #expect(IkeruTheme.Colors.primaryAccent == 0xFFB347)
        }

        @Test("Secondary accent is vermillion")
        func secondaryAccent() {
            #expect(IkeruTheme.Colors.secondaryAccent == 0xFF6B6B)
        }

        @Test("Success is teal")
        func success() {
            #expect(IkeruTheme.Colors.success == 0x4ECDC4)
        }

        @Test("Kanji text is warm white")
        func kanjiText() {
            #expect(IkeruTheme.Colors.kanjiText == 0xF5F0E8)
        }

        @Test("Text primary is white")
        func textPrimary() {
            #expect(IkeruTheme.Colors.textPrimary == 0xFFFFFF)
        }

        @Test("Text secondary opacity is 60%")
        func textSecondaryOpacity() {
            #expect(IkeruTheme.Colors.textSecondaryOpacity == 0.6)
        }
    }

    // MARK: - SRS Stage Colors

    @Suite("SRS Stage Colors")
    struct SRSColorsTests {

        @Test("Apprentice color")
        func apprentice() {
            #expect(IkeruTheme.Colors.SRS.apprentice == 0xFF9A76)
        }

        @Test("Guru color")
        func guru() {
            #expect(IkeruTheme.Colors.SRS.guru == 0xFFB347)
        }

        @Test("Master color")
        func master() {
            #expect(IkeruTheme.Colors.SRS.master == 0x4ECDC4)
        }

        @Test("Enlightened color")
        func enlightened() {
            #expect(IkeruTheme.Colors.SRS.enlightened == 0xB44AFF)
        }

        @Test("Burned color")
        func burned() {
            #expect(IkeruTheme.Colors.SRS.burned == 0xFFD700)
        }
    }

    // MARK: - Skill Colors

    @Suite("Skill Colors")
    struct SkillColorsTests {

        @Test("Reading color")
        func reading() {
            #expect(IkeruTheme.Colors.Skills.reading == 0x4A9EFF)
        }

        @Test("Writing color")
        func writing() {
            #expect(IkeruTheme.Colors.Skills.writing == 0x4ECDC4)
        }

        @Test("Listening color")
        func listening() {
            #expect(IkeruTheme.Colors.Skills.listening == 0xFFB347)
        }

        @Test("Speaking color")
        func speaking() {
            #expect(IkeruTheme.Colors.Skills.speaking == 0xFF6B6B)
        }
    }

    // MARK: - Loot Rarity Colors

    @Suite("Loot Rarity Colors")
    struct RarityColorsTests {

        @Test("Common is gray")
        func common() {
            #expect(IkeruTheme.Colors.Rarity.common == 0x808080)
        }

        @Test("Rare is blue")
        func rare() {
            #expect(IkeruTheme.Colors.Rarity.rare == 0x4A9EFF)
        }

        @Test("Epic is purple")
        func epic() {
            #expect(IkeruTheme.Colors.Rarity.epic == 0xB44AFF)
        }

        @Test("Legendary is gold")
        func legendary() {
            #expect(IkeruTheme.Colors.Rarity.legendary == 0xFFD700)
        }
    }

    // MARK: - Typography

    @Suite("Typography")
    struct TypographyTests {

        @Test("Kanji serif font family name")
        func kanjiSerifFamily() {
            #expect(IkeruTheme.Typography.FontFamily.kanjiSerif == "NotoSerifJP-Bold")
        }

        @Test("Kanji serif medium font family name")
        func kanjiSerifMediumFamily() {
            #expect(IkeruTheme.Typography.FontFamily.kanjiSerifMedium == "NotoSerifJP-Medium")
        }

        @Test("Kanji hero size is 64pt")
        func kanjiHeroSize() {
            #expect(IkeruTheme.Typography.Size.kanjiHero == 64)
        }

        @Test("Kanji display size is 48pt")
        func kanjiDisplaySize() {
            #expect(IkeruTheme.Typography.Size.kanjiDisplay == 48)
        }

        @Test("Kanji medium size is 32pt")
        func kanjiMediumSize() {
            #expect(IkeruTheme.Typography.Size.kanjiMedium == 32)
        }

        @Test("Body size is 16pt")
        func bodySize() {
            #expect(IkeruTheme.Typography.Size.body == 16)
        }

        @Test("Caption size is 13pt")
        func captionSize() {
            #expect(IkeruTheme.Typography.Size.caption == 13)
        }

        @Test("Stats size is 14pt")
        func statsSize() {
            #expect(IkeruTheme.Typography.Size.stats == 14)
        }
    }

    // MARK: - Spacing

    @Suite("Spacing")
    struct SpacingTests {

        @Test("Spacing values follow scale")
        func spacingScale() {
            #expect(IkeruTheme.Spacing.xs == 4)
            #expect(IkeruTheme.Spacing.sm == 8)
            #expect(IkeruTheme.Spacing.md == 16)
            #expect(IkeruTheme.Spacing.lg == 24)
            #expect(IkeruTheme.Spacing.xl == 32)
            #expect(IkeruTheme.Spacing.xxl == 48)
        }
    }

    // MARK: - Radius

    @Suite("Radius")
    struct RadiusTests {

        @Test("Radius values follow scale")
        func radiusScale() {
            #expect(IkeruTheme.Radius.sm == 8)
            #expect(IkeruTheme.Radius.md == 12)
            #expect(IkeruTheme.Radius.lg == 16)
            #expect(IkeruTheme.Radius.xl == 24)
            #expect(IkeruTheme.Radius.full == 9999)
        }
    }

    // MARK: - Animation

    @Suite("Animation Timings")
    struct AnimationTests {

        @Test("Quick animation is 0.2s")
        func quickDuration() {
            #expect(IkeruTheme.Animation.quickDuration == 0.2)
        }

        @Test("Standard animation is 0.35s")
        func standardDuration() {
            #expect(IkeruTheme.Animation.standardDuration == 0.35)
        }

        @Test("Dramatic animation is 0.6s")
        func dramaticDuration() {
            #expect(IkeruTheme.Animation.dramaticDuration == 0.6)
        }

        @Test("Dramatic bounce is 0.3")
        func dramaticBounce() {
            #expect(IkeruTheme.Animation.dramaticBounce == 0.3)
        }

        @Test("Mesh shift duration is 4.0s")
        func meshShiftDuration() {
            #expect(IkeruTheme.Animation.meshShiftDuration == 4.0)
        }
    }

    // MARK: - Shadows

    @Suite("Shadow Definitions")
    struct ShadowTests {

        @Test("Card shadow properties")
        func cardShadow() {
            let shadow = IkeruTheme.Shadow.card
            #expect(shadow.colorHex == 0x000000)
            #expect(shadow.opacity == 0.3)
            #expect(shadow.radius == 12)
            #expect(shadow.y == 4)
        }

        @Test("Glow shadow properties")
        func glowShadow() {
            let shadow = IkeruTheme.Shadow.glow
            #expect(shadow.colorHex == 0xFFB347)
            #expect(shadow.opacity == 0.3)
            #expect(shadow.radius == 16)
        }

        @Test("Loot glow shadow properties")
        func lootGlowShadow() {
            let shadow = IkeruTheme.Shadow.lootGlow
            #expect(shadow.colorHex == 0xFFB347)
            #expect(shadow.opacity == 0.3)
            #expect(shadow.radius == 24)
        }
    }
}
