import Testing
import Foundation
@testable import IkeruCore

@Suite("RPGAttribute")
struct RPGAttributeTests {

    @Test("withValue clamps between 0 and 100")
    func withValueClamping() {
        let attr = RPGAttribute(
            id: "test", name: "Test", iconName: "star",
            value: 50, unlockLevel: 1, description: "Test"
        )

        let increased = attr.withValue(150)
        #expect(increased.value == 100)

        let decreased = attr.withValue(-10)
        #expect(decreased.value == 0)

        let normal = attr.withValue(75)
        #expect(normal.value == 75)
    }

    @Test("withValue preserves other fields")
    func withValuePreservesFields() {
        let attr = RPGAttribute(
            id: "reading", name: "Reading", iconName: "book.fill",
            value: 10, unlockLevel: 1, description: "Kanji recognition"
        )

        let updated = attr.withValue(50)
        #expect(updated.id == "reading")
        #expect(updated.name == "Reading")
        #expect(updated.iconName == "book.fill")
        #expect(updated.unlockLevel == 1)
        #expect(updated.description == "Kanji recognition")
    }

    @Test("Predefined attributes have unique IDs")
    func predefinedUniqueIDs() {
        let ids = RPGAttribute.allPredefined.map(\.id)
        let uniqueIDs = Set(ids)
        #expect(ids.count == uniqueIDs.count)
    }

    @Test("Predefined attributes have increasing unlock levels")
    func predefinedUnlockLevels() {
        let levels = RPGAttribute.allPredefined.map(\.unlockLevel)
        // Should be non-decreasing
        for i in 1..<levels.count {
            #expect(levels[i] >= levels[i - 1])
        }
    }

    @Test("Codable round-trip preserves attribute")
    func codableRoundTrip() throws {
        let attr = RPGAttribute(
            id: "test", name: "Test", iconName: "star",
            value: 42, unlockLevel: 5, description: "A test attribute"
        )

        let data = try JSONEncoder().encode(attr)
        let decoded = try JSONDecoder().decode(RPGAttribute.self, from: data)
        #expect(decoded == attr)
    }
}
