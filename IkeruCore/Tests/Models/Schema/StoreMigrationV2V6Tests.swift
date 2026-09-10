import Testing
import SwiftData
import Foundation
@testable import IkeruCore

// MARK: - V2 → V6, la chaîne entière d'un coup
//
// Pourquoi cette suite existe (2026-09-10) : le dernier build TestFlight
// (2026-08-09) embarquait `IkeruSchemaV2`. La release suivante livre V6. Un
// testeur qui met à jour migre donc QUATRE étapes lightweight au premier
// lancement (V2→V3→V4→V5→V6), sans jamais passer par un build intermédiaire.
// Chaque étape est prouvée par sa propre suite ; la chaîne entière, sur un
// vrai store V2 sur disque, ne l'était pas. C'est ce que vit l'apprenant,
// c'est donc ce qu'on prouve ici.
//
// Même contrainte de confinement que les autres suites de migration : son
// PROPRE process (step CI dédié, `--skip` dans le run principal). Voir
// `StoreMigrationV2V3Tests.swift` pour l'empoisonnement du cache
// entité↔classe de CoreData qui l'impose.
@Suite("StoreMigrationV2V6", .serialized)
struct StoreMigrationV2V6Tests {

    @Test("A genuine V2 store migrates V2→V3→V4→V5→V6 in one open; rows survive, new tables are empty and usable")
    func v2ToV6FullChain() throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("ikeru-mig-v2v6-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: url.deletingLastPathComponent()
                        .appendingPathComponent(url.lastPathComponent + suffix)
                )
            }
        }

        let profileName = "Migrator V2"
        let logStamp = Date(timeIntervalSince1970: 1_800_000_000)

        // 1. Un vrai store V2 : container sans plan de migration, types FIGÉS
        //    de V2 — exactement ce que le build du 2026-08-09 a écrit sur les
        //    appareils des testeurs.
        try Self.seedV2Store(at: url, profileName: profileName, logStamp: logStamp)

        // 2. Une seule réouverture avec le schéma LIVE (V6) et le plan : les
        //    quatre étapes s'enchaînent dans ce `ModelContainer(...)`.
        let schemaV6 = Schema(versionedSchema: IkeruSchemaV6.self)
        let containerV6 = try ModelContainer(
            for: schemaV6,
            migrationPlan: IkeruMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schemaV6, url: url)]
        )
        let ctx = ModelContext(containerV6)

        // Les lignes V2 ont survécu, lisibles à travers les types live.
        let profiles = try ctx.fetch(FetchDescriptor<UserProfile>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.displayName == profileName)

        let cards = try ctx.fetch(FetchDescriptor<Card>())
        #expect(cards.count == 1)
        #expect(cards.first?.front == "犬")

        let logs = try ctx.fetch(FetchDescriptor<ReviewLog>())
        #expect(logs.count == 1)
        let migratedLog = try #require(logs.first)
        #expect(migratedLog.grade == .good)
        #expect(migratedLog.responseTimeMs == 1_800)
        #expect(migratedLog.timestamp == logStamp)
        // V3 : provenance de réponse, jamais fabriquée.
        #expect(migratedLog.answeredValue == nil)
        #expect(migratedLog.exerciseType == nil)
        #expect(migratedLog.surface == nil)
        // V4 : colonnes cloud, sentinelle epoch et nil.
        #expect(migratedLog.updatedAt == Date(timeIntervalSince1970: 0))
        #expect(migratedLog.deletedAt == nil)
        #expect(migratedLog.syncedAt == nil)

        let rpgStates = try ctx.fetch(FetchDescriptor<RPGState>())
        #expect(rpgStates.count == 1)
        #expect(rpgStates.first?.xp == 1_234)
        #expect(rpgStates.first?.activeDaysCount == 12)

        // Les tables nées après V2 existent, vides, et n'ont rien à adopter.
        #expect(try ctx.fetch(FetchDescriptor<VocabularyEntry>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<TextImport>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<ExerciseOutcomeLog>()).isEmpty)
        let owner = try #require(profiles.first?.id)
        let adoption = try OwnershipAdoption.adoptUnownedRows(into: owner, in: ctx)
        #expect(adoption.isEmpty)

        // Et le store migré est utilisable en V6.
        try Self.assertUsableInV6(ctx, owner: owner, card: #require(cards.first))
    }

    // MARK: - Helpers

    /// Écrit un store V2 tel que le build du 2026-08-09 le laissait : profil,
    /// RPGState, une carte, un log de révision — via les types figés de V2.
    private static func seedV2Store(at url: URL, profileName: String, logStamp: Date) throws {
        let schema = Schema(versionedSchema: IkeruSchemaV2.self)
        let config = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: [config])
        let ctx = ModelContext(container)

        let profile = IkeruSchemaV2.UserProfile(displayName: profileName)
        let rpg = try #require(profile.rpgState)
        rpg.xp = 1_234
        rpg.activeDaysCount = 12
        ctx.insert(profile)

        let card = IkeruSchemaV2.Card(front: "犬", back: "chien", type: .vocabulary, dueDate: Date())
        card.profile = profile
        ctx.insert(card)

        let log = IkeruSchemaV2.ReviewLog(
            card: card,
            grade: .good,
            responseTimeMs: 1_800,
            timestamp: logStamp
        )
        ctx.insert(log)
        try ctx.save()
    }

    /// Une entrée de dictionnaire attribuée au profil, un import, un log de
    /// révision avec provenance : les écritures V6 passent dans le store migré.
    private static func assertUsableInV6(_ ctx: ModelContext, owner: UUID, card: Card) throws {
        let entry = VocabularyEntry(word: "猫", reading: "ねこ", meaning: "chat", profileID: owner)
        ctx.insert(entry)
        let textImport = TextImport(title: "Premier texte", content: "猫がいます。", profileID: owner)
        ctx.insert(textImport)
        ctx.insert(ReviewLog(
            card: card,
            grade: .easy,
            responseTimeMs: 700,
            answeredValue: "chien",
            exerciseType: "vocabulary.flashcard",
            surface: "iphone.session"
        ))
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<VocabularyEntry>()).first?.profileID == owner)
        #expect(try ctx.fetch(FetchDescriptor<TextImport>()).first?.profileID == owner)
        #expect(try ctx.fetch(FetchDescriptor<ReviewLog>()).count == 2)
    }
}
