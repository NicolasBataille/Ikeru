// Segment Japanese text with Apple's NLTokenizer (NaturalLanguage framework).
//
// There is no Japanese segmenter in this repository and none may be added
// (IkeruCore ships without external dependencies, and the build scripts should
// not either). NLTokenizer is on every macOS machine that can build this app,
// works offline, and is a real morphological segmenter rather than a
// substring heuristic.
//
// Protocol, so the Python funnel can shell out to it once:
//   stdin  — one `<id>\t<japanese text>` per line
//   stdout — one `<id>\t<token> <token> …` per line, same order
//
// Punctuation and whitespace are dropped by the tokenizer, which is what the
// caller wants: it scores lexical difficulty, not typography.
//
// Build:  swiftc -O -o tokenize-japanese tokenize-japanese.swift

import Foundation
import NaturalLanguage

let tokenizer = NLTokenizer(unit: .word)
tokenizer.setLanguage(.japanese)

while let line = readLine(strippingNewline: true) {
    guard let tab = line.firstIndex(of: "\t") else { continue }
    let identifier = String(line[line.startIndex..<tab])
    let text = String(line[line.index(after: tab)...])
    tokenizer.string = text
    let ranges = tokenizer.tokens(for: text.startIndex..<text.endIndex)
    let tokens = ranges.map { String(text[$0]) }
    print("\(identifier)\t\(tokens.joined(separator: " "))")
}
