import SwiftUI
import AppKit
import CueKit

// MARK: - Attributed key

private extension NSAttributedString.Key {
    /// Keeps a line's screenplay type attached to its characters so native undo,
    /// paste and IME commits cannot lose it.
    static let demoElementType = NSAttributedString.Key("cue.demo.elementType")
}

// MARK: - SwiftUI wrapper

/// The demo page's editor. One `NSTextView` holds the whole seven-line script;
/// line types live in paragraph styles and an attributed key, never in the text.
struct DemoEditor: NSViewRepresentable {
    let model: DemoModel
    let compact: Bool
    let pageWidth: CGFloat
    let theme: Theme
    let focusToken: Int
    let reduceMotion: Bool

    func makeCoordinator() -> DemoCoordinator {
        DemoCoordinator(model: model)
    }

    func makeNSView(context: Context) -> DemoContainerView {
        let container = context.coordinator.makeContainer()
        context.coordinator.update(
            container: container,
            theme: theme,
            compact: compact,
            pageWidth: pageWidth,
            focusToken: focusToken,
            reduceMotion: reduceMotion
        )
        return container
    }

    func updateNSView(_ nsView: DemoContainerView, context: Context) {
        context.coordinator.update(
            container: nsView,
            theme: theme,
            compact: compact,
            pageWidth: pageWidth,
            focusToken: focusToken,
            reduceMotion: reduceMotion
        )
    }
}

// MARK: - Coordinator

@MainActor
final class DemoCoordinator: NSObject, NSTextViewDelegate {
    let model: DemoModel
    private(set) var textView: DemoTextView!
    private(set) weak var container: DemoContainerView?

    private(set) var theme: Theme = .daylight
    private(set) var compact = false
    private(set) var reduceMotion = false
    private(set) var metrics = PageMetrics(pageWidth: 780)
    private(set) var pageWidth: CGFloat = 780

    private var isApplying = false
    private var hasLoaded = false
    private var lastFocusToken = 0

    init(model: DemoModel) {
        self.model = model
        super.init()
    }

    // MARK: Construction

