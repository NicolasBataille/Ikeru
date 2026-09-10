import XCTest

/// Page object for the Explore tab (`ExploreView`, file still named
/// `EtudeView.swift`) — GAP-01 two-client merge test only. The only row this
/// test needs is the one leading into `KanaPoolSelectorView`.
struct ExplorePage {
    let app: XCUIApplication

    private var kanaRow: XCUIElement {
        app.buttons["explore.kanaRow"]
    }

    @discardableResult
    func waitForKanaRow(timeout: TimeInterval = 10) -> Bool {
        kanaRow.waitForExistence(timeout: timeout)
    }

    func tapKanaRow() {
        kanaRow.tap()
    }
}
