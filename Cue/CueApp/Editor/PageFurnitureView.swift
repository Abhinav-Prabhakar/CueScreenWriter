import SwiftUI
import AppKit
import CueKit

/// The margin layer: scene numbers, character rails and page numbers.
///
/// It is a child of `ScriptTextView`, so it shares the text view's flipped
/// coordinate space and scrolls with the page. It never takes a click or a
/// focus; only scene numbers are exposed to assistive technology.
final class PageFurnitureView: NSView {
    weak var textView: ScriptTextView?
    var theme: Theme = .daylight {
        didSet { invalidate() }
    }

    private var invalidationQueued = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Scene numbers")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    /// Rails and page numbers are decoration; clicks belong to the text view.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Coalesce invalidations to one redraw per run loop.
    func invalidate() {
        guard !invalidationQueued else { return }
        invalidationQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.invalidationQueued = false
            self.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else {
            return
        }

        layoutManager.ensureLayout(for: container)
        let width = max(container.size.width, 1)
        let metrics = PageMetrics(pageWidth: width)
        let scriptSize = ScreenplayTypography.size(forWidth: width)
        let furnitureSize = scriptSize * 0.85
        let furnitureFont = Fonts.scriptNS(furnitureSize)
        let ink2 = theme.nsInk2
        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: furnitureFont,
            .foregroundColor: ink2
        ]
        let sceneFont = ScreenplayTypography.font(for: .scene, size: scriptSize)

        // Scene numbers, aligned to the scene heading's baseline.
        if textView.sceneNumbersVisible {
            for mark in textView.sceneMarks {
                guard let line = textView.firstLineRect(forParagraph: mark.paragraph) else { continue }
                let text = "\(mark.number + textView.sceneNumberOffset)" as NSString
                let textSize = text.size(withAttributes: numberAttributes)
                // Scene numbers are right-aligned in a 12 % margin column so a
                // two-digit scene does not push the slug to the right.
                let x = width * 0.12 - textSize.width
                let y = line.minY + max(0, sceneFont.ascender - furnitureFont.ascender)
                text.draw(at: NSPoint(x: x, y: y), withAttributes: numberAttributes)
                _ = textSize
            }
        }

        // Character rails. Each paragraph in a speech draws its own segment;
        // because character/parenthetical/dialogue have no paragraph spacing
        // between them, the segments read as one continuous bar.
        for rail in textView.rails {
            guard let rect = textView.paragraphRect(forParagraph: rail.paragraph) else { continue }
            let index = rail.colourIndex % Hex.characters.count
            let colour = NSColor(hex: Hex.characters[index], opacity: 0.9)
            let railRect = NSRect(x: width * 0.1447,
                                  y: rect.minY,
                                  width: 2,
                                  height: max(2, rect.height))
            let path = NSBezierPath(roundedRect: railRect, xRadius: 1, yRadius: 1)
            colour.setFill()
            path.fill()
        }

        // Page numbers from page 2 onward, top right, 10 % from the page edge.
        let pages = textView.estimatedPageCount
        if pages >= 2 {
            let pageHeight = width * 11.0 / 8.5
            let topInset = metrics.topPadding
            let yOffset = metrics.inch * 0.5
            for page in 2...pages {
                let pageTop = CGFloat(page - 1) * pageHeight - topInset
                let y = pageTop + yOffset
                if y < -24 || y > bounds.height + 24 { continue }
                let text = "\(page)." as NSString
                let textSize = text.size(withAttributes: numberAttributes)
                let x = width * 0.88 - textSize.width
                text.draw(at: NSPoint(x: x, y: y), withAttributes: numberAttributes)
            }
        }
    }

    override func accessibilityChildren() -> [Any]? {
        guard let textView, textView.sceneNumbersVisible else { return nil }
        return textView.sceneMarks.compactMap { mark in
            guard let line = textView.firstLineRect(forParagraph: mark.paragraph),
                  let window else { return nil }
            let screenRect = window.convertToScreen(convert(line, to: nil))
            let element = NSAccessibilityElement()
            element.setAccessibilityRole(.staticText)
            element.setAccessibilityLabel("Scene \(mark.number + textView.sceneNumberOffset)")
            element.setAccessibilityParent(self)
            element.setAccessibilityFrame(screenRect)
            return element
        }
    }
}
