import SwiftUI
import IkeruCore

// MARK: - Pure-logic helper (retained for reference; unused since the pager
// switched to a native ScrollView+.paging implementation below).
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
// Horizontal pager over a fixed array of pages. Backed by a native iOS 17
// horizontal ScrollView with `.scrollTargetBehavior(.paging)` so the
// UIScrollView gesture-priority logic applies: inner horizontal scrollers
// (e.g. the kana preset bar) claim pans they can absorb; the parent pager
// only takes pans when the inner scroller has nothing left to scroll.
//
// `liveOffsetFraction` is updated when the active page changes (snap, not
// finger-tracked) — the kintsugi rail still animates smoothly between
// indices via the tab bar's `matchedGeometryEffect`.

struct PagedLearningStack<Content: View>: View {

    let pageCount: Int
    @Binding var activeIndex: Int
    /// 0 ... pageCount-1. Updated post-snap when the active page changes.
    @Binding var liveOffsetFraction: CGFloat
    @ViewBuilder let content: (Int) -> Content

    /// Local mirror that drives `scrollPosition(id:)`. Sync'd with
    /// `activeIndex` in both directions via `.onChange`.
    @State private var scrolledIndex: Int?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(0..<pageCount, id: \.self) { index in
                    content(index)
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledIndex)
        .scrollClipDisabled()
        .onAppear {
            if scrolledIndex == nil {
                scrolledIndex = activeIndex
                liveOffsetFraction = CGFloat(activeIndex)
            }
        }
        .onChange(of: activeIndex) { _, new in
            // External selection (tap on a tab cell) → scroll to that page.
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                scrolledIndex = new
                liveOffsetFraction = CGFloat(new)
            }
        }
        .onChange(of: scrolledIndex) { _, new in
            // User-driven scroll → propagate to external binding.
            guard let new, new != activeIndex else { return }
            activeIndex = new
            liveOffsetFraction = CGFloat(new)
        }
    }
}
