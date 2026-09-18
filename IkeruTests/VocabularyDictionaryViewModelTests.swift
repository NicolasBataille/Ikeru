import Testing
import Foundation
import SwiftData
@testable import Ikeru
@testable import IkeruCore

// MARK: - Helpers

private func makeContainer() throws -> ModelContainer {
    let schema = Schema([VocabularyEntry.self, VocabularyEncounter.self,
                         UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
    return try ModelContainer(for: schema,
                              configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
}

/// Un mot dont le dictionnaire embarqué connaît les deux gloses, tel qu'il est
/// capturé depuis un texte importé côté français (`GlossResolver.gloss`).
private let capturedWord = "雨"
private let capturedReading = "あめ"
private let capturedFrenchGloss = "pluie"

@Suite("VocabularyDictionaryViewModel")
@MainActor
struct VocabularyDictionaryViewModelTests {

    /// OBS2-041 : l'apprenant change la langue dans Réglages et revient sur le
    /// dictionnaire déjà chargé. La vue repose `glossLocale` puis recharge ;
    /// le sens affiché doit suivre, sans que le sens stocké bouge.
    @Test
    func reloadingAfterALanguageChangeReResolvesCapturedGlosses() async throws {
        let container = try makeContainer()
        let repository = VocabularyRepository(modelContainer: container)
        _ = await repository.addEntry(word: capturedWord, reading: capturedReading, meaning: capturedFrenchGloss)

        let viewModel = VocabularyDictionaryViewModel(vocabularyRepository: repository)
        viewModel.glossLocale = Locale(identifier: "fr")
        await viewModel.loadData()
        let french = try #require(viewModel.entries.first?.meaning)
        #expect(french == capturedFrenchGloss)

        viewModel.glossLocale = Locale(identifier: "en")
        await viewModel.loadData()
        let english = try #require(viewModel.entries.first?.meaning)
        #expect(english != capturedFrenchGloss, "la glose affichée doit suivre la nouvelle langue")
        #expect(english.hasPrefix("rain"), "glose EN du dictionnaire attendue, reçu « \(english) »")

        let stored = try #require(await repository.allEntries().first?.meaning)
        #expect(stored == capturedFrenchGloss, "rien n'est réécrit : le sens stocké reste celui de la capture")
    }
}
