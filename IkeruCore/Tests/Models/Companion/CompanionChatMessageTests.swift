import Testing
import Foundation
@testable import IkeruCore

// MARK: - CompanionChatMessage Tests

@Suite("CompanionChatMessage")
struct CompanionChatMessageTests {

    @Test("Creates message with correct defaults")
    func createsWithDefaults() {
        let profileId = UUID()
        let message = CompanionChatMessage(
            role: .user,
            content: "Hello",
            profileId: profileId
        )

        #expect(message.roleRawValue == "user")
        #expect(message.content == "Hello")
        #expect(message.profileId == profileId)
        #expect(message.role == .user)
    }

    @Test("Role computed property maps correctly")
    func roleMapping() {
        let profileId = UUID()

        let userMsg = CompanionChatMessage(role: .user, content: "", profileId: profileId)
        #expect(userMsg.role == .user)

        let companionMsg = CompanionChatMessage(role: .companion, content: "", profileId: profileId)
        #expect(companionMsg.role == .companion)

        let systemMsg = CompanionChatMessage(role: .system, content: "", profileId: profileId)
        #expect(systemMsg.role == .system)
    }

    @Test("Each message gets a unique ID")
    func uniqueIds() {
        let profileId = UUID()
        let msg1 = CompanionChatMessage(role: .user, content: "A", profileId: profileId)
        let msg2 = CompanionChatMessage(role: .user, content: "B", profileId: profileId)
        #expect(msg1.id != msg2.id)
    }
}

// MARK: - CompanionMessageRole Tests

@Suite("CompanionMessageRole")
struct CompanionMessageRoleTests {

    @Test("Raw values are correct strings")
    func rawValues() {
        #expect(CompanionMessageRole.user.rawValue == "user")
        #expect(CompanionMessageRole.companion.rawValue == "companion")
        #expect(CompanionMessageRole.system.rawValue == "system")
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let role = CompanionMessageRole.companion
        let data = try JSONEncoder().encode(role)
        let decoded = try JSONDecoder().decode(CompanionMessageRole.self, from: data)
        #expect(decoded == role)
    }
}
