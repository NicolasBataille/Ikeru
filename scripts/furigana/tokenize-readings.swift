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
guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: tokenize-readings <fichier>\n".utf8))
    exit(2)
}
let path = CommandLine.arguments[1]
guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
    FileHandle.standardError.write(Data("lecture impossible : \(path)\n".utf8))
    exit(2)
}

for line in raw.components(separatedBy: "\u{1E}\n") {
    let sentence = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if sentence.isEmpty { continue }
    let ns = sentence as NSString
    let tokenizer = CFStringTokenizerCreate(
        nil, sentence as CFString, CFRangeMake(0, ns.length),
        kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale)
    var parts: [String] = []
    while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
        let r = CFStringTokenizerGetCurrentTokenRange(tokenizer)
        let word = ns.substring(with: NSRange(location: r.location, length: r.length))
        var reading = (CFStringTokenizerCopyCurrentTokenAttribute(
            tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String) ?? ""
        if !reading.isEmpty {
            let mutable = NSMutableString(string: reading) as CFMutableString
            CFStringTransform(mutable, nil, kCFStringTransformLatinHiragana, false)
            reading = mutable as String
        }
        parts.append(word + US + reading)
    }
    print(sentence + RS + parts.joined(separator: GS))
}
