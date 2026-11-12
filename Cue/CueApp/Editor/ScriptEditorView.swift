import SwiftUI
import AppKit
import CueKit

/// The SwiftUI bridge for the writing surface.
///
/// The host view contains an `NSScrollView` and one `ScriptTextView`; the
/// paper itself is painted by the SwiftUI page around this view.
struct ScriptEditorView: NSViewRepresentable {
    @Binding var script: Script
    private let theme: Theme
    private let isEditable: Bool
    private let sceneOffset: Int
    private let pageOffset: Int
    private let declaredPages: Int?
    private let scrollRequest: ScrollRequest?
    let onPosition: (EditorPosition) -> Void
    let onSelection: (String, String, Int) -> Void
    let onRequestNote: () -> Void

    init(script: Binding<Script>,
         theme: Theme,
         isEditable: Bool = true,
         sceneOffset: Int = 0,
         pageOffset: Int = 0,
         declaredPages: Int? = nil,
         scrollRequest: ScrollRequest? = nil,
         onPosition: @escaping (EditorPosition) -> Void = { _ in },
         onSelection: @escaping (String, String, Int) -> Void = { _, _, _ in },
         onRequestNote: @escaping () -> Void = {}) {
        self._script = script
        self.theme = theme
        self.isEditable = isEditable
        self.sceneOffset = sceneOffset
        self.pageOffset = pageOffset
        self.declaredPages = declaredPages
        self.scrollRequest = scrollRequest
        self.onPosition = onPosition
        self.onSelection = onSelection
        self.onRequestNote = onRequestNote
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> EditorHostView {
        let host = EditorHostView()
        let textView = host.textView
        let coordinator = context.coordinator
        coordinator.textView = textView

        textView.onChange = { [weak coordinator] script in
            coordinator?.scriptChanged(script)
        }
        textView.onPosition = { [weak coordinator] position in
            coordinator?.positionChanged(position)
        }
        textView.onSelection = { [weak coordinator] selected, line, paragraph in
            coordinator?.selectionChanged(selected, line: line, paragraph: paragraph)
        }
        textView.onRequestNote = { [weak coordinator] in
            coordinator?.parent.onRequestNote()
        }

        textView.isEditable = isEditable
        textView.apply(theme: theme, animated: false)
        textView.load(script)
        textView.applyDocumentNumbering(sceneOffset: sceneOffset,
                                        pageOffset: pageOffset,
                                        pages: declaredPages)
        return host
    }

    func updateNSView(_ host: EditorHostView, context: Context) {
        context.coordinator.parent = self
        let textView = host.textView
        let coordinator = context.coordinator

        textView.onChange = { [weak coordinator] script in
            coordinator?.scriptChanged(script)
        }
        textView.onPosition = { [weak coordinator] position in
            coordinator?.positionChanged(position)
        }
        textView.onSelection = { [weak coordinator] selected, line, paragraph in
            coordinator?.selectionChanged(selected, line: line, paragraph: paragraph)
        }
        textView.onRequestNote = { [weak coordinator] in
            coordinator?.parent.onRequestNote()
        }

        if let scrollRequest, scrollRequest.id != coordinator.lastScrollRequest {
            coordinator.lastScrollRequest = scrollRequest.id
            textView.scrollToParagraph(scrollRequest.paragraph)
        }

        textView.isEditable = isEditable
        textView.apply(theme: theme)
        textView.applyDocumentNumbering(sceneOffset: sceneOffset,
                                        pageOffset: pageOffset,
                                        pages: declaredPages)

        // Do not clobber the selection while the writer is typing. The binding
        // only reloads when the incoming script is genuinely external.
        if textView.scriptSnapshot != script {
            if textView.currentScript == script {
                textView.scriptSnapshot = script
            } else {
                textView.load(script)
            }
        }
    }

    static func dismantleNSView(_ host: EditorHostView, coordinator: Coordinator) {
        host.textView.onChange = nil
        host.textView.onPosition = nil
        host.textView.onSelection = nil
        host.textView.onRequestNote = nil
        host.textView.onLayoutNeeded = nil
    }

    @MainActor
    final class Coordinator {
        var parent: ScriptEditorView
        weak var textView: ScriptTextView?
        var lastScrollRequest: UUID?

        init(_ parent: ScriptEditorView) {
            self.parent = parent
        }

        func scriptChanged(_ newScript: Script) {
            // The text view generated this script; remember it so the next
            // SwiftUI update does not mistake our own edit for an external one.
            textView?.scriptSnapshot = newScript
            guard parent.script != newScript else { return }
            parent.script = newScript
        }

        func positionChanged(_ position: EditorPosition) {
            parent.onPosition(position)
        }

        func selectionChanged(_ selected: String, line: String, paragraph: Int) {
            parent.onSelection(selected, line, paragraph)
        }
    }
}

// MARK: - AppKit host

/// Scroll view + text view + margin furniture.
final class EditorHostView: NSView {
    let scrollView = NSScrollView()
    let textView = ScriptTextView()
    let furniture = PageFurnitureView()

    private var boundsObserver: NSObjectProtocol?
    private var lastContentWidth: CGFloat = 0

    init() {
        super.init(frame: .zero)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = textView
        addSubview(scrollView)

        furniture.textView = textView
        furniture.frame = textView.bounds
        textView.addSubview(furniture, positioned: .below, relativeTo: nil)

        textView.onLayoutNeeded = { [weak self] in
            self?.needsLayout = true
        }

        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.furniture.invalidate()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds

        let contentWidth = max(scrollView.contentSize.width, 1)
        if abs(contentWidth - lastContentWidth) > 0.5 {
            lastContentWidth = contentWidth
            textView.updateWidth(contentWidth)
        }
        updateDocumentSize()
    }

    private func updateDocumentSize() {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }

        let contentWidth = max(scrollView.contentSize.width, 1)
        if abs(textView.frame.width - contentWidth) > 0.5 {
            textView.setFrameSize(NSSize(width: contentWidth,
                                         height: max(textView.frame.height, 1)))
        }

        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let height = max(used.height + 16, scrollView.contentSize.height)
        if abs(textView.frame.height - height) > 0.5 {
            textView.setFrameSize(NSSize(width: contentWidth, height: height))
        }
        furniture.frame = textView.bounds
        furniture.invalidate()
    }
}
