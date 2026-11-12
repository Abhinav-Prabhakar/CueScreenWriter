import SwiftUI
import AppKit
import QuartzCore
import CueKit

// MARK: - Shared screenplay typography

/// The paragraph geometry shared by the editor and the PDF renderer.
/// Widths are percentages of the text container, exactly as on the site.
enum ScreenplayTypography {
    static func size(forWidth width: CGFloat) -> CGFloat {
        // 12 pt on an 8.5 in page: at the 1200 pt reference window this is 11 pt,
        // which is what the screenshots measure. Do not clamp it upward — a larger
        // minimum changes every dialogue line's wrap.
        max(10, width / 8.5 * (12.0 / 72.0))
    }

    static func font(for type: ElementType, size: CGFloat) -> NSFont {
        Fonts.scriptNS(size, bold: type == .scene)
    }

    static func paragraphStyle(for type: ElementType,
                               width: CGFloat,
                               line: CGFloat,
                               spacingBefore: CGFloat) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.0
        p.minimumLineHeight = line
        p.maximumLineHeight = line
        p.lineBreakMode = .byWordWrapping
        p.hyphenationFactor = 0
        p.paragraphSpacingBefore = spacingBefore
        p.paragraphSpacing = 0

        let lead = width * 0.1765
        let tail = width * 0.1176

        switch type {
        case .scene, .action, .new:
            p.firstLineHeadIndent = lead
            p.headIndent = lead
            p.tailIndent = -tail
        case .character:
            p.firstLineHeadIndent = width * 0.435
            p.headIndent = width * 0.435
            p.tailIndent = -tail
        case .paren:
            p.firstLineHeadIndent = width * 0.365
            p.headIndent = width * 0.365
            p.tailIndent = -width * 0.30
        case .dialogue:
            p.firstLineHeadIndent = width * 0.294
            p.headIndent = width * 0.294
            p.tailIndent = -width * 0.294
        case .transition:
            p.firstLineHeadIndent = lead
            p.headIndent = lead
            p.tailIndent = -tail
            p.alignment = .right
        }
        return p
    }
}

extension NSAttributedString.Key {
    /// The stored screenplay type of a paragraph, kept in parallel with
    /// `ScriptTextView.paragraphTypes` and repaired after every edit.
    static let elementType = NSAttributedString.Key("CueElementType")
}

// MARK: - Menu overlay

/// A small, focus-refusing child view for the chooser and the time menu.
/// It is deliberately not an `NSMenu`: the text view keeps first responder and
/// all key handling stays in `ScriptTextView`.
final class EditorMenuView: NSView {
    enum Kind {
        case chooser
        case time
    }

    let kind: Kind
    var items: [String] = [] { didSet { needsDisplay = true } }
    var selected: Int = 0 { didSet { needsDisplay = true } }
    var theme: Theme = .daylight { didSet { needsDisplay = true } }
    var fontSize: CGFloat = 12 { didSet { needsDisplay = true } }
    var onPick: ((Int) -> Void)?

    private let rowHeight: CGFloat = 22
    private let verticalPadding: CGFloat = 4

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        setAccessibilityLabel(kind == .chooser ? "Element type" : "Scene time")
        setAccessibilityHelp(kind == .chooser
            ? "Choose what the new line is. Use the arrow keys and Return."
            : "Choose a time of day. Use the arrow keys and Return.")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    private func rowRect(_ index: Int) -> NSRect {
        NSRect(x: 1,
               y: verticalPadding + CGFloat(index) * rowHeight,
               width: max(0, bounds.width - 2),
               height: rowHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !items.isEmpty else { return }

        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                      xRadius: 6, yRadius: 6)
        theme.nsPaper.withAlphaComponent(0.97).setFill()
        background.fill()
        theme.nsInk.withAlphaComponent(0.12).setStroke()
        background.lineWidth = 1
        background.stroke()

        for (index, item) in items.enumerated() {
            let rect = rowRect(index)

            if index == selected {
                let selection = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 1),
                                             xRadius: 4, yRadius: 4)
                NSColor(hex: Hex.choice, opacity: 0.10).setFill()
                selection.fill()

                let dot = NSBezierPath(ovalIn: NSRect(x: rect.minX + 6,
                                                     y: rect.midY - 2,
                                                     width: 4, height: 4))
                NSColor(hex: Hex.choice).setFill()
                dot.fill()
            }

            let color = index == selected
                ? NSColor(hex: Hex.choiceText)
                : theme.nsInk
            let font: NSFont
            let attributes: [NSAttributedString.Key: Any]
            let textSize: NSSize

            switch kind {
            case .chooser:
                font = Fonts.uiNS(10.5, weight: .medium)
                attributes = [
                    .font: font,
                    .foregroundColor: color,
                    .kern: 0.65
                ]
                textSize = (item as NSString).size(withAttributes: attributes)
                (item as NSString).draw(at: NSPoint(x: rect.maxX - 8 - textSize.width,
                                                    y: rect.minY + (rowHeight - textSize.height) / 2),
                                        withAttributes: attributes)
            case .time:
                font = Fonts.scriptNS(fontSize)
                attributes = [
                    .font: font,
                    .foregroundColor: color
                ]
                textSize = (item as NSString).size(withAttributes: attributes)
                (item as NSString).draw(at: NSPoint(x: rect.minX + 12,
                                                    y: rect.minY + (rowHeight - textSize.height) / 2),
                                        withAttributes: attributes)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let raw = Int(floor((point.y - verticalPadding) / rowHeight))
        guard raw >= 0, raw < items.count else { return }
        selected = raw
        onPick?(raw)
    }

    override func accessibilityChildren() -> [Any]? {
        items.enumerated().compactMap { index, item in
            guard let window else { return nil }
            let screenRect = window.convertToScreen(convert(rowRect(index), to: nil))
            let element = NSAccessibilityElement()
            element.setAccessibilityRole(.menuItem)
            element.setAccessibilityLabel(item)
            element.setAccessibilityParent(self)
            element.setAccessibilityFrame(screenRect)
            return element
        }
    }

    func show() {
        guard isHidden else { return }
        isHidden = false
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            alphaValue = 1
            return
        }
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            animator().alphaValue = 1
        }
    }

    func hide() {
        isHidden = true
        alphaValue = 1
    }
}

// MARK: - Script text view

/// One `NSTextView` over TextKit 1. The text storage owns the words; the
/// parallel `paragraphTypes` array owns the screenplay semantics. Both are
/// mirrored into a custom attribute for rendering.
final class ScriptTextView: NSTextView, NSTextViewDelegate {

