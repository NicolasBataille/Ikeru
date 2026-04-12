import SwiftUI
import IkeruCore

// MARK: - KanaDrillSessionSummary

/// End-of-session card with accuracy stats and continue / restart actions.
struct KanaDrillSessionSummary: View {

    let correct: Int
    let wrong: Int
    let duration: TimeInterval
    let onContinue: () -> Void
    let onRestart: () -> Void

    private var total: Int { correct + wrong }
    private var accuracy: Double {
        guard total > 0 else { return 0 }
        return Double(correct) / Double(total)
    }
    private var emoji: String {
        if total == 0 { return "🌿" }
        if wrong == 0 { return "🎉" }
        if accuracy >= 0.5 { return "🌿" }
        return "🌧️"
    }

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            Spacer()

            Text(emoji)
                .font(.system(size: 80))

            VStack(spacing: 6) {
                Text("Session complete")
                    .font(.ikeruDisplaySmall)
                    .ikeruTracking(.display)
                    .foregroundStyle(Color.ikeruTextPrimary)
                Text("Well done")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }

            statsGrid

            Spacer()

            VStack(spacing: 10) {
                Button { onContinue() } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .ikeruButtonStyle(.primary)

                Button { onRestart() } label: {
                    Text("Restart").frame(maxWidth: .infinity)
                }
                .ikeruButtonStyle(.secondary)
            }
        }
        .padding(.horizontal, IkeruTheme.Spacing.lg)
        .padding(.vertical, IkeruTheme.Spacing.xl)
        .padding(.bottom, 88) // Floating tab bar clearance
    }

    private var statsGrid: some View {
        HStack(spacing: 10) {
            statCell(value: "\(correct)", label: "Correct")
            statCell(value: "\(wrong)", label: "Missed")
            statCell(value: "\(Int(accuracy * 100)) %", label: "Accuracy")
            statCell(value: formatDuration(duration), label: "Duration")
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.ikeruTextPrimary)
            Text(label)
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.md, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.md, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}
