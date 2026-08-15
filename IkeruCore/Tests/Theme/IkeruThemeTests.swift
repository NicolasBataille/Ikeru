import Testing
@testable import IkeruCore

// NOTE ON PURPOSE: these tests assert the exact literal value of each design
// token. They do NOT — and cannot — prove a color, size, or duration is
// "correct": that judgment was made on-device by eye during the wabi-sabi
// visual redesign (PR #22, "feat(wabi): ..."), which superseded the earlier
// (pre-redesign) palette these assertions used to encode. What this suite
// buys us instead is a **change detector**: if a token's value drifts —
// whether from a typo, a bad merge, or an accidental edit — one of these
// tests goes red and points at exactly which token moved and from what to
// what. Treat a failure here as "a token changed, go confirm that was
// intentional," not as "the app is broken."
@Suite("IkeruTheme Design Tokens")
struct IkeruThemeTests {

    // MARK: - Colors

    @Suite("Colors")
    struct ColorsTests {

        @Test("Background color is ink black (sumi)")
        func background() {
            #expect(IkeruTheme.Colors.background == 0x0A0A0F)
        }

        @Test("Surface color is raised near-black")
        func surface() {
            #expect(IkeruTheme.Colors.surface == 0x18181F)
        }

        @Test("Primary accent is warm gold (kintsugi)")
        func primaryAccent() {
            #expect(IkeruTheme.Colors.primaryAccent == 0xD4A574)
        }

        @Test("Secondary accent is sakura pink")
        func secondaryAccent() {
            #expect(IkeruTheme.Colors.secondaryAccent == 0xE8B4B8)
        }

        @Test("Success is moss green")
        func success() {
            #expect(IkeruTheme.Colors.success == 0x8FBCA0)
        }

        @Test("Kanji text is warm white")
        func kanjiText() {
            #expect(IkeruTheme.Colors.kanjiText == 0xF5F2EC)
        }

        @Test("Text primary is washi-paper white, never pure white")
        func textPrimary() {
            #expect(IkeruTheme.Colors.textPrimary == 0xF5F2EC)
        }

        @Test("Text secondary opacity is 70%")
        func textSecondaryOpacity() {
            #expect(IkeruTheme.Colors.textSecondaryOpacity == 0.7)
        }
    }

    // MARK: - SRS Stage Colors

    @Suite("SRS Stage Colors")
    struct SRSColorsTests {

        @Test("Apprentice color is terracotta")
        func apprentice() {
            #expect(IkeruTheme.Colors.SRS.apprentice == 0xC97064)
        }

        @Test("Guru color is gold")
        func guru() {
            #expect(IkeruTheme.Colors.SRS.guru == 0xD4A574)
        }

        @Test("Master color is matcha")
        func master() {
            #expect(IkeruTheme.Colors.SRS.master == 0x7A8471)
        }

        @Test("Enlightened color is murasaki purple")
        func enlightened() {
            #expect(IkeruTheme.Colors.SRS.enlightened == 0x9580B5)
        }

        @Test("Burned color is sakura")
        func burned() {
            #expect(IkeruTheme.Colors.SRS.burned == 0xE8B4B8)
        }
    }

    // MARK: - Skill Colors

    @Suite("Skill Colors")
    struct SkillColorsTests {

        @Test("Reading color is dusk blue")
        func reading() {
            #expect(IkeruTheme.Colors.Skills.reading == 0x6B92B5)
        }

        @Test("Writing color is matcha")
        func writing() {
            #expect(IkeruTheme.Colors.Skills.writing == 0x7A8471)
        }

        @Test("Listening color is gold")
        func listening() {
            #expect(IkeruTheme.Colors.Skills.listening == 0xD4A574)
        }

        @Test("Speaking color is terracotta")
        func speaking() {
            #expect(IkeruTheme.Colors.Skills.speaking == 0xC97064)
        }
    }

    // MARK: - Loot Rarity Colors

    @Suite("Loot Rarity Colors")
    struct RarityColorsTests {

