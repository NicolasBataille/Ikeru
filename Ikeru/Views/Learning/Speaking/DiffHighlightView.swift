import SwiftUI
import IkeruCore

// MARK: - DiffHighlightView

/// Renders a diff comparison between expected and recognized text
/// using color-coded segments.
struct DiffHighlightView: View {

    let segments: [DiffSegment]
    let accuracy: Double

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            accuracyBadge
            diffText
        }
    }

    // MARK: - Accuracy Badge

    private var accuracyBadge: some View {
        let percentage = Int(accuracy * 100)
        return Text("\(percentage)%")
            .font(.ikeruHeading2)
            .foregroundStyle(accuracyColor)
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .padding(.vertical, IkeruTheme.Spacing.xs)
            .background {
                Capsule()
                    .fill(accuracyColor.opacity(0.15))
            }
    }

    private var accuracyColor: Color {
        if accuracy >= 0.8 {
            return Color.ikeruSuccess // jade green / teal
        } else if accuracy >= 0.5 {
            return Color.ikeruPrimaryAccent // amber
        } else {
            return Color.ikeruSecondaryAccent // vermillion
        }
    }

    // MARK: - Diff Text

    private var diffText: some View {
        segmentedText
            .font(.ikeruHeading3)
            .multilineTextAlignment(.center)
    }

    /// Builds an attributed Text from diff segments using the `+` operator.
    private var segmentedText: Text {
        var result = Text("")

        for segment in segments {
            switch segment {
            case .match(let text):
                result = result + Text(text)
                    .foregroundColor(Color.ikeruSuccess)

            case .mismatch(let expected, _):
                result = result + Text(expected)
                    .foregroundColor(Color.ikeruSecondaryAccent)
                    .strikethrough(color: Color.ikeruSecondaryAccent)

            case .missing(let text):
                result = result + Text(text)
                    .foregroundColor(Color.ikeruSecondaryAccent)
                    .underline(color: Color.ikeruSecondaryAccent)

            case .extra(let text):
                result = result + Text(text)
                    .foregroundColor(Color.ikeruPrimaryAccent)
            }
        }

        return result
    }
}

// MARK: - Preview

#Preview("DiffHighlightView — High Accuracy") {
    DiffHighlightView(
        segments: [
            .match("こんにち"),
            .missing("は")
        ],
        accuracy: 0.85
    )
    .padding()
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}

#Preview("DiffHighlightView — Low Accuracy") {
    DiffHighlightView(
        segments: [
            .match("た"),
            .missing("べ"),
            .extra("め"),
            .match("る")
        ],
        accuracy: 0.4
    )
    .padding()
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
