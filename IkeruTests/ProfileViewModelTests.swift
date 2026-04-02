import Testing
import SwiftData
@testable import Ikeru
@testable import IkeruCore

@Suite("ProfileViewModel")
@MainActor
struct ProfileViewModelTests {

    // MARK: - Helpers

    private func makeModelContext() throws -> ModelContext {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
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
}
