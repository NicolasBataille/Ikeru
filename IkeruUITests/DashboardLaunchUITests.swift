import XCTest

/// Launching with `-mockProfile` must actually reach the dashboard WITH
/// data — not just launch without crashing. Before GAP-09, this fixture
/// infrastructure (`TestFixtures.swift`) existed but nothing exercised it
/// end-to-end through the real app UI.
final class DashboardLaunchUITests: IkeruUITestCase {

    func testMockProfileReachesDashboardWithSeededData() {
        let app = launch([
            LaunchArguments.mockProfile,
            LaunchArguments.mockLevel(15),
            LaunchArguments.mockDue(10),
            LaunchArguments.mockMastered(40),
            LaunchArguments.startTab(1), // Practice/Home
        ])

        let home = HomePage(app: app)
        XCTAssertTrue(
            home.waitForDashboardData(),
            "Home never showed the かな progress count — fixture data did not seed or the dashboard did not load"
        )

        // level=15 with masteredCount > 0 (see TestFixtures.seedKana) means
        // this is never "0/92" — a genuinely blank dashboard would also
        // satisfy plain existence, so assert the label actually carries a
        // fraction rather than being empty.
        let label = home.kanaProgressCount.label
        XCTAssertTrue(
            label.contains("/"),
            "Expected a 'X/92' kana progress count, got '\(label)'"
        )
        XCTAssertFalse(
            label.hasPrefix("0/"),
            "Expected some kana already mastered at mockLevel=15, got '\(label)'"
        )
    }

    func testSkipOnboardingReachesDashboardWithPlainProfile() {
        // No -mockProfile: `-skipOnboarding` alone creates a bare "Nico"
        // profile with no fixture content — a different launch path than
        // the fixture-seeded one above, worth its own assertion that it
        // also lands on the dashboard rather than stuck on onboarding.
        let app = launch([
            LaunchArguments.skipOnboarding,
            LaunchArguments.startTab(1),
        ])

        let home = HomePage(app: app)
        XCTAssertTrue(
            home.waitForDashboardData(),
            "Home never showed the かな progress count for a plain -skipOnboarding profile"
        )
        XCTAssertEqual(
            home.kanaProgressCount.label, "0/92",
            "A brand-new -skipOnboarding profile should start at 0/92 kana learned"
        )
    }
}
