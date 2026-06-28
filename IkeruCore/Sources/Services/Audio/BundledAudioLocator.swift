import Foundation
import CryptoKit

/// Resolves pre-generated, bundled pronunciation clips by their spoken text.
///
/// Audio is generated offline (see `scripts/generate-audio.sh` / the VOICEVOX
/// pipeline) and shipped in the app bundle under `Audio/`, one `.m4a` per unique
/// spoken string, named by a stable hash of that string. At runtime we hash the
/// text the same way and look the file up — so playback is fully offline with
/// zero user setup, and falls back to on-device synthesis when a clip is absent
/// (e.g. user-authored text, or audio not yet generated for that string).
///
/// The key MUST stay in lockstep with the generator: first 16 hex characters of
/// SHA-256 over the UTF-8 bytes of the text (Python: `sha256(text).hexdigest()[:16]`).
public enum BundledAudioLocator {

    /// Stable filename stem for a spoken text.
    public static func key(for text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }

    /// URL of the bundled clip for `text`, or nil when none is bundled.
    public static func url(for text: String, in bundle: Bundle = .main) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return bundle.url(forResource: key(for: trimmed), withExtension: "m4a", subdirectory: "Audio")
    }
}
