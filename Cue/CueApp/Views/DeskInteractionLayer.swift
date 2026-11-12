import AppKit
import SwiftUI

/// The open desk behind the page: right-click, double-click and drop all happen
/// here, at the exact point under the pointer. SwiftUI's `contextMenu` cannot
/// report where a right-click landed, so this thin AppKit view owns the desk's
/// native menu and drag destination.
struct DeskInteractionLayer: NSViewRepresentable {
    let model: AppModel
    var onTitlePage: () -> Void

    func makeNSView(context: Context) -> DeskSurface {
        let view = DeskSurface()
        view.model = model
        view.onTitlePage = onTitlePage
        return view
    }

    func updateNSView(_ view: DeskSurface, context: Context) {
        view.model = model
        view.onTitlePage = onTitlePage
    }

    final class DeskSurface: NSView {
        weak var model: AppModel?
        var onTitlePage: () -> Void = {}

        override var isOpaque: Bool { false }
        override var acceptsFirstResponder: Bool { false }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            registerForDraggedTypes([.fileURL, .png, .tiff])
        }

        /// The toolbar floats above the desk but its empty space is not
        /// hit-testable, so clicks there would otherwise fall through and drop
        /// a sticky under the title. The band stays out of the desk's reach.
        private func deskPoint(for event: NSEvent) -> CGPoint? {
            let local = convert(event.locationInWindow, from: nil)
            guard local.y <= bounds.height - Self.toolbarBand else { return nil }
            return normalized(local)
        }

        private static let toolbarBand: CGFloat = 86

        private func normalized(_ local: CGPoint) -> CGPoint {
            guard bounds.width > 0, bounds.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
            return CGPoint(x: min(0.95, max(0.03, local.x / bounds.width)),
                           y: min(0.95, max(0.06, 1 - local.y / bounds.height)))
        }

        // MARK: Menu

        override func rightMouseDown(with event: NSEvent) {
            guard let model, let at = deskPoint(for: event) else { return }
            let menu = NSMenu()

            let sticky = ClosureItem("Add Sticky Note") { [weak self] in
                _ = self?.model?.addSticky(at: at, beginEditing: true)
            }
            sticky.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)
            menu.addItem(sticky)

            let pin = ClosureItem("Pin a Photo…") { [weak self] in
                self?.model?.pinPhotoPanel(at: at)
            }
            pin.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
            menu.addItem(pin)

            menu.addItem(.separator())

            let note = ClosureItem("Add Note on This Line…") { [weak self] in
                self?.model?.beginNote()
            }
            note.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)
            menu.addItem(note)

            let title = ClosureItem("Open Title Page…") { [weak self] in
                self?.onTitlePage()
            }
            title.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
            menu.addItem(title)

            menu.addItem(.separator())
            let lamp = ClosureItem(model.lit ? "Turn the Lamp Off" : "Turn the Lamp On") { [weak self] in
                self?.model?.toggleLit()
            }
            lamp.image = NSImage(systemSymbolName: "lamp.desk", accessibilityDescription: nil)
            menu.addItem(lamp)

            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        override func mouseDown(with event: NSEvent) {
            guard event.clickCount == 2, let model, let at = deskPoint(for: event) else { return }
            _ = model.addSticky(at: at, beginEditing: true)
        }

        // MARK: Drop

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            .copy
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            guard let model else { return false }
            let at = normalized(convert(sender.draggingLocation, from: nil))
            let board = sender.draggingPasteboard

            if let urls = board.readObjects(forClasses: [NSURL.self],
                                            options: [.urlReadingFileURLsOnly: true]) as? [URL],
               let url = urls.first {
                model.addPin(from: url, at: at)
                return true
            }

            if let image = NSImage(pasteboard: board),
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString).png")
                try? png.write(to: temp)
                model.addPin(from: temp, at: at)
                try? FileManager.default.removeItem(at: temp)
                return true
            }
            return false
        }
    }
}

/// A menu item that owns a closure. AppKit menus use target/action, so the item
/// retains the closure and targets itself.
private final class ClosureItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: nil, keyEquivalent: "")
        target = self
        action = #selector(run)
    }

    required init(coder: NSCoder) {
        handler = {}
        super.init(coder: coder)
    }

    @objc private func run() {
        handler()
    }
}
