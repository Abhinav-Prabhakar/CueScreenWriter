import AppKit
import Foundation

/// The on-disk library.
///
/// A Cue library is a folder in Application Support with one JSON manifest and
/// a directory of attachments (pinned images, title graphics). Everything is
/// written atomically; a corrupt manifest is moved aside rather than deleted,
/// so a writer never loses the only copy of their work to a bad decode.
final class LibraryStore {
    static let shared = LibraryStore()

    let root: URL
    private let manifestURL: URL
    private let attachmentsURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(root: URL? = nil) {
        let base = root ?? Self.defaultRoot()
        self.root = base
        manifestURL = base.appendingPathComponent("library.json")
        attachmentsURL = base.appendingPathComponent("Attachments", isDirectory: true)

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // ISO 8601 with fractional seconds: human-readable, but a round trip is
        // still exact to the millisecond, so autosave never looks like an edit.
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(precise.string(from: date))
        }
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = precise.date(from: string) ?? plain.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "Invalid date: \(string)")
        }

        try? FileManager.default.createDirectory(at: attachmentsURL,
                                                 withIntermediateDirectories: true)
    }

    private static func defaultRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["CUE_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("Cue", isDirectory: true)
    }

    // MARK: - Manifest

    func load() -> [CueDocument]? {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: manifestURL)
            return try decoder.decode([CueDocument].self, from: data)
        } catch {
            quarantineManifest()
            return nil
        }
    }

    func save(_ documents: [CueDocument]) {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let data = try encoder.encode(documents)
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            NSLog("Cue: could not save the library: \(error.localizedDescription)")
        }
    }

    private func quarantineManifest() {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = root.appendingPathComponent("library-corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: manifestURL, to: backup)
    }

    // MARK: - Attachments

    func attachmentURL(document: UUID, filename: String) -> URL {
        attachmentsURL
            .appendingPathComponent(document.uuidString, isDirectory: true)
            .appendingPathComponent(filename)
    }

    @discardableResult
    func writeAttachment(_ data: Data, document: UUID, filename: String) -> Bool {
        let url = attachmentURL(document: document, filename: filename)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            NSLog("Cue: could not write attachment \(filename): \(error.localizedDescription)")
            return false
        }
    }

    func image(document: UUID, filename: String) -> NSImage? {
        NSImage(contentsOf: attachmentURL(document: document, filename: filename))
    }

    func copyAttachment(document: UUID, filename: String, to newDocument: UUID) -> String? {
        let source = attachmentURL(document: document, filename: filename)
        guard let data = try? Data(contentsOf: source) else { return nil }
        let ext = (filename as NSString).pathExtension
        let copy = "\(UUID().uuidString).\(ext.isEmpty ? "png" : ext)"
        return writeAttachment(data, document: newDocument, filename: copy) ? copy : nil
    }

    func removeAttachments(document: UUID) {
        let directory = attachmentsURL.appendingPathComponent(document.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

    func removeAttachment(document: UUID, filename: String) {
        try? FileManager.default.removeItem(at: attachmentURL(document: document, filename: filename))
    }

    func attachmentDirectory(document: UUID) -> URL {
        attachmentsURL.appendingPathComponent(document.uuidString, isDirectory: true)
    }
}