    func makeContainer() -> DemoContainerView {
        let container = DemoContainerView()
        container.coordinator = self

        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)

        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 780, height: 800)
        )
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 0
        layout.addTextContainer(textContainer)

        let view = DemoTextView(
            frame: NSRect(x: 0, y: 0, width: 780, height: 800),
            textContainer: textContainer
        )
        view.coordinator = self
        view.delegate = self
        configureTextView(view)

        container.editor = view
        container.addSubview(view)
        textView = view
        self.container = container
        return container
    }

    private func configureTextView(_ view: DemoTextView) {
        view.isRichText = false
        view.importsGraphics = false
        view.allowsImageEditing = false
        view.usesFontPanel = false
        view.usesRuler = false
        view.isEditable = true
        view.isSelectable = true
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.autoresizingMask = []
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0

        // The demo is a screenplay, not a word processor: nothing may rewrite
        // the writer's punctuation.
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticTextCompletionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.smartInsertDeleteEnabled = false

        view.setAccessibilityLabel("Script demo")
        view.setAccessibilityRole(.textArea)
        view.setAccessibilityHelp("A screenplay page demo. Press Control-Tab to leave.")
    }

    // MARK: SwiftUI → AppKit

    func update(
        container: DemoContainerView,
        theme: Theme,
        compact: Bool,
        pageWidth: CGFloat,
        focusToken: Int,
        reduceMotion: Bool
    ) {
        self.theme = theme
        self.compact = compact
        self.reduceMotion = reduceMotion
        self.pageWidth = pageWidth > 0 ? pageWidth : 780
        self.metrics = PageMetrics(pageWidth: self.pageWidth)

        container.pageWidth = self.pageWidth
        container.compact = compact
        container.reduceMotion = reduceMotion
        container.coordinator = self

        applyAppearance()
        syncFromModel(selectCaret: false)
        applyStyles()
        container.syncMenus()
        textView?.needsDisplay = true

        if focusToken != lastFocusToken {
            lastFocusToken = focusToken
            DispatchQueue.main.async { [weak self] in
                self?.focusCaret()
            }
        }
    }

    private func applyAppearance() {
        guard let textView else { return }
        textView.insertionPointColor = theme.nsInk
        textView.textColor = theme.nsInk
        textView.selectedTextAttributes = [
            .backgroundColor: theme.nsSelection,
            .foregroundColor: theme.nsInk
        ]
        textView.setAccessibilityHelp("Script demo. Press Control-Tab to leave.")
    }

    // MARK: Text synchronisation

    private var modelString: String {
        model.lines.map(\.text).joined(separator: "\n") + "\n"
    }

    func syncFromModel(selectCaret: Bool) {
        guard let textView, let storage = textView.textStorage else { return }
        // A live composition owns the storage; rewriting it would cancel the IME.
        guard !textView.hasMarkedText() else { return }
        let wanted = modelString

        if storage.string != wanted {
            let location = globalLocation(line: model.caret.line, offset: model.caret.offset)
            if !hasLoaded {
                storage.setAttributedString(NSAttributedString(string: wanted))
                hasLoaded = true
                let clamped = min(location, max(storage.length - 1, 0))
                textView.setSelectedRange(NSRange(location: clamped, length: 0))
            } else {
                applyEdit(
                    range: NSRange(location: 0, length: storage.length),
                    replacement: wanted,
                    selection: NSRange(location: location, length: 0)
                )
            }
        }

        applyStyles()

        if selectCaret {
            let location = globalLocation(line: model.caret.line, offset: model.caret.offset)
            let clamped = min(location, max(storage.length - 1, 0))
            textView.setSelectedRange(NSRange(location: clamped, length: 0))
        }

        textView.needsDisplay = true
        container?.syncMenus()
    }

    func applyStyles() {
        guard let textView, let storage = textView.textStorage else { return }
        guard !textView.hasMarkedText() else { return }
        storage.beginEditing()
        var location = 0
        for (index, line) in model.lines.enumerated() {
            let length = line.text.demoUTF16Count
            let range = NSRange(location: location, length: length + 1)
            if NSMaxRange(range) <= storage.length {
                let type = model.displayType(for: index)
                let preview = isPreview(index)
                storage.setAttributes(attributes(for: type, first: index == 0, preview: preview),
                                      range: range)
            }
            location += length + 1
        }
        storage.endEditing()
        updateTypingAttributes()
    }

    private func isPreview(_ index: Int) -> Bool {
        guard model.lines.indices.contains(index) else { return false }
        let line = model.lines[index]
        return line.type == .new
            && line.text.isEmpty
            && model.pageIsFocused
            && model.caret.line == index
            && model.menu != .time
    }

    private func attributes(for type: ElementType, first: Bool, preview: Bool) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = leftInset(for: type)
        paragraph.headIndent = leftInset(for: type)
        paragraph.tailIndent = -rightInset(for: type)
        paragraph.minimumLineHeight = metrics.line
        paragraph.maximumLineHeight = metrics.line
        paragraph.lineSpacing = 0
        paragraph.paragraphSpacing = 0
        paragraph.paragraphSpacingBefore = preview
            ? (first ? 0 : metrics.line)
            : paragraphSpacingBefore(for: type, first: first)
        paragraph.alignment = type == .transition ? .right : .left
        paragraph.lineBreakMode = .byWordWrapping

        let bold = type == .scene && !preview
        return [
            .font: Fonts.scriptNS(metrics.scriptSize, bold: bold),
            .foregroundColor: theme.nsInk,
            .paragraphStyle: paragraph,
            .demoElementType: type.rawValue
        ]
    }

    private func paragraphSpacingBefore(for type: ElementType, first: Bool) -> CGFloat {
        if first { return 0 }
        if type == .paren || type == .dialogue { return 0 }
        if type == .scene { return metrics.line * 2 }
        return metrics.line
    }

    private func updateTypingAttributes() {
        guard let textView, model.lines.indices.contains(model.caret.line) else { return }
        let type = model.displayType(for: model.caret.line)
        textView.typingAttributes = attributes(
            for: type,
            first: model.caret.line == 0,
            preview: isPreview(model.caret.line)
        )
    }

    // MARK: Geometry helpers

    private func leftInset(for type: ElementType) -> CGFloat {
        let fraction: CGFloat
        switch type {
        case .character: fraction = compact ? 0.38 : 0.435
        case .paren: fraction = compact ? 0.30 : 0.365
        case .dialogue: fraction = compact ? 0.22 : 0.294
        case .scene, .action, .transition, .new: fraction = compact ? 0.13 : 0.1765
        }
        return pageWidth * fraction
    }

    private func rightInset(for type: ElementType) -> CGFloat {
        let fraction: CGFloat
        switch type {
        case .paren: fraction = compact ? 0.14 : 0.30
        case .dialogue: fraction = compact ? 0.10 : 0.294
        case .scene, .action, .character, .transition, .new: fraction = compact ? 0.05 : 0.1176
        }
        return pageWidth * fraction
    }

    private func lineStart(_ index: Int) -> Int {
        guard !model.lines.isEmpty else { return 0 }
        var location = 0
        for i in 0..<min(max(index, 0), model.lines.count) {
            location += model.lines[i].text.demoUTF16Count + 1
        }
        return location
    }

    func globalLocation(line: Int, offset: Int) -> Int {
        guard !model.lines.isEmpty else { return 0 }
        let index = min(max(line, 0), model.lines.count - 1)
        let local = min(max(offset, 0), model.lines[index].text.demoUTF16Count)
        return lineStart(index) + local
    }

    private func lineAndOffset(for location: Int, in lines: [Element]) -> (Int, Int) {
        guard !lines.isEmpty else { return (0, 0) }
        var start = 0
        for (index, line) in lines.enumerated() {
            let end = start + line.text.demoUTF16Count
            if location <= end {
                return (index, max(0, location - start))
            }
            start = end + 1
        }
        let last = lines.count - 1
        return (last, lines[last].text.demoUTF16Count)
    }

    func lineAndOffset(for location: Int) -> (Int, Int) {
        lineAndOffset(for: location, in: model.lines)
    }

    func fragmentRect(forLine index: Int, in view: DemoTextView) -> NSRect? {
        guard let layout = view.layoutManager,
              let container = view.textContainer,
              let storage = view.textStorage,
              storage.length > 0,
              model.lines.indices.contains(index) else { return nil }
        layout.ensureLayout(for: container)
        let start = min(lineStart(index), storage.length - 1)
        let glyph = layout.glyphIndexForCharacter(at: start)
        var effective = NSRange()
        let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &effective)
        let origin = view.textContainerOrigin
        return NSRect(
            x: rect.minX + origin.x,
            y: rect.minY + origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    // MARK: Editing

    private func applyEdit(range: NSRange, replacement: String, selection: NSRange) {
        guard let textView, let storage = textView.textStorage else { return }
        let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        isApplying = true
        defer { isApplying = false }
        if textView.shouldChangeText(in: safeRange, replacementString: replacement) {
            storage.replaceCharacters(in: safeRange, with: replacement)
            textView.didChangeText()
        }
        let clamped = min(max(selection.location, 0), max(storage.length - 1, 0))
        textView.setSelectedRange(NSRange(location: clamped, length: 0))
    }

    private func crossesLineBreak(_ range: NSRange) -> Bool {
        guard let storage = textView.textStorage, range.length > 0 else { return false }
        let string = storage.string as NSString
        let safe = NSIntersectionRange(range, NSRange(location: 0, length: string.length))
        return string.range(of: "\n", options: [], range: safe).location != NSNotFound
    }

    func handleInsert(_ string: String, replacementRange: NSRange) {
        guard let textView, let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        var range = replacementRange
        if range.location == NSNotFound { range = selection }
        range.location = min(max(range.location, 0), storage.length)
        range.length = min(max(range.length, 0), storage.length - range.location)

        // The final separator is structural: it gives the last line a fragment.
        // Never consume it while replacing text.
        if storage.string.hasSuffix("\n"), range.length > 0,
           NSMaxRange(range) == storage.length {
            range.length -= 1
        }

        let cleaned = string.replacingOccurrences(of: "\n", with: "")
        guard !cleaned.isEmpty || range.length > 0 else { return }

        if crossesLineBreak(range) {
            let location = range.location
            let after = NSRange(location: location + cleaned.demoUTF16Count, length: 0)
            applyEdit(range: range, replacement: cleaned, selection: after)
            parseAndUpdate(selection: after)
            return
        }

        let (lineIndex, _) = lineAndOffset(for: range.location)
        guard model.lines.indices.contains(lineIndex) else { return }
        let start = lineStart(lineIndex)
        let oldLength = model.lines[lineIndex].text.demoUTF16Count
        let oldText = (storage.string as NSString).substring(
            with: NSRange(location: start, length: oldLength)
        )
        let localStart = max(range.location - start, 0)
        let local = NSRange(
            location: localStart,
            length: min(range.length, max(oldLength - localStart, 0))
        )
        let raw = (oldText as NSString).replacingCharacters(in: local, with: cleaned)
        let result = model.retype(lineIndex: lineIndex, oldText: oldText, rawText: raw)

        let selectionAfter: NSRange
        if result.text == raw, !cleaned.isEmpty {
            selectionAfter = NSRange(
                location: range.location + cleaned.demoUTF16Count,
                length: 0
            )
            applyEdit(range: range, replacement: cleaned, selection: selectionAfter)
        } else {
            let offset = result.caretOffset ?? (local.location + cleaned.demoUTF16Count)
            let clamped = min(max(offset, 0), result.text.demoUTF16Count)
            selectionAfter = NSRange(location: start + clamped, length: 0)
            applyEdit(
                range: NSRange(location: start, length: oldLength),
                replacement: result.text,
                selection: selectionAfter
            )
        }

        parseAndUpdate(selection: selectionAfter,
                       overrideLine: lineIndex,
                       overrideType: result.type)
    }

    private func parseAndUpdate(
        selection: NSRange,
        overrideLine: Int? = nil,
        overrideType: ElementType? = nil
    ) {
        guard let textView else { return }
        var (lines, caret, empty) = parseStorage(caretRange: selection)
        if let overrideLine, let overrideType, lines.indices.contains(overrideLine) {
            lines[overrideLine].type = overrideType
        }
        model.setEditing(
            lines: lines,
            caret: caret,
            focused: textView.window?.firstResponder === textView,
            selectionIsEmpty: empty
        )
        applyStyles()
        container?.syncMenus()
        textView.needsDisplay = true
    }

    private func parseStorage(caretRange: NSRange) -> ([Element], DemoCaret, Bool) {
        guard let storage = textView.textStorage else {
            return (model.lines, model.caret, true)
        }
        let raw = storage.string
        var parts = raw.components(separatedBy: "\n")
        // The storage always ends in the separator that gives the last line a
        // fragment. Drop the phantom paragraph it creates.
        if parts.last == "" { parts.removeLast() }
        if parts.isEmpty { parts = [""] }

        var lines: [Element] = []
        var location = 0
        for (index, text) in parts.enumerated() {
            var type: ElementType?
            if storage.length > 0 {
                let at = min(location, storage.length - 1)
                if let rawType = storage.attribute(.demoElementType, at: at, effectiveRange: nil) as? String {
                    type = ElementType(rawValue: rawType)
                }
            }
            if type == nil, model.lines.indices.contains(index) {
                type = model.lines[index].type
            }
            if type == nil {
                type = text.isEmpty ? .new : Formatter.inferType(text)
            }
            let id = model.lines.indices.contains(index) ? model.lines[index].id : UUID()
            lines.append(Element(id: id, type: type ?? .new, text: text))
            location += text.demoUTF16Count + 1
        }

        let (line, offset) = lineAndOffset(for: caretRange.location, in: lines)
        return (lines, DemoCaret(line: line, offset: offset), caretRange.length == 0)
    }

    // MARK: Keys

    func handleTab(shift: Bool) -> Bool {
        if model.isTimeMenuOpen {
            let time = SceneTime.allCases[model.timeIndex]
            model.chooseTime(time, keepCaret: true)
            syncFromModel(selectCaret: true)
            return true
        }
        if model.ghost != nil {
            model.acceptGhost()
            syncFromModel(selectCaret: true)
            return true
        }
        if model.currentType == .new, model.currentLine?.text.isEmpty == true {
            model.cycleChooser(forward: !shift)
            applyStyles()
            container?.syncMenus()
            return true
        }
        if !shift, model.currentType == .action {
            model.promoteAction()
            syncFromModel(selectCaret: true)
            return true
        }
        // Every Tab is consumed while the page has focus; Control-Tab is the
        // explicit escape.
        return true
    }

    func handleReturn() -> Bool {
        if model.isTimeMenuOpen {
            let time = SceneTime.allCases[model.timeIndex]
            model.chooseTime(time, keepCaret: false)
            syncFromModel(selectCaret: true)
            return true
        }
        if model.ghost != nil {
            model.acceptGhost()
            syncFromModel(selectCaret: true)
            return true
        }
        model.enter()
        syncFromModel(selectCaret: true)
        return true
    }

    func handleEscape() -> Bool {
        model.escape()
        syncFromModel(selectCaret: true)
        return true
    }

    func handleBackspace() -> Bool {
        // Only a collapsed caret may merge lines or collapse `()`; a selection
        // must be deleted by AppKit.
        guard textView?.selectedRange().length == 0 else { return false }
        if model.backspaceCollapseOrMerge() {
            syncFromModel(selectCaret: true)
            return true
        }
        return false
    }

    func handleArrow(_ keyCode: UInt16, shift: Bool) -> Bool {
        guard let textView else { return false }

        if model.isTimeMenuOpen, keyCode == 125 || keyCode == 126 {
            model.cycleTime(forward: keyCode == 125)
            container?.syncMenus()
            return true
        }

        if model.isChooserOpen, keyCode == 125 || keyCode == 126 {
            model.cycleChooser(forward: keyCode == 125)
            applyStyles()
            container?.syncMenus()
            return true
        }

        let selection = textView.selectedRange()
        if keyCode == 124, selection.length == 0, model.ghost != nil {
            model.acceptGhost()
            syncFromModel(selectCaret: true)
            return true
        }

        guard selection.length == 0, model.lines.indices.contains(model.caret.line) else {
            return false
        }

        let line = model.caret.line
        let lineLength = model.lines[line].text.demoUTF16Count
        if keyCode == 126, selection.location == globalLocation(line: line, offset: 0), line > 0 {
            let previous = line - 1
            let offset = model.lines[previous].text.demoUTF16Count
            setSelection(line: previous, offset: offset)
            model.updateCaret(line: previous, offset: offset,
                              selectionIsEmpty: true,
                              focused: textView.window?.firstResponder === textView)
            container?.syncMenus()
            return true
        }
        if keyCode == 125, selection.location == globalLocation(line: line, offset: lineLength),
           line < model.lines.count - 1 {
            let next = line + 1
            setSelection(line: next, offset: 0)
            model.updateCaret(line: next, offset: 0,
                              selectionIsEmpty: true,
                              focused: textView.window?.firstResponder === textView)
            container?.syncMenus()
            return true
        }

        return false
    }

    func leaveDemo() {
        textView?.window?.makeFirstResponder(nil)
    }

    // MARK: Focus

    func focusLastLine() {
        guard let textView else { return }
        let last = max(model.lines.count - 1, 0)
        let offset = model.lines.indices.contains(last)
            ? model.lines[last].text.demoUTF16Count
            : 0
        textView.window?.makeFirstResponder(textView)
        setSelection(line: last, offset: offset)
        model.focus(line: last, offset: offset)
        applyStyles()
        container?.syncMenus()
        textView.needsDisplay = true
    }

    func focusCaret() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        setSelection(line: model.caret.line, offset: model.caret.offset)
        model.focus(line: model.caret.line, offset: model.caret.offset)
        applyStyles()
        container?.syncMenus()
        textView.needsDisplay = true
    }

    func setSelection(line: Int, offset: Int) {
        guard let textView else { return }
        let location = globalLocation(line: line, offset: offset)
        let clamped = min(location, max((textView.textStorage?.length ?? 1) - 1, 0))
        textView.setSelectedRange(NSRange(location: clamped, length: 0))
    }

    // MARK: Menus

    func commitChoice(_ index: Int) {
        model.commitChoice(index)
        textView?.window?.makeFirstResponder(textView)
        syncFromModel(selectCaret: true)
        applyStyles()
        container?.syncMenus()
    }

    func hoverChoice(_ index: Int) {
        model.setChooserIndex(index)
        container?.syncMenus()
    }

    func commitTime(_ index: Int) {
        let times = SceneTime.allCases
        guard times.indices.contains(index) else { return }
        model.chooseTime(times[index], keepCaret: false)
        textView?.window?.makeFirstResponder(textView)
        syncFromModel(selectCaret: true)
        container?.syncMenus()
    }

    // MARK: NSTextViewDelegate

    /// Every native mutation (delete, cut, drag, IME, undo) passes through here.
    /// The storage must always end in a paragraph separator, so an edit that
    /// would swallow it is replayed with the separator kept.
    func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        guard !isApplying, let storage = textView.textStorage else { return true }
        let string = storage.string
        let replacement = replacementString ?? ""
        guard string.hasSuffix("\n"),
              NSMaxRange(affectedCharRange) == storage.length,
              !replacement.hasSuffix("\n") else { return true }

        var range = affectedCharRange
        var text = replacement
        if text.isEmpty {
            range.length = max(range.length - 1, 0)
            if range.length == 0 { return false }   // deleting only the separator
        } else {
            text += "\n"
        }

        let selection = NSRange(
            location: range.location + replacement.demoUTF16Count,
            length: 0
        )
        applyEdit(range: range, replacement: text, selection: selection)
        parseAndUpdate(selection: selection)
        return false
    }

    func textDidBeginEditing(_ notification: Notification) {
        guard let textView else { return }
        let (line, offset) = lineAndOffset(for: textView.selectedRange().location)
        model.focus(line: line, offset: offset)
        applyStyles()
        container?.syncMenus()
    }

    func textDidEndEditing(_ notification: Notification) {
        model.setFocused(false)
        applyStyles()
        container?.syncMenus()
        textView?.needsDisplay = true
    }

    func textDidChange(_ notification: Notification) {
        guard !isApplying, let textView else { return }
        let range = textView.selectedRange()
        let (lines, caret, empty) = parseStorage(caretRange: range)
        model.setEditing(
            lines: lines,
            caret: caret,
            focused: textView.window?.firstResponder === textView,
            selectionIsEmpty: empty
        )
        applyStyles()
        container?.syncMenus()
        textView.needsDisplay = true

        let wanted = globalLocation(line: caret.line, offset: caret.offset)
        if wanted != range.location {
            textView.setSelectedRange(NSRange(location: wanted, length: 0))
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplying, let textView else { return }
        var range = textView.selectedRange()
        let last = max(model.lines.count - 1, 0)
        let maxLocation = globalLocation(
            line: last,
            offset: model.lines.indices.contains(last) ? model.lines[last].text.demoUTF16Count : 0
        )
        if range.location > maxLocation {
            range = NSRange(location: maxLocation, length: 0)
            textView.setSelectedRange(range)
        }
        let (line, offset) = lineAndOffset(for: range.location)
        model.updateCaret(
            line: line,
            offset: offset,
            selectionIsEmpty: range.length == 0,
            focused: textView.window?.firstResponder === textView
        )
        container?.syncMenus()
        textView.needsDisplay = true
    }

    // MARK: Drawing

    func drawBackdrop(in view: DemoTextView) {
        guard let layout = view.layoutManager, let container = view.textContainer else { return }
        layout.ensureLayout(for: container)
        let origin = view.textContainerOrigin

        for (index, line) in model.lines.enumerated() {
            guard let fragment = fragmentRect(forLine: index, in: view) else { continue }

            if let speaker = model.derived.speakerOf[line.id],
               let colourIndex = model.derived.colours[speaker] {
                let colour = NSColor(
                    hex: Hex.characters[colourIndex % Hex.characters.count],
                    opacity: 0.9
                )
                colour.setFill()
                let x = origin.x + pageWidth * (compact ? 0.10 : 0.1447)
                let rail = NSRect(x: x, y: fragment.minY, width: 2, height: fragment.height)
                NSBezierPath(roundedRect: rail, xRadius: 1, yRadius: 1).fill()
            }

            if let number = model.derived.sceneNo[line.id] {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: Fonts.scriptNS(metrics.scriptSize * 0.85),
                    .foregroundColor: theme.nsInk2
                ]
                let string = NSAttributedString(string: "\(number)", attributes: attributes)
                let x = origin.x + pageWidth * (compact ? 0.04 : 0.10)
                string.draw(at: NSPoint(x: x, y: fragment.minY))
            }
        }
    }

    func drawOverlay(in view: DemoTextView) {
        guard let layout = view.layoutManager, let container = view.textContainer else { return }
        layout.ensureLayout(for: container)
        let origin = view.textContainerOrigin

        // Placeholders belong to a line, not to the caret: the last line keeps
        // its invitation while focus sits elsewhere on the page.
        for index in model.lines.indices {
            guard let placeholder = model.placeholder(for: index), !placeholder.isEmpty,
                  let fragment = fragmentRect(forLine: index, in: view) else { continue }
            let type = model.displayType(for: index)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: Fonts.scriptNS(metrics.scriptSize),
                .foregroundColor: theme.nsInk2.withAlphaComponent(0.5)
            ]
            let string = NSAttributedString(string: placeholder, attributes: attributes)
            let size = string.size()
            var x = origin.x + leftInset(for: type)
            if type == .transition {
                x = origin.x + pageWidth - rightInset(for: type) - size.width
            }
            let y = fragment.minY + (fragment.height - size.height) / 2
            string.draw(at: NSPoint(x: x, y: y))
        }

        let index = model.caret.line
        guard model.lines.indices.contains(index),
              let ghost = model.ghost, !ghost.text.isEmpty,
              let fragment = fragmentRect(forLine: index, in: view) else { return }
        let type = model.displayType(for: index)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Fonts.scriptNS(metrics.scriptSize, bold: type == .scene),
            .foregroundColor: theme.nsInk2.withAlphaComponent(0.55)
        ]
        let string = NSAttributedString(string: ghost.text, attributes: attributes)
        let size = string.size()
        let y = fragment.minY + (fragment.height - size.height) / 2
        string.draw(at: NSPoint(x: textEndX(for: index, in: view), y: y))
    }

    private func textEndX(for index: Int, in view: DemoTextView) -> CGFloat {
        guard let layout = view.layoutManager,
              model.lines.indices.contains(index) else { return 0 }
        let length = model.lines[index].text.demoUTF16Count
        guard length > 0 else {
            return view.textContainerOrigin.x + leftInset(for: model.displayType(for: index))
        }
        let last = lineStart(index) + length - 1
        let glyph = layout.glyphIndexForCharacter(at: last)
        var effective = NSRange()
        let used = layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: &effective)
        return used.maxX + view.textContainerOrigin.x
    }
}

