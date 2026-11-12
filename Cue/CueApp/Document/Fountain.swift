import Foundation
import CueKit

/// Fountain import and export.
///
/// Cue's model is a flat list of typed paragraphs. Fountain is a flat list of
/// blank-line separated blocks, so the importer reads one block at a time and
/// turns it into the elements the editor understands. Notes, sections,
/// synopses and boneyards are deliberately discarded: they have no place in
/// the Cue document model and would otherwise leak into an export.
enum Fountain {

    // MARK: - Parsing

    static func parse(_ text: String) -> Script {
        let normalised = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let source = normalised.hasPrefix("\u{FEFF}")
            ? String(normalised.dropFirst())
            : normalised

        let titlePage = parseTitlePage(source)
        let body = stripIgnored(titlePage.body)
        let elements = parseBody(body)
        let parsedTitle = titlePage.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        if let parsedTitle, !parsedTitle.isEmpty {
            title = parsedTitle
        } else {
            title = "Untitled"
        }
        return Script(title: title, elements: elements)
    }

    /// Known Fountain title-page keys. A body line such as `TIME: NIGHT` must
    /// not be mistaken for a title page just because it contains a colon.
    private static let titleKeys: Set<String> = [
        "title", "credit", "author", "authors", "source", "notes",
        "draft date", "date", "contact", "copyright", "revision",
        "header", "footer"
    ]

    private static func parseTitlePage(_ text: String) -> (title: String?, body: String) {
        let lines = text.components(separatedBy: "\n")
        var start = 0
        while start < lines.count && lines[start].trimmingCharacters(in: .whitespaces).isEmpty {
            start += 1
        }
        guard start < lines.count,
              let firstKey = keyValue(lines[start]),
              titleKeys.contains(firstKey.key.lowercased()) else {
            return (nil, text)
        }

        var fields: [String: String] = [:]
        var currentKey: String?
        var index = start

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                break
            }

