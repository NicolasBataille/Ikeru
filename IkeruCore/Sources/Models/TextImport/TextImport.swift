import Foundation
import SwiftData

/// A text the learner brought in: a tweet, song lyrics, a photographed menu, a
/// message, a manga bubble.
///
/// ## Why the link to vocabulary lives HERE and not on the encounter
///
/// The obvious modelling is a relationship from `VocabularyEncounter` back to
/// its import. It was deliberately not done. `VocabularyEncounter` is frozen
/// inside `IkeruSchemaV1`, `V2` and `V3` as a nested snapshot, and is
/// referenced **live** by `IkeruSchemaV4` — so adding a property to it silently
/// changes what V4 means, which is precisely the `aa03566` failure the schema
/// file documents at length: every store on a real device stops hash-matching
/// any known schema and the container refuses to open.
///
/// Avoiding it would have meant freezing `VocabularyEncounter` *and*
/// `VocabularyEntry` (reachable through their mutual relationship) into V4
/// first. Carrying the identifiers on this side instead makes V5 purely
/// additive — one new entity, nothing else touched — and puts the deletion rule
/// in code, where it can be tested, rather than in a cascade, where it cannot.
///
/// ## Deleting an import
///
/// Product rule, agreed with the review side: deleting an import removes the
/// entries whose **only** provenance was this import, and leaves alone any
/// entry the learner also met elsewhere or added by hand — it merely loses this
/// encounter. `TextImportRepository.delete(_:)` owns that, and
/// `TextImportRepositoryTests` pins both halves.
@Model
public final class TextImport {

    /// Stable identity, shared with the server row.
    public var id: UUID

    /// A short label for lists — the first line, trimmed. Derived at creation
    /// rather than asked for: naming an import is friction, and the vision
    /// budgets under a minute for the whole journey.
    public var title: String

    /// The text itself, **as the learner left it** — including any correction
    /// they made to what the OCR read. Never re-derived from the photo.
    public var content: String

    /// Raw storage for `source`, so SwiftData predicates can reach it.
    public var sourceRawValue: String

    public var createdAt: Date

    /// Share of content words already known when the text was imported, 0…1,
    /// `nil` when there was nothing measurable to count.
    ///
    /// Frozen at import time on purpose: it is a snapshot of « where I was when
    /// I met this text », and the reading journal reads it back months later.
    /// Recomputing it would quietly rewrite the learner's own history.
    public var coverage: Double?

    /// Vocabulary entries **created** by this import, in selection order.
    ///
    /// Created, not merely met: a word the learner already had in their
    /// dictionary before this text does not belong here, because
    /// `TextImportRepository.delete(_:)` reads this list as « what this import
    /// alone brought in » and tombstones what it finds. Putting an older card
    /// in it destroys that card and its FSRS history. Pinned by
    /// `preexistingDictionaryWordsAreNotClaimed` in `TextImportViewModelTests`.
    public var entryIDs: [UUID]

    public var source: ImportSource {
        get { ImportSource(rawValue: sourceRawValue) ?? .paste }
        set { sourceRawValue = newValue.rawValue }
    }

    // MARK: - Cloud sync
    //
    // Nico's ruling (2026-08-19): imported text IS backed up. It travels in the
    // learner's own Supabase rows — anonymous identity, RLS, cascade delete —
    // and `docs/privacy.html` says so in the same change that created the
    // table, not after it.

    public var updatedAt: Date = Date(timeIntervalSince1970: 0)
    public var deletedAt: Date?
    public var syncedAt: Date?

    public init(id: UUID = UUID(), title: String = "", content: String,
                source: ImportSource = .paste, createdAt: Date = Date(),
                coverage: Double? = nil, entryIDs: [UUID] = []) {
        self.id = id
        self.content = content
        self.title = title.isEmpty ? Self.derivedTitle(from: content) : title
        self.sourceRawValue = source.rawValue
        self.createdAt = createdAt
        self.coverage = coverage
        self.entryIDs = entryIDs
        self.updatedAt = createdAt
    }

    /// The first non-empty line, capped. Kept `static` and pure so the title of
    /// a pasted text is predictable and testable.
    public static func derivedTitle(from content: String, limit: Int = 40) -> String {
        let firstLine = content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard firstLine.count > limit else { return firstLine }
        return String(firstLine.prefix(limit)) + "…"
    }
}

// MARK: - DTO

/// Sendable snapshot for cross-actor transfer, mirroring `VocabularyEntryDTO`.
public struct TextImportDTO: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let content: String
    public let source: ImportSource
    public let createdAt: Date
    public let coverage: Double?
    public let entryIDs: [UUID]

    public init(id: UUID, title: String, content: String, source: ImportSource,
                createdAt: Date, coverage: Double?, entryIDs: [UUID]) {
        self.id = id
        self.title = title
        self.content = content
        self.source = source
        self.createdAt = createdAt
        self.coverage = coverage
        self.entryIDs = entryIDs
    }

    /// Words kept from this text.
    public var wordCount: Int { entryIDs.count }
}

extension TextImport {
    public func toDTO() -> TextImportDTO {
        TextImportDTO(id: id, title: title, content: content, source: source,
                      createdAt: createdAt, coverage: coverage, entryIDs: entryIDs)
    }
}
