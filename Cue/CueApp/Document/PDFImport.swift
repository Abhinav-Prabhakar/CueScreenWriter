import AppKit
import PDFKit
import CueKit

enum PDFImportError: LocalizedError {
    case unreadable
    case empty
    case encrypted

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "Cue couldn’t open that PDF."
        case .empty:
            "Cue couldn’t find any script text in that PDF. If it is a scan, export a text PDF from the writing app instead."
        case .encrypted:
            "That PDF is password-protected. Remove the password and try again."
        }
    }
}

/// Rebuilds a script from a screenplay PDF.
///
/// This is deliberately a layout reader, not an OCR reader: it uses each line's
/// horizontal position to recover the screenplay's indents, and its vertical
/// gaps to recover paragraph boundaries. It handles the standard Cue, Final
/// Draft and Fountain PDF geometry; unusual templates can still be fixed by
/// hand after import.
enum PDFImporter {
    private struct Line {
        var text: String
        var x: CGFloat
        var y: CGFloat
        var height: CGFloat
        var page: Int
    }

    static func parse(url: URL) throws -> Script {
        guard let document = PDFDocument(url: url) else { throw PDFImportError.unreadable }
        if document.isLocked { throw PDFImportError.encrypted }

        var pages: [[Line]] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            pages.append(pageLines(on: page, page: pageIndex))
        }

        // A screenplay PDF often opens with a title page. It has no scene
        // headings and only a handful of lines, so it would otherwise arrive as
        // a stray action block at the top of the imported script.
        if pages.count > 1,
           let first = pages.first,
           first.count <= 14,
           !first.contains(where: { isSceneHeading($0.text) }) {
            pages.removeFirst()
        }

        var allLines = pages.flatMap { $0 }
        guard !allLines.isEmpty else { throw PDFImportError.empty }

        // Drop page numbers and repeated running heads: a line with no letters,
        // or a bare number at the very top/bottom of a page.
        allLines.removeAll { line in
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return true }
            let digits = trimmed.filter(\.isNumber)
            if digits.count == trimmed.count, trimmed.count <= 4 { return true }
            if trimmed.range(of: #"^\d+\s*\.?$"#, options: .regularExpression) != nil { return true }
            return false
        }

        guard !allLines.isEmpty else { throw PDFImportError.empty }

        let width = allLines.map { $0.x + estimatedWidth(of: $0.text) }.max() ?? 612
        let pageWidth = max(468, width)
        let elements = elements(from: allLines, pageWidth: pageWidth)
        guard !elements.isEmpty else { throw PDFImportError.empty }

        let metadataTitle = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        let title = (metadataTitle?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? url.deletingPathExtension().lastPathComponent

        return Script(title: title, elements: elements)
    }

    private static func pageLines(on page: PDFPage, page pageIndex: Int) -> [Line] {
        guard let pageString = page.string else { return [] }
        let source = pageString as NSString
        var result: [Line] = []

        var location = 0
        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let raw = source.substring(with: lineRange)
            let text = raw.trimmingCharacters(in: .newlines)
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                let offset = text.range(of: trimmed).map { text.distance(from: text.startIndex, to: $0.lowerBound) } ?? 0
                let range = NSRange(location: lineRange.location + offset,
                                    length: (trimmed as NSString).length)
                if let selection = page.selection(for: range) {
                    let bounds = selection.bounds(for: page)
                    if bounds.width > 0 {
                        result.append(Line(text: trimmed,
                                           x: bounds.minX,
                                           y: bounds.minY,
                                           height: max(bounds.height, 1),
                                           page: pageIndex))
                    }
                }
            }
            location = NSMaxRange(lineRange)
        }
        return result
    }

    private static func estimatedWidth(of text: String) -> CGFloat {
        CGFloat(text.count) * 6.0
    }

    // MARK: - Classification

    private static func elements(from lines: [Line], pageWidth: CGFloat) -> [Element] {
        var elements: [Element] = []
        var current: Element?
        var lastLine: Line?

        func flush() {
            if let current, !current.text.trimmingCharacters(in: .whitespaces).isEmpty {
                elements.append(current)
            }
            current = nil
        }

        func append(_ text: String, type: ElementType) {
            if var existing = current, existing.type == type,
               type != .character, type != .scene, type != .transition {
                existing.text += " " + text
                current = existing
            } else {
                flush()
                current = Element(type: type, text: text)
            }
        }

        for line in lines {
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let gap = lastLine.map { $0.y - line.y } ?? 0
            let wrapped = gap >= 0 && gap < max(line.height, lastLine?.height ?? line.height) * 1.25
            let indent = line.x / max(pageWidth, 1)

            let type: ElementType
            if isSceneHeading(trimmed), indent < 0.24 {
                type = .scene
            } else if isTransition(trimmed) {
                type = .transition
            } else if indent >= 0.39, Formatter.isUpper(trimmed), trimmed.count < 48 {
                type = .character
            } else if indent >= 0.33, trimmed.hasPrefix("("), trimmed.hasSuffix(")") {
                type = .paren
            } else if indent >= 0.24 {
                type = .dialogue
            } else {
                type = .action
            }

            let continuesPrevious = wrapped
                && current != nil
                && (type == .action || type == .dialogue || type == .paren)
                && (current?.type == type || (current?.type == .character && type == .dialogue))

            if continuesPrevious {
                if current?.type == .character, type == .dialogue {
                    flush()
                    current = Element(type: .dialogue, text: trimmed)
                } else if let existing = current {
                    current?.text = existing.text + " " + trimmed
                }
            } else if type == .character {
                flush()
                current = Element(type: .character, text: trimmed)
            } else if type == .scene {
                flush()
                current = Element(type: .scene, text: trimmed.uppercased())
            } else if type == .transition {
                flush()
                current = Element(type: .transition, text: trimmed.uppercased())
            } else {
                append(trimmed, type: type)
            }

            lastLine = line
        }
        flush()

        // A scene heading in a PDF should never carry a trailing page number.
        return elements.map { element in
            var copy = element
            if element.type == .scene {
                copy.text = element.text
                    .replacingOccurrences(of: #"\s+\d+\.?$"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            return copy
        }
    }

    private static func isSceneHeading(_ text: String) -> Bool {
        text.range(of: #"^(INT|EXT|EST|INT\.?/EXT|I/E)[\.\s]"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isTransition(_ text: String) -> Bool {
        guard Formatter.isUpper(text) else { return false }
        return text.range(of: #"(TO:|FADE OUT\.|FADE TO BLACK\.|FADE IN:)$"#,
                          options: .regularExpression) != nil
    }
}
