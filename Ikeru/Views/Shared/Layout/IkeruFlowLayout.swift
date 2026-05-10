import SwiftUI
import IkeruCore

// MARK: - IkeruFlowLayout

/// A horizontal flow layout that wraps items to the next row when they exceed
/// the available width. Used throughout the app for vocabulary chips, furigana
/// word sequences, and any content that needs dynamic line-breaking.
///
/// - `spacing`: gap between items and between rows (defaults to `IkeruTheme.Spacing.xs`)
/// - `maxWidth`: explicit width cap; when `nil` the layout uses the proposed width
struct IkeruFlowLayout: Layout {

    let spacing: CGFloat
    let maxWidth: CGFloat?

    init(spacing: CGFloat = IkeruTheme.Spacing.xs, maxWidth: CGFloat? = nil) {
        self.spacing = spacing
        self.maxWidth = maxWidth
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        computeLayout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = computeLayout(proposal: proposal, subviews: subviews)

        for (index, position) in result.positions.enumerated() {
            guard index < subviews.count else { break }
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + position.x,
                    y: bounds.minY + position.y
                ),
                proposal: .unspecified
            )
        }
    }

    // MARK: - Internal

    private struct LayoutResult {
        let size: CGSize
        let positions: [CGPoint]
    }

    private func computeLayout(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> LayoutResult {
        let effectiveMaxWidth = maxWidth ?? proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > effectiveMaxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, currentX)
        }

        return LayoutResult(
            size: CGSize(width: totalWidth, height: currentY + lineHeight),
            positions: positions
        )
    }
}
