#if IKERU_DEV_TOOLS
import Testing
import Foundation
import SwiftData
@testable import Ikeru
@testable import IkeruCore

/// Proves the fixture shape `-mockNothingDue` was added for: a learner with
/// **nothing left to review right now**.
///
/// ## Why this is asserted here and not in a UI test
///
/// The screens that consume this state — the caught-up proposal and its
/// deepen / discover offers — live on a separate branch. Waiting for them to
/// land before proving the fixture would repeat the mistake this whole effort
/// exists to correct: two UI tests shipped red on a *stated* premise
/// (`-mockDue=0` produces nothing due) that nobody had measured, and the
/// premise was false. The fixture is provable on its own, so it is proved on
/// its own.
///
/// The second test below is the measurement itself, kept executable: it pins
/// the old, wrong premise as **red by construction**, so if someone ever
/// "simplifies" `nothingDue` away in favour of `dueCount: 0`, the suite says
/// why that doesn't work instead of leaving a UI test to time out.
@Suite("TestFixtures — nothing due")
@MainActor
struct TestFixturesNothingDueTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // The resolver persists the active profile id in UserDefaults, which
        // crosses test boundaries — same guard `HomeViewModelTests` uses.
        ActiveProfileResolver.setActiveProfileID(nil)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func seed(
        container: ModelContainer,
        level: Int = 30,
        dueCount: Int = 0,
        masteredCount: Int = 0,
        nothingDue: Bool
    ) -> [Card] {
        let context = container.mainContext
        let profileVM = ProfileViewModel(modelContext: context)
        TestFixtures.wipeAndSeed(
            context: context,
            profileVM: profileVM,
            level: level,
            dueCount: dueCount,
            masteredCount: masteredCount,
            nothingDue: nothingDue
        )
        return (try? context.fetch(FetchDescriptor<Card>())) ?? []
    }

    @Test("nothingDue leaves no card due — kana included")
    func nothingDueLeavesNothingDue() throws {
        let container = try makeContainer()
        let now = Date()
        let cards = seed(container: container, nothingDue: true)

        #expect(!cards.isEmpty, "the fixture seeded nothing at all")

        let due = cards.filter { $0.dueDate <= now }
        // `Comment(rawValue:)` rather than a bare interpolated string:
        // `#expect`'s comment parameter is a `Comment`, which is
        // `ExpressibleByStringLiteral` only — a computed String doesn't
        // convert.
        #expect(
            due.isEmpty,
            Comment(rawValue: "\(due.count) of \(cards.count) cards are due — fronts: "
                + due.prefix(5).map(\.front).joined(separator: " "))
        )

        // Not-due is not enough on its own: a pool of never-reviewed cards
        // would also need to be excluded some other way. Assert the positive
        // shape too — every card was actually begun.
        #expect(cards.allSatisfy { $0.fsrsState.reps > 0 })
    }

    /// The measurement that produced `-mockNothingDue`, kept executable.
    ///
    /// `-mockDue=0` governs only `seedContentCards`. `seedKana` seeds its own
    /// 92 characters from `level`: a fixed 10-card overdue band at every
    /// level, plus never-reviewed cards (due today) for whatever the mastered
    /// band leaves over. So the sliders alone can never express a quiet queue
    /// — measured 2026-08-16, and the reason two UI tests were red on a false
    /// premise for a day.
    @Test("dueCount 0 alone does NOT produce a quiet queue")
    func dueCountZeroIsNotEnough() throws {
        let container = try makeContainer()
        let now = Date()
        let cards = seed(container: container, nothingDue: false)

        let due = cards.filter { $0.dueDate <= now }
        #expect(
            !due.isEmpty,
            """
            dueCount 0 produced a quiet queue — if this is now genuinely true, \
            `nothingDue` is redundant and should be removed along with this \
            test, not left to rot
            """
        )
    }

    /// The pool a "deepen this further" offer would draw from — begun, not
    /// yet due — is non-empty, and its counterpart is necessarily empty.
    ///
    /// Stated in terms of the card pool rather than of any planner API, so
    /// this holds regardless of which branch owns the caught-up proposal. The
    /// consequence for whoever writes a test against this fixture: a
    /// never-reviewed card is itself due, so it cannot exist in a pool with
    /// nothing due. **Deepen and discover are mutually exclusive here.** Assert
    /// on deepen, or on the pair — never on discover alone.
    @Test("nothingDue can offer deepen, and cannot offer discover")
    func nothingDueLeavesADeepenPool() throws {
        let container = try makeContainer()
        let now = Date()
        let cards = seed(container: container, nothingDue: true)

        let deepenPool = cards.filter { $0.fsrsState.reps > 0 && $0.dueDate > now }
        let discoverPool = cards.filter { $0.fsrsState.reps == 0 }

        #expect(!deepenPool.isEmpty)
        #expect(discoverPool.isEmpty)
    }
}
#endif
