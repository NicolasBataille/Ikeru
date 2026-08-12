import Foundation
import Testing
import SwiftData
@testable import Ikeru
@testable import IkeruCore

@Suite("ProfileViewModel")
@MainActor
struct ProfileViewModelTests {

    // MARK: - Helpers

    private func makeModelContext() throws -> ModelContext {
        // Full V2 schema so ExerciseOutcomeLog (scalar-scoped, no cascade) is
        // present for the deletion-cleanup test.
        //
        // NOTE (pre-existing, not fixed here — out of this repair's scope):
        // every `@Test` in this file SIGTRAPs inside SwiftData (EXC_BREAKPOINT,
        // stripped frames, no diagnostic message) on the first
        // `modelContext.fetch` when actually *run* in the app-hosted test host
        // (`xcodebuild test`), even though `build-for-testing` compiles clean.
        // Swapping this to a plain, non-versioned `Schema([UserProfile.self,
        // Card.self, ReviewLog.self, RPGState.self, ...])` (matching
        // `KanaDrillViewModelTests`'s pattern) was tried and did NOT fix it —
        // same SIGTRAP, same `ProfileViewModel.loadProfile()` call site, on
        // every test; reverted back to this versioned form since the swap
        // didn't help. Observed matrix across the app-hosted test host
        // (same simulator/session): ProfileViewModelTests 18/18 crash
        // (both schema forms); HomeViewModelTests 4/5 crash (plain schema);
        // SessionDecouplingTests 9/9 pass (this *same* versioned-schema +
        // direct-`mainContext`-fetch pattern, via
        // `ActiveProfileResolver.fetchActiveProfile`); KanaDrillViewModelTests
        // 13/13 pass (actor-routed via `CardRepository`). No consistent
        // discriminator (schema form, actor- vs. context-routing) was found
        // that explains the full matrix — flagging for a dedicated follow-up
        // rather than guessing further.
        let schema = Schema(versionedSchema: IkeruSchemaV2.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return container.mainContext
    }

    // MARK: - Tests

    @Test("No profile on fresh launch")
    func noProfileOnFreshLaunch() throws {
        let context = try makeModelContext()
        let viewModel = ProfileViewModel(modelContext: context)

        #expect(viewModel.hasProfile == false)
        #expect(viewModel.displayName == "")
    }

    @Test("Creates profile with valid name")
    func createsProfileWithValidName() throws {
        let context = try makeModelContext()
        let viewModel = ProfileViewModel(modelContext: context)

        viewModel.createProfile(name: "Nico")

        #expect(viewModel.hasProfile == true)
        #expect(viewModel.displayName == "Nico")
    }

    @Test("Trims whitespace from name on creation")
    func trimsWhitespaceOnCreation() throws {
        let context = try makeModelContext()
        let viewModel = ProfileViewModel(modelContext: context)

        viewModel.createProfile(name: "  Nico  ")

        #expect(viewModel.displayName == "Nico")
    }

    @Test("Does not create profile with empty name")
    func doesNotCreateWithEmptyName() throws {
        let context = try makeModelContext()
        let viewModel = ProfileViewModel(modelContext: context)

        viewModel.createProfile(name: "")

        #expect(viewModel.hasProfile == false)
    }

    @Test("Does not create profile with whitespace-only name")
    func doesNotCreateWithWhitespaceOnlyName() throws {
        let context = try makeModelContext()
        let viewModel = ProfileViewModel(modelContext: context)

        viewModel.createProfile(name: "   ")

        #expect(viewModel.hasProfile == false)
    }

    @Test("Loads existing profile on init")
    func loadsExistingProfileOnInit() throws {
        let context = try makeModelContext()

        // Pre-seed a profile
        let profile = UserProfile(displayName: "Existing")
        context.insert(profile)
        try context.save()

        let viewModel = ProfileViewModel(modelContext: context)

        #expect(viewModel.hasProfile == true)
        #expect(viewModel.displayName == "Existing")
    }

    @Test("Updates display name")
    func updatesDisplayName() throws {
        let context = try makeModelContext()
        let viewModel = ProfileViewModel(modelContext: context)

        viewModel.createProfile(name: "OldName")
        #expect(viewModel.displayName == "OldName")

        viewModel.updateDisplayName("NewName")
        #expect(viewModel.displayName == "NewName")
    }

    @Test("Trims whitespace on name update")
    func trimsWhitespaceOnUpdate() throws {
        let context = try makeModelContext()
        let viewModel = ProfileViewModel(modelContext: context)

        viewModel.createProfile(name: "Nico")
        viewModel.updateDisplayName("  Updated  ")

        #expect(viewModel.displayName == "Updated")
    }

    @Test("Does not update to empty name")
    func doesNotUpdateToEmptyName() throws {
        let context = try makeModelContext()
        let viewModel = ProfileViewModel(modelContext: context)

        viewModel.createProfile(name: "Nico")
        viewModel.updateDisplayName("")

        #expect(viewModel.displayName == "Nico")
    }

    @Test("Does not update to whitespace-only name")
    func doesNotUpdateToWhitespaceOnlyName() throws {
        let context = try makeModelContext()
        let viewModel = ProfileViewModel(modelContext: context)

        viewModel.createProfile(name: "Nico")
        viewModel.updateDisplayName("   ")

        #expect(viewModel.displayName == "Nico")
    }

    @Test("Update without profile does nothing")
    func updateWithoutProfileDoesNothing() throws {
        let context = try makeModelContext()
        let viewModel = ProfileViewModel(modelContext: context)

        viewModel.updateDisplayName("SomeName")

        #expect(viewModel.hasProfile == false)
        #expect(viewModel.displayName == "")
    }

    @Test("Name change propagates via observable")
    func nameChangePropagatesViaObservable() throws {
        let context = try makeModelContext()
        let viewModel = ProfileViewModel(modelContext: context)

        viewModel.createProfile(name: "Before")
        let nameBefore = viewModel.displayName

        viewModel.updateDisplayName("After")
        let nameAfter = viewModel.displayName

        #expect(nameBefore == "Before")
        #expect(nameAfter == "After")
    }

    @Test("Deleting a non-active profile leaves the other profile's cards and RPG state untouched")
    func deleteProfileLeavesOtherProfileDataIntact() throws {
        let context = try makeModelContext()
        let viewModel = ProfileViewModel(modelContext: context)
        viewModel.createProfile(name: "A")
        viewModel.createProfile(name: "B")
        // "B" is active (last-created wins per createProfile).

        let toDelete = try #require(viewModel.allProfiles.first { $0.displayName == "A" })
        let toKeep = try #require(viewModel.allProfiles.first { $0.displayName == "B" })

        let deletedCard = Card(front: "捨てる", back: "to discard", type: .vocabulary)
        deletedCard.profile = toDelete
        toDelete.cards?.append(deletedCard)
        let keptCard = Card(front: "残る", back: "to remain", type: .vocabulary)
        keptCard.profile = toKeep
        toKeep.cards?.append(keptCard)
        context.insert(deletedCard)
        context.insert(keptCard)
        toKeep.rpgState?.xp = 500
        toKeep.rpgState?.level = 7
        try context.save()

        let keptCardID = keptCard.id
        let keptRPGStateID = try #require(toKeep.rpgState?.id)

        viewModel.deleteProfile(toDelete)

        // The other profile's own row still exists...
        let remainingProfiles = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(remainingProfiles.count == 1)
        #expect(remainingProfiles.first?.id == toKeep.id)

        // ...its card survived, untouched...
        let remainingCards = try context.fetch(FetchDescriptor<Card>())
        #expect(remainingCards.count == 1)
        #expect(remainingCards.first?.id == keptCardID)

        // ...and its RPG progress survived, untouched.
        let remainingRPGStates = try context.fetch(FetchDescriptor<RPGState>())
        #expect(remainingRPGStates.count == 1)
        #expect(remainingRPGStates.first?.id == keptRPGStateID)
        #expect(remainingRPGStates.first?.xp == 500)
        #expect(remainingRPGStates.first?.level == 7)
    }

    @Test("Deleting the active profile switches to a remaining profile")
    func deleteActiveProfileSwitchesToRemaining() throws {
        let context = try makeModelContext()
        let viewModel = ProfileViewModel(modelContext: context)
        viewModel.createProfile(name: "A")
        viewModel.createProfile(name: "B")

        let active = try #require(viewModel.currentProfile)
        #expect(active.displayName == "B")

        viewModel.deleteProfile(active)

        #expect(viewModel.hasProfile == true)
        #expect(viewModel.currentProfile?.displayName == "A")
        #expect(viewModel.allProfiles.count == 1)
        #expect(ActiveProfileResolver.activeProfileID() == viewModel.currentProfile?.id)
    }

    @Test("Refuses to delete the last remaining profile")
    func refusesToDeleteLastRemainingProfile() throws {
        let context = try makeModelContext()
        let viewModel = ProfileViewModel(modelContext: context)
        viewModel.createProfile(name: "Solo")
        let solo = try #require(viewModel.currentProfile)

        viewModel.deleteProfile(solo)

        // Nothing changed: still the same, sole profile.
        #expect(viewModel.hasProfile == true)
        #expect(viewModel.allProfiles.count == 1)
        #expect(viewModel.currentProfile?.id == solo.id)
        let stillThere = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(stillThere.count == 1)
    }

    @Test("switchProfile posts .displayModeDidChange so the cached display mode is re-read")
    func switchProfilePostsDisplayModeDidChange() throws {
        let context = try makeModelContext()
        let viewModel = ProfileViewModel(modelContext: context)
        viewModel.createProfile(name: "A")
        viewModel.createProfile(name: "B")
        let a = try #require(viewModel.allProfiles.first { $0.displayName == "A" })

        // `addObserver(forName:object:queue:using:)`'s handler is `@Sendable`,
        // so a captured mutable local (`var received = false`) doesn't
        // compile — same constraint the repository tests already work
        // around with a class box (see `DisplayModePreferenceRepositoryTests`).
        final class Flag: @unchecked Sendable { var value = false }
        let flag = Flag()
        let observer = NotificationCenter.default.addObserver(
            forName: .displayModeDidChange, object: nil, queue: nil
        ) { _ in flag.value = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        viewModel.switchProfile(to: a)

        #expect(flag.value == true)
    }

    @Test("createProfile posts .displayModeDidChange so a new profile doesn't inherit the prior mode")
    func createProfilePostsDisplayModeDidChange() throws {
        let context = try makeModelContext()
        let viewModel = ProfileViewModel(modelContext: context)
        viewModel.createProfile(name: "A")

        final class Flag: @unchecked Sendable { var value = false }
        let flag = Flag()
        let observer = NotificationCenter.default.addObserver(
            forName: .displayModeDidChange, object: nil, queue: nil
        ) { _ in flag.value = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        viewModel.createProfile(name: "B")

        #expect(flag.value == true)
    }

    @Test("Deleting a profile removes its ExerciseOutcomeLog rows (no orphans)")
    func deleteProfileRemovesOutcomes() throws {
        let context = try makeModelContext()
        let viewModel = ProfileViewModel(modelContext: context)
        viewModel.createProfile(name: "A")
        viewModel.createProfile(name: "B")

        let target = try #require(viewModel.allProfiles.first { $0.displayName == "A" })
        let keep = try #require(viewModel.allProfiles.first { $0.displayName == "B" })

        // ExerciseOutcomeLog is scalar-scoped (no cascade), so deleteProfile
        // must remove the deleted profile's rows explicitly.
        context.insert(ExerciseOutcomeLog(skill: .listening, accuracy: 1.0, profileID: target.id))
        context.insert(ExerciseOutcomeLog(skill: .speaking, accuracy: 0.8, profileID: target.id))
        context.insert(ExerciseOutcomeLog(skill: .listening, accuracy: 0.0, profileID: keep.id))
        try context.save()

        viewModel.deleteProfile(target)

        let remaining = try context.fetch(FetchDescriptor<ExerciseOutcomeLog>())
        // Only the surviving profile's single outcome remains.
        #expect(remaining.count == 1)
        #expect(remaining.first?.profileID == keep.id)
    }
}
