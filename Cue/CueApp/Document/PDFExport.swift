import AppKit
import PDFKit
import CueKit

enum PDFExportError: LocalizedError {
    case contextUnavailable
    case documentUnavailable
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .contextUnavailable:
            "The PDF could not be created."
        case .documentUnavailable:
            "The PDF could not be read back for export."
        case .writeFailed:
            "The PDF could not be written to the chosen location."
        }
    }
}

/// The print renderer. It deliberately shares the editor's paragraph geometry
/// but fixes the type at 12 pt and uses white paper, so an export is the same
/// in Daylight, Evening and Night.
@MainActor
enum PDFExport {
    static let pageWidth: CGFloat = 612
    static let pageHeight: CGFloat = 792
    static let scriptSize: CGFloat = 12
    static let topPadding: CGFloat = pageWidth / 8.5 * 0.9
    static let bottomPadding: CGFloat = pageWidth / 8.5
    static let contentHeight: CGFloat = pageHeight - topPadding - bottomPadding

    private static let ink = NSColor(hex: Hex.ink)
    private static let ink2 = NSColor(hex: Hex.ink2)
    private static let paper = NSColor.white

    // MARK: - Public API

    static func write(script: Script,
                      title: String,
                      titlePage: CueTitlePage = CueTitlePage(),
                      graphic: NSImage? = nil,
                      to url: URL) throws {
        let data = try data(for: script, title: title, titlePage: titlePage, graphic: graphic)
        guard let document = PDFDocument(data: data) else {
            throw PDFExportError.documentUnavailable
        }
        document.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: title,
            PDFDocumentAttribute.subjectAttribute: "Screenplay",
            PDFDocumentAttribute.creatorAttribute: "Cue",
            PDFDocumentAttribute.producerAttribute: "Cue"
        ]
        guard document.write(to: url) else {
            throw PDFExportError.writeFailed
        }
    }

    static func data(for script: Script,
                     title: String,
                     titlePage: CueTitlePage = CueTitlePage(),
                     graphic: NSImage? = nil) throws -> Data {
        let layout = makeLayout(elements: script.elements)
        let marks = script.sceneNumbers ? sceneMarks(for: script.elements, layout: layout) : []
        let data = NSMutableData()

        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw PDFExportError.contextUnavailable
        }

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: title,
            kCGPDFContextSubject: "Screenplay",
            kCGPDFContextCreator: "Cue"
        ]
        guard let context = CGContext(consumer: consumer,
                                      mediaBox: &mediaBox,
                                      info as CFDictionary) else {
            throw PDFExportError.contextUnavailable
        }

        if hasTitlePage(title) {
            drawTitlePage(title: title, page: titlePage, graphic: graphic, in: context)
        }

        for (index, container) in layout.containers.enumerated() {
            context.beginPDFPage(nil)
            fillPaper(in: context)

            withFlippedPage(in: context) {
                layout.manager.ensureLayout(for: container)
                let glyphs = layout.manager.glyphRange(for: container)
                if glyphs.length > 0 {
                    layout.manager.drawGlyphs(forGlyphRange: glyphs,
                                              at: NSPoint(x: 0, y: topPadding))
                }

                for mark in marks where mark.page == index {
                    let text = mark.text as NSString
                    text.draw(at: NSPoint(x: mark.x, y: mark.y),
                              withAttributes: furnitureAttributes())
                }

                if index > 0 {
                    drawPageNumber(index + 1)
                }
            }

            context.endPDFPage()
        }

        context.closePDF()
        return data as Data
    }

    static func pageCount(for script: Script) -> Int {
        makeLayout(elements: script.elements).containers.count
    }

    // MARK: - Title page

    private static func hasTitlePage(_ title: String) -> Bool {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !clean.isEmpty && clean.lowercased() != "untitled"
    }

    private static func drawTitlePage(title: String,
                                      page: CueTitlePage,
                                      graphic: NSImage?,
                                      in context: CGContext) {
        context.beginPDFPage(nil)
        fillPaper(in: context)

        withFlippedPage(in: context) {
            let inch: CGFloat = 72
            let pageTop: CGFloat = 0

            if let graphic {
                let maxWidth = pageWidth * 0.62
                let maxHeight = inch * 1.55
                let ratio = graphic.size.width / max(graphic.size.height, 1)
                var width = maxWidth
                var height = width / ratio
                if height > maxHeight {
                    height = maxHeight
                    width = height * ratio
                }
                let rect = CGRect(x: (pageWidth - width) / 2,
                                  y: pageTop + inch * 2.15,
                                  width: width,
                                  height: height)
                graphic.draw(in: rect,
                             from: .zero,
                             operation: .sourceOver,
                             fraction: 1,
                             respectFlipped: true,
                             hints: nil)
            } else {
                drawCentred(title.uppercased(),
                            size: scriptSize,
                            bold: true,
                            y: inch * 3.5 - scriptSize * 0.75)
            }

            drawCentred(page.credit,
                        size: scriptSize * 0.9,
                        y: inch * 4.6 - scriptSize * 0.7)
            drawCentred(page.author.uppercased(),
                        size: scriptSize,
                        y: inch * 5.2 - scriptSize * 0.7)

            let block = NSMutableParagraphStyle()
            block.lineHeightMultiple = 1
            block.minimumLineHeight = scriptSize * 1.08
            block.maximumLineHeight = scriptSize * 1.08
            let attributes: [NSAttributedString.Key: Any] = [
                .font: Fonts.scriptNS(scriptSize * 0.95),
                .foregroundColor: ink,
                .paragraphStyle: block
            ]

            let contact = page.contact as NSString
            let contactSize = contact.size(withAttributes: attributes)
            contact.draw(at: NSPoint(x: inch,
                                     y: pageHeight - inch * 0.9 - contactSize.height),
                         withAttributes: attributes)

            let draftStyle = NSMutableParagraphStyle()
            draftStyle.alignment = .right
            draftStyle.minimumLineHeight = scriptSize
            draftStyle.maximumLineHeight = scriptSize
            let draftAttributes: [NSAttributedString.Key: Any] = [
                .font: Fonts.scriptNS(scriptSize * 0.95),
                .foregroundColor: ink,
                .paragraphStyle: draftStyle
            ]
            let draft = page.draftDate as NSString
            let draftSize = draft.size(withAttributes: draftAttributes)
            draft.draw(in: CGRect(x: pageWidth * 0.25,
                                  y: pageHeight - inch * 0.9 - draftSize.height,
                                  width: pageWidth * 0.66,
                                  height: draftSize.height),
                       withAttributes: draftAttributes)
        }

        context.endPDFPage()
    }

    private static func drawCentred(_ text: String,
                                    size: CGFloat,
                                    bold: Bool = false,
                                    y: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.minimumLineHeight = size
        paragraph.maximumLineHeight = size
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Fonts.scriptNS(size, bold: bold),
            .foregroundColor: ink,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(in: CGRect(x: pageWidth * 0.15,
                                           y: y,
                                           width: pageWidth * 0.7,
                                           height: size * 1.8),
                                withAttributes: attributes)
    }

    // MARK: - Text system

    private struct Layout {
        let storage: NSTextStorage
        let manager: NSLayoutManager
        let containers: [NSTextContainer]
        let ranges: [NSRange]
    }

    private static func makeLayout(elements: [Element]) -> Layout {
        let storage = NSTextStorage()
        var ranges: [NSRange] = []
        ranges.reserveCapacity(elements.count)

        for (index, element) in elements.enumerated() {
            let start = storage.length
            let attributes = attributes(for: element, index: index, elements: elements)
            storage.append(NSAttributedString(string: element.text, attributes: attributes))
            ranges.append(NSRange(location: start, length: (element.text as NSString).length))
            if index < elements.count - 1 {
                storage.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }

        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)

        var containers: [NSTextContainer] = []
        while true {
            let container = makeContainer()
            manager.addTextContainer(container)
            manager.ensureLayout(for: container)
            let glyphs = manager.glyphRange(for: container)
            if glyphs.length == 0 {
                manager.removeTextContainer(at: manager.textContainers.count - 1)
                break
            }
            containers.append(container)
            if NSMaxRange(glyphs) >= manager.numberOfGlyphs { break }
        }

        if containers.isEmpty {
            let container = makeContainer()
            manager.addTextContainer(container)
            containers.append(container)
        }

        return Layout(storage: storage, manager: manager, containers: containers, ranges: ranges)
    }

    private static func makeContainer() -> NSTextContainer {
        let container = NSTextContainer(size: CGSize(width: pageWidth, height: contentHeight))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        container.lineBreakMode = .byWordWrapping
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        return container
    }

    private static func attributes(for element: Element,
                                   index: Int,
                                   elements: [Element]) -> [NSAttributedString.Key: Any] {
        let type: ElementType
        if element.type == .new {
            type = element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .action
                : Formatter.inferType(element.text)
        } else {
            type = element.type
        }

        let spacing: CGFloat
        if index > 0, type != .paren, type != .dialogue {
            let previous = elements[index - 1].text
            spacing = previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : scriptSize
        } else {
            spacing = 0
        }

        let paragraph = ScreenplayTypography.paragraphStyle(
            for: type,
            width: pageWidth,
            line: scriptSize,
            spacingBefore: spacing
        )
        return [
            .font: ScreenplayTypography.font(for: type, size: scriptSize),
            .foregroundColor: ink,
            .paragraphStyle: paragraph
        ]
    }

    // MARK: - Margin furniture

    private struct SceneMark {
        let page: Int
        let text: String
        let x: CGFloat
        let y: CGFloat
    }

    private static func sceneMarks(for elements: [Element], layout: Layout) -> [SceneMark] {
        guard layout.manager.numberOfGlyphs > 0 else { return [] }
        for container in layout.containers {
            layout.manager.ensureLayout(for: container)
        }

        let sceneFont = ScreenplayTypography.font(for: .scene, size: scriptSize)
        let numberFont = Fonts.scriptNS(scriptSize * 0.85)
        let baseline = max(0, sceneFont.ascender - numberFont.ascender)
        let length = (layout.storage.string as NSString).length

        var marks: [SceneMark] = []
        var number = 0

        for (index, element) in elements.enumerated() where element.type == .scene {
            number += 1
            guard index < layout.ranges.count, !element.text.isEmpty else { continue }

            let character = min(layout.ranges[index].location, max(0, length - 1))
            let glyph = layout.manager.glyphIndexForCharacter(at: character)
            guard let page = layout.containers.firstIndex(where: { container in
                let range = layout.manager.glyphRange(for: container)
                return glyph >= range.location && glyph < NSMaxRange(range)
            }) else { continue }

            let line = layout.manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            marks.append(SceneMark(
                page: page,
                text: "\(number)",
                x: pageWidth * 0.10,
                y: topPadding + line.minY + baseline
            ))
        }
        return marks
    }

    private static func furnitureAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: Fonts.scriptNS(scriptSize * 0.85),
            .foregroundColor: ink2
        ]
    }

    private static func drawPageNumber(_ number: Int) {
        let text = "\(number)." as NSString
        let attributes = furnitureAttributes()
        let size = text.size(withAttributes: attributes)
        let inch = pageWidth / 8.5
        text.draw(at: NSPoint(x: pageWidth * 0.90 - size.width, y: inch * 0.5),
                  withAttributes: attributes)
    }

    // MARK: - Drawing helpers

    private static func fillPaper(in context: CGContext) {
        context.setFillColor(paper.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
    }

    private static func withFlippedPage(in context: CGContext, _ body: () -> Void) {
        context.saveGState()
        context.translateBy(x: 0, y: pageHeight)
        context.scaleBy(x: 1, y: -1)

        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        body()
        NSGraphicsContext.restoreGraphicsState()

        context.restoreGState()
    }
}
