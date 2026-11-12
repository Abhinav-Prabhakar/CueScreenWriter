import XCTest
import PDFKit
import AppKit
@testable import Cue
import CueKit

final class FountainTests: XCTestCase {
    private let source = """
    Title: Harrow Light
    Credit: written by
    Author: A. Writer
    Draft date: 3 Nov 2026

    INT. MARIGOLD - WHEELHOUSE - NIGHT

    Elias leans over the chart.

    ELIAS
    Who else would be daft enough?

    INGRID (V.O.)
    (on the radio)
    I had you down for home by six.

    CUT TO:

    EXT. MARIGOLD - DECK - NIGHT

    Something bumps the hull.
    """

    func testParseReadsTitlePageAndElements() {
        let script = Fountain.parse(source)
        XCTAssertEqual(script.title, "Harrow Light")
        XCTAssertEqual(script.elements.map(\.type), [
            .scene, .action, .character, .dialogue,
            .character, .paren, .dialogue, .transition,
            .scene, .action
        ])
        XCTAssertEqual(script.elements[2].text, "ELIAS")
        XCTAssertEqual(script.elements[3].text, "Who else would be daft enough?")
        XCTAssertEqual(script.elements[4].text, "INGRID (V.O.)")
        XCTAssertEqual(script.elements[5].text, "(on the radio)")
        XCTAssertEqual(script.elements[8].text, "EXT. MARIGOLD - DECK - NIGHT")
    }

    func testSerialiseThenParsePreservesTheScreenplay() {
        let original = Fountain.parse(source)
        let exported = Fountain.serialise(original, title: "Harrow Light")
        let reimported = Fountain.parse(exported)

        XCTAssertEqual(reimported.title, original.title)
        XCTAssertEqual(reimported.elements.map(\.type), original.elements.map(\.type))
        XCTAssertEqual(reimported.elements.map(\.text), original.elements.map(\.text))
    }

    func testSerialiseWritesATitlePage() {
        let script = Script(title: "One Good Line", elements: [
            Element(type: .scene, text: "INT. APARTMENT - NIGHT"),
            Element(type: .action, text: "Rain on the window.")
        ])
        let text = Fountain.serialise(script, title: "One Good Line")
        XCTAssertTrue(text.contains("Title: One Good Line"))
        XCTAssertTrue(text.contains("INT. APARTMENT - NIGHT"))
        XCTAssertTrue(text.hasSuffix("\n"))
    }

    func testSectionsNotesAndBoneyardsAreDiscarded() {
        let text = """
        # Act One
        = A synopsis
        /* a boneyard line */
        INT. ROOM - DAY

        [[a note]]
        Action.
        """
        let script = Fountain.parse(text)
        XCTAssertEqual(script.elements.count, 2)
        XCTAssertEqual(script.elements[0].type, .scene)
        XCTAssertEqual(script.elements[1].text, "Action.")
    }
}

final class LibraryStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSaveAndLoadRoundTrip() {
        let store = LibraryStore(root: root)
        var document = CueDocument(title: "Harrow Light",
                                   script: Script(title: "Harrow Light", elements: [
                                       Element(type: .scene, text: "INT. ROOM - NIGHT"),
                                       Element(type: .character, text: "ELIAS"),
                                       Element(type: .dialogue, text: "Hello.")
                                   ]))
        document.notes = [CueNote(quote: "Hello.", body: "Try it quieter.",
                                  paragraph: 2, scene: 1, tint: 2)]
        document.stickies = [CueSticky(text: "A thought", x: 0.2, y: 0.3)]
        document.pins = [CuePin(artwork: .dusk, x: 0.1, y: 0.2, width: 0.1, height: 0.16)]
        document.titlePage.author = "A. Writer"
        store.save([document])

        let loaded = try! XCTUnwrap(store.load())
        XCTAssertEqual(loaded.count, 1)
        let restored = try! XCTUnwrap(loaded.first)
        XCTAssertEqual(restored.id, document.id)
        XCTAssertEqual(restored.title, document.title)
        XCTAssertEqual(restored.script, document.script)
        XCTAssertEqual(restored.notes.map(\.quote), document.notes.map(\.quote))
        XCTAssertEqual(restored.notes.map(\.body), document.notes.map(\.body))
        XCTAssertEqual(restored.notes.map(\.paragraph), document.notes.map(\.paragraph))
        XCTAssertEqual(restored.notes.map(\.tint), document.notes.map(\.tint))
        XCTAssertEqual(restored.stickies, document.stickies)
        XCTAssertEqual(restored.pins, document.pins)
        XCTAssertEqual(restored.titlePage, document.titlePage)
        // ISO 8601 keeps milliseconds, which is all a modified date needs.
        XCTAssertEqual(restored.modified.timeIntervalSince1970,
                       document.modified.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(restored.notes.first?.body, "Try it quieter.")
        XCTAssertEqual(restored.titlePage.author, "A. Writer")
    }

    func testMissingManifestReturnsNil() {
        let store = LibraryStore(root: root)
        XCTAssertNil(store.load())
    }

