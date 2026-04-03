import Foundation

// MARK: - ChatContentBlock

/// Parsed content block from a companion chat message.
/// Messages can contain plain text interspersed with rich inline elements.
public enum ChatContentBlock: Sendable, Equatable, Identifiable {
    case text(String)
    case kanji(character: String)
    case mnemonic(character: String, hint: String)
    case quiz(character: String, correctAnswer: String, options: [String])

    public var id: String {
        switch self {
        case .text(let value):
            return "text-\(value.hashValue)"
        case .kanji(let character):
            return "kanji-\(character)"
        case .mnemonic(let character, _):
            return "mnemonic-\(character)"
        case .quiz(let character, _, _):
            return "quiz-\(character)"
        }
    }
}

// MARK: - ChatContentParser

/// Parses raw message content into structured content blocks.
/// Supports tags: [KANJI:食], [MNEMONIC:食|hint], [QUIZ:食|correct|opt2|opt3]
public enum ChatContentParser {

    /// Parse a raw content string into an array of content blocks.
    public static func parse(_ rawContent: String) -> [ChatContentBlock] {
        var blocks: [ChatContentBlock] = []
        var remaining = rawContent[rawContent.startIndex...]

        while !remaining.isEmpty {
            guard let openBracket = remaining.firstIndex(of: "[") else {
                let text = String(remaining)
                if !text.isEmpty {
                    blocks.append(.text(text))
                }
                break
            }

            // Add any text before the tag
            let prefix = remaining[remaining.startIndex..<openBracket]
            if !prefix.isEmpty {
                blocks.append(.text(String(prefix)))
            }

            guard let closeBracket = remaining[openBracket...].firstIndex(of: "]") else {
                // Malformed tag — treat rest as text
                blocks.append(.text(String(remaining[openBracket...])))
                break
            }

            let tagContent = String(remaining[remaining.index(after: openBracket)..<closeBracket])
            if let block = parseTag(tagContent) {
                blocks.append(block)
            } else {
                // Unknown tag — keep as text
                blocks.append(.text("[\(tagContent)]"))
            }

            remaining = remaining[remaining.index(after: closeBracket)...]
        }

        return blocks
    }

    // MARK: - Private

    private static func parseTag(_ tag: String) -> ChatContentBlock? {
        let parts = tag.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        let type = parts[0].trimmingCharacters(in: .whitespaces)
        let payload = parts[1].trimmingCharacters(in: .whitespaces)

        switch type.uppercased() {
        case "KANJI":
            return .kanji(character: payload)

        case "MNEMONIC":
            let segments = payload.split(separator: "|", maxSplits: 1)
            guard segments.count == 2 else { return nil }
            let character = segments[0].trimmingCharacters(in: .whitespaces)
            let hint = segments[1].trimmingCharacters(in: .whitespaces)
            return .mnemonic(character: character, hint: hint)

        case "QUIZ":
            let segments = payload.split(separator: "|")
            guard segments.count >= 3 else { return nil }
            let character = segments[0].trimmingCharacters(in: .whitespaces)
            let correctAnswer = segments[1].trimmingCharacters(in: .whitespaces)
            let options = segments.dropFirst(1).map { $0.trimmingCharacters(in: .whitespaces) }
            return .quiz(character: character, correctAnswer: correctAnswer, options: options)

        default:
            return nil
        }
    }
}
