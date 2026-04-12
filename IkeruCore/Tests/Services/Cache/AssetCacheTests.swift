import Testing
import Foundation
@testable import IkeruCore

// MARK: - AssetCacheTests
//
// Note: SwiftData ModelContainer instantiation crashes on macOS test runtime
// (`Could not cast __NSCFNumber to NSString` deep inside SwiftData internals
// on Xcode 26.4 / macOS 14). This is a known limitation that affects every
// model-touching test in IkeruCore (no other test in the suite instantiates
// a ModelContainer either).
//
// The SwiftData persistence path is therefore covered exclusively by iOS
// simulator integration in the Ikeru app target — `AssetCache.store/read/
// evictIfNeeded/clearAll/clearStale` are exercised end-to-end via the
// AISettingsView "Local Rig" + SettingsView "Asset Cache" sections.
//
// What stays in this file: pure-Swift tests for the hash function and the
// configuration helpers, which run fast and have no platform dependencies.

@Suite("AssetCache (pure)")
struct AssetCacheTests {

    @Test("Hash is deterministic and 32 hex chars")
    func hashIsDeterministic() {
        let h1 = AssetCache.hash(of: "tts|voicevox-v0.21|3|食べる")
        let h2 = AssetCache.hash(of: "tts|voicevox-v0.21|3|食べる")
        #expect(h1 == h2)
        #expect(h1.count == 32)
    }

    @Test("Different inputs produce different hashes")
    func differentInputs() {
        let h1 = AssetCache.hash(of: "tts|3|食べる")
        let h2 = AssetCache.hash(of: "tts|4|食べる")
        #expect(h1 != h2)
    }

    @Test("Hash uses lowercase hex")
    func hashIsLowercaseHex() {
        let h = AssetCache.hash(of: "anything")
        #expect(h.allSatisfy { $0.isHexDigit && (!$0.isLetter || $0.isLowercase) })
    }

    @Test("Default configuration uses 500 MB quota")
    func defaultQuotaIs500MB() {
        let config = AssetCache.Configuration.default()
        #expect(config.quotaBytes == 500 * 1024 * 1024)
    }

    @Test("Default configuration roots under Caches/ikeru-assets")
    func defaultRootDirectory() {
        let config = AssetCache.Configuration.default()
        #expect(config.rootDirectory.lastPathComponent == "ikeru-assets")
    }

    @Test("AssetType maps to correct file extension")
    func assetTypeFileExtensions() {
        #expect(AssetType.audioOpus.fileExtension == "opus")
        #expect(AssetType.imagePng.fileExtension == "png")
        #expect(AssetType.textPlain.fileExtension == "txt")
    }

    @Test("RigAudioCoordinator hash is stable for same input")
    func coordinatorHashStable() {
        let h1 = RigAudioCoordinator.makeHash(text: "食べる", speaker: 3)
        let h2 = RigAudioCoordinator.makeHash(text: "食べる", speaker: 3)
        #expect(h1 == h2)
    }

    @Test("RigAudioCoordinator hash differs by speaker")
    func coordinatorHashDifferBySpeaker() {
        let h1 = RigAudioCoordinator.makeHash(text: "食べる", speaker: 3)
        let h2 = RigAudioCoordinator.makeHash(text: "食べる", speaker: 5)
        #expect(h1 != h2)
    }

    @Test("RigAudioCoordinator hash differs by text")
    func coordinatorHashDifferByText() {
        let h1 = RigAudioCoordinator.makeHash(text: "食べる", speaker: 3)
        let h2 = RigAudioCoordinator.makeHash(text: "飲む", speaker: 3)
        #expect(h1 != h2)
    }
}
