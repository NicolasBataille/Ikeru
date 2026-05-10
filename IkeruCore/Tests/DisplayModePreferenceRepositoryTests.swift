import Testing
import Foundation
import Combine
@testable import IkeruCore

@Suite("UserDefaultsDisplayModePreferenceRepository")
struct DisplayModePreferenceRepositoryTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "DisplayModeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Lazy migration: pre-release profile defaults to .tatami")
    func migrationExisting() {
        let defaults = makeDefaults()
        let preReleaseDate = DisplayModeReleaseDate.value.addingTimeInterval(-86_400)
        let profileID = UUID()

        let repo = UserDefaultsDisplayModePreferenceRepository(
            defaults: defaults,
            activeProfileID: { profileID },
            profileCreatedAt: { _ in preReleaseDate }
        )

        #expect(repo.current() == .tatami)
        // Stored after first read
        #expect(defaults.string(forKey: "ikeru.display.mode.\(profileID.uuidString)") == "tatami")
    }

    @Test("Lazy migration: post-release profile defaults to .beginner")
    func migrationNew() {
        let defaults = makeDefaults()
        let postReleaseDate = DisplayModeReleaseDate.value.addingTimeInterval(86_400)
        let profileID = UUID()

        let repo = UserDefaultsDisplayModePreferenceRepository(
            defaults: defaults,
            activeProfileID: { profileID },
            profileCreatedAt: { _ in postReleaseDate }
        )

        #expect(repo.current() == .beginner)
        #expect(defaults.string(forKey: "ikeru.display.mode.\(profileID.uuidString)") == "beginner")
    }

    @Test("set persists and is read back")
    func setAndRead() {
        let defaults = makeDefaults()
        let profileID = UUID()
        let repo = UserDefaultsDisplayModePreferenceRepository(
            defaults: defaults,
            activeProfileID: { profileID },
            profileCreatedAt: { _ in Date() }
        )

        repo.set(.tatami)
        #expect(repo.current() == .tatami)
        repo.set(.beginner)
        #expect(repo.current() == .beginner)
    }

    @Test("Profile scoping: two profiles maintain independent values")
    func profileScoping() {
        let defaults = makeDefaults()
        let p1 = UUID()
        let p2 = UUID()
        // We need a captured mutable selector. Use a class wrapper to satisfy
        // the @Sendable closure constraint while allowing mutation in test.
        final class Holder: @unchecked Sendable {
            var id: UUID
            init(_ id: UUID) { self.id = id }
        }
        let holder = Holder(p1)
        let repo = UserDefaultsDisplayModePreferenceRepository(
            defaults: defaults,
            activeProfileID: { holder.id },
            profileCreatedAt: { _ in Date() }
        )

        repo.set(.tatami)
        holder.id = p2
        #expect(repo.current() == .beginner) // p2's lazy default
        repo.set(.beginner)
        holder.id = p1
        #expect(repo.current() == .tatami)
    }

    @Test("Publisher replays current and emits on set")
    func publisher() async {
        let defaults = makeDefaults()
        let profileID = UUID()
        let repo = UserDefaultsDisplayModePreferenceRepository(
            defaults: defaults,
            activeProfileID: { profileID },
            profileCreatedAt: { _ in Date() }
        )

        final class Bag: @unchecked Sendable { var values: [DisplayMode] = [] }
        let bag = Bag()
        let cancellable = repo.publisher.sink { bag.values.append($0) }
        defer { cancellable.cancel() }

        // Wait one runloop tick for the replay
        try? await Task.sleep(nanoseconds: 50_000_000)
        repo.set(.tatami)
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(bag.values == [.beginner, .tatami])
    }

    @Test("Missing profile resolution falls back to .beginner without writing")
    func missingProfile() {
        let defaults = makeDefaults()
        let repo = UserDefaultsDisplayModePreferenceRepository(
            defaults: defaults,
            activeProfileID: { nil },
            profileCreatedAt: { _ in nil }
        )

        #expect(repo.current() == .beginner)
        // No persistent write keyed on nil id
        #expect(defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("ikeru.display.mode.") } == false)
    }
}

// Helper: a class wrapper inside the profileScoping test handles the
// captured-mutable-id pattern under Swift 6 strict concurrency.
