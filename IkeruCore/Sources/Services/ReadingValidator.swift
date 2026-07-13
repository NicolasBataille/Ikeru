import Foundation

// MARK: - Reading Validator

/// Reconciles AI-generated vocabulary hint readings against the curated
/// content bundle, which holds authoritative hiragana readings for known
/// words. The AI's furigana is generated text and can be hallucinated — when
/// a hint's word matches a known bundle word, the bundle reading is trusted
/// over the model's.
///
/// Pure and deterministic: no I/O, no dates, no randomness. Safe to unit-test
/// directly and safe to call from any isolation context.
enum ReadingValidator {

    /// Reconcile a single vocabulary hint against a `word -> reading` lookup
    /// built from the content bundle.
    ///
    /// - word not present in `bundleReadings` → hint unchanged.
    /// - bundle reading present but empty → treated as not-usable, unchanged.
    /// - bundle reading equals the AI reading (after trimming) → unchanged.
    /// - AI reading is empty and bundle reading is usable → filled in (enrichment).
    /// - AI reading differs from the bundle reading → replaced with the bundle
    ///   reading, since the bundle is authoritative.
    ///
    /// - Parameters:
    ///   - hint: The AI-parsed vocabulary hint.
    ///   - bundleReadings: `word -> reading` map for known bundle vocabulary.
    /// - Returns: The (possibly corrected) hint plus whether a correction happened.
    static func reconcile(_ hint: VocabularyHint, against bundleReadings: [String: String]) -> ReconciledReading {
        guard let bundleReading = bundleReadings[hint.word] else {
            return ReconciledReading(hint: hint, corrected: false)
        }

        let trimmedBundleReading = bundleReading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBundleReading.isEmpty else {
            return ReconciledReading(hint: hint, corrected: false)
        }

        let trimmedAIReading = hint.reading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAIReading != trimmedBundleReading else {
            return ReconciledReading(hint: hint, corrected: false)
        }

        // Covers both enrichment (empty AI reading) and correction (differing
        // AI reading) — in both cases the bundle reading wins.
        let correctedHint = VocabularyHint(
            id: hint.id,
            word: hint.word,
            reading: trimmedBundleReading,
            meaning: hint.meaning
        )
        return ReconciledReading(hint: correctedHint, corrected: true)
    }
}

// MARK: - Reconciled Reading

/// Result of reconciling a vocabulary hint's reading against the content
/// bundle: the (possibly corrected) hint, plus whether a correction happened
/// so callers can log it.
struct ReconciledReading: Sendable, Equatable {
    let hint: VocabularyHint
    let corrected: Bool
}
