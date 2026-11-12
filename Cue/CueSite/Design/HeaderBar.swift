import SwiftUI
import AppKit
import QuartzCore
import ApplicationServices
import CueKit

/// The marketing page's sticky header.
///
/// Geometry is fixed at **67 pt** at every width (the site: `14px + 26px logo + 14px + 1px`,
/// measured 67). The row is vertically centred inside that height so the 30 pt lamp pill and
/// the 56 pt App Store pill can both sit in it without changing the header's measured height.
struct HeaderBar: View {
    @Environment(SiteModel.self) private var model
    @Environment(\.theme) private var theme

    @FocusState private var skipFocused: Bool
    @State private var hovered: String?

    /// In-page anchors, in source order, paired with the labels in `SiteCopy.nav`.
    private let anchors = ["try", "price", "features", "questions"]

    private var width: CGFloat { max(model.viewport.width, 320) }
    private var gutter: CGFloat { SiteMath.gutter(width) }
    private var isPhone: Bool { SiteMath.isPhone(width) }
    /// The reference site's header is logo + links + lamp only; the App Store
    /// CTA lives in the hero, not in the sticky bar.
    private var showsCTA: Bool { false }

    var body: some View {
        HStack(spacing: 38) {
            logoButton
            Spacer(minLength: 8)
            if !isPhone { navLinks }
            lampButton
            if isPhone { navMenu }
        }
        .padding(.horizontal, gutter)
        .frame(maxWidth: .infinity)
        .frame(height: SiteMath.headerHeight)
        .background { headerBackground }
        .overlay(alignment: .bottom) { Hairline() }
        .overlay(alignment: .leading) { skipLink.padding(.leading, gutter) }
        .accessibilityElement(children: .contain)
    }

    // MARK: Backdrop

