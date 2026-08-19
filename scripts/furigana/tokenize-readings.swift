// Emits one line per input sentence: sentence <RS> token <US> reading <GS> token <US> reading …
//
// Uses CFStringTokenizer's Latin transcription, converted to hiragana — the
// standard Apple route to a reading. It is CONTEXT-AWARE (it gets 電話中 →
// ちゅう and あの人 → ひと right) but not infallible; see
// `scripts/furigana/overrides.json` for the reviewed corrections layered on top.
//
// Reading this file to reproduce the corpus? Run generate-furigana.py, not this.
import Foundation

let RS = "\u{1E}", GS = "\u{1D}", US = "\u{1F}"
let path = CommandLine.arguments[1]
let raw = try! String(contentsOfFile: path, encoding: .utf8)

for line in raw.components(separatedBy: "\u{1E}\n") {
    let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty { continue }
    let ns = s as NSString
    let tokenizer = CFStringTokenizerCreate(
        nil, s as CFString, CFRangeMake(0, ns.length),
        kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale)
    var parts: [String] = []
    while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
        let r = CFStringTokenizerGetCurrentTokenRange(tokenizer)
        let word = ns.substring(with: NSRange(location: r.location, length: r.length))
        var reading = (CFStringTokenizerCopyCurrentTokenAttribute(
            tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String) ?? ""
        if !reading.isEmpty {
            let m = NSMutableString(string: reading) as CFMutableString
            CFStringTransform(m, nil, kCFStringTransformLatinHiragana, false)
            reading = m as String
        }
        parts.append(word + US + reading)
    }
    print(s + RS + parts.joined(separator: GS))
}
