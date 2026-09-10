import XCTest

/// Validates `-wipeData` itself — the flag every other test in this target
/// depends on for isolation (see `IkeruUITestCase`'s doc comment). Without
/// this test, a regression in `-wipeData` (e.g. someone reorders it after
/// `-skipOnboarding` in `IkeruApp.initializeProfileViewModel()`) would make
/// every OTHER UI test in this target silently order-dependent instead of
/// failing loudly and specifically.
final class ProfileResetUITests: IkeruUITestCase {

    func testWipeDataResetsProfileBetweenLaunches() {
        // First launch: seed a mock profile with visible progress.
        let first = launch([
            LaunchArguments.mockProfile,
            LaunchArguments.mockLevel(20),
            LaunchArguments.mockDue(5),
            LaunchArguments.mockMastered(30),
            LaunchArguments.startTab(1),
        ])
        let firstHome = HomePage(app: first)
        XCTAssertTrue(firstHome.waitForDashboardData())
        XCTAssertNotEqual(
            firstHome.kanaProgressCount.label, "0/92",
            "Sanity check: mockLevel=20 should seed some mastered kana"
        )
        first.terminate()

        // Second launch, same simulator, no erase in between: `-wipeData`
        // must still clear the first launch's profile before `-skipOnboarding`
        // creates a fresh, contentless one — proving the reset actually
        // fires rather than the second run silently inheriting state.
        let second = launch([
            LaunchArguments.skipOnboarding,
            LaunchArguments.startTab(1),
        ])
        let secondHome = HomePage(app: second)
        XCTAssertTrue(secondHome.waitForDashboardData())
        XCTAssertEqual(
            secondHome.kanaProgressCount.label, "0/92",
            "-wipeData did not clear the previous launch's fixture profile"
        )
    }
}