// MARK: - Container

final class DemoContainerView: NSView {
    weak var coordinator: DemoCoordinator?
    var editor: DemoTextView?

    var pageWidth: CGFloat = 780
    var compact = false
    var reduceMotion = false

    let chooserView = ChooserView()
    let timeMenuView = TimeMenuView()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        chooserView.isHidden = true
        timeMenuView.isHidden = true
        addSubview(chooserView)
        addSubview(timeMenuView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        if bounds.width > 0 {
            pageWidth = bounds.width
        }
        guard let editor else { return }
        let metrics = PageMetrics(pageWidth: pageWidth)
        editor.frame = NSRect(
            x: 0,
            y: metrics.topPadding,
            width: pageWidth,
            height: max(bounds.height - metrics.topPadding - metrics.bottomPadding, 0)
        )
        editor.textContainer?.containerSize = NSSize(
            width: editor.bounds.width,
            height: editor.bounds.height
        )
        positionMenus()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .iBeam)
    }

    override func mouseDown(with event: NSEvent) {
        coordinator?.focusLastLine()
    }

    func syncMenus() {
        guard let coordinator, let textView = coordinator.textView else { return }

        let chooserVisible = coordinator.model.isChooserOpen
        let timeVisible = coordinator.model.isTimeMenuOpen
        let chooserWasHidden = chooserView.isHidden
        let timeWasHidden = timeMenuView.isHidden

        chooserView.isHidden = !chooserVisible
        timeMenuView.isHidden = !timeVisible

        if chooserVisible {
            chooserView.configure(
                model: coordinator.model,
                theme: coordinator.theme,
                metrics: coordinator.metrics,
                compact: compact,
                onCommit: { [weak coordinator] index in coordinator?.commitChoice(index) },
                onHover: { [weak coordinator] index in coordinator?.hoverChoice(index) }
            )
        }

        if timeVisible {
            timeMenuView.configure(
                model: coordinator.model,
                theme: coordinator.theme,
                metrics: coordinator.metrics,
                onChoose: { [weak coordinator] index in coordinator?.commitTime(index) }
            )
        }

        positionMenus()

        if chooserVisible, chooserWasHidden {
            animateIn(chooserView)
        }
        if timeVisible, timeWasHidden {
            animateIn(timeMenuView)
        }

        textView.needsDisplay = true
    }

    private func positionMenus() {
        guard let coordinator, let textView = coordinator.textView else { return }
        let line = coordinator.model.caret.line
        guard let fragment = coordinator.fragmentRect(forLine: line, in: textView) else { return }
        let top = textView.frame.minY + fragment.minY
        let bottom = textView.frame.minY + fragment.maxY

        if !chooserView.isHidden {
            if compact {
                let left = pageWidth * 0.13
                let available = max(pageWidth - left - 8, 40)
                let size = chooserView.measure(compact: true, availableWidth: available)
                chooserView.frame = NSRect(
                    x: left,
                    y: bottom + 4,
                    width: available,
                    height: size.height
                )
            } else {
                let size = chooserView.measure(compact: false, availableWidth: pageWidth)
                let right = pageWidth * 0.1765 - 14
                chooserView.frame = NSRect(
                    x: right - size.width,
                    y: top,
                    width: size.width,
                    height: size.height
                )
            }
            chooserView.needsLayout = true
        }

        if !timeMenuView.isHidden {
            let size = timeMenuView.measure(metrics: coordinator.metrics)
            let left = pageWidth * (compact ? 0.13 : 0.1765)
            timeMenuView.frame = NSRect(
                x: left,
                y: bottom + 6,
                width: size.width,
                height: size.height
            )
            timeMenuView.needsLayout = true
        }
    }

    private func animateIn(_ view: NSView) {
        guard !reduceMotion else {
            view.alphaValue = 1
            return
        }
        view.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            view.animator().alphaValue = 1
        }
    }
}