    // MARK: Public callbacks

    var onChange: ((Script) -> Void)?
    var onPosition: ((EditorPosition) -> Void)?
    var onLayoutNeeded: (() -> Void)?
    var onSelection: ((String, String, Int) -> Void)?
    var onRequestNote: (() -> Void)?

    // MARK: Model

    /// The last script the host handed us (or the last one we emitted).
    var scriptSnapshot: Script = Script(title: "Untitled", elements: [Element(type: .scene)])

    /// Parallel type map, indexed by paragraph.
    private(set) var paragraphTypes: [ElementType] = [.scene]

    /// Visible scene number toggle, mirrored from the document.
    private(set) var sceneNumbersVisible = true

    /// Excerpt offsets: the bundled sample starts part-way through the real
    /// document, so the margins and toolbar continue its numbering.
    private(set) var sceneNumberOffset = 0
    private(set) var pageNumberOffset = 0
    private(set) var declaredPageCount: Int?

    private var paragraphRangesCache: [NSRange] = []
    private var paragraphTextsCache: [String] = []
    private var elementsCache: [Element] = []
    private var derived = ScriptDerived()

    private(set) var sceneMarks: [(paragraph: Int, number: Int)] = []
    private(set) var rails: [(paragraph: Int, colourIndex: Int)] = []

    // MARK: Text system

    private let backingStorage: NSTextStorage
    private let backingLayoutManager: NSLayoutManager
    private let backingContainer: NSTextContainer

    // MARK: Theme

    private var theme: Theme = .daylight
    private var inkColor = NSColor(hex: Hex.ink)
    private var ink2Color = NSColor(hex: Hex.ink2)
    private var selectionColor = NSColor(hex: Hex.ink, opacity: 0.12)

    // MARK: Editing state

    private var isLoading = false
    private var isApplyingShortcut = false
    private var pendingNewParagraphType: ElementType?
    private var changeWorkItem: DispatchWorkItem?
    private var lastPosition: EditorPosition?

    // MARK: Menus and ghost

    private let chooserView = EditorMenuView(kind: .chooser)
    private let timeView = EditorMenuView(kind: .time)

    private var chooserOpen = false
    private var chooserIndex = 0
    private var timeMenuOpen = false
    private var timeMenuIndex = 0
    private var timeMenuParagraph: Int?
    private var dismissedTimeTexts = Set<String>()

    private var ghost: Ghost?

    // MARK: Init

    init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        layoutManager.addTextContainer(container)

        backingStorage = storage
        backingLayoutManager = layoutManager
        backingContainer = container

        super.init(frame: .zero, textContainer: container)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        delegate = self

        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isEditable = true
        isSelectable = true

        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        smartInsertDeleteEnabled = false

        isContinuousSpellCheckingEnabled = true
        isGrammarCheckingEnabled = false
        usesFindBar = true
        isIncrementalSearchingEnabled = true

        drawsBackground = false
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = false
        textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        isVerticallyResizable = true
        isHorizontallyResizable = false
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        autoresizingMask = [.width]

        insertionPointColor = inkColor
        selectedTextAttributes = [.backgroundColor: selectionColor]
        textColor = inkColor

        setAccessibilityLabel("Script")
        setAccessibilityRole(.textArea)
        setAccessibilityHelp("Screenplay editor. Return creates the next line, Tab promotes action to character.")

        chooserView.onPick = { [weak self] index in
            self?.chooserIndex = index
            self?.acceptChooser()
        }
        timeView.onPick = { [weak self] index in
            self?.timeMenuIndex = index
            self?.commitTimeSelection(advance: true)
        }
        chooserView.isHidden = true
        timeView.isHidden = true
        addSubview(chooserView)
        addSubview(timeView)

