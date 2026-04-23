import SwiftUI
import IkeruCore

// MARK: - GradeButtonsView
//
// Four grade buttons with indicative next-due intervals under each label.
// Intervals are *representative* — the real FSRS next-due depends on the
// card's current state (stability, difficulty, lapse count). The chip
// communicates the scheduler's direction so the user can grade with intent,
// without pretending to show a pixel-accurate prediction.

struct GradeButtonsView: View {

    let onGrade: (Grade) -> Void

    /// Indicative due windows — tuned to "what a typical early-review card
    /// would see after this grade". Kept terse to fit on a mobile row.
    private let dueHints: [Grade: String] = [
        .again: "<1m",
        .hard:  "~6m",
        .good:  "1d",
        .easy:  "4d"
    ]

    var body: some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            gradeButton(grade: .again, label: "Again",
                        color: Color.ikeruDanger)
            gradeButton(grade: .hard,  label: "Hard",
                        color: Color.ikeruWarning)
            gradeButton(grade: .good,  label: "Good",
                        color: Color.ikeruPrimaryAccent, primary: true)
            gradeButton(grade: .easy,  label: "Easy",
                        color: Color.ikeruSuccess)
        }
    }

    // MARK: - Grade Button

    private func gradeButton(
        grade: Grade,
        label: String,
        color: Color,
        primary: Bool = false
    ) -> some View {
        Button {
            onGrade(grade)
        } label: {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(primary ? Color(red: 0.16, green: 0.11, blue: 0.05) : color)
                Text(dueHints[grade] ?? "")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(
                        primary
                            ? Color(red: 0.16, green: 0.11, blue: 0.05).opacity(0.7)
                            : Color.ikeruTextTertiary
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background {
                if primary {
                    RoundedRectangle(cornerRadius: IkeruTheme.Radius.md, style: .continuous)
                        .fill(LinearGradient.ikeruGold)
                } else {
                    RoundedRectangle(cornerRadius: IkeruTheme.Radius.md, style: .continuous)
                        .fill(color.opacity(0.14))
                        .overlay {
                            RoundedRectangle(cornerRadius: IkeruTheme.Radius.md, style: .continuous)
                                .strokeBorder(color.opacity(0.35), lineWidth: 1)
                        }
                }
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