    func testCorruptManifestIsQuarantinedNotDeleted() throws {
        let store = LibraryStore(root: root)
        let manifest = root.appendingPathComponent("library.json")
        try Data("not json".utf8).write(to: manifest)

        XCTAssertNil(store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: manifest.path))
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("library-corrupt-") },
                      "Expected a quarantined copy, found \(files)")
    }

    func testAttachmentWriteReadCopyAndRemove() {
        let store = LibraryStore(root: root)
        let document = UUID()
        // A real 1×1 PNG, so NSImage can decode the copied attachment.
        let data = try! XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lY1JqQAAAABJRU5ErkJggg=="))
        XCTAssertTrue(store.writeAttachment(data, document: document, filename: "one.png"))
        XCTAssertEqual(try? Data(contentsOf: store.attachmentURL(document: document,
                                                                 filename: "one.png")),
                       data)

        let copy = UUID()
        let copied = store.copyAttachment(document: document, filename: "one.png", to: copy)
        let copyName = try! XCTUnwrap(copied)
        XCTAssertNotEqual(copyName, "one.png")
        XCTAssertNotNil(store.image(document: copy, filename: copyName))

        store.removeAttachment(document: document, filename: "one.png")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: store.attachmentURL(document: document, filename: "one.png").path))

        store.removeAttachments(document: copy)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: store.attachmentDirectory(document: copy).path))
    }
}

final class DocumentCodableTests: XCTestCase {
    func testDocumentEncodesEveryDeskObject() throws {
        var document = CueDocument(title: "Harrow Light",
                                   script: Script(title: "Harrow Light", elements: [
                                       Element(type: .scene, text: "EXT. SEA - NIGHT")
                                   ]))
        document.shelfTitle = "HARROW LIGHT"
        document.declaredPages = 19
        document.declaredScenes = 25
        document.sceneNumberOffset = 2
        document.pageNumberOffset = 1
        document.declaredCharacterLines = ["ELIAS": 57]
        document.notes = [CueNote(quote: "Q", body: "B", paragraph: 4, scene: 2, tint: 3)]
        document.stickies = [CueSticky(text: "S", tint: 2, x: 0.4, y: 0.6, width: 0.15, strike: true)]
        document.pins = [CuePin(artwork: .image("one.png"), x: 0.1, y: 0.2,
                                width: 0.3, height: 0.4, rotation: 1.5)]
        document.titlePage = CueTitlePage(credit: "written by", author: "Ada",
                                          contact: "Ada\nada@example.com",
                                          draftDate: "Draft date: today",
                                          graphic: "title.png")

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(CueDocument.self, from: data)
        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.displayTitle, "HARROW LIGHT")
        XCTAssertEqual(decoded.sceneCount, 25)
        XCTAssertEqual(decoded.pageCount, 19)
    }

    func testStickyDerivesLinesAndFootnote() {
        let sticky = CueSticky(text: "First line\nSecond line\n\nA footnote")
        XCTAssertEqual(sticky.lines, ["First line", "Second line"])
        XCTAssertEqual(sticky.footnote, "A footnote")
        XCTAssertNil(CueSticky(text: "Just one line").footnote)
    }

    func testSceneAndCharacterTotalsFallBackToTheScript() {
        let document = CueDocument(title: "Test", script: Script(title: "Test", elements: [
            Element(type: .scene, text: "INT. ROOM - DAY"),
            Element(type: .scene, text: "EXT. STREET - DAY")
        ]))
        XCTAssertEqual(document.sceneCount, 2)
        XCTAssertEqual(document.pageCount, 1)
    }
}

@MainActor
final class PDFTests: XCTestCase {
    private let script = Script(title: "Harrow Light", elements: [
        Element(type: .scene, text: "INT. MARIGOLD - WHEELHOUSE - NIGHT"),
        Element(type: .action, text: "Elias leans over the chart. The lamp swings."),
        Element(type: .character, text: "ELIAS"),
        Element(type: .dialogue, text: "Who else would be daft enough?"),
        Element(type: .character, text: "INGRID (V.O.)"),
        Element(type: .paren, text: "(on the radio)"),
        Element(type: .dialogue, text: "I had you down for home by six."),
        Element(type: .transition, text: "CUT TO:")
    ])

    override func setUp() {
        Fonts.register()
    }

    func testExportProducesAReadablePDFWithATitlePage() throws {
        var page = CueTitlePage()
        page.author = "Ada Lovelace"
        let data = try PDFExport.data(for: script, title: "Harrow Light", titlePage: page)
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(document.pageCount, PDFExport.pageCount(for: script) + 1)
        let firstPage = try XCTUnwrap(document.page(at: 0)?.string)
        XCTAssertTrue(firstPage.contains("HARROW LIGHT"))
        XCTAssertTrue(firstPage.contains("ADA LOVELACE"))

        let body = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        XCTAssertTrue(body.contains("INT. MARIGOLD - WHEELHOUSE - NIGHT"))
        XCTAssertTrue(body.contains("Who else would be daft enough?"))
    }

    func testPageCountGrowsWithTheScript() {
        XCTAssertEqual(PDFExport.pageCount(for: script), 1)
        let long = Script(title: "Long", elements: (0..<200).map {
            Element(type: .action, text: "Action line \($0).")
        })
        XCTAssertGreaterThan(PDFExport.pageCount(for: long), 1)
    }

    func testPDFImportRecoversSceneCharacterAndDialogue() throws {
        let exporter = CueTitlePage()
        let data = try PDFExport.data(for: script, title: "Harrow Light", titlePage: exporter)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-import-\(UUID().uuidString).pdf")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let imported = try PDFImporter.parse(url: url)
        // The title page is not part of the script body.
        XCTAssertFalse(imported.elements.contains {
            $0.text.contains("written by") || $0.text.contains("ADA LOVELACE")
        })
        XCTAssertTrue(imported.elements.contains {
            $0.type == .scene && $0.text.contains("MARIGOLD")
        })
        XCTAssertTrue(imported.elements.contains {
            $0.type == .character && $0.text.contains("ELIAS")
        })
        XCTAssertTrue(imported.elements.contains {
            $0.type == .dialogue && $0.text.contains("daft enough")
        })
    }

    func testPDFImportRejectsANonPDF() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-bad-\(UUID().uuidString).pdf")
        try? Data("not a pdf".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try PDFImporter.parse(url: url))
    }
}