        rebuildParagraphCache()
    }

    // MARK: Public API

    func load(_ script: Script) {
        let oldSelection = selectedRange()
        let oldParagraph = paragraphIndex(at: oldSelection.location)
        let oldRange = paragraphRange(at: oldParagraph)
        let oldOffset = max(0, oldSelection.location - (oldRange?.location ?? 0))

        changeWorkItem?.cancel()
        changeWorkItem = nil
        isLoading = true
        scriptSnapshot = script
        sceneNumbersVisible = script.sceneNumbers

        var source = script.elements
        if source.isEmpty {
            source = [Element(type: .scene)]
        }

        paragraphTypes = source.map(\.type)
        let text = source.map(\.text).joined(separator: "\n")
        backingStorage.setAttributedString(NSAttributedString(string: text))
        rebuildParagraphCache()
        restyleAll()
        refreshAnalysis()

        let count = paragraphTypes.count
        if oldSelection.length > 0,
           NSMaxRange(oldSelection) <= (string as NSString).length {
            setSelectedRange(oldSelection)
        } else {
            let target = min(oldParagraph, max(0, count - 1))
            let targetRange = paragraphRange(at: target)
            let targetLength = (textForParagraph(target) as NSString).length
            let location = (targetRange?.location ?? 0) + min(oldOffset, targetLength)
            setSelectedRange(NSRange(location: min(location, (string as NSString).length), length: 0))
        }

        isLoading = false
        updateTypingAttributes()
        updateGhost()
        updateOverlays()
        invalidateFurniture()
        publishPosition()
    }

    /// Move the caret to a paragraph and reveal it. Used by scene rows and
    /// notes so a click always lands on the line it refers to.
    func scrollToParagraph(_ index: Int) {
        guard index >= 0, index < paragraphRangesCache.count,
              let range = paragraphRange(at: index) else { return }
        let target = NSRange(location: range.location, length: 0)
        setSelectedRange(target)
        scrollRangeToVisible(target)
        window?.makeFirstResponder(self)
        reportSelection()
    }

    func reportSelection() {
        let selection = selectedRange()
        let paragraph = currentParagraph()
        let selected = selection.length > 0
            ? (string as NSString).substring(with: selection)
            : ""
        onSelection?(selected, textForParagraph(paragraph), paragraph)
    }

    var currentScript: Script {
        let texts = paragraphTextsCache
        guard !texts.isEmpty else {
            return Script(title: scriptSnapshot.title,
                          sceneNumbers: scriptSnapshot.sceneNumbers,
                          elements: [Element(type: .scene)])
        }
        var result: [Element] = []
        result.reserveCapacity(texts.count)
        for index in texts.indices {
            let type = index < paragraphTypes.count ? paragraphTypes[index] : .action
            result.append(Element(type: type, text: texts[index]))
        }
        return Script(title: scriptSnapshot.title,
                      sceneNumbers: scriptSnapshot.sceneNumbers,
                      elements: result)
    }

    func apply(theme newTheme: Theme, animated: Bool = true) {
        let newInk = NSColor(newTheme.ink)
        let newSelection = NSColor(newTheme.selection)
        let changed = !newInk.isEqual(inkColor) || !newSelection.isEqual(selectionColor)

        if changed, animated, window != nil {
            let snapshot = snapshotImage()
            let duration: TimeInterval = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.01 : 1.2
            theme = newTheme
            applyColors()
            if let snapshot {
                crossFade(snapshot: snapshot, duration: duration)
            }
        } else {
            theme = newTheme
            applyColors()
        }
    }

    func updateWidth(_ width: CGFloat) {
        guard width > 0 else { return }
        if abs(backingContainer.size.width - width) > 0.5 {
            backingContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        }
        restyleAll()
        refreshAnalysis()
        updateTypingAttributes()
        updateGhost()
        updateOverlays()
        invalidateFurniture()
        publishPosition()
    }

    // MARK: Theme

    private func applyColors() {
        inkColor = NSColor(theme.ink)
        ink2Color = NSColor(theme.ink2)
        selectionColor = NSColor(theme.selection)

        insertionPointColor = inkColor
        selectedTextAttributes = [.backgroundColor: selectionColor]
        textColor = inkColor

        chooserView.theme = theme
        timeView.theme = theme
        restyleAll()
        invalidateFurniture()
        needsDisplay = true
    }

    private func snapshotImage() -> NSImage? {
        guard bounds.width > 1, bounds.height > 1,
              let representation = bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        cacheDisplay(in: bounds, to: representation)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(representation)
        return image
    }

    private func crossFade(snapshot: NSImage, duration: TimeInterval) {
        let overlay = SnapshotOverlayView(frame: bounds, image: snapshot)
        overlay.autoresizingMask = [.width, .height]
        overlay.wantsLayer = true
        overlay.alphaValue = 1
        addSubview(overlay, positioned: .above, relativeTo: nil)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            overlay.animator().alphaValue = 0
        }, completionHandler: {
            overlay.removeFromSuperview()
        })
    }

    // MARK: Paragraph cache

    private func rebuildParagraphCache() {
        let source = string as NSString
        let ranges = Self.paragraphRanges(in: source)
        paragraphRangesCache = ranges
        paragraphTextsCache = ranges.map { range in
            var length = range.length
            if length > 0, source.character(at: range.location + length - 1) == 10 {
                length -= 1
            }
            return source.substring(with: NSRange(location: range.location, length: length))
        }
        if paragraphTextsCache.isEmpty {
            paragraphTextsCache = [""]
            paragraphRangesCache = [NSRange(location: 0, length: 0)]
        }
    }

    private static func paragraphRanges(in source: NSString) -> [NSRange] {
        guard source.length > 0 else {
            return [NSRange(location: 0, length: 0)]
        }
        var ranges: [NSRange] = []
        var start = 0
        while start < source.length {
            let search = NSRange(location: start, length: source.length - start)
            let newline = source.range(of: "\n", options: [], range: search)
            if newline.location == NSNotFound {
                ranges.append(NSRange(location: start, length: source.length - start))
                return ranges
            }
            ranges.append(NSRange(location: start, length: newline.location - start + 1))
            start = newline.location + 1
        }
        // The document ended with a newline: there is one final empty paragraph.
        ranges.append(NSRange(location: source.length, length: 0))
        return ranges
    }

    private func paragraphIndex(at location: Int) -> Int {
        guard !paragraphRangesCache.isEmpty else { return 0 }
        let length = (string as NSString).length
        let point = min(max(0, location), length)
        var result = 0
        for (index, range) in paragraphRangesCache.enumerated() {
            if point >= range.location {
                result = index
            } else {
                break
            }
        }
        return result
    }

    private func paragraphRange(at index: Int) -> NSRange? {
        guard index >= 0, index < paragraphRangesCache.count else { return nil }
        return paragraphRangesCache[index]
    }

    private func textRange(at index: Int) -> NSRange? {
        guard let range = paragraphRange(at: index) else { return nil }
        var length = range.length
        if length > 0, (string as NSString).character(at: range.location + length - 1) == 10 {
            length -= 1
        }
        return NSRange(location: range.location, length: length)
    }

    private func textForParagraph(_ index: Int) -> String {
        guard index >= 0, index < paragraphTextsCache.count else { return "" }
        return paragraphTextsCache[index]
    }

    private func currentParagraph() -> Int {
        min(paragraphIndex(at: selectedRange().location), max(0, paragraphTypes.count - 1))
    }

    private func displayType(at index: Int) -> ElementType {
        let stored = index < paragraphTypes.count ? paragraphTypes[index] : .action
        guard stored == .new else { return stored }
        let text = textForParagraph(index).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? .action : Formatter.inferType(text)
    }

    private func spacingBefore(at index: Int, type: ElementType) -> CGFloat {
        guard index > 0 else { return 0 }
        if type == .paren || type == .dialogue { return 0 }
        if textForParagraph(index - 1).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return 0
        }
        let size = ScreenplayTypography.size(forWidth: max(backingContainer.size.width, 1))
        // A scene heading gets two lines of air above it: the blank line a
        // screenwriter types, plus the paragraph spacing every block receives.
        if type == .scene { return size * 2 }
        return size
    }

    // MARK: Styling

    private func attributes(for index: Int) -> [NSAttributedString.Key: Any] {
        let type = displayType(at: index)
        let width = max(backingContainer.size.width, 1)
        let size = ScreenplayTypography.size(forWidth: width)
        let stored = index < paragraphTypes.count ? paragraphTypes[index] : .action
        return [
            .font: ScreenplayTypography.font(for: type, size: size),
            .foregroundColor: inkColor,
            .paragraphStyle: ScreenplayTypography.paragraphStyle(
                for: type,
                width: width,
                line: size,
                spacingBefore: spacingBefore(at: index, type: type)
            ),
            .elementType: stored.rawValue
        ]
    }

    private func restyle(paragraphs: IndexSet) {
        guard !paragraphTypes.isEmpty else { return }
        backingStorage.beginEditing()
        for index in paragraphs where index >= 0 && index < paragraphTypes.count {
            guard let range = paragraphRange(at: index) else { continue }
            backingStorage.setAttributes(attributes(for: index), range: range)
        }
        backingStorage.endEditing()
        updateTypingAttributes()
    }

    private func restyleAll() {
        guard !paragraphTypes.isEmpty else { return }
        backingStorage.beginEditing()
        for index in paragraphTypes.indices {
            guard let range = paragraphRange(at: index) else { continue }
            backingStorage.setAttributes(attributes(for: index), range: range)
        }
        backingStorage.endEditing()
        updateTypingAttributes()
    }

    private func updateTypingAttributes() {
        let index = currentParagraph()
        guard index >= 0, index < paragraphTypes.count else { return }
        typingAttributes = attributes(for: index)
    }

    // MARK: Analysis and furniture

    private func refreshAnalysis() {
        guard !paragraphTextsCache.isEmpty else { return }
        var elements: [Element] = []
        elements.reserveCapacity(paragraphTextsCache.count)
        for index in paragraphTextsCache.indices {
            let type = index < paragraphTypes.count ? paragraphTypes[index] : .action
            elements.append(Element(type: type, text: paragraphTextsCache[index]))
        }
        let result = ScriptAnalysis.derive(elements)
        elementsCache = elements
        derived = result

        var marks: [(Int, Int)] = []
        var railSegments: [(Int, Int)] = []
        for (index, element) in elements.enumerated() {
            if element.type == .scene, let number = result.sceneNo[element.id] {
                marks.append((index, number))
            }
            if element.type == .character || element.type == .paren || element.type == .dialogue,
               let speaker = result.speakerOf[element.id],
               let colour = result.colours[speaker] {
                railSegments.append((index, colour))
            }
        }
        sceneMarks = marks
        rails = railSegments
    }

    func firstLineRect(forParagraph index: Int) -> NSRect? {
        guard let range = textRange(at: index) else { return nil }
        backingLayoutManager.ensureLayout(for: backingContainer)
        let glyphRange = backingLayoutManager.glyphRange(forCharacterRange: range,
                                                         actualCharacterRange: nil)
        if glyphRange.length > 0 {
            return backingLayoutManager.lineFragmentRect(forGlyphAt: glyphRange.location,
                                                         effectiveRange: nil)
        }
        if index == paragraphTypes.count - 1,
           backingLayoutManager.extraLineFragmentTextContainer === backingContainer {
            return backingLayoutManager.extraLineFragmentRect
        }
        let length = (string as NSString).length
        if length > 0 {
            let glyph = backingLayoutManager.glyphIndexForCharacter(at: min(range.location, length - 1))
            if backingLayoutManager.numberOfGlyphs > 0 {
                return backingLayoutManager.lineFragmentRect(forGlyphAt: min(glyph, backingLayoutManager.numberOfGlyphs - 1),
                                                             effectiveRange: nil)
            }
        }
        let size = ScreenplayTypography.size(forWidth: max(backingContainer.size.width, 1))
        return NSRect(x: 0, y: 0, width: max(backingContainer.size.width, 1), height: size)
    }

    func paragraphRect(forParagraph index: Int) -> NSRect? {
        guard let range = textRange(at: index) else { return nil }
        backingLayoutManager.ensureLayout(for: backingContainer)
        let glyphRange = backingLayoutManager.glyphRange(forCharacterRange: range,
                                                         actualCharacterRange: nil)
        if glyphRange.length > 0 {
            return backingLayoutManager.boundingRect(forGlyphRange: glyphRange, in: backingContainer)
        }
        return firstLineRect(forParagraph: index)
    }

    func invalidateFurniture() {
        subviews.compactMap { $0 as? PageFurnitureView }.forEach {
            $0.theme = theme
            $0.invalidate()
        }
    }

    /// Apply the document's excerpt numbering. A page/scene offset is only used
    /// by the bundled sample, whose script is a slice of a longer document.
    func applyDocumentNumbering(sceneOffset: Int, pageOffset: Int, pages: Int?) {
        guard sceneNumberOffset != sceneOffset
                || pageNumberOffset != pageOffset
                || declaredPageCount != pages else { return }
        sceneNumberOffset = sceneOffset
        pageNumberOffset = pageOffset
        declaredPageCount = pages
        invalidateFurniture()
        publishPosition()
    }

    var estimatedPageCount: Int {
        let width = max(backingContainer.size.width, 1)
        let metrics = PageMetrics(pageWidth: width)
        backingLayoutManager.ensureLayout(for: backingContainer)
        let used = backingLayoutManager.usedRect(for: backingContainer).height
        let pageHeight = width * 11.0 / 8.5
        let total = used + metrics.topPadding + metrics.bottomPadding
        return max(1, Int(ceil(total / max(pageHeight, 1))))
    }

    // MARK: Change handling

    func textDidChange(_ notification: Notification) {
        guard !isLoading else { return }

        let previousCount = paragraphRangesCache.count
        rebuildParagraphCache()
        let count = paragraphTextsCache.count
        if count != paragraphTypes.count {
            if count < paragraphTypes.count {
                paragraphTypes.removeLast(paragraphTypes.count - count)
            } else {
                let fill = paragraphTypes.last ?? .action
                paragraphTypes.append(contentsOf: Array(repeating: fill, count: count - paragraphTypes.count))
            }
        }

        if count != previousCount {
            // A paste, undo or multi-paragraph edit can introduce paragraphs
            // that never received the `.elementType` attribute.
            restyleAll()
        } else {
            let edited = paragraphIndex(at: backingStorage.editedRange.location)
            var affected = IndexSet(integer: edited)
            if edited > 0 { affected.insert(edited - 1) }
            if edited + 1 < paragraphTypes.count { affected.insert(edited + 1) }
            restyle(paragraphs: affected)
        }

        refreshAnalysis()
        updateTypingAttributes()
        updateGhost()
        updateOverlays()
        invalidateFurniture()
        publishPosition()
        scheduleChange()
        onLayoutNeeded?()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isLoading else { return }
        updateTypingAttributes()
        updateGhost()
        updateOverlays()
        publishPosition()
        reportSelection()
        needsDisplay = true
    }

    func textDidEndEditing(_ notification: Notification) {
        guard !isLoading else { return }
        commitPendingTypes()
        flushChange()
        hideChooser()
        hideTimeMenu()
    }

    private func scheduleChange() {
        changeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.onChange?(self.currentScript)
        }
        changeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    private func flushChange() {
        changeWorkItem?.cancel()
        changeWorkItem = nil
        onChange?(currentScript)
    }

    // MARK: Text mutations

    func textView(_ textView: NSTextView,
                  shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString replacement: String?) -> Bool {
        guard !isLoading, !isApplyingShortcut, !hasMarkedText() else { return true }
        let replacement = replacement ?? ""

        let paragraph = paragraphIndex(at: affectedCharRange.location)
        let type = paragraph < paragraphTypes.count ? paragraphTypes[paragraph] : .action
        let text = textForParagraph(paragraph)

        if !replacement.isEmpty, !replacement.contains("\n") {
            // The chooser's highlighted type wins for the first typed character.
            if type == .new, text.isEmpty, chooserOpen, chooserIndex != 0 {
                paragraphTypes[paragraph] = Formatter.choices[chooserIndex]
                hideChooser()
            }

            // "(" on an empty dialogue line becomes a parenthetical with the
            // caret inside the parentheses.
            if type == .dialogue, text.isEmpty, replacement == "(" {
                replaceParagraph(paragraph, with: "()", type: .paren, caretOffset: 1)
                return false
            }

            // i / e on an empty scene line expand to INT. / EXT.
            if type == .scene, text.isEmpty, replacement.lowercased() == "i" {
                replaceParagraph(paragraph, with: "INT. ", type: .scene, caretOffset: 5)
                return false
            }
            if type == .scene, text.isEmpty, replacement.lowercased() == "e" {
                replaceParagraph(paragraph, with: "EXT. ", type: .scene, caretOffset: 5)
                return false
            }

            // "/" after INT. or EXT. swaps to the combined prefix.
            if type == .scene, replacement == "/" {
                let upper = text.uppercased()
                if upper == "INT. " {
                    replaceParagraph(paragraph, with: "INT./EXT. ", type: .scene, caretOffset: 10)
                    return false
                }
                if upper == "EXT. " {
                    replaceParagraph(paragraph, with: "EXT./INT. ", type: .scene, caretOffset: 10)
                    return false
                }
            }
        }

        updateTypes(for: affectedCharRange, replacement: replacement)
        return true
    }

    private func updateTypes(for range: NSRange, replacement: String) {
        let source = string as NSString
        let oldText = range.length > 0 ? source.substring(with: range) : ""
        let oldNewlines = oldText.filter { $0 == "\n" }.count
        let newNewlines = replacement.filter { $0 == "\n" }.count
        let delta = newNewlines - oldNewlines
        guard delta != 0 else { return }

        let start = paragraphIndex(at: range.location)
        if delta > 0 {
            let base = pendingNewParagraphType
                ?? (start < paragraphTypes.count ? paragraphTypes[start] : .action)
            let insertAt = min(start + 1, paragraphTypes.count)
            paragraphTypes.insert(contentsOf: Array(repeating: base, count: delta), at: insertAt)
        } else {
            let removeCount = -delta
            let removeStart = min(start + 1, paragraphTypes.count)
            let removeEnd = min(removeStart + removeCount, paragraphTypes.count)
            if removeStart < removeEnd {
                paragraphTypes.removeSubrange(removeStart..<removeEnd)
            }
        }
    }

    private func replaceParagraph(_ index: Int,
                                  with newText: String,
                                  type: ElementType,
                                  caretOffset: Int) {
        guard let range = textRange(at: index) else { return }
        if index < paragraphTypes.count {
            paragraphTypes[index] = type
        }
        isApplyingShortcut = true
        replaceCharacters(in: range, with: newText)
        isApplyingShortcut = false
        let location = (paragraphRange(at: index)?.location ?? 0) + min(caretOffset, (newText as NSString).length)
        setSelectedRange(NSRange(location: location, length: 0))
        restyle(paragraphs: IndexSet(integer: index))
        refreshAnalysis()
        updateTypingAttributes()
        updateGhost()
        updateOverlays()
        invalidateFurniture()
        scheduleChange()
    }

    private func uppercaseParagraph(_ index: Int) {
        let text = textForParagraph(index)
        let upper = text.uppercased()
        guard upper != text, let range = textRange(at: index) else { return }
        isApplyingShortcut = true
        replaceCharacters(in: range, with: upper)
        isApplyingShortcut = false
    }

    private func commitPendingTypes() {
        guard !isLoading else { return }
        var changed = false
        for index in paragraphTypes.indices.reversed() {
            let stored = paragraphTypes[index]
            let text = textForParagraph(index)
            if stored == .new, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let inferred = Formatter.inferType(text)
                paragraphTypes[index] = inferred
                changed = true
                if inferred.isUppercase {
                    uppercaseParagraph(index)
                }
            } else if stored.isUppercase {
                uppercaseParagraph(index)
                changed = true
            }
        }
        if changed {
            rebuildParagraphCache()
            restyleAll()
            refreshAnalysis()
            updateTypingAttributes()
            updateGhost()
            updateOverlays()
            invalidateFurniture()
            scheduleChange()
        }
    }

    // MARK: Keyboard

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard isEditable else { return false }

        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            return handleReturn()
        case #selector(NSResponder.insertTab(_:)):
            return handleTab(shift: false)
        case #selector(NSResponder.insertBacktab(_:)):
            return handleTab(shift: true)
        case #selector(NSResponder.deleteBackward(_:)):
            return handleDeleteBackward()
        case #selector(NSResponder.moveUp(_:)):
            return handleMoveUp()
        case #selector(NSResponder.moveDown(_:)):
            return handleMoveDown()
        case #selector(NSResponder.moveRight(_:)):
            if ghost != nil, caretAtEnd {
                acceptGhost()
                return true
            }
            return false
        case #selector(NSResponder.cancelOperation(_:)):
            return handleEscape()
        default:
            return false
        }
    }

    private var caretAtEnd: Bool {
        let range = selectedRange()
        guard range.length == 0 else { return false }
        let paragraph = currentParagraph()
        let start = paragraphRange(at: paragraph)?.location ?? 0
        let offset = range.location - start
        return offset == (textForParagraph(paragraph) as NSString).length
    }

    private func handleReturn() -> Bool {
        guard !hasMarkedText() else { return false }

        if timeMenuOpen {
            commitTimeSelection(advance: true)
            return true
        }

        let paragraph = currentParagraph()
        let range = selectedRange()
        let start = paragraphRange(at: paragraph)?.location ?? 0
        let offset = max(0, range.location - start)
        let text = textForParagraph(paragraph)

        if ghost != nil, range.length == 0, offset == (text as NSString).length {
            acceptGhost()
            return true
        }

        // An empty new line adopts the chooser's type without inserting a line.
        if paragraphTypes[paragraph] == .new,
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            paragraphTypes[paragraph] = Formatter.choices[min(chooserIndex, Formatter.choices.count - 1)]
            chooserIndex = 0
            hideChooser()
            restyle(paragraphs: IndexSet(integer: paragraph))
            refreshAnalysis()
            updateTypingAttributes()
            updateOverlays()
            invalidateFurniture()
            scheduleChange()
            return true
        }

        // A new line with text commits its inferred type first.
        if paragraphTypes[paragraph] == .new {
            let inferred = Formatter.inferType(text)
            paragraphTypes[paragraph] = inferred
            if inferred.isUppercase {
                uppercaseParagraph(paragraph)
            }
        }

        let type = paragraphTypes[paragraph]
        let currentText = textForParagraph(paragraph)
        let currentStart = paragraphRange(at: paragraph)?.location ?? 0
        let currentOffset = max(0, selectedRange().location - currentStart)
        let nsText = currentText as NSString
        let safeOffset = min(currentOffset, nsText.length)
        var before = nsText.substring(to: safeOffset)
        let after = nsText.substring(from: safeOffset)

        // A scene heading ending in "-" offers the time menu.
        if type == .scene,
           currentOffset == nsText.length,
           before.trimmingCharacters(in: .whitespaces).hasSuffix("-"),
           !dismissedTimeTexts.contains(before) {
            showTimeMenu(for: paragraph)
            return true
        }

        // Empty structured lines collapse back to a chooser line.
        if currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           type == .action || type == .dialogue || type == .character {
            paragraphTypes[paragraph] = .new
            chooserIndex = 0
            hideChooser()
            restyle(paragraphs: IndexSet(integer: paragraph))
            refreshAnalysis()
            updateTypingAttributes()
            updateOverlays()
            invalidateFurniture()
            scheduleChange()
            return true
        }

        // Parentheticals auto-close; "()" becomes an empty dialogue line.
        if type == .paren {
            if !before.isEmpty, !before.hasSuffix(")") {
                before += ")"
            }
            if before == "()" {
                replaceParagraph(paragraph, with: "", type: .dialogue, caretOffset: 0)
                return true
            }
            if before != currentText {
                replaceParagraph(paragraph, with: before, type: .paren, caretOffset: before.count)
            }
        }

        _ = after
        let nextType = type.next
        insertNewline(nextType: nextType)
        chooserIndex = 0
        return true
    }

    private func insertNewline(nextType: ElementType) {
        pendingNewParagraphType = nextType
        insertText("\n", replacementRange: selectedRange())
        pendingNewParagraphType = nil
        let location = selectedRange().location
        scrollRangeToVisible(NSRange(location: max(0, location - 1), length: 1))
    }

    private func handleTab(shift: Bool) -> Bool {
        if timeMenuOpen {
            commitTimeSelection(advance: false)
            return true
        }

        if chooserOpen {
            if shift {
                chooserIndex = (chooserIndex - 1 + Formatter.choices.count) % Formatter.choices.count
                chooserView.selected = chooserIndex
            } else {
                acceptChooser()
            }
            return true
        }

        if ghost != nil, caretAtEnd {
            acceptGhost()
            return true
        }

        let paragraph = currentParagraph()
        let type = paragraph < paragraphTypes.count ? paragraphTypes[paragraph] : .action
        let text = textForParagraph(paragraph)

        if type == .action, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            paragraphTypes[paragraph] = .character
            uppercaseParagraph(paragraph)
            restyle(paragraphs: IndexSet(integer: paragraph))
            refreshAnalysis()
            updateTypingAttributes()
            let end = (paragraphRange(at: paragraph)?.location ?? 0) + (textForParagraph(paragraph) as NSString).length
            setSelectedRange(NSRange(location: end, length: 0))
            updateOverlays()
            invalidateFurniture()
            scheduleChange()
            return true
        }

        if type == .new, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let inferred = Formatter.inferType(text)
            if inferred == .action {
                paragraphTypes[paragraph] = .character
                uppercaseParagraph(paragraph)
                restyle(paragraphs: IndexSet(integer: paragraph))
                refreshAnalysis()
                updateTypingAttributes()
                let end = (paragraphRange(at: paragraph)?.location ?? 0) + (textForParagraph(paragraph) as NSString).length
                setSelectedRange(NSRange(location: end, length: 0))
                updateOverlays()
                invalidateFurniture()
                scheduleChange()
                return true
            }
            paragraphTypes[paragraph] = inferred
            restyle(paragraphs: IndexSet(integer: paragraph))
            refreshAnalysis()
            updateTypingAttributes()
            updateOverlays()
            invalidateFurniture()
            scheduleChange()
            return true
        }

        let target = shift ? paragraph - 1 : paragraph + 1
        guard target >= 0, target < paragraphTypes.count,
              let range = paragraphRange(at: target) else {
            return true
        }
        setSelectedRange(NSRange(location: range.location, length: 0))
        scrollRangeToVisible(NSRange(location: range.location, length: 0))
        return true
    }

    private func handleDeleteBackward() -> Bool {
        let selection = selectedRange()
        guard selection.length == 0 else { return false }
        let paragraph = currentParagraph()
        let offset = max(0, selection.location - (paragraphRange(at: paragraph)?.location ?? 0))

        if paragraphTypes[paragraph] == .paren,
           textForParagraph(paragraph) == "()",
           offset == 1 {
            replaceParagraph(paragraph, with: "", type: .dialogue, caretOffset: 0)
            return true
        }

        guard offset == 0, paragraph > 0,
              let previous = paragraphRange(at: paragraph - 1) else {
            return false
        }

        let previousLength = (textForParagraph(paragraph - 1) as NSString).length
        let newlineLocation = NSMaxRange(previous) - 1
        guard newlineLocation >= previous.location else { return false }
        replaceCharacters(in: NSRange(location: newlineLocation, length: 1), with: "")
        setSelectedRange(NSRange(location: previous.location + previousLength, length: 0))
        return true
    }

    private func handleMoveUp() -> Bool {
        if timeMenuOpen {
            timeMenuIndex = (timeMenuIndex - 1 + SceneTime.allCases.count) % SceneTime.allCases.count
            timeView.selected = timeMenuIndex
            return true
        }
        if chooserOpen {
            chooserIndex = (chooserIndex - 1 + Formatter.choices.count) % Formatter.choices.count
            chooserView.selected = chooserIndex
            return true
        }

        let paragraph = currentParagraph()
        let offset = selectedRange().location - (paragraphRange(at: paragraph)?.location ?? 0)
        if selectedRange().length == 0, offset == 0, paragraph > 0,
           let previous = paragraphRange(at: paragraph - 1) {
            let end = previous.location + (textForParagraph(paragraph - 1) as NSString).length
            setSelectedRange(NSRange(location: end, length: 0))
            scrollRangeToVisible(NSRange(location: end, length: 0))
            return true
        }
        return false
    }

    private func handleMoveDown() -> Bool {
        if timeMenuOpen {
            timeMenuIndex = (timeMenuIndex + 1) % SceneTime.allCases.count
            timeView.selected = timeMenuIndex
            return true
        }
        if chooserOpen {
            chooserIndex = (chooserIndex + 1) % Formatter.choices.count
            chooserView.selected = chooserIndex
            return true
        }

        let paragraph = currentParagraph()
        let text = textForParagraph(paragraph)
        let offset = selectedRange().location - (paragraphRange(at: paragraph)?.location ?? 0)
        if selectedRange().length == 0,
           offset == (text as NSString).length,
           paragraph + 1 < paragraphTypes.count,
           let next = paragraphRange(at: paragraph + 1) {
            setSelectedRange(NSRange(location: next.location, length: 0))
            scrollRangeToVisible(NSRange(location: next.location, length: 0))
            return true
        }
        return false
    }

    private func handleEscape() -> Bool {
        if timeMenuOpen {
            if let paragraph = timeMenuParagraph {
                dismissedTimeTexts.insert(textForParagraph(paragraph))
            }
            hideTimeMenu()
            return true
        }
        if chooserOpen {
            let paragraph = currentParagraph()
            if paragraphTypes[paragraph] == .new,
               textForParagraph(paragraph).isEmpty {
                paragraphTypes[paragraph] = .action
                hideChooser()
                restyle(paragraphs: IndexSet(integer: paragraph))
                refreshAnalysis()
                updateTypingAttributes()
                updateOverlays()
                invalidateFurniture()
                scheduleChange()
            } else {
                hideChooser()
            }
            return true
        }
        ghost = nil
        needsDisplay = true
        return false
    }

    // MARK: Ghost and menus

    private func updateGhost() {
        guard isEditable, selectedRange().length == 0 else {
            if ghost != nil {
                ghost = nil
                needsDisplay = true
            }
            return
        }
        let paragraph = currentParagraph()
        let start = paragraphRange(at: paragraph)?.location ?? 0
        let offset = selectedRange().location - start
        let text = textForParagraph(paragraph)
        guard offset == (text as NSString).length else {
            if ghost != nil {
                ghost = nil
                needsDisplay = true
            }
            return
        }

        let line = Element(type: paragraph < paragraphTypes.count ? paragraphTypes[paragraph] : .action,
                           text: text)
        let rules = GhostRules(names: derived.names, places: derived.places)
        let next = rules.suggest(line: line, lines: elementsCache)
        if next != ghost {
            ghost = next
            needsDisplay = true
        }
    }

    private func acceptGhost() {
        guard let ghost else { return }
        let text = ghost.text
        self.ghost = nil
        insertText(text, replacementRange: selectedRange())
        needsDisplay = true
    }

    private func updateOverlays() {
        guard isEditable else {
            hideChooser()
            hideTimeMenu()
            return
        }

        let paragraph = currentParagraph()
        let start = paragraphRange(at: paragraph)?.location ?? 0
        let offset = selectedRange().location - start
        let text = textForParagraph(paragraph)
        let shouldShowChooser = selectedRange().length == 0
            && offset == 0
            && text.isEmpty
            && paragraphTypes[paragraph] == .new

        if shouldShowChooser {
            chooserOpen = true
            chooserIndex = min(max(0, chooserIndex), Formatter.choices.count - 1)
            chooserView.items = Formatter.choices.map { $0.accessibilityName.replacingOccurrences(of: " line", with: "").uppercased() }
            chooserView.selected = chooserIndex
            chooserView.theme = theme
            chooserView.fontSize = ScreenplayTypography.size(forWidth: max(backingContainer.size.width, 1))
            positionChooser(for: paragraph)
            chooserView.show()
        } else {
            hideChooser()
        }

        if timeMenuOpen {
            if timeMenuParagraph != paragraph {
                hideTimeMenu()
            } else {
                positionTimeMenu(for: paragraph)
            }
        }
    }

    private func acceptChooser() {
        let paragraph = currentParagraph()
        guard paragraphTypes[paragraph] == .new else {
            hideChooser()
            return
        }
        paragraphTypes[paragraph] = Formatter.choices[min(chooserIndex, Formatter.choices.count - 1)]
        hideChooser()
        restyle(paragraphs: IndexSet(integer: paragraph))
        refreshAnalysis()
        updateTypingAttributes()
        updateOverlays()
        invalidateFurniture()
        scheduleChange()
    }

    private func positionChooser(for paragraph: Int) {
        guard let line = firstLineRect(forParagraph: paragraph) else { return }
        let width: CGFloat = 104
        let height = CGFloat(Formatter.choices.count) * 22 + 8
        let textLeft = max(backingContainer.size.width, 1) * 0.1765
        var x = textLeft - 14 - width
        if x < 4 {
            x = textLeft + 14
        }
        let y = max(0, line.minY)
        chooserView.frame = NSRect(x: x, y: y, width: width, height: height)
        chooserView.needsDisplay = true
    }

    private func showTimeMenu(for paragraph: Int) {
        let text = textForParagraph(paragraph)
        guard !dismissedTimeTexts.contains(text) else { return }
        timeMenuOpen = true
        timeMenuParagraph = paragraph
        timeMenuIndex = 0
        timeView.items = SceneTime.allCases.map(\.menuLabel)
        timeView.selected = 0
        timeView.theme = theme
        timeView.fontSize = ScreenplayTypography.size(forWidth: max(backingContainer.size.width, 1))
        positionTimeMenu(for: paragraph)
        timeView.show()
    }

    private func positionTimeMenu(for paragraph: Int) {
        guard let line = paragraphRect(forParagraph: paragraph) else { return }
        let width = max(156, max(backingContainer.size.width, 1) * 0.20)
        let height = CGFloat(SceneTime.allCases.count) * 22 + 8
        let x = max(4, max(backingContainer.size.width, 1) * 0.1765)
        var y = line.maxY + 6
        if y + height > bounds.height - 4 {
            y = max(4, line.minY - height - 6)
        }
        timeView.frame = NSRect(x: x, y: y, width: width, height: height)
        timeView.needsDisplay = true
    }

    private func hideChooser() {
        chooserOpen = false
        chooserView.hide()
    }

    private func hideTimeMenu() {
        timeMenuOpen = false
        timeMenuParagraph = nil
        timeView.hide()
    }

    private func commitTimeSelection(advance: Bool) {
        guard timeMenuOpen,
              let paragraph = timeMenuParagraph,
              paragraph >= 0, paragraph < paragraphTypes.count else {
            hideTimeMenu()
            return
        }
        let value = SceneTime.allCases[min(timeMenuIndex, SceneTime.allCases.count - 1)]
        let text = textForParagraph(paragraph)
        let base = text.replacingOccurrences(of: #"\s*-\s*$"#, with: "", options: .regularExpression)
        let newText = "\(base) - \(value.rawValue)"
        hideTimeMenu()
        paragraphTypes[paragraph] = .scene
        replaceParagraph(paragraph, with: newText, type: .scene, caretOffset: newText.count)
        if advance {
            insertNewline(nextType: .action)
        }
    }

    // MARK: Caret, drawing and position

    private func caretRect(for location: Int) -> NSRect {
        backingLayoutManager.ensureLayout(for: backingContainer)
        let length = (string as NSString).length
        let point = min(max(0, location), length)
        if length == 0 {
            if backingLayoutManager.extraLineFragmentTextContainer === backingContainer,
               backingLayoutManager.extraLineFragmentRect.height > 0 {
                return backingLayoutManager.extraLineFragmentRect
            }
            let size = ScreenplayTypography.size(forWidth: max(backingContainer.size.width, 1))
            return NSRect(x: 0, y: 0, width: 2, height: size)
        }
        if point >= length, backingLayoutManager.numberOfGlyphs > 0 {
            let last = backingLayoutManager.boundingRect(
                forGlyphRange: NSRange(location: backingLayoutManager.numberOfGlyphs - 1, length: 1),
                in: backingContainer
            )
            return NSRect(x: last.maxX, y: last.minY, width: 2, height: last.height)
        }
        let glyph = backingLayoutManager.glyphIndexForCharacter(at: min(point, length - 1))
        if glyph < backingLayoutManager.numberOfGlyphs {
            let rect = backingLayoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyph, length: 0),
                in: backingContainer
            )
            if rect.height > 0 { return rect }
        }
        let paragraph = paragraphIndex(at: point)
        if let line = firstLineRect(forParagraph: paragraph) {
            return NSRect(x: line.minX, y: line.minY, width: 2, height: line.height)
        }
        let size = ScreenplayTypography.size(forWidth: max(backingContainer.size.width, 1))
        return NSRect(x: 0, y: 0, width: 2, height: size)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawPlaceholder()
        drawGhost()
    }

    private func drawGhost() {
        guard let ghost, !ghost.text.isEmpty,
              window?.firstResponder === self,
              selectedRange().length == 0 else { return }
        let rect = caretRect(for: selectedRange().location)
        let width = max(backingContainer.size.width, 1)
        let size = ScreenplayTypography.size(forWidth: width)
        let font = Fonts.scriptNS(size, italic: true)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: ink2Color.withAlphaComponent(0.80)
        ]
        let textSize = (ghost.text as NSString).size(withAttributes: attributes)
        (ghost.text as NSString).draw(
            at: NSPoint(x: rect.minX, y: rect.minY + max(0, (rect.height - textSize.height) / 2)),
            withAttributes: attributes
        )
    }

    private func drawPlaceholder() {
        guard isEditable, selectedRange().length == 0 else { return }
        let paragraph = currentParagraph()
        guard paragraph >= 0, paragraph < paragraphTypes.count else { return }
        let text = textForParagraph(paragraph)
        guard text.isEmpty else { return }
        if chooserOpen, paragraphTypes[paragraph] == .new { return }

        let type = displayType(at: paragraph)
        let placeholder: String
        switch type {
        case .scene: placeholder = "I or E"
        case .character: placeholder = "Character"
        case .paren: placeholder = "(parenthetical)"
        case .dialogue: placeholder = "Dialogue"
        case .transition: placeholder = "TRANSITION"
        case .action: placeholder = "Action"
        case .new: placeholder = ""
        }
        guard !placeholder.isEmpty, let line = firstLineRect(forParagraph: paragraph) else { return }

        let width = max(backingContainer.size.width, 1)
        let size = ScreenplayTypography.size(forWidth: width)
        let font = ScreenplayTypography.font(for: type, size: size)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: ink2Color.withAlphaComponent(0.50)
        ]
        (placeholder as NSString).draw(
            at: NSPoint(x: line.minX, y: line.minY + max(0, (line.height - font.ascender + font.descender) / 2)),
            withAttributes: attributes
        )
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var narrow = rect
        narrow.size.width = 1.5
        super.drawInsertionPoint(in: narrow, color: color, turnedOn: flag)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        updateGhost()
        updateOverlays()
        needsDisplay = true
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        commitPendingTypes()
        flushChange()
        hideChooser()
        hideTimeMenu()
        ghost = nil
        return super.resignFirstResponder()
    }

    // MARK: Position

    private func publishPosition() {
        let width = max(backingContainer.size.width, 1)
        let pageHeight = width * 11.0 / 8.5
        let metrics = PageMetrics(pageWidth: width)
        let paragraph = currentParagraph()

        var scene = 0
        if !paragraphTypes.isEmpty {
            for index in 0...min(paragraph, paragraphTypes.count - 1) where paragraphTypes[index] == .scene {
                scene += 1
            }
        }
        scene = max(1, scene + sceneNumberOffset)

        let pages = declaredPageCount ?? estimatedPageCount
        let caret = caretRect(for: selectedRange().location)
        let localPage = max(1, min(estimatedPageCount, Int(floor((caret.minY + metrics.topPadding) / max(pageHeight, 1))) + 1))
        let page = localPage + pageNumberOffset
        let position = EditorPosition(scene: scene, page: page, pages: pages)
        if position != lastPosition {
            lastPosition = position
            onPosition?(position)
        }
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if !menu.items.contains(where: { $0.action == #selector(addNoteFromMenu) }) {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let note = NSMenuItem(title: "Add Note…",
                                  action: #selector(addNoteFromMenu),
                                  keyEquivalent: "")
            note.target = self
            menu.addItem(note)
        }
        return menu
    }

    @objc private func addNoteFromMenu() {
        reportSelection()
        onRequestNote?()
    }
}

// MARK: - Snapshot overlay

/// A hit-test-transparent cross-fade layer used for lamp changes. Text colour
/// cannot be interpolated per glyph by `NSAnimationContext`, so the old
/// appearance is faded over the new one.
private final class SnapshotOverlayView: NSView {
    private let image: NSImage

    init(frame: NSRect, image: NSImage) {
        self.image = image
        super.init(frame: frame)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
