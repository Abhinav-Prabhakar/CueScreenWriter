import SwiftUI
import Observation
import AppKit
import CueKit
import UniformTypeIdentifiers

// MARK: - Document model

/// A note pinned to a line of the script.
struct CueNote: Identifiable, Codable, Equatable {
    var id = UUID()
    var quote: String
    var body: String
    /// Zero-based paragraph in the document at the time the note was made.
    var paragraph: Int
    var scene: Int
    var tint: Int
    var createdAt = Date()
}

/// A sticky on the desk, positioned in fractions of the desk so it survives a
/// window resize.
struct CueSticky: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var tint: Int = 0
    var x: Double = 0.16
    var y: Double = 0.57
    var width: Double = 0.153
    var strike: Bool = false

    var lines: [String] {
        let body = text.components(separatedBy: "\n\n").first ?? text
        return body.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    var footnote: String? {
        let parts = text.components(separatedBy: "\n\n")
        guard parts.count > 1 else { return nil }
        return parts.dropFirst().joined(separator: "\n\n")
    }
}

enum PinArtwork: Codable, Equatable {
    case dusk
    case fog
    case image(String)

    var filename: String? {
        if case .image(let name) = self { return name }
        return nil
    }
}

/// A photograph pinned to the desk.
struct CuePin: Identifiable, Codable, Equatable {
    var id = UUID()
    var artwork: PinArtwork
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double = 0
}

/// The editable title page. The title itself lives on the document.
struct CueTitlePage: Codable, Equatable {
    var credit = "written by"
    var author = "A. Writer"
    var contact = "Contact:\nA. Writer\nwriter@example.com\n+44 20 7946 0958"
    var draftDate = "Draft date: 3 Nov 2026"
    /// Optional logo/title graphic stored beside the document.
    var graphic: String? = nil
}

struct CueDocument: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var title: String
    /// Some scripts are titled in all caps on the shelf while the toolbar keeps
    /// the writer's title case.
    var shelfTitle: String? = nil
    var script: Script
    var cover: String? = nil
    var createdAt: Date = Date()
    var modified: Date = Date()
    /// The bundled sample scripts are excerpts, so they carry the real totals
    /// rather than their own line count. Imported and new scripts use live data.
    var declaredPages: Int? = nil
    var declaredScenes: Int? = nil
    var sceneNumberOffset: Int = 0
    var pageNumberOffset: Int = 0
    var declaredCharacterLines: [String: Int] = [:]
    var deskExtras: Bool = true
    var notes: [CueNote] = []
    var stickies: [CueSticky] = []
    var pins: [CuePin] = []
    var titlePage = CueTitlePage()

    var sceneCount: Int {
        declaredScenes ?? script.elements.filter { $0.type == .scene }.count
    }
    var pageCount: Int {
        declaredPages ?? max(1, Int(ceil(Double(script.elements.count) / 55.0)))
    }
    var wordCount: Int {
        script.elements.reduce(0) { total, element in
            total + element.text.split(whereSeparator: { $0.isWhitespace }).count
        }
    }
    var displayTitle: String { shelfTitle ?? title }
}

// MARK: - Transient UI data

struct NoteDraft: Identifiable, Equatable {
    var id = UUID()
    var editing: UUID?
    var quote: String
    var body: String = ""
    var paragraph: Int
    var scene: Int
    var tint: Int = 0
}

struct ScrollRequest: Identifiable, Equatable {
    var id = UUID()
    var paragraph: Int
}

// MARK: - App model

@MainActor
@Observable
final class AppModel {
    enum Route: Equatable { case library, writing }

    var route: Route = .writing
    var documents: [CueDocument] = []
    var currentID: UUID = UUID()
    var currentScript = Script(title: "Untitled", elements: [Element(type: .scene)])

    var sidebarVisible = true
    var sidebarTab: SidebarTab = .scenes
    var search = ""
    var position = EditorPosition()
    var saveState: SaveState = .saved
    var notesVisible = true
    var fullScreen = false

    /// The last selection reported by the editor, used by Add Note.
    var selectionText = ""
    var selectionLine = ""
    var selectionParagraph = 0
    var noteDraft: NoteDraft?
    var scrollRequest: ScrollRequest?
    var showHelp = false

    let lamp = LampController(persist: true)
    var lit: Bool {
        get { lamp.lit }
        set { lamp.setLit(newValue) }
    }

    var music = MusicState()
    let audio = AmbientPlayer()

    var theme: Theme { Theme.of(lamp.lamp) }

