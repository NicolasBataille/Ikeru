import Foundation
import SwiftData
import os

// MARK: - TextImportRepository

/// Stores the texts the learner brought in, and owns what happens when one is
/// deleted.
///
/// Mirrors `VocabularyRepository`: a `Sendable` façade over a `@ModelActor`,
/// DTOs across the boundary.
public final class TextImportRepository: Sendable {

    private let backgroundActor: TextImportModelActor

    public init(modelContainer: ModelContainer) {
        self.backgroundActor = TextImportModelActor(modelContainer: modelContainer)
    }

    /// Records an import and the entries kept from it.
    public func create(content: String, source: ImportSource,
                       coverage: Double?, entryIDs: [UUID]) async -> TextImportDTO {
        await backgroundActor.create(content: content, source: source,
                                     coverage: coverage, entryIDs: entryIDs)
    }

    /// Every live import, newest first — the reading journal.
    public func all() async -> [TextImportDTO] {
        await backgroundActor.all()
    }

    public func textImport(by id: UUID) async -> TextImportDTO? {
        await backgroundActor.textImport(by: id)
    }

    /// Imports that produced a given vocabulary entry — « vu dans ton import du
    /// 19/08 » on a card, resolved from this side because the link lives here.
    public func imports(containing entryID: UUID) async -> [TextImportDTO] {
        await backgroundActor.imports(containing: entryID)
    }

    /// Deletes an import and, with it, only the entries it alone brought in.
    ///
    /// Returns the entry identifiers actually removed, so a view can say how
    /// many cards went with the text instead of implying « all of them ».
    @discardableResult
    public func delete(id: UUID) async -> [UUID] {
        await backgroundActor.delete(id: id)
    }
}

// MARK: - TextImportModelActor

@ModelActor
actor TextImportModelActor {

    // MARK: Create / read

    func create(content: String, source: ImportSource,
                coverage: Double?, entryIDs: [UUID]) -> TextImportDTO {
        let record = TextImport(content: content, source: source,
                                coverage: coverage, entryIDs: entryIDs)
        modelContext.insert(record)
        try? modelContext.save()
        Logger.content.info("Imported text: \(record.entryIDs.count) words kept")
        return record.toDTO()
    }

    func all() -> [TextImportDTO] {
        let predicate = #Predicate<TextImport> { $0.deletedAt == nil }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return ((try? modelContext.fetch(descriptor)) ?? []).map { $0.toDTO() }
    }

    func textImport(by id: UUID) -> TextImportDTO? {
        live(id).map { $0.toDTO() }
    }

    func imports(containing entryID: UUID) -> [TextImportDTO] {
        // `entryIDs` is a stored array; `#Predicate` cannot reach into it, so
        // the filter happens in memory. Imports are a handful per learner, not
        // a table to scan.
        all().filter { $0.entryIDs.contains(entryID) }
    }

    // MARK: Delete

    /// The deletion rule, in one place because it is a **product** rule.
    ///
    /// Deleting an import must not quietly take down words the learner met
    /// elsewhere. So an entry leaves with the text only when this import was
    /// its sole provenance:
    ///
    /// 1. no other live import lists it, and
    /// 2. it carries no encounter from any source other than `.importedText`
    ///    — meeting the word in a Sakura conversation or a session makes it the
    ///    learner's, not the text's.
    ///
    /// An entry that survives still loses **this** text's encounter — for
    /// *either* reason it survived — so its history stops claiming a context
    /// that no longer exists. Those encounters are the `.importedText` ones
    /// whose snippet is part of the deleted content — the snippet is a sentence
    /// of the text, so containment is exact.
    ///
    /// The one ambiguity this cannot resolve: two imports carrying the *same*
    /// sentence are indistinguishable here, because no foreign key ties an
    /// encounter to an import (adding one would have meant growing
    /// `VocabularyEncounter`, which V4 references live — see `TextImport`).
    /// Deleting either then drops that shared encounter. Measured cost: one
    /// context line on a word the learner keeps.
    ///
    /// Everything is tombstoned (`deletedAt`), never hard-deleted: a hard delete
    /// is undone by the next pull, as `VocabularyRepository.addEntry` documents.
    func delete(id: UUID) -> [UUID] {
        guard let record = live(id) else { return [] }
        let content = record.content
        let candidates = record.entryIDs

        record.deletedAt = Date()
        record.updatedAt = Date()

        let otherImports = ((try? modelContext.fetch(
            FetchDescriptor<TextImport>(predicate: #Predicate { $0.deletedAt == nil })
        )) ?? []).filter { $0.id != id }
        let stillReferenced = Set(otherImports.flatMap(\.entryIDs))

        var removed: [UUID] = []
        for entryID in candidates {
            guard let entry = liveEntry(entryID) else { continue }
            let encounters = (entry.encounters ?? []).filter { $0.deletedAt == nil }
            // Deux raisons de survivre, un seul traitement. Elles étaient
            // traitées séparément et divergeaient : « revendiqué par un autre
            // import » sautait l'entrée entière, donc le mot gardait une
            // rencontre citant un texte effacé, alors que « rencontré
            // ailleurs » la retirait. Même situation, deux issues, selon la
            // seule raison de la survie — voir `survivorLosesThisTextsEncounter`.
            let claimedByAnotherImport = stillReferenced.contains(entryID)
            let metElsewhere = encounters.contains { $0.source != .importedText }

            if claimedByAnotherImport || metElsewhere {
                // Le mot reste : il n'appartient plus au texte seul. On ne
                // retire que la rencontre issue de CE texte — l'extrait est une
                // phrase du texte, donc l'inclusion suffit à l'identifier. Un
                // extrait vide n'appartient à personne : `contains("")` rend
                // `false` en Swift (vérifié par `emptySnippetIsNotMatched…`),
                // mais le dire ici évite qu'un refactor le suppose.
                for encounter in encounters
                where encounter.source == .importedText
                    && !encounter.contextSnippet.isEmpty
                    && content.contains(encounter.contextSnippet) {
                    encounter.deletedAt = Date()
                    encounter.updatedAt = Date()
                }
                continue
            }

            entry.deletedAt = Date()
            entry.updatedAt = Date()
            for encounter in encounters {
                encounter.deletedAt = Date()
                encounter.updatedAt = Date()
            }
            removed.append(entryID)
        }

        try? modelContext.save()
        Logger.content.info("Deleted import \(id): \(removed.count) entries removed")
        return removed
    }

    // MARK: Helpers

    private func live(_ id: UUID) -> TextImport? {
        let predicate = #Predicate<TextImport> { $0.id == id && $0.deletedAt == nil }
        return (try? modelContext.fetch(FetchDescriptor(predicate: predicate)))?.first
    }

    private func liveEntry(_ id: UUID) -> VocabularyEntry? {
        let predicate = #Predicate<VocabularyEntry> { $0.id == id && $0.deletedAt == nil }
        return (try? modelContext.fetch(FetchDescriptor(predicate: predicate)))?.first
    }
}
