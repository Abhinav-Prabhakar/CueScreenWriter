import AppKit
import UniformTypeIdentifiers
import CueKit

/// The two export commands in the File menu.
///
/// There is no document manager here: the panel chooses a destination, the
/// renderer writes it, and any failure is reported once with the real reason.
@MainActor
enum Exporter {
    static func exportPDF(script: Script,
                          title: String,
                          titlePage: CueTitlePage = CueTitlePage(),
                          graphic: NSImage? = nil) {
        let panel = NSSavePanel()
        panel.title = "Export PDF"
        panel.message = "Choose where to save the screenplay."
        panel.nameFieldStringValue = suggestedName(title: title, fileExtension: "pdf")
        panel.allowedContentTypes = [.pdf]
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let choice = panel.url else { return }
        let url = ensuringExtension(choice, "pdf")

        do {
            try PDFExport.write(script: script,
                                title: title,
                                titlePage: titlePage,
                                graphic: graphic,
                                to: url)
        } catch {
            present(error, action: "export the PDF")
        }
    }

    static func exportFountain(script: Script, title: String) {
        let panel = NSSavePanel()
        panel.title = "Export Fountain"
        panel.message = "Choose where to save the Fountain file."
        panel.nameFieldStringValue = suggestedName(title: title, fileExtension: "fountain")
        panel.allowedContentTypes = [fountainType]
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let choice = panel.url else { return }
        let url = ensuringExtension(choice, "fountain")

        do {
            let text = Fountain.serialise(script, title: title)
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            present(error, action: "export the Fountain file")
        }
    }

    // MARK: - Files

    private static var fountainType: UTType {
        UTType(filenameExtension: "fountain")
            ?? UTType(exportedAs: "com.cue.fountain", conformingTo: .plainText)
    }

    private static func ensuringExtension(_ url: URL, _ pathExtension: String) -> URL {
        if url.pathExtension.lowercased() == pathExtension { return url }
        return url.appendingPathExtension(pathExtension)
    }

    private static func suggestedName(title: String, fileExtension pathExtension: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Untitled" : trimmed

        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        var clean = base.components(separatedBy: forbidden).joined(separator: "-")
        clean = clean.replacingOccurrences(of: "\n", with: " ")
        clean = clean.replacingOccurrences(of: "\t", with: " ")
        while clean.contains("--") {
            clean = clean.replacingOccurrences(of: "--", with: "-")
        }
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { clean = "Untitled" }
        if clean.count > 120 {
            clean = String(clean.prefix(120)).trimmingCharacters(in: .whitespaces)
        }
        return "\(clean).\(pathExtension)"
    }

    // MARK: - Errors

    private static func present(_ error: Error, action: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t \(action)"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
