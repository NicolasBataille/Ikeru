import Foundation
import SwiftData
import IkeruCore
import os

// MARK: - ComposeSessionViewModel
//
// The state behind `ComposeSessionSheet` (Étude → « Composer une séance »):
// the exercise types the learner may opt into, which of them are locked and
// why, the selection, and the duration. Pure over a `SessionComposer` for the
// snapshot and the unlock set — the same two calls `SessionViewModel` makes
// at session start, so what the sheet shows as unlocked IS what the planner
// will accept.
//
// This is the door `DefaultSessionPlanner.untaughtContentTypes` justified
// itself with for seven weeks without it existing (2026-07-19 → 2026-09-09).

@MainActor
@Observable
final class ComposeSessionViewModel {

    /// One line of the sheet: a type, and whether the learner may pick it.
    struct Offer: Identifiable, Equatable {
        let type: ExerciseType
        let unlockState: ExerciseUnlockState

        var id: ExerciseType { type }
        var isUnlocked: Bool { unlockState.isUnlocked }
    }

    /// Durations the sheet proposes, in minutes.
    static let durationChoices = [5, 10, 15, 20]

    private(set) var offers: [Offer] = []
    private(set) var selectedTypes: Set<ExerciseType> = []
    var durationMinutes: Int = 10
    private(set) var hasLoaded = false

    private let composer: SessionComposer

    init(
        cardRepository: CardRepository,
        modelContainer: ModelContainer,
        contentRepository: ContentRepository? = nil,
        unlockService: any ExerciseUnlockService = DefaultExerciseUnlockService()
    ) {
        self.composer = SessionComposer(
            plannerService: PlannerService(cardRepository: cardRepository),
            sessionPlanner: DefaultSessionPlanner(),
            unlockService: unlockService,
            cardRepository: cardRepository,
            contentRepository: contentRepository,
            modelContainer: modelContainer
        )
    }

    /// Builds the offer list from the learner's real snapshot. Locked types
    /// stay in the list, disabled, with their reason: an opt-in door that
    /// hides what is locked would teach nothing about how to unlock it.
    func load(unlockService: any ExerciseUnlockService = DefaultExerciseUnlockService()) async {
        let cards = await composer.cardRepository.allCards()
        let snapshot = await composer.buildSnapshot(cards: cards)
        let unlocked = composer.effectiveUnlockedTypes(profile: snapshot)
        offers = ExerciseType.composableInStudySession.map { type in
            // An acknowledged (one-way) unlock beats the live threshold —
            // same rule as the planner's `effectiveUnlockedTypes`.
            let state: ExerciseUnlockState = unlocked.contains(type)
                ? .unlocked
                : unlockService.state(for: type, profile: snapshot)
            return Offer(type: type, unlockState: state)
        }
        // Keep a selection that is still valid; drop anything now locked.
        selectedTypes = selectedTypes.intersection(unlocked)
        hasLoaded = true
    }

    /// Whether « Commencer » makes sense: at least one unlocked type chosen.
    var canStart: Bool { !selectedTypes.isEmpty }

    func toggle(_ type: ExerciseType) {
        guard offers.first(where: { $0.type == type })?.isUnlocked == true else { return }
        if selectedTypes.contains(type) {
            selectedTypes.remove(type)
        } else {
            selectedTypes.insert(type)
        }
    }

    func isSelected(_ type: ExerciseType) -> Bool { selectedTypes.contains(type) }

    /// Starts the composed session on `sessionViewModel`. `false` means the
    /// selection composed nothing (see `startStudyCustomSession`), and the
    /// sheet must say so rather than dismiss.
    func start(on sessionViewModel: SessionViewModel) async -> Bool {
        guard canStart else { return false }
        // JLPT levels are deliberately not offered: `composeStudy` ignores
        // them today (content packs are not tagged by level) and logs the
        // fact — a picker would promise a filter that does not exist.
        return await sessionViewModel.startStudyCustomSession(
            types: selectedTypes,
            levels: [.n5],
            duration: durationMinutes
        )
    }
}