    private var headerBackground: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .background(theme.desk.opacity(0.55))
            .allowsHitTesting(false)
    }

    // MARK: Skip link

    /// The site has no skip link; this build adds one as the first focusable element.
    private var skipLink: some View {
        Button { go("top") } label: {
            Text("Skip to content")
                .font(Fonts.ui(13, weight: .medium))
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(theme.paper, in: .capsule)
                .overlay { Capsule().strokeBorder(theme.hair, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .focused($skipFocused)
        .opacity(skipFocused ? 1 : 0)
        .allowsHitTesting(skipFocused)
        .accessibilitySortPriority(10)
        .accessibilityLabel("Skip to content")
    }

    // MARK: Logo

    private var logoButton: some View {
        Button { go("top") } label: {
            CueLogo(height: 26)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cue, back to the top")
    }

    // MARK: Navigation

    private var navLinks: some View {
        HStack(spacing: 24) {
            ForEach(Array(SiteCopy.nav.enumerated()), id: \.offset) { index, title in
                let id = index < anchors.count ? anchors[index] : "top"
                Button { go(id) } label: {
                    Text(title)
                        .font(Fonts.ui(14))
                        .foregroundStyle(hovered == id ? theme.ink : theme.ink2)
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside {
                        hovered = id
                    } else if hovered == id {
                        hovered = nil
                    }
                }
                .animation(.linear(duration: 0.16), value: hovered)
            }
        }
    }

    private var navMenu: some View {
        Menu {
            ForEach(Array(SiteCopy.nav.enumerated()), id: \.offset) { index, title in
                Button(title) { go(index < anchors.count ? anchors[index] : "top") }
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.ink)
                .frame(width: 30, height: 30)
                .background(theme.glass, in: .circle)
                .overlay { Circle().strokeBorder(theme.hair, lineWidth: 1) }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Sections")
    }

    // MARK: Lamp button

    private var lampButton: some View {
        Button { model.lamp.next() } label: {
            HStack(spacing: 6) {
                LampGlyph()
                    .stroke(theme.ink, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                    .frame(width: 14, height: 14)
                Text(model.lamp.label)
                    .font(Fonts.ui(12.5))
                    .foregroundStyle(theme.ink)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .padding(.trailing, 4)
            .background(theme.glass, in: .capsule)
            .overlay { Capsule().strokeBorder(theme.hair, lineWidth: 1) }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(theme.glassEdge)
                    .frame(height: 1)
                    .padding(.horizontal, 8)
            }
        }
        .buttonStyle(.plain)
        .help("Change the lamp")
        .accessibilityLabel("Lamp")
        .accessibilityValue(model.lamp.label)
        .accessibilityHint("Cycles Daylight, Evening, Night and Auto")
    }

    // MARK: Actions

    private func go(_ id: String) {
        PageScroll.scroll(to: id, model: model)
    }
}

// MARK: - Lamp glyph

/// The header's 16 × 16 line drawing of a desk lamp: shade, stem and base.
struct LampGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }
        var path = Path()
        path.move(to: p(5, 2))
        path.addLine(to: p(11, 2))
        path.addLine(to: p(13, 7))
        path.addLine(to: p(3, 7))
        path.closeSubpath()
        path.move(to: p(8, 7))
        path.addLine(to: p(8, 13))
        path.move(to: p(5, 14))
        path.addLine(to: p(11, 14))
        return path
    }
}

// MARK: - Page scrolling

/// Anchor navigation for the chapter links.
///
/// `LandingView` owns the `ScrollViewReader`, and the header is a `safeAreaInset` outside it, so
/// no `ScrollViewProxy` reaches the header. Instead the header scrolls the page's own
/// `NSScrollView` (the tallest scroll view in the window) to a document offset. Sections
/// register their tops in `SiteModel`; the two anchors that belong to other agents' sections
/// (the demo and the price line) are located from their accessibility frames, with a
/// proportional fallback.
@MainActor
enum PageScroll {
    static func scroll(to id: String, model: SiteModel) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible),
              let scroll = pageScrollView(in: window) else { return }

        let top = documentTop(for: id, in: window, scroll: scroll, model: model)
        guard let top else { return }

        let y = top - 72                        // the site's `scroll-margin-top: 72px`
        apply(scroll, y: y, animated: !model.reduceMotion)
    }

    // MARK: Locating

    static func pageScrollView(in window: NSWindow) -> NSScrollView? {
        var candidates: [NSScrollView] = []
        func walk(_ view: NSView, depth: Int) {
            guard depth < 40 else { return }
            if let scroll = view as? NSScrollView { candidates.append(scroll) }
            for sub in view.subviews { walk(sub, depth: depth + 1) }
        }
        if let content = window.contentView { walk(content, depth: 0) }

        // The page is by far the tallest scrollable document in the window; the demo editor is
        // the only other one and is about a tenth of the height.
        return candidates.max { lhs, rhs in
            documentHeight(lhs) < documentHeight(rhs)
        }
    }

    private static func documentHeight(_ scroll: NSScrollView) -> CGFloat {
        (scroll.documentView?.frame.height ?? 0) * max(scroll.frame.width, 1)
    }

    private static func documentTop(
        for id: String,
        in window: NSWindow,
        scroll: NSScrollView,
        model: SiteModel
    ) -> CGFloat? {
        if id == "top" { return 0 }

        if let registered = model.sectionTops[id] {
            return registered
        }

        switch id {
        case "try":
            if let top = accessibilityTop(matching: "Go on. Type something.", in: window, scroll: scroll)
                ?? accessibilityTop(matching: "CUT TO:", in: window, scroll: scroll) {
                return top
            }
        case "price":
            if let top = accessibilityTop(matching: "$6.99", in: window, scroll: scroll) {
                return top
            }
        default:
            break
        }

        // Fallback proportions of the (known) features anchor, measured from the reference page.
        if let features = model.sectionTops["features"] {
            switch id {
            case "try": return features * 0.52
            case "price": return features * 0.38
            default: return features
            }
        }
        return nil
    }

    // MARK: Accessibility

    /// The document offset of the first accessibility element whose value contains `needle`.
    /// Used for the two anchors no section owns.
    private static func accessibilityTop(
        matching needle: String,
        in window: NSWindow,
        scroll: NSScrollView
    ) -> CGFloat? {
        let application = AXUIElementCreateApplication(getpid())
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windows) == .success,
              let windowList = windows as? [AXUIElement],
              let axWindow = windowList.first else { return nil }

        var match: CGRect?
        var visits = 0

        func visit(_ element: AXUIElement, _ depth: Int) {
            guard match == nil, visits < 4000, depth < 40 else { return }
            visits += 1

            var value: CFTypeRef?
            var title: CFTypeRef?
            var description: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
            _ = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
            _ = AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description)
            let texts = [value, title, description].compactMap { $0 as? String }
            if texts.contains(where: { $0.contains(needle) }) {
                var position: CFTypeRef?
                var size: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
                   AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
                   let position, let size {
                    var point = CGPoint.zero
                    var extent = CGSize.zero
                    if AXValueGetValue(position as! AXValue, .cgPoint, &point),
                       AXValueGetValue(size as! AXValue, .cgSize, &extent) {
                        match = CGRect(origin: point, size: extent)
                    }
                }
                return
            }

            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let list = children as? [AXUIElement] {
                for child in list { visit(child, depth + 1) }
            }
        }

        visit(axWindow, 0)
        guard let match else { return nil }

        // AX frames are in screen points with a top-left origin; AppKit screens are bottom-left.
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        let viewport = scroll.convert(scroll.bounds, to: nil)
        let viewportOnScreen = window.convertToScreen(viewport)
        let viewportTop = mainHeight - viewportOnScreen.maxY
        let delta = match.minY - viewportTop
        return scroll.contentView.bounds.origin.y + delta
    }

    // MARK: Applying

    private static func apply(_ scroll: NSScrollView, y: CGFloat, animated: Bool) {
        let clip = scroll.contentView
        let maxY = max(0, (scroll.documentView?.frame.height ?? 0) - clip.bounds.height)
        let target = min(max(0, y), maxY)
        let origin = NSPoint(x: clip.bounds.origin.x, y: target)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.42
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
                clip.animator().setBoundsOrigin(origin)
            } completionHandler: {
                scroll.reflectScrolledClipView(clip)
            }
        } else {
            clip.setBoundsOrigin(origin)
            scroll.reflectScrolledClipView(clip)
        }
    }
}