// MARK: - Text view

final class DemoTextView: NSTextView {
    weak var coordinator: DemoCoordinator?

    override func draw(_ dirtyRect: NSRect) {
        coordinator?.drawBackdrop(in: self)
        super.draw(dirtyRect)
        coordinator?.drawOverlay(in: self)
    }

    override func keyDown(with event: NSEvent) {
        guard let coordinator else {
            super.keyDown(with: event)
            return
        }

        if event.modifierFlags.contains(.control), event.keyCode == 48 {
            coordinator.leaveDemo()
            return
        }

        // Let the input method finish a composition before the demo's own
        // Return, Tab, Escape and arrow behaviour runs.
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 48:
            if coordinator.handleTab(shift: shift) { return }
        case 36, 76:
            if coordinator.handleReturn() { return }
        case 53:
            if coordinator.handleEscape() { return }
        case 123, 124, 125, 126:
            if coordinator.handleArrow(event.keyCode, shift: shift) { return }
        default:
            break
        }
        super.keyDown(with: event)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard let coordinator, !hasMarkedText(), let string = insertString as? String else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }
        coordinator.handleInsert(string, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        if coordinator?.handleBackspace() == true { return }
        super.deleteBackward(sender)
    }

    override func paste(_ sender: Any?) {
        guard let coordinator,
              let string = NSPasteboard.general.string(forType: .string) else {
            super.paste(sender)
            return
        }
        coordinator.handleInsert(string, replacementRange: selectedRange())
    }

    override func mouseDown(with event: NSEvent) {
        if let coordinator,
           let last = coordinator.fragmentRect(
               forLine: max(coordinator.model.lines.count - 1, 0),
               in: self
           ) {
            let point = convert(event.locationInWindow, from: nil)
            if point.y > last.maxY + 2 {
                coordinator.focusLastLine()
                return
            }
        }
        super.mouseDown(with: event)
    }
}