        @Test("Common is warm gray")
        func common() {
            #expect(IkeruTheme.Colors.Rarity.common == 0x8A8780)
        }

        @Test("Rare is dusk blue")
        func rare() {
            #expect(IkeruTheme.Colors.Rarity.rare == 0x6B92B5)
        }

        @Test("Epic is murasaki purple")
        func epic() {
            #expect(IkeruTheme.Colors.Rarity.epic == 0x9580B5)
        }

        @Test("Legendary is gold")
        func legendary() {
            #expect(IkeruTheme.Colors.Rarity.legendary == 0xD4A574)
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

        @Test("Kanji hero size is 96pt")
        func kanjiHeroSize() {
            #expect(IkeruTheme.Typography.Size.kanjiHero == 96)
        }

        @Test("Kanji display size is 64pt")
        func kanjiDisplaySize() {
            #expect(IkeruTheme.Typography.Size.kanjiDisplay == 64)
        }

        @Test("Kanji medium size is 40pt")
        func kanjiMediumSize() {
            #expect(IkeruTheme.Typography.Size.kanjiMedium == 40)
        }

        @Test("Body size is 15pt")
        func bodySize() {
            #expect(IkeruTheme.Typography.Size.body == 15)
        }

        @Test("Caption size is 12pt")
        func captionSize() {
            #expect(IkeruTheme.Typography.Size.caption == 12)
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
            #expect(IkeruTheme.Spacing.xs == 6)
            #expect(IkeruTheme.Spacing.sm == 10)
            #expect(IkeruTheme.Spacing.md == 16)
            #expect(IkeruTheme.Spacing.lg == 24)
            #expect(IkeruTheme.Spacing.xl == 36)
            #expect(IkeruTheme.Spacing.xxl == 56)
        }
    }

    // MARK: - Radius

    @Suite("Radius")
    struct RadiusTests {

        @Test("Radius values follow scale")
        func radiusScale() {
            #expect(IkeruTheme.Radius.sm == 12)
            #expect(IkeruTheme.Radius.md == 18)
            #expect(IkeruTheme.Radius.lg == 24)
            #expect(IkeruTheme.Radius.xl == 32)
            #expect(IkeruTheme.Radius.full == 9999)
        }
    }

    // MARK: - Animation

    @Suite("Animation Timings")
    struct AnimationTests {

        @Test("Quick animation is 0.18s")
        func quickDuration() {
            #expect(IkeruTheme.Animation.quickDuration == 0.18)
        }

        @Test("Standard animation is 0.32s")
        func standardDuration() {
            #expect(IkeruTheme.Animation.standardDuration == 0.32)
        }

        @Test("Dramatic animation is 0.55s")
        func dramaticDuration() {
            #expect(IkeruTheme.Animation.dramaticDuration == 0.55)
        }

        @Test("Dramatic bounce is 0.28")
        func dramaticBounce() {
            #expect(IkeruTheme.Animation.dramaticBounce == 0.28)
        }

        @Test("Mesh shift duration is 8.0s")
        func meshShiftDuration() {
            #expect(IkeruTheme.Animation.meshShiftDuration == 8.0)
        }
    }

    // MARK: - Shadows

    @Suite("Shadow Definitions")
    struct ShadowTests {

        @Test("Card shadow properties")
        func cardShadow() {
            let shadow = IkeruTheme.Shadow.card
            #expect(shadow.colorHex == 0x000000)
            #expect(shadow.opacity == 0.45)
            #expect(shadow.radius == 24)
            #expect(shadow.y == 8)
        }

        @Test("Glow shadow properties")
        func glowShadow() {
            let shadow = IkeruTheme.Shadow.glow
            #expect(shadow.colorHex == 0xD4A574)
            #expect(shadow.opacity == 0.25)
            #expect(shadow.radius == 32)
        }

        @Test("Loot glow shadow properties")
        func lootGlowShadow() {
            let shadow = IkeruTheme.Shadow.lootGlow
            #expect(shadow.colorHex == 0xD4A574)
            #expect(shadow.opacity == 0.35)
            #expect(shadow.radius == 40)
        }
    }
}
