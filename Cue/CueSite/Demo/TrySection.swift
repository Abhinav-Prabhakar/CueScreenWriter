import SwiftUI
import AppKit
import CueKit

/// The landing page's live demo: a centred screenplay page with the real
/// formatting engine underneath it.
struct TrySection: View {
    @Environment(SiteModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    @State private var demo = DemoModel()
    @State private var focusToken = 0
    @State private var lastHintState: HintState = .unfocused

    private var width: CGFloat { max(model.viewport.width, 320) }
    private var gutter: CGFloat { SiteMath.gutter(width) }
    private var contentWidth: CGFloat { SiteMath.content(width) }
    private var pageWidth: CGFloat { min(SiteMath.demoMaxWidth, contentWidth) }
    private var pageHeight: CGFloat {
        SiteMath.demoPageHeight(pageWidth: pageWidth, viewportWidth: width)
    }
    private var compact: Bool { width <= 640 }
    private var reduceMotion: Bool { systemReduceMotion || model.reduceMotion }
    private var h2Size: CGFloat { SiteMath.h2(width) }

    var body: some View {
        VStack(spacing: 0) {
            head
            page
            footer
                .frame(width: pageWidth)
                .padding(.top, 22)
        }
        .frame(maxWidth: SiteMath.contentMax)
        .padding(.top, 40)
        .padding(.bottom, 120)
        .padding(.horizontal, gutter)
        .frame(maxWidth: .infinity)
        .onChange(of: demo.hintState) { _, newState in
            guard newState != lastHintState else { return }
            lastHintState = newState
            announce(demo.hintAnnouncement)
        }
    }

    // MARK: Head

    private var head: some View {
        VStack(spacing: 0) {
            Text(SiteCopy.trySlug)
                .font(Fonts.script(14, bold: true))
                .tracking(14 * 0.02)
                .textCase(.uppercase)
                .foregroundStyle(theme.ink2)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.bottom, 36)

            Text(SiteCopy.tryTitle)
                .font(Fonts.script(h2Size))
                .tracking(-h2Size * 0.01)
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)

            Text(SiteCopy.tryNote)
                .font(Fonts.ui(15))
                .foregroundStyle(theme.ink2)
                .multilineTextAlignment(.center)
                .lineSpacing(15 * 0.55)
                .frame(maxWidth: 34 * 15)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 56)
    }

    // MARK: Page

    private var page: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.paper)
                .shadow(color: theme.shadow, radius: 30, x: 0, y: 30)
                .shadow(color: theme.shadow.opacity(0.65), radius: 12, x: 0, y: 12)
                .shadow(color: theme.hair, radius: 0, x: 0, y: 1)

            DemoEditor(
                model: demo,
                compact: compact,
                pageWidth: pageWidth,
                theme: theme,
                focusToken: focusToken,
                reduceMotion: reduceMotion
            )
            .frame(width: pageWidth, height: pageHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .frame(width: pageWidth, height: pageHeight)
        .animation(reduceMotion ? nil : .cueLamp, value: model.lamp.lamp)
    }

    // MARK: Footer

    private var footer: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 10) {
                    hint
                    HStack {
                        Spacer(minLength: 0)
                        trailing
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    hint
                    Spacer(minLength: 16)
                    trailing
                }
            }
        }
    }

    private var hint: some View {
        HintFlow(spacing: 16, lineSpacing: 4) {
            ForEach(Array(demo.hintItems.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    if !item.key.isEmpty {
                        KeyCap(text: item.key)
                    }
                    Text(item.text)
                        .font(Fonts.ui(15))
                        .foregroundStyle(theme.ink2)
                }
                .fixedSize()
            }
        }
        .frame(minHeight: 24, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(demo.hintAnnouncement)
    }

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 18) {
                textButton("Clear") {
                    demo.resetClear()
                    focusToken += 1
                }
                textButton("Start a blank page") {
                    demo.resetBlankPage()
                    focusToken += 1
                }
            }
            Text("⌃Tab leaves the demo")
                .font(Fonts.ui(12))
                .foregroundStyle(theme.ink2.opacity(0.8))
                .accessibilityLabel("Control-Tab leaves the demo")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Fonts.ui(15))
                .foregroundStyle(theme.ink2)
                .underline(true, color: theme.hair)
        }
        .buttonStyle(.plain)
        .accessibilityHint(
            title == "Clear"
                ? "Replaces the page with one empty scene heading"
                : "Replaces the page with one empty line and the chooser"
        )
    }

    private func announce(_ text: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }
}

// MARK: - Keycap

private struct KeyCap: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        Text(text)
            .font(Fonts.ui(15 * 0.78, weight: .medium))
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(theme.glass, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(theme.hair, lineWidth: 1)
            }
    }
}

// MARK: - Hint flow

/// A small wrapping row: items keep their intrinsic width and drop to the next
/// line when the page's footer runs out of room.
private struct HintFlow: Layout {
    var spacing: CGFloat = 16
    var lineSpacing: CGFloat = 4

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let limit = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > limit {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width
            widest = max(widest, x)
            x += spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: min(widest, limit), height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
