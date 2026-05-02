import SwiftUI
import IkeruCore

// MARK: - Pure-logic helper
//
// Lives outside the view so it's unit-testable without bringing up SwiftUI.
struct PagedLearningStackLogic {
    let width: CGFloat
    let pageCount: Int
    /// Velocity threshold (pt/s) above which a small drag still commits.
    let velocityThreshold: CGFloat
    /// Halfway threshold for distance-based commit.
    var distanceThreshold: CGFloat { width / 2 }

    init(width: CGFloat, pageCount: Int = 3, velocityThreshold: CGFloat = 600) {
        self.width = width
        self.pageCount = pageCount
        self.velocityThreshold = velocityThreshold
    }

    func commit(currentIndex: Int, dragTranslation: CGFloat, velocity: CGFloat) -> Int {
        let goingForward = dragTranslation < 0
        let absTranslation = abs(dragTranslation)
        let absVelocity = abs(velocity)

        let crossedDistance = absTranslation > distanceThreshold
        let crossedVelocity = absVelocity > velocityThreshold && absTranslation > 20

        guard crossedDistance || crossedVelocity else { return currentIndex }

        let candidate = goingForward ? currentIndex + 1 : currentIndex - 1
        return max(0, min(pageCount - 1, candidate))
    }

    func rubberBandedOffset(currentIndex: Int, dragTranslation: CGFloat) -> CGFloat {
        let isAtLeft = currentIndex == 0
        let isAtRight = currentIndex == pageCount - 1
        let pullingPastEdge = (isAtLeft && dragTranslation > 0)
            || (isAtRight && dragTranslation < 0)
        guard pullingPastEdge else { return dragTranslation }
        return dragTranslation * 0.35
    }
}

// MARK: - PagedLearningStack
//
// Horizontal pager over a fixed array of pages. Active index is bound
// externally so the surrounding tab bar can render the rail position.
// While dragging, `liveOffsetFraction` reports a value in
// `[0, pageCount-1]` for live rail interpolation.

struct PagedLearningStack<Content: View>: View {

    let pageCount: Int
    @Binding var activeIndex: Int
    /// 0 ... pageCount-1, fractional during drag.
    @Binding var liveOffsetFraction: CGFloat
    @ViewBuilder let content: (Int) -> Content

    @State private var dragTranslation: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let logic = PagedLearningStackLogic(width: width, pageCount: pageCount)
            let damped = logic.rubberBandedOffset(
                currentIndex: activeIndex,
                dragTranslation: dragTranslation
            )

            HStack(spacing: 0) {
                ForEach(0..<pageCount, id: \.self) { index in
                    if abs(index - activeIndex) <= 1 {
                        content(index)
                            .frame(width: width)
                    } else {
                        Color.clear.frame(width: width) // page placeholder
                    }
                }
            }
            .frame(width: width * CGFloat(pageCount), alignment: .leading)
            .offset(x: -CGFloat(activeIndex) * width + damped)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        // Only horizontal-dominated drags engage.
                        guard abs(value.translation.width) > abs(value.translation.height) else {
                            return
                        }
                        dragTranslation = value.translation.width
                        let fractional = CGFloat(activeIndex) - damped / width
                        liveOffsetFraction = fractional
                    }
                    .onEnded { value in
                        let v = value.predictedEndTranslation.width - value.translation.width
                        let next = logic.commit(
                            currentIndex: activeIndex,
                            dragTranslation: value.translation.width,
                            velocity: v
                        )
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            activeIndex = next
                            dragTranslation = 0
                            liveOffsetFraction = CGFloat(next)
                        }
                    }
            )
            .onChange(of: activeIndex) { _, new in
                liveOffsetFraction = CGFloat(new)
            }
        }
    }
}