// MARK: - Menu button

final class MenuHitButton: NSButton {
    var label = NSAttributedString()
    var labelText = ""
    var selected = false
    var fillColor: NSColor?
    var textAlignment: NSTextAlignment = .left
    var optionWidth: CGFloat = 0
    var onPress: (() -> Void)?
    var onHover: (() -> Void)?

    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .regularSquare
        refusesFirstResponder = true
        focusRingType = .none
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(
        label: NSAttributedString,
        labelText: String,
        selected: Bool,
        alignment: NSTextAlignment,
        fill: NSColor?
    ) {
        self.label = label
        self.labelText = labelText
        self.selected = selected
        self.textAlignment = alignment
        self.fillColor = fill
        optionWidth = ceil(label.size().width) + 1
        setAccessibilityLabel(labelText)
        setAccessibilitySelected(selected)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if selected, let fillColor {
            fillColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        }
        let size = label.size()
        let x: CGFloat
        switch textAlignment {
        case .right: x = bounds.width - size.width
        case .center: x = (bounds.width - size.width) / 2
        default: x = 0
        }
        let y = (bounds.height - size.height) / 2
        label.draw(at: NSPoint(x: x, y: y))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?()
    }

    override func mouseDown(with event: NSEvent) {
        onPress?()
    }
}

