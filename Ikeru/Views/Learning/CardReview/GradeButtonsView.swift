import SwiftUI
import IkeruCore

// MARK: - GradeButtonsView
//
// Tatami-direction FSRS grade row: four sharp tatami buttons, each with a
// kanji header (又 / 難 / 良 / 易), a colored sumi-corner frame, the
// localized chrome label, and the indicative next-due interval rendered
// as a serif numeral below.
//
// Indicative intervals are *representative* — the real FSRS next-due
// depends on the card's current state (stability, difficulty, lapse
// count). The numeral communicates the scheduler's direction so the user
// can grade with intent, without pretending to show a pixel-accurate
// prediction.

struct GradeButtonsView: View {

    let onGrade: (Grade) -> Void

    /// Real per-card FSRS predictions (grade → formatted interval), computed
    /// with the profile's desired retention. When provided they replace the
    /// static representative hints — the learner sees exactly what each
    /// grade will schedule (owner request, device pass 2026-07-19).
    var predictedIntervals: [Grade: String]? = nil

    /// Indicative due windows — tuned to "what a typical early-review card
    /// would see after this grade". Fallback when no per-card prediction is
    /// supplied. Kept terse to fit on a mobile row.
    private let dueHints: [Grade: String] = [
        .again: "<1m",
        .hard:  "~6m",
        .good:  String(localized: "1d"),
        .easy:  String(localized: "4d")
    ]

    private func hint(for grade: Grade) -> String {
        predictedIntervals?[grade] ?? dueHints[grade] ?? ""
    }

    private struct GradeSpec {
        let grade: Grade
        let kanji: String
        let label: LocalizedStringKey
        let color: Color
        /// Untranslated slug for this button's accessibility identifier.
        /// Spelled out rather than derived from `Grade.rawValue` (an `Int`,
        /// so it would read `session.gradeButton.3`) or from `label` (a
        /// `LocalizedStringKey`, so it would change with the simulator's
        /// language — the exact trap `IkeruUITestCase` forces `-AppleLanguages
        /// (en)` to avoid).
        let identifierSlug: String
    }

    /// Color-coded specs for the four FSRS grades. Colors come from the
    /// Tatami direction: vermilion warns "again", muted brown signals
    /// effort ("hard"), gold rewards a confident "good", green frees an
    /// easy review.
    private var specs: [GradeSpec] {
        [
            // 再
            .init(grade: .again, kanji: "\u{518D}", label: "Again",
                  color: TatamiTokens.vermilion, identifierSlug: "again"),
            // 難
            .init(grade: .hard, kanji: "\u{96E3}", label: "Hard",
                  color: Color(red: 0.627, green: 0.451, blue: 0.302), identifierSlug: "hard"),
            // 良
            .init(grade: .good, kanji: "\u{826F}", label: "Good",
                  color: Color.ikeruPrimaryAccent, identifierSlug: "good"),
            // 易
            .init(grade: .easy, kanji: "\u{6613}", label: "Easy",
                  color: Color(red: 0.616, green: 0.729, blue: 0.486), identifierSlug: "easy")
        ]
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(specs, id: \.grade) { spec in
                Button {
                    onGrade(spec.grade)
                } label: {
                    VStack(spacing: 4) {
                        Text(spec.kanji)
                            .font(.system(size: 18, weight: .light, design: .serif))
                            .foregroundStyle(spec.color)
                            .padding(.bottom, 2)
                        Text(spec.label)
                            .ikeruScaledFont(11, weight: .bold, relativeTo: .caption2)
                            .tracking(1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(Color.ikeruTextPrimary)
                            .textCase(.uppercase)
                        SerifNumeral(
                            hint(for: spec.grade),
                            size: 10,
                            weight: .regular,
                            color: TatamiTokens.paperGhost
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.102, green: 0.102, blue: 0.133))
                    .overlay(alignment: .top) {
                        Rectangle().fill(spec.color).frame(height: 1)
                    }
                    .sumiCorners(color: spec.color, size: 8, weight: 1.2, inset: -1)
                }
                .buttonStyle(.plain)
                // Per-grade, not one shared identifier: unlike the kana
                // quiz's four interchangeable options, which grade a test
                // taps changes what FSRS schedules next. A test that means
                // "answer Good" must be able to say so.
                .accessibilityIdentifier("session.gradeButton.\(spec.identifierSlug)")
            }
        }
    }
}

// MARK: - Preview

#Preview("GradeButtonsView") {
    ZStack {
        Color.ikeruBackground.ignoresSafeArea()
        GradeButtonsView { grade in
            print("Graded: \(grade)")
        }
        .padding(IkeruTheme.Spacing.md)
    }
    .preferredColorScheme(.dark)
}
