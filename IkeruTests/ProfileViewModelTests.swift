import Foundation
import Testing
import SwiftData
@testable import Ikeru
@testable import IkeruCore

// GAP-10: cross-suite SwiftData isolation — see SwiftDataTestIsolation.swift.
@Suite("ProfileViewModel", .swiftDataIsolated)
@MainActor
struct ProfileViewModelTests {

    // MARK: - Helpers

    private func makeModelContext() throws -> ModelContext {
        // Full V3 schema so ExerciseOutcomeLog (scalar-scoped, no cascade) is
        // present for the deletion-cleanup test. Must track the app's current
        // schema version (see IkeruApp) — declaring a stale version opens the
        // container without error but traps on the first insert.
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
        //
        // GAP-10 (2026-08-16), symbolicated proof this suite's crash is a
        // DIFFERENT bug from HomeViewModelTests's, not the same one wearing
        // two faces: `xcrun xcresulttool export diagnostics` +
        // `~/Library/Logs/DiagnosticReports/Ikeru-*.ips` on a crash from
        // `updatesDisplayName()` shows `EXC_BREAKPOINT`/`SIGTRAP`, faulting
        // thread stack (innermost first) `SwiftData + 645672` →
        // `SwiftData + 594444` → `SwiftData + 643760` →
        // `ProfileViewModel.loadProfile()` → `ProfileViewModel.init
        // (modelContext:)` — i.e. a trap inside SwiftData's own internals on
        // this class's very FIRST `modelContext.fetch` call, synchronously
        // inside `init`, no relationship faulting, no background actor
        // involved, and (unlike HomeViewModelTests) NO
        // "Fatal error: ..." text printed anywhere — a silent trap, not an
        // assertion with a message. HomeViewModelTests's crash is instead an
        // explicit `SwiftData/BackingData.swift:940: Fatal error: Never
        // access a full future backing data` with two mismatched Core Data
        // store UUIDs in the message, hit via `ActiveProfileResolver
        // .fetchActiveRPGState` → `profile.rpgState` relationship fault,
        // well after other SwiftData work has already happened successfully.
        // Different signal, different call shape, different SwiftData
        // subsystem — treat these as two separate open bugs, not one.
        //
        // V4, not V3 (2026-08-13, cloud-sync lot 0): `IkeruSchemaV3` is now
        // frozen (nested snapshot types) — a container opened at V3 would
        // bind this file's live-type fetches to the wrong entity identity.
        let schema = Schema(versionedSchema: IkeruSchemaV4.self)
        let config = ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
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

        let deletedCardID = deletedCard.id
        let deletedProfileID = toDelete.id

        viewModel.deleteProfile(toDelete)

        // Deletion is a tombstone now, not a hard delete (GAP-15): the rows
        // survive carrying `deletedAt` so the deletion has something to push,
        // and every read path filters them out. So these assertions ask "what
        // is still LIVE", which is what they always meant.
        let liveProfiles = try context.fetch(
            FetchDescriptor<UserProfile>(predicate: #Predicate { $0.deletedAt == nil })
        )
        #expect(liveProfiles.count == 1)
        #expect(liveProfiles.first?.id == toKeep.id)

        // ...its card survived, untouched...
        let liveCards = try context.fetch(
            FetchDescriptor<Card>(predicate: #Predicate { $0.deletedAt == nil })
        )
        #expect(liveCards.count == 1)
        #expect(liveCards.first?.id == keptCardID)

        // ...and its RPG progress survived, untouched.
        let liveRPGStates = try context.fetch(
            FetchDescriptor<RPGState>(predicate: #Predicate { $0.deletedAt == nil })
        )
        #expect(liveRPGStates.count == 1)
        #expect(liveRPGStates.first?.id == keptRPGStateID)
        #expect(liveRPGStates.first?.xp == 500)
        #expect(liveRPGStates.first?.level == 7)

        // And the other half of the same invariant: the deleted profile's own
        // graph really is tombstoned, not merely hidden. Without this the
        // cascade could silently stop at the profile row and leave its cards
        // and RPG state live — pushed to the server, resurrectable on any
        // device that pulls them.
        let deletedProfileRow = try #require(
            try context.fetch(
                FetchDescriptor<UserProfile>(predicate: #Predicate { $0.id == deletedProfileID })
            ).first
        )
        #expect(deletedProfileRow.deletedAt != nil)
        let deletedCardRow = try #require(
            try context.fetch(
                FetchDescriptor<Card>(predicate: #Predicate { $0.id == deletedCardID })
            ).first
        )
        #expect(deletedCardRow.deletedAt != nil, "the profile's cards were not cascade-tombstoned")
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
        let stillThere = try context.fetch(
            FetchDescriptor<UserProfile>(predicate: #Predicate { $0.deletedAt == nil })
        )
        #expect(stillThere.count == 1)
        // The refusal must not tombstone it either — a "refused" delete that
        // silently stamps `deletedAt` would push a deletion to the server for
        // a profile the app still shows.
        #expect(stillThere.first?.deletedAt == nil)
    }

    @Test("switchProfile posts .displayModeDidChange so the cached display mode is re-read")
    func switchProfilePostsDisplayModeDidChange() throws {
        let context = try makeModelContext()
        let viewModel = ProfileViewModel(modelContext: context)
        viewModel.createProfile(name: "A")
        viewModel.createProfile(name: "B")
        let profileA = try #require(viewModel.allProfiles.first { $0.displayName == "A" })

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

        viewModel.switchProfile(to: profileA)

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

    @Test("Deleting a profile tombstones its ExerciseOutcomeLog rows (no orphans, no resurrection)")
    func deleteProfileRemovesOutcomes() throws {
        let context = try makeModelContext()
        let viewModel = ProfileViewModel(modelContext: context)
        viewModel.createProfile(name: "A")
        viewModel.createProfile(name: "B")

        let target = try #require(viewModel.allProfiles.first { $0.displayName == "A" })
        let keep = try #require(viewModel.allProfiles.first { $0.displayName == "B" })

        // ExerciseOutcomeLog is scalar-scoped (no SwiftData cascade), so
        // deleteProfile must handle the deleted profile's rows explicitly.
        context.insert(ExerciseOutcomeLog(skill: .listening, accuracy: 1.0, profileID: target.id))
        context.insert(ExerciseOutcomeLog(skill: .speaking, accuracy: 0.8, profileID: target.id))
        context.insert(ExerciseOutcomeLog(skill: .listening, accuracy: 0.0, profileID: keep.id))
        try context.save()

        let targetID = target.id
        viewModel.deleteProfile(target)

        // Live rows: only the surviving profile's single outcome.
        let live = try context.fetch(
            FetchDescriptor<ExerciseOutcomeLog>(predicate: #Predicate { $0.deletedAt == nil })
        )
        #expect(live.count == 1)
        #expect(live.first?.profileID == keep.id)

        // And the deleted profile's rows carry a tombstone rather than having
        // vanished (GAP-15): a hard delete left the server copies alive and
        // they came back on the next pull that rewound its cursor.
        let orphans = try context.fetch(
            FetchDescriptor<ExerciseOutcomeLog>(predicate: #Predicate { $0.profileID == targetID })
        )
        #expect(orphans.count == 2)
        #expect(orphans.allSatisfy { $0.deletedAt != nil })
    }

    @Test("Deleting a profile removes its MasteryBookSnapshotStore baseline (chantier #45h)")
    func deleteProfileRemovesMasteryBookSnapshot() throws {
        let context = try makeModelContext()
        let viewModel = ProfileViewModel(modelContext: context)
        viewModel.createProfile(name: "A")
        viewModel.createProfile(name: "B")

        let target = try #require(viewModel.allProfiles.first { $0.displayName == "A" })
        let keep = try #require(viewModel.allProfiles.first { $0.displayName == "B" })

        // MasteryBookSnapshotStore is UserDefaults-backed, keyed by profile
        // id — it does NOT cascade with the SwiftData profile delete, so
        // `deleteProfile` must clear it explicitly (same pattern as
        // `OnboardingFlags` and `ExerciseOutcomeLog` above).
        MasteryBookSnapshotStore.recordIfStale(
            profileID: target.id,
            counts: MasteryBookCounts(masteredCount: 4)
        )
        MasteryBookSnapshotStore.recordIfStale(
            profileID: keep.id,
            counts: MasteryBookCounts(masteredCount: 2)
        )
        defer {
            MasteryBookSnapshotStore.clear(profileID: target.id)
            MasteryBookSnapshotStore.clear(profileID: keep.id)
        }

        viewModel.deleteProfile(target)

        // The deleted profile's baseline is gone; the surviving profile's
        // baseline — proof the store really is scoped per profile — is
        // untouched.
        #expect(MasteryBookSnapshotStore.priorSnapshot(profileID: target.id) == nil)
        #expect(
            MasteryBookSnapshotStore.priorSnapshot(profileID: keep.id)
                == MasteryBookCounts(masteredCount: 2)
        )
    }
}
