import XCTest

/// A returning learner on a fresh install must be able to reach the Sign in
/// with Apple button at the foot of the name screen. The field takes focus
/// on its own, so the keyboard is up from the start; a tap anywhere outside
/// the field has to put it away (measured 2026-09-18: it did not, and the
/// button sat under the keyboard with no way to reach it).
final class OnboardingKeyboardUITests: IkeruUITestCase {

    func testTapOutsideTheFieldDismissesTheKeyboardAndFreesSignIn() {
        let app = launch()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15), "Name screen never showed its field")

        // The software keyboard is not guaranteed on every simulator
        // (hardware keyboard setting); only assert on it when it showed up.
        let keyboardShown = app.keyboards.firstMatch.waitForExistence(timeout: 5)

        app.staticTexts["\u{4E2D}"].firstMatch.tap()

        if keyboardShown {
            XCTAssertTrue(
                waitUntil(timeout: 5) { app.keyboards.count == 0 },
                "Tapping outside the field must dismiss the keyboard"
            )
        }

        let signIn = app.buttons["I already have an account"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5), "Sign in with Apple button absent")
        XCTAssertTrue(signIn.isHittable, "Sign in with Apple button must be reachable")
        let window = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(signIn.frame.maxY, window.maxY, "Sign in button sits below the screen")
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return condition()
    }
}