    private let store: LibraryStore
    private var saveTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?

    init(store: LibraryStore = .shared) {
        self.store = store
        lamp.start()

        if let saved = store.load(), !saved.isEmpty {
            documents = saved
        } else {
            documents = Self.samples
            store.save(documents)
        }

        let remembered = UserDefaults.standard.string(forKey: "cue.lastDocument")
            .flatMap(UUID.init(uuidString:))
        let document = documents.first(where: { $0.id == remembered }) ?? documents[0]
        currentID = document.id
        currentScript = document.script
        syncMusic()

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.flush() }
        }
    }

    // MARK: Current document

    var current: CueDocument {
        get { documents.first(where: { $0.id == currentID }) ?? documents[0] }
        set {
            if let index = documents.firstIndex(where: { $0.id == newValue.id }) {
                documents[index] = newValue
            }
        }
    }

    var title: String { current.title }

    var wordCount: Int { currentScript.elements.reduce(0) { sum, element in
        sum + element.text.split(whereSeparator: { $0.isWhitespace }).count
    } }

    var sceneCount: Int { currentScript.elements.filter { $0.type == .scene }.count }

    var characterCount: Int {
        var names = Set<String>()
        for element in currentScript.elements where element.type == .character {
            let name = ScriptAnalysis.cueName(element.text)
            if !name.isEmpty { names.insert(name) }
        }
        return names.count
    }

    // MARK: Navigation

    func open(_ document: CueDocument) {
        persistCurrent()
        guard let fresh = documents.first(where: { $0.id == document.id }) else { return }
        currentID = fresh.id
        currentScript = fresh.script
        search = ""
        position = EditorPosition()
        route = .writing
        UserDefaults.standard.set(fresh.id.uuidString, forKey: "cue.lastDocument")
        scheduleSave()
    }

    func openLibrary() {
        persistCurrent()
        scheduleSave()
        search = ""
        route = .library
    }

    // MARK: Library

    func newScript() {
        persistCurrent()
        let base = "Untitled"
        var title = base
        var number = 2
        while documents.contains(where: { $0.title == title }) {
            title = "\(base) \(number)"
            number += 1
        }
        var doc = CueDocument(
            title: title,
            script: Script(title: title, elements: [Element(type: .scene)])
        )
        doc.titlePage = CueTitlePage()
        documents.insert(doc, at: 0)
        currentID = doc.id
        currentScript = doc.script
        route = .writing
        search = ""
        UserDefaults.standard.set(doc.id.uuidString, forKey: "cue.lastDocument")
        scheduleSave()
    }

    func duplicate(_ document: CueDocument) {
        persistCurrent()
        var copy = document
        copy.id = UUID()
        copy.title = "\(document.title) copy"
        copy.shelfTitle = document.shelfTitle.map { _ in copy.title }
        copy.createdAt = Date()
        copy.modified = Date()
        copy.notes = document.notes.map { note in
            var copyNote = note
            copyNote.id = UUID()
            return copyNote
        }
        copy.stickies = document.stickies.map { sticky in
            var copySticky = sticky
            copySticky.id = UUID()
            return copySticky
        }
        copy.pins = document.pins.map { pin in
            var copyPin = pin
            copyPin.id = UUID()
            if let filename = pin.artwork.filename,
               let copied = store.copyAttachment(document: document.id,
                                                 filename: filename,
                                                 to: copy.id) {
                copyPin.artwork = .image(copied)
            }
            return copyPin
        }
        if let graphic = document.titlePage.graphic,
           let copied = store.copyAttachment(document: document.id,
                                             filename: graphic,
                                             to: copy.id) {
            copy.titlePage.graphic = copied
        }
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents.insert(copy, at: index + 1)
        } else {
            documents.append(copy)
        }
        scheduleSave()
    }

    func delete(_ document: CueDocument) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        let wasCurrent = document.id == currentID
        documents.remove(at: index)
        store.removeAttachments(document: document.id)

        if documents.isEmpty {
            let fresh = CueDocument(title: "Untitled",
                                    script: Script(title: "Untitled",
                                                   elements: [Element(type: .scene)]))
            documents = [fresh]
            currentID = fresh.id
            currentScript = fresh.script
        } else if wasCurrent {
            let next = documents[min(index, documents.count - 1)]
            currentID = next.id
            currentScript = next.script
            UserDefaults.standard.set(next.id.uuidString, forKey: "cue.lastDocument")
        }
        scheduleSave()
    }

    func rename(_ document: CueDocument, to newTitle: String) {
        let clean = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        documents[index].title = clean
        documents[index].shelfTitle = nil
        documents[index].script.title = clean
        documents[index].modified = Date()
        if document.id == currentID {
            currentScript.title = clean
        }
        scheduleSave()
    }

    func setTitle(_ newTitle: String) {
        rename(current, to: newTitle)
    }

    // MARK: Import and export

    /// Returns a user-facing error message, or nil on success.
    @discardableResult
    func importFile(_ url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        let script: Script
        switch ext {
        case "fountain", "txt":
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                return "Cue couldn’t read \(url.lastPathComponent)."
            }
            script = Fountain.parse(text)
        case "pdf":
            do {
                script = try PDFImporter.parse(url: url)
            } catch {
                return error.localizedDescription
            }
        default:
            return "Cue imports Fountain files and screenplay PDFs."
        }

        let fallback = url.deletingPathExtension().lastPathComponent
        var title = script.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title == "Untitled" { title = fallback }
        var imported = script
        imported.title = title

        var doc = CueDocument(title: title, script: imported)
        doc.shelfTitle = nil
        doc.titlePage = CueTitlePage()
        documents.insert(doc, at: 0)
        currentID = doc.id
        currentScript = imported
        route = .writing
        UserDefaults.standard.set(doc.id.uuidString, forKey: "cue.lastDocument")
        flush()
        return nil
    }

    func importScriptPanel() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Import a Script"
        panel.message = "Choose a Fountain file or a screenplay PDF."
        panel.allowedContentTypes = [.pdf,
                                     UTType(filenameExtension: "fountain") ?? .plainText,
                                     .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return importFile(url)
    }

    /// Accept a dropped image or image file anywhere on the desk.
    func dropPin(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).png")

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data, let image = NSImage(data: data), let png = image.pngData else { return }
                try? png.write(to: temp)
                Task { @MainActor in self.addPin(from: temp, at: CGPoint(x: 0.10, y: 0.18)) }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in self.addPin(from: url, at: CGPoint(x: 0.10, y: 0.18)) }
            }
            return true
        }
        return false
    }

    func pinPhotoPanel() {
        let panel = NSOpenPanel()
        panel.title = "Pin a Photo"
        panel.message = "Choose an image to keep beside the page."
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addPin(from: url, at: CGPoint(x: 0.10, y: 0.18))
    }

    func exportPDF() {
        persistCurrent()
        Exporter.exportPDF(script: currentScript,
                           title: current.title,
                           titlePage: current.titlePage,
                           graphic: titleGraphic())
    }

    func exportFountain() {
        persistCurrent()
        Exporter.exportFountain(script: currentScript, title: current.title)
    }

    func exportPDF(_ document: CueDocument) {
        persistCurrent()
        Exporter.exportPDF(script: document.script,
                           title: document.title,
                           titlePage: document.titlePage,
                           graphic: titleGraphic(for: document))
    }

    func exportFountain(_ document: CueDocument) {
        persistCurrent()
        Exporter.exportFountain(script: document.script, title: document.title)
    }

    // MARK: Saving

    /// Called by the writing view whenever the script changes.
    func scriptChanged() {
        persistCurrent()
        saveState = .saving
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func scheduleSave() {
        saveState = .saving
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        persistCurrent()
        store.save(documents)
        saveState = .saved
    }

    private func persistCurrent() {
        guard let index = documents.firstIndex(where: { $0.id == currentID }) else { return }
        documents[index].script = currentScript
        documents[index].modified = Date()
        UserDefaults.standard.set(currentID.uuidString, forKey: "cue.lastDocument")
    }

    // MARK: Notes

    func updateSelection(text: String, line: String, paragraph: Int) {
        selectionText = text
        selectionLine = line
        selectionParagraph = paragraph
    }

    func beginNote() {
        let selected = selectionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = selectionLine.trimmingCharacters(in: .whitespacesAndNewlines)
        var quote = selected.isEmpty ? line : selected
        if quote.count > 220 {
            quote = String(quote.prefix(220)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        noteDraft = NoteDraft(
            quote: quote,
            paragraph: selectionParagraph,
            scene: max(1, position.scene),
            tint: current.notes.count % 4
        )
    }

    func editNote(_ note: CueNote) {
        noteDraft = NoteDraft(editing: note.id,
                              quote: note.quote,
                              body: note.body,
                              paragraph: note.paragraph,
                              scene: note.scene,
                              tint: note.tint)
    }

    func saveNoteDraft() {
        guard let draft = noteDraft else { return }
        persistCurrent()
        guard let index = documents.firstIndex(where: { $0.id == currentID }) else { return }
        if let editing = draft.editing,
           let noteIndex = documents[index].notes.firstIndex(where: { $0.id == editing }) {
            documents[index].notes[noteIndex].quote = draft.quote.trimmingCharacters(in: .whitespacesAndNewlines)
            documents[index].notes[noteIndex].body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
            documents[index].notes[noteIndex].tint = draft.tint
            documents[index].notes[noteIndex].paragraph = draft.paragraph
        } else {
            let quote = draft.quote.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !quote.isEmpty else { noteDraft = nil; return }
            documents[index].notes.append(CueNote(
                quote: quote,
                body: draft.body.trimmingCharacters(in: .whitespacesAndNewlines),
                paragraph: draft.paragraph,
                scene: draft.scene,
                tint: draft.tint
            ))
        }
        noteDraft = nil
        sidebarVisible = true
        sidebarTab = .notes
        scheduleSave()
    }

    func deleteNote(_ note: CueNote) {
        guard let index = documents.firstIndex(where: { $0.id == currentID }) else { return }
        documents[index].notes.removeAll { $0.id == note.id }
        scheduleSave()
    }

    func jump(to note: CueNote) {
        sidebarVisible = true
        sidebarTab = .notes
        scrollRequest = ScrollRequest(paragraph: note.paragraph)
    }

    func jump(toParagraph paragraph: Int) {
        scrollRequest = ScrollRequest(paragraph: paragraph)
    }

    // MARK: Desk objects

    func addSticky(at point: CGPoint = CGPoint(x: 0.16, y: 0.57)) {
        guard let index = documents.firstIndex(where: { $0.id == currentID }) else { return }
        var sticky = CueSticky(text: "New note\n\nDouble-click to edit.",
                               tint: documents[index].stickies.count % 4,
                               x: min(0.82, max(0.05, point.x)),
                               y: min(0.82, max(0.12, point.y)))
        sticky.text = "New note"
        documents[index].stickies.append(sticky)
        scheduleSave()
    }

    func updateSticky(_ sticky: CueSticky) {
        guard let index = documents.firstIndex(where: { $0.id == currentID }),
              let stickyIndex = documents[index].stickies.firstIndex(where: { $0.id == sticky.id }) else { return }
        documents[index].stickies[stickyIndex] = sticky
        scheduleSave()
    }

    func moveSticky(_ sticky: CueSticky, to point: CGPoint) {
        var copy = sticky
        copy.x = min(0.88, max(0.02, point.x))
        copy.y = min(0.90, max(0.05, point.y))
        updateSticky(copy)
    }

    func deleteSticky(_ sticky: CueSticky) {
        guard let index = documents.firstIndex(where: { $0.id == currentID }) else { return }
        documents[index].stickies.removeAll { $0.id == sticky.id }
        scheduleSave()
    }

    func addPin(from url: URL? = nil, at point: CGPoint = CGPoint(x: 0.12, y: 0.2)) {
        guard let index = documents.firstIndex(where: { $0.id == currentID }) else { return }
        var artwork: PinArtwork = .dusk
        if let url {
            guard let data = try? Data(contentsOf: url),
                  let image = NSImage(data: data),
                  let png = image.pngData else { return }
            let filename = "\(UUID().uuidString).png"
            guard store.writeAttachment(png, document: currentID, filename: filename) else { return }
            artwork = .image(filename)
            let aspect = image.size.width / max(image.size.height, 1)
            let width = 0.105
            let height = width * 1600 / 1000 / aspect
            documents[index].pins.append(CuePin(
                artwork: artwork,
                x: min(0.86, max(0.06, point.x)),
                y: min(0.82, max(0.08, point.y)),
                width: width,
                height: min(0.22, max(0.10, height)),
                rotation: Double.random(in: -2.6...2.6)
            ))
        } else {
            documents[index].pins.append(CuePin(
                artwork: artwork,
                x: min(0.86, max(0.06, point.x)),
                y: min(0.82, max(0.08, point.y)),
                width: 0.105,
                height: 0.16,
                rotation: Double.random(in: -2.6...2.6)
            ))
        }
        scheduleSave()
    }

    func updatePin(_ pin: CuePin) {
        guard let index = documents.firstIndex(where: { $0.id == currentID }),
              let pinIndex = documents[index].pins.firstIndex(where: { $0.id == pin.id }) else { return }
        documents[index].pins[pinIndex] = pin
        scheduleSave()
    }

    func movePin(_ pin: CuePin, to point: CGPoint) {
        var copy = pin
        copy.x = min(0.9, max(0.02, point.x))
        copy.y = min(0.9, max(0.05, point.y))
        updatePin(copy)
    }

    func deletePin(_ pin: CuePin) {
        guard let index = documents.firstIndex(where: { $0.id == currentID }) else { return }
        if let filename = pin.artwork.filename {
            store.removeAttachment(document: currentID, filename: filename)
        }
        documents[index].pins.removeAll { $0.id == pin.id }
        scheduleSave()
    }

    func setTitleGraphic(_ url: URL) {
        guard let index = documents.firstIndex(where: { $0.id == currentID }),
              let data = try? Data(contentsOf: url),
              let image = NSImage(data: data),
              let png = image.pngData else { return }
        let filename = "\(UUID().uuidString).png"
        guard store.writeAttachment(png, document: currentID, filename: filename) else { return }
        if let old = documents[index].titlePage.graphic {
            store.removeAttachment(document: currentID, filename: old)
        }
        documents[index].titlePage.graphic = filename
        scheduleSave()
    }

    func clearTitleGraphic() {
        guard let index = documents.firstIndex(where: { $0.id == currentID }) else { return }
        if let old = documents[index].titlePage.graphic {
            store.removeAttachment(document: currentID, filename: old)
        }
        documents[index].titlePage.graphic = nil
        scheduleSave()
    }

    func updateTitlePage(_ page: CueTitlePage) {
        guard let index = documents.firstIndex(where: { $0.id == currentID }) else { return }
        documents[index].titlePage = page
        scheduleSave()
    }

    func titleGraphic() -> NSImage? {
        titleGraphic(for: current)
    }

    func titleGraphic(for document: CueDocument) -> NSImage? {
        guard let filename = document.titlePage.graphic else { return nil }
        return store.image(document: document.id, filename: filename)
    }

    func pinImage(_ pin: CuePin) -> NSImage? {
        guard let filename = pin.artwork.filename else { return nil }
        return store.image(document: currentID, filename: filename)
    }

    // MARK: Controls

    func toggleLit() {
        withAnimation(.cueLamp) { lit.toggle() }
        scheduleSave()
    }

    func toggleMusic() {
        audio.toggle()
        syncMusic()
    }

    func skipMusic(_ direction: Int) {
        audio.skip(direction)
        syncMusic()
    }

    func selectTrack(_ index: Int) {
        audio.select(index)
        syncMusic()
    }

    func syncMusic() {
        music.playing = audio.playing
        music.title = audio.track.title
        music.duration = max(1, Int(audio.duration.rounded()))
        music.time = min(music.duration - 1, max(0, Int(audio.elapsed.rounded())))
        music.palette = audio.track.palette.map { Color(hex: $0) }
    }

    func showHelpSheet() { showHelp = true }

    // MARK: - Sample library

    static let samples: [CueDocument] = [
        CueDocument(
            title: "Harrow Light",
            shelfTitle: "HARROW LIGHT",
            script: Script(title: "Harrow Light", elements: [
                Element(type: .character, text: "ELIAS"),
                Element(type: .dialogue, text: "Who else would be daft enough?"),
                Element(type: .character, text: "INGRID (V.O.)"),
                Element(type: .dialogue, text: "I had you down for home by six."),
                Element(type: .character, text: "ELIAS"),
                Element(type: .dialogue, text: "I had me down for home by six. The fog had other plans."),
                Element(type: .character, text: "INGRID (V.O.)"),
                Element(type: .dialogue, text: "It came in off the bank about four. I can't see my own railing. What's your position?"),
                Element(type: .action, text: "Elias leans over the chart. Walks two fingers across it like a man pacing out a grave."),
                Element(type: .character, text: "ELIAS"),
                Element(type: .dialogue, text: "Nine miles north-east of you. Give or take a mile, and I'd rather give than take."),
                Element(type: .character, text: "INGRID (V.O.)"),
                Element(type: .dialogue, text: "Then come in slow. I'll keep the lamp turning and the kettle on."),
                Element(type: .character, text: "ELIAS"),
                Element(type: .dialogue, text: "In that order?"),
                Element(type: .character, text: "INGRID (V.O.)"),
                Element(type: .dialogue, text: "In that order."),
                Element(type: .action, text: "He hangs up the handset. Smiles at nothing. Eases the throttle forward a hair."),
                Element(type: .action, text: "Something bumps the hull. Soft. Almost polite."),
                Element(type: .action, text: "Elias goes still. Listens. The engine knocks. The water slaps. Nothing else."),
                Element(type: .character, text: "ELIAS"),
                Element(type: .dialogue, text: "Driftwood."),
                Element(type: .action, text: "He does not sound convinced."),
                Element(type: .scene, text: "EXT. MARIGOLD - DECK - NIGHT"),
                Element(type: .action, text: "Elias steps out with a torch. The beam goes six feet and gives up."),
                Element(type: .new, text: "")
            ]),
            cover: "night",
            declaredPages: 19,
            declaredScenes: 25,
            sceneNumberOffset: 2,
            pageNumberOffset: 1,
            declaredCharacterLines: ["ELIAS": 57, "INGRID": 49],
            notes: [
                CueNote(quote: "Something bumps the hull.",
                        body: "First hint. Don’t explain it yet.",
                        paragraph: 18, scene: 1, tint: 1)
            ],
            stickies: [
                CueSticky(text: "Elias’s line about the grave\n\nIs it too on the nose?",
                          tint: 0, x: 0.1626, y: 0.5725),
                CueSticky(text: "The lamp should fail\nbefore the fog lifts.",
                          tint: 1, x: 0.8374, y: 0.2425)
            ],
            pins: [
                CuePin(artwork: .dusk, x: 0.101, y: 0.155, width: 0.094, height: 0.10, rotation: 2.4),
                CuePin(artwork: .fog, x: 0.880, y: 0.600, width: 0.0725, height: 0.148, rotation: -2.2)
            ]
        ),
        CueDocument(
            title: "One Good Line",
            script: Script(title: "One Good Line", elements: [
                Element(type: .scene, text: "INT. APARTMENT - NIGHT"),
                Element(type: .action, text: "A small room lit by a single desk lamp. Rain on the window. DANIEL (30s, tired, kind) sits at a typewriter he no longer uses."),
                Element(type: .action, text: "The door opens. AMY (30s) shakes the rain from her coat."),
                Element(type: .character, text: "AMY"),
                Element(type: .dialogue, text: "You're still up."),
                Element(type: .character, text: "DANIEL"),
                Element(type: .paren, text: "(not looking up)"),
                Element(type: .dialogue, text: "I'm still up."),
                Element(type: .action, text: "She crosses to the lamp. Warm light on both of them."),
                Element(type: .character, text: "AMY"),
                Element(type: .dialogue, text: "Did you write anything?"),
                Element(type: .character, text: "DANIEL"),
                Element(type: .dialogue, text: "One line. It's a good line, though."),
                Element(type: .transition, text: "CUT TO:"),
                Element(type: .scene, text: "EXT. CITY STREET - DAY"),
                Element(type: .action, text: "Morning. The city hums. Daniel walks, hands in pockets, reading the line again and again from a folded page."),
                Element(type: .character, text: "DANIEL (V.O.)"),
                Element(type: .dialogue, text: "Everything starts with one line."),
                Element(type: .new, text: "")
            ]),
            cover: "harrow",
            declaredPages: 1,
            declaredScenes: 2,
            deskExtras: false,
            notes: [
                CueNote(quote: "single desk lamp",
                        body: "Could the lamp be a character? Keep coming back to it.",
                        paragraph: 1, scene: 1, tint: 0),
                CueNote(quote: "shakes the rain from her coat",
                        body: "Too tidy an entrance?",
                        paragraph: 2, scene: 1, tint: 1)
            ],
            stickies: [
                CueSticky(text: "Daniel's typewriter: pay it off\nin the last scene?",
                          tint: 0, x: 0.1626, y: 0.5725),
                CueSticky(text: "Does Amy already know\nabout the line?\n\nTry the scene without the lamp.",
                          tint: 0, x: 0.8374, y: 0.2425)
            ]
        )
    ]
}

enum SidebarTab: String, CaseIterable, Identifiable {
    case scenes = "Scenes"
    case characters = "Characters"
    case notes = "Notes"
    var id: String { rawValue }
}

enum SaveState: Equatable {
    case saved, saving
}

struct MusicState {
    var playing = false
    var title = "Night Drive"
    var duration = 180
    var time = 0
    var palette: [Color] = [Color(hex: 0x5B3F8C), Color(hex: 0xC2577A), Color(hex: 0xE59A4E)]
    var bars = 34
}

private extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
