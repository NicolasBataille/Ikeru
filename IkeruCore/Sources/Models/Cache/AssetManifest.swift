import Foundation
import SwiftData

// MARK: - AssetManifest
//
// SwiftData record describing one cached asset on disk. The actual binary
// payload lives at `<Caches>/ikeru-assets/<hash[:2]>/<hash>.<ext>` and is
// addressed by content hash. The manifest tracks size, source text, and the
// last access timestamp so the LRU evictor can prune the oldest entries when
// the on-disk total exceeds the configured quota.

@Model
public final class AssetManifest {

    /// Stable unique identifier for this manifest entry.
    public var id: UUID

    /// Content hash that maps to the on-disk filename. Uniqueness is enforced
    /// at the cache layer (`AssetCache.store` filters by hash before insert).
    public var hash: String

    /// Asset MIME-style category — `audio_opus`, `image_png`, etc.
    public var typeRawValue: String

    /// File size in bytes.
    public var sizeBytes: Int

    /// Optional human-readable source text (e.g. the Japanese sentence for TTS).
    public var sourceText: String?

    /// When this asset was generated and first stored.
    public var generatedAt: Date

    /// Touched on every cache hit so the LRU policy works.
    public var lastAccessedAt: Date

    public init(
        hash: String,
        type: AssetType,
        sizeBytes: Int,
        sourceText: String? = nil,
        generatedAt: Date = Date(),
        lastAccessedAt: Date = Date()
    ) {
        self.id = UUID()
        self.hash = hash
        self.typeRawValue = type.rawValue
        self.sizeBytes = sizeBytes
        self.sourceText = sourceText
        self.generatedAt = generatedAt
        self.lastAccessedAt = lastAccessedAt
    }

    public var type: AssetType {
        AssetType(rawValue: typeRawValue) ?? .audioOpus
    }
}

// MARK: - AssetType

public enum AssetType: String, Codable, Sendable, CaseIterable {
    case audioOpus = "audio_opus"
    case imagePng = "image_png"
    case textPlain = "text_plain"

    public var fileExtension: String {
        switch self {
        case .audioOpus: "opus"
        case .imagePng:  "png"
        case .textPlain: "txt"
        }
    }
}
