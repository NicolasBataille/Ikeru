import SwiftUI
import IkeruCore

// MARK: - GradeButtonsView

struct GradeButtonsView: View {

    let onGrade: (Grade) -> Void

    var body: some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            gradeButton(grade: .again, label: "Again", color: Color(hex: IkeruTheme.Colors.secondaryAccent))
            gradeButton(grade: .hard, label: "Hard", color: Color(hex: 0xFF8C42))
            gradeButton(grade: .good, label: "Good", color: Color(hex: IkeruTheme.Colors.primaryAccent))
            gradeButton(grade: .easy, label: "Easy", color: Color(hex: IkeruTheme.Colors.success))
        }
    }

    // MARK: - Grade Button

    private func gradeButton(grade: Grade, label: String, color: Color) -> some View {
        Button {
            onGrade(grade)
        } label: {
            Text(label)
                .font(.system(size: IkeruTheme.Typography.Size.caption, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(color.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm))
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