// MARK: - Chooser

final class ChooserView: NSView {
    private var buttons: [MenuHitButton] = []
    private let hint = NSTextField(frame: .zero)
    private var compact = false
    private var optionHeight: CGFloat = 14
    private var hintHeight: CGFloat = 24
    private var optionWidths: [CGFloat] = []
    private var hintWidth: CGFloat = 0

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.list)
        setAccessibilityLabel("What comes next")

        for _ in 0..<Formatter.choices.count {
            let button = MenuHitButton(frame: .zero)
            buttons.append(button)
            addSubview(button)
        }

        hint.isEditable = false
        hint.isBordered = false
        hint.drawsBackground = false
        hint.isSelectable = false
        hint.focusRingType = .none
        hint.alignment = .right
        hint.maximumNumberOfLines = 2
        hint.lineBreakMode = .byWordWrapping
        hint.cell?.wraps = true
        hint.cell?.isScrollable = false
        addSubview(hint)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Menu chrome swallows clicks so they cannot reach the page and focus the
    /// last line.
    override func mouseDown(with event: NSEvent) {}

    func configure(
        model: DemoModel,
        theme: Theme,
        metrics: PageMetrics,
        compact: Bool,
        onCommit: @escaping (Int) -> Void,
        onHover: @escaping (Int) -> Void
    ) {
        self.compact = compact
        let size = max(10, metrics.scriptSize * 0.68)
        optionHeight = ceil(size * 1.35)
        let tracking = size * 0.08

        optionWidths = []
        for (index, button) in buttons.enumerated() {
            let type = Formatter.choices[index]
            let isSelected = index == model.chooserIndex
            let title = type.rawValue.uppercased() + (isSelected ? " •" : "")
            let font = Fonts.uiNS(size, weight: isSelected ? .semibold : .regular)
            let colour = isSelected
                ? NSColor(hex: Hex.choice)
                : theme.nsInk2.withAlphaComponent(0.75)
            let attributed = NSAttributedString(
                string: title,
                attributes: [
                    .font: font,
                    .foregroundColor: colour,
                    .kern: tracking
                ]
            )
            button.apply(
                label: attributed,
                labelText: type.rawValue.capitalized,
                selected: isSelected,
                alignment: compact ? .left : .right,
                fill: nil
            )
            button.onPress = { onCommit(index) }
            button.onHover = { onHover(index) }
            optionWidths.append(button.optionWidth)
        }

        let hintSize = size * 0.85
        let hintFont = Fonts.uiNS(hintSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.minimumLineHeight = hintSize * 1.35
        paragraph.maximumLineHeight = hintSize * 1.35
        let hintText = "⏎ choose · ⇥ next\nor just type"
        hint.attributedStringValue = NSAttributedString(
            string: hintText,
            attributes: [
                .font: hintFont,
                .foregroundColor: theme.nsInk2.withAlphaComponent(0.6),
                .paragraphStyle: paragraph
            ]
        )
        hintWidth = hintText
            .components(separatedBy: "\n")
            .map { line in
                NSAttributedString(string: line, attributes: [.font: hintFont]).size().width
            }
            .max() ?? 0
        hintHeight = ceil(hintSize * 1.35) * 2

        needsLayout = true
        needsDisplay = true
    }

    func measure(compact: Bool, availableWidth: CGFloat) -> NSSize {
        if compact {
            var x: CGFloat = 0
            var rows = 1
            for width in optionWidths {
                if x > 0, x + width > availableWidth {
                    rows += 1
                    x = 0
                }
                x += width + 14
            }
            return NSSize(
                width: availableWidth,
                height: CGFloat(rows) * optionHeight + CGFloat(max(rows - 1, 0)) * 2
            )
        }
        let width = ceil(max(optionWidths.max() ?? 0, hintWidth)) + 2
        let height = CGFloat(buttons.count) * optionHeight
            + CGFloat(max(buttons.count - 1, 0)) * 2
            + 6 + hintHeight
        return NSSize(width: width, height: height)
    }

    override func layout() {
        super.layout()
        guard !buttons.isEmpty else { return }
        if compact {
            hint.isHidden = true
            var x: CGFloat = 0
            var y: CGFloat = 0
            for button in buttons {
                if x > 0, x + button.optionWidth > bounds.width {
                    x = 0
                    y += optionHeight + 2
                }
                button.frame = NSRect(x: x, y: y, width: button.optionWidth, height: optionHeight)
                x += button.optionWidth + 14
            }
        } else {
            hint.isHidden = false
            for (index, button) in buttons.enumerated() {
                button.frame = NSRect(
                    x: 0,
                    y: CGFloat(index) * (optionHeight + 2),
                    width: bounds.width,
                    height: optionHeight
                )
            }
            hint.frame = NSRect(
                x: 0,
                y: CGFloat(buttons.count) * (optionHeight + 2) + 6,
                width: bounds.width,
                height: hintHeight
            )
        }
    }
}

