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

    /// Indicative due windows — tuned to "what a typical early-review card
    /// would see after this grade". Kept terse to fit on a mobile row and
    /// surfaced as a serif numeral under each button.
    private let dueHints: [Grade: String] = [
        .again: "<1m",
        .hard:  "~6m",
        .good:  "1d",
        .easy:  "4d"
    ]

    private struct GradeSpec {
        let grade: Grade
        let kanji: String
        let label: LocalizedStringKey
        let color: Color
    }

    /// Color-coded specs for the four FSRS grades. Colors come from the
    /// Tatami direction: vermilion warns "again", muted brown signals
    /// effort ("hard"), gold rewards a confident "good", green frees an
    /// easy review.
    private var specs: [GradeSpec] {
        [
            .init(grade: .again, kanji: "\u{518D}", label: "Again",   // 再
                  color: TatamiTokens.vermilion),
            .init(grade: .hard,  kanji: "\u{96E3}", label: "Hard",    // 難
                  color: Color(red: 0.627, green: 0.451, blue: 0.302)),
            .init(grade: .good,  kanji: "\u{826F}", label: "Good",    // 良
                  color: Color.ikeruPrimaryAccent),
            .init(grade: .easy,  kanji: "\u{6613}", label: "Easy",    // 易
                  color: Color(red: 0.616, green: 0.729, blue: 0.486))
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
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(Color.ikeruTextPrimary)
                            .textCase(.uppercase)
                        SerifNumeral(
                            dueHints[spec.grade] ?? "",
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
