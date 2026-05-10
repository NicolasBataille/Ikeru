import Testing
import SwiftUI
@testable import Ikeru

@Suite("PagedLearningStack selection logic")
@MainActor
struct PagedLearningStackTests {

    @Test("Drag past halfway commits to next page")
    func commitForward() {
        let model = PagedLearningStackLogic(width: 400)
        let next = model.commit(currentIndex: 1, dragTranslation: -210, velocity: 0)
        #expect(next == 2)
    }

    @Test("Drag below halfway springs back")
    func springBack() {
        let model = PagedLearningStackLogic(width: 400)
        let next = model.commit(currentIndex: 1, dragTranslation: -120, velocity: 0)
        #expect(next == 1)
    }

    @Test("High forward velocity commits even below halfway")
    func velocityCommit() {
        let model = PagedLearningStackLogic(width: 400)
        let next = model.commit(currentIndex: 1, dragTranslation: -80, velocity: -800)
        #expect(next == 2)
    }

    @Test("Cannot swipe past first or last")
    func clamping() {
        let model = PagedLearningStackLogic(width: 400, pageCount: 3)
        let nextLeft = model.commit(currentIndex: 0, dragTranslation: 250, velocity: 0)
        #expect(nextLeft == 0)
        let nextRight = model.commit(currentIndex: 2, dragTranslation: -250, velocity: 0)
        #expect(nextRight == 2)
    }

    @Test("Rubber band scales offset past edges")
    func rubberBand() {
        let model = PagedLearningStackLogic(width: 400, pageCount: 3)
        let raw = model.rubberBandedOffset(currentIndex: 0, dragTranslation: 200)
        #expect(raw < 200) // damped
        #expect(raw > 0)
        let center = model.rubberBandedOffset(currentIndex: 1, dragTranslation: 100)
        #expect(center == 100) // not at boundary
    }
}