// MARK: - Time menu

final class TimeMenuView: NSView {
    private let effect = NSVisualEffectView()
    private var buttons: [MenuHitButton] = []
    private var buttonHeight: CGFloat = 23
    private var menuWidth: CGFloat = 200

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityRole(.list)
        setAccessibilityLabel("Time of day")

        effect.material = .popover
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        addSubview(effect)

        for _ in SceneTime.allCases {
            let button = MenuHitButton(frame: .zero)
            buttons.append(button)
            addSubview(button)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {}

    func configure(
        model: DemoModel,
        theme: Theme,
        metrics: PageMetrics,
        onChoose: @escaping (Int) -> Void
    ) {
        let size = metrics.scriptSize
        buttonHeight = ceil(size + 8)
        var widest: CGFloat = 0

        for (index, button) in buttons.enumerated() {
            let time = SceneTime.allCases[index]
            let isSelected = index == model.timeIndex
            let font = Fonts.scriptNS(size, bold: isSelected)
            let colour = isSelected ? NSColor(hex: Hex.choice) : theme.nsInk
            let attributed = NSAttributedString(
                string: time.menuLabel,
                attributes: [.font: font, .foregroundColor: colour]
            )
            button.apply(
                label: attributed,
                labelText: time.rawValue,
                selected: isSelected,
                alignment: .left,
                fill: isSelected
                    ? NSColor(hex: Hex.choice, opacity: 0.08)
                    : nil
            )
            button.onPress = { onChoose(index) }
            button.onHover = nil
            widest = max(widest, button.optionWidth)
        }

        menuWidth = ceil(max(13 * size, widest + 20 + 12))
        effect.appearance = NSAppearance(named: theme.colorScheme == .dark ? .darkAqua : .aqua)
        effect.layer?.borderColor = theme.nsInk.withAlphaComponent(0.10).cgColor
        layer?.shadowColor = NSColor(theme.shadow).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 14
        layer?.shadowOffset = CGSize(width: 0, height: -10)

        needsLayout = true
    }

    func measure(metrics: PageMetrics) -> NSSize {
        let height = CGFloat(buttons.count) * buttonHeight + 12
        return NSSize(width: menuWidth, height: height)
    }

    override func layout() {
        super.layout()
        effect.frame = bounds
        let padding: CGFloat = 6
        let usable = max(bounds.height - padding * 2, 0)
        let height = buttons.isEmpty ? 0 : usable / CGFloat(buttons.count)
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(
                x: padding,
                y: padding + CGFloat(index) * height,
                width: max(bounds.width - padding * 2, 0),
                height: height
            )
        }
    }
}