            if let pair = keyValue(line), titleKeys.contains(pair.key.lowercased()) {
                let key = pair.key.lowercased()
                fields[key] = pair.value
                currentKey = key
            } else if line.first?.isWhitespace == true, let key = currentKey {
                // Indented continuation, used by `Contact:` and similar blocks.
                let value = trimmed
                let existing = fields[key] ?? ""
                fields[key] = existing.isEmpty ? value : existing + "\n" + value
            } else {
                // A title page ends at the first non-key, non-indented line even
                // when the writer forgot the blank separator.
                break
            }
            index += 1
        }

        while index < lines.count && lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            index += 1
        }

        let title = fields["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = lines[index...].joined(separator: "\n")
        return (title, body)
    }

    /// Splits `Title: HARROW LIGHT` without being fooled by a colon in the value.
    private static func keyValue(_ line: String) -> (key: String, value: String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        let value = String(line[line.index(after: colon)...])
            .trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    private static func stripIgnored(_ text: String) -> String {
        var result = text
        // Boneyard comments.
        result = result.replacingOccurrences(
            of: #"(?s)/\*.*?\*/"#,
            with: " ",
            options: .regularExpression
        )
        // Inline and block notes.
        result = result.replacingOccurrences(
            of: #"(?s)\[\[.*?\]\]"#,
            with: " ",
            options: .regularExpression
        )
        return result
    }

    private static func isIgnoredLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return true }
        if first == "#" || first == "=" { return true }
        if trimmed.allSatisfy({ $0 == "=" }) { return true }
        return false
    }

    private static func parseBody(_ text: String) -> [Element] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [[String]] = []
        var current: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || isIgnoredLine(line) {
                if !current.isEmpty {
                    blocks.append(current)
                    current.removeAll(keepingCapacity: true)
                }
            } else {
                current.append(trimmed)
            }
        }
        if !current.isEmpty { blocks.append(current) }

        return blocks.flatMap(parseBlock)
    }

    private static func parseBlock(_ rawLines: [String]) -> [Element] {
        let lines = rawLines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return [] }

        var type = classify(first)
        if type == .action, lines.count > 1, isCharacter(first) {
            type = .character
        }

        switch type {
        case .scene:
            let scene = stripSceneNumber(stripSceneMarker(first)).uppercased()
            var result = [Element(type: .scene, text: scene)]
            if lines.count > 1 {
                let rest = lines.dropFirst()
                    .map(stripEscape)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty {
                    result.append(Element(type: .action, text: rest))
                }
            }
            return result

        case .transition:
            return [Element(type: .transition, text: stripTransitionMarker(first).uppercased())]

        case .character:
            return parseSpeech(lines)

        case .paren:
            var result = [Element(type: .paren, text: stripEscape(first))]
            let rest = lines.dropFirst()
                .map(stripEscape)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty {
                result.append(Element(type: .dialogue, text: rest))
            }
            return result

        default:
            let action = lines.enumerated()
                .map { index, line in
                    index == 0 ? stripActionLine(line) : stripEscape(line)
                }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            return action.isEmpty ? [] : [Element(type: .action, text: action)]
        }
    }

    private static func parseSpeech(_ lines: [String]) -> [Element] {
        guard let first = lines.first else { return [] }
        var result = [Element(type: .character, text: stripCharacterMarker(first).uppercased())]
        var dialogue: [String] = []

        func flushDialogue() {
            guard !dialogue.isEmpty else { return }
            let text = dialogue.joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                result.append(Element(type: .dialogue, text: text))
            }
            dialogue.removeAll(keepingCapacity: true)
        }

        for raw in lines.dropFirst() {
            let escaped = raw.hasPrefix("\\")
            let line = stripEscape(raw)
            if !escaped && isParenthetical(line) {
                flushDialogue()
                result.append(Element(type: .paren, text: line))
            } else {
                dialogue.append(line)
            }
        }
        flushDialogue()
        return result
    }

    /// Classifies one line without applying the "all caps above dialogue"
    /// character heuristic, which needs to see the whole block.
    private static func classify(_ raw: String) -> ElementType? {
        let text = raw.trimmingCharacters(in: .whitespaces)

        if text.hasPrefix("\\"), text.count > 1 {
            let next = text[text.index(after: text.startIndex)]
            if "@>#=!.~\\(".contains(next) {
                return .action
            }
        }
        if text.hasPrefix("@") {
            return .character
        }
        if text.hasPrefix(">") {
            return text.hasSuffix("<") && text.count > 2 ? .action : .transition
        }
        if text.hasPrefix("!") || text.hasPrefix("~") {
            return .action
        }
        if text.hasPrefix(".") {
            return .scene
        }
        if text.hasPrefix("#") || text.hasPrefix("=") {
            return nil
        }
        if isSceneHeading(text) {
            return .scene
        }
        if isTransition(text) {
            return .transition
        }
        if isParenthetical(text) {
            return .paren
        }
        return .action
    }

    private static func isSceneHeading(_ text: String) -> Bool {
        text.range(
            of: #"^(INT|EXT|EST|INT\.?/EXT|I/E)[\.\s]"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func isTransition(_ text: String) -> Bool {
        guard Formatter.isUpper(text) else { return false }
        return text.range(
            of: #"(TO:|FADE OUT\.|FADE TO BLACK\.|FADE IN:)$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isParenthetical(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("(") && trimmed.hasSuffix(")")
    }

    private static func isCharacter(_ text: String) -> Bool {
        let name = text
            .replacingOccurrences(of: #"\(.*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
              !name.hasPrefix("@"),
              !name.hasPrefix(">"),
              !name.hasPrefix("."),
              !isSceneHeading(name),
              !isTransition(name),
              !isParenthetical(name) else {
            return false
        }
        return Formatter.isUpper(name)
    }

    private static func stripEscape(_ line: String) -> String {
        guard line.hasPrefix("\\"), line.count > 1 else { return line }
        let next = line[line.index(after: line.startIndex)]
        guard "@>#=!.~\\(".contains(next) else { return line }
        return String(line.dropFirst())
    }

    private static func stripSceneMarker(_ text: String) -> String {
        if text.hasPrefix(".") {
            return String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return stripEscape(text)
    }

    private static func stripCharacterMarker(_ text: String) -> String {
        if text.hasPrefix("@") {
            return String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return stripEscape(text)
    }

    private static func stripTransitionMarker(_ text: String) -> String {
        guard text.hasPrefix(">") else { return stripEscape(text) }
        var result = String(text.dropFirst())
        if result.hasSuffix("<") {
            result = String(result.dropLast())
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func stripActionLine(_ text: String) -> String {
        if text.hasPrefix("\\") {
            return stripEscape(text)
        }
        if text.hasPrefix(">"), text.hasSuffix("<"), text.count > 2 {
            return String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        if text.hasPrefix("!") || text.hasPrefix("~") {
            return String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    private static func stripSceneNumber(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\s*#[^#]*#\s*$"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Serialising

    static func serialise(_ script: Script) -> String {
        serialise(script, title: script.title)
    }

    static func serialise(_ script: Script, title: String) -> String {
        var lines: [String] = []
        let cleanTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if !cleanTitle.isEmpty {
            lines.append("Title: \(cleanTitle)")
            lines.append("")
        }

        var previous: ElementType?

        for element in script.elements {
            let text = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let type: ElementType
            if element.type == .new {
                type = Formatter.inferType(text)
            } else {
                type = element.type
            }

            let continuesSpeech = type == .paren || type == .dialogue
            let previousContinues = previous == .character || previous == .paren || previous == .dialogue
            if continuesSpeech && previousContinues {
                // No blank line inside a speech.
            } else {
                appendBlankLine(to: &lines)
            }

            switch type {
            case .scene:
                var line = text
                if !isSceneHeading(line) {
                    line = "." + line
                }
                lines.append(line)

            case .character:
                var line = text
                if !Formatter.isUpper(line) || "@>#=!.~\\".contains(line.first!) {
                    line = "@" + line
                }
                lines.append(line)

            case .transition:
                var line = text
                if !isTransition(line) {
                    line = ">" + line
                }
                lines.append(line)

            case .paren:
                if text.hasPrefix("(") && text.hasSuffix(")") {
                    lines.append(text)
                } else {
                    lines.append("(" + text + ")")
                }

            case .dialogue:
                lines.append(escapeDialogue(text))

            case .action, .new:
                lines.append(escapeAction(text))
            }

            previous = type
        }

        while lines.last?.isEmpty == true { lines.removeLast() }
        guard !lines.isEmpty else { return "" }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func appendBlankLine(to lines: inout [String]) {
        guard !lines.isEmpty else { return }
        if lines.last?.isEmpty != true { lines.append("") }
    }

    private static func escapeAction(_ text: String) -> String {
        guard let first = text.first else { return text }
        if "@>#=!.~\\".contains(first) {
            return "\\" + text
        }
        if isSceneHeading(text) || isTransition(text) || isCharacter(text) || isParenthetical(text) {
            // `!` is Fountain's forced-action marker.
            return "!" + text
        }
        return text
    }

    private static func escapeDialogue(_ text: String) -> String {
        guard let first = text.first else { return text }
        if "@>#=!.~\\".contains(first) {
            return "\\" + text
        }
        if isParenthetical(text) {
            return "\\" + text
        }
        return text
    }
}
