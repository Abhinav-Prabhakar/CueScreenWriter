import SwiftUI
import CueKit

/// The landing hero: slug, MacBook, scroll-typed headline, lede, price promise and offer.
struct HeroSection: View {
    @Environment(SiteModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    @State private var headingTop: CGFloat = 900
    @State private var macBookFrame: CGRect = .zero

    private var reduceMotion: Bool { systemReduceMotion || model.reduceMotion }
    private var width: CGFloat { max(model.viewport.width, 320) }
    private var viewportHeight: CGFloat { max(model.viewport.height, 480) }
    /// The site measures `vh` against the whole window; the native scroll view sits below
    /// the fixed header, so add its height back for the viewport-relative rhythm.
    private var siteHeight: CGFloat {
        max(model.windowHeight, viewportHeight + SiteMath.headerHeight)
    }

    private var h1Size: CGFloat { SiteMath.h1(width) }
    private var ledeSize: CGFloat { SiteMath.lede(width) }
    private var promiseSize: CGFloat { SiteMath.promise(width) }

    // Measured rhythm at 1440 × 900: 45 / 126 outer, 72 / 45 around the h1,
    // 81 under the lede, 63 under the promise.
    private var heroTop: CGFloat { clamp(siteHeight * 0.05, 28, 56) }
    private var heroBottom: CGFloat { clamp(siteHeight * 0.14, 96, 160) }
    private var titleTop: CGFloat { clamp(siteHeight * 0.08, 48, 88) }
    private var titleBottom: CGFloat { clamp(siteHeight * 0.05, 32, 48) }
    private var ledeBottom: CGFloat { clamp(siteHeight * 0.09, 56, 88) }
    private var promiseBottom: CGFloat { clamp(siteHeight * 0.07, 44, 64) }

    var body: some View {
        VStack(spacing: 0) {
            Slug(text: SiteCopy.heroSlug)
                .frame(height: 14 * 1.55)
                .padding(.bottom, 14)

            // The site's width formula reads `vh` as the whole window; the model's viewport
            // is the scroll area below the header, so use the site height for parity.
            MacBookView(width: SiteMath.macBookWidth(width, viewportHeight: siteHeight),
                        shellLamp: model.lamp.lamp,
                        isActive: mockIsActive)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named("hero"))
                } action: { frame in
                    macBookFrame = frame
                }
                .padding(.top, 8)

            headline
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .named("hero")).minY
                } action: { top in
                    headingTop = top
                }
                .padding(.top, titleTop)
                .padding(.bottom, titleBottom)

            lede
                .padding(.bottom, ledeBottom)

            PromiseLine(size: promiseSize, reduceMotion: reduceMotion)
                .padding(.bottom, promiseBottom)

            downloadLink

            Text(SiteCopy.priceNote)
                .font(Fonts.ui(13))
                .foregroundStyle(theme.ink2.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.top, 18)

            tryLink
                .padding(.top, 22)
        }
        .frame(maxWidth: 1120)
        .padding(.top, heroTop)
        .padding(.bottom, heroBottom)
        .padding(.horizontal, SiteMath.gutter(width))
        .frame(maxWidth: .infinity)
        .coordinateSpace(.named("hero"))
    }

    // MARK: Headline

    private var headline: some View {
        TypedHeadline(
            fixed: SiteCopy.heroFixed,
            typed: SiteCopy.heroTyped,
            visible: visibleCharacters,
            size: h1Size,
            maxWidth: min(h1Size * (820.27 / 72), SiteMath.content(width)),
            animateCaret: !reduceMotion
        )
        .frame(maxWidth: .infinity)
    }

    /// Scroll-mapped character count: the heading types out between 92 % and 50 % of the
    /// viewport, and un-types when the visitor scrolls back up.
    private var visibleCharacters: Int {
        let typed = SiteCopy.heroTyped
        guard !reduceMotion else { return typed.count }
        // The heading is measured in the hero's own space; the scroll offset carries the
        // header inset, so `headingTop - scrollY` is the heading's window-relative top.
        let top = headingTop - model.scrollY
        let progress = clamp((siteHeight * 0.92 - top) / (siteHeight * 0.42), 0, 1)
        return Int((progress * CGFloat(typed.count)).rounded())
    }

    private var mockIsActive: Bool {
        guard macBookFrame.height > 0 else { return true }
        let top = macBookFrame.minY - model.scrollY - SiteMath.headerHeight
        let bottom = macBookFrame.maxY - model.scrollY - SiteMath.headerHeight
        let visible = min(bottom, viewportHeight) - max(top, 0)
        return visible / macBookFrame.height >= 0.05
    }

    // MARK: Copy

    private var lede: some View {
        Text(SiteCopy.heroLede)
            .font(Fonts.ui(ledeSize))
            .foregroundStyle(theme.ink2)
            .multilineTextAlignment(.center)
            .lineSpacing(ledeSize * 0.55)
            .frame(maxWidth: 34 * ledeSize)
            .frame(maxWidth: .infinity)
    }

    private var downloadLink: some View {
        Link(destination: SiteCopy.appStoreURL) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: Hex.orange))
                    .frame(width: 8, height: 8)
                    .shadow(color: Color(hex: Hex.orange).opacity(0.8), radius: 5)
                Text(SiteCopy.download)
                    .font(Fonts.ui(15, weight: .medium))
            }
            .foregroundStyle(theme.desk)
            .padding(.leading, 28)
            .padding(.trailing, 34)
            .frame(height: 56)
            .background(theme.ink, in: .capsule)
            .shadow(color: Color(hex: 0x14110E, opacity: 0.28), radius: 13, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Download Cue now on the Mac App Store")
    }

    private var tryLink: some View {
        Text(SiteCopy.tryBelow)
            .font(Fonts.ui(15))
            .foregroundStyle(theme.ink)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.hair)
                    .frame(height: 1)
                    .offset(y: 4)
            }
    }
}

// MARK: - Promise

private struct PromiseLine: View {
    @Environment(\.theme) private var theme

    let size: CGFloat
    let reduceMotion: Bool

    @State private var index = 0

    private var words: [String] { SiteCopy.promiseWords }
    private var advance: CGFloat { size * 0.6 }
    private var currentWidth: CGFloat { CGFloat(words[index].count) * advance }
    private var previousIndex: Int { (index + words.count - 1) % words.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: advance) {
                Text(SiteCopy.price + " once.")
                    .font(Fonts.script(size))
                    .foregroundStyle(theme.ink)
                    .fixedSize()

                roller
            }

            if reduceMotion {
                Text(SiteCopy.promiseSmall)
                    .font(Fonts.script(size * 0.56))
                    .tracking(size * 0.56 * 0.01)
                    .foregroundStyle(theme.ink2)
                    .padding(.top, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(SiteCopy.price) once. Yours to keep. No subscription, no ads, no AI writing."
        )
        .task(id: reduceMotion) {
            index = 0
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.4))
                if Task.isCancelled { break }
                index = (index + 1) % words.count
            }
        }
    }

    private var roller: some View {
        ZStack(alignment: .topLeading) {
            ForEach(words.indices, id: \.self) { word in
                Text(words[word])
                    .font(Fonts.script(size))
                    .foregroundStyle(theme.ink)
                    .fixedSize()
                    .opacity(word == index ? 1 : 0)
                    .rotation3DEffect(
                        .degrees(rotation(for: word)),
                        axis: (x: 1, y: 0, z: 0),
                        anchor: .center,
                        perspective: 0.4
                    )
                    .offset(y: offset(for: word))
                    .animation(.cueFade, value: index)
            }
        }
        .frame(width: currentWidth, height: size * 1.35, alignment: .topLeading)
        .clipped()
        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5), value: index)
    }

    private func rotation(for word: Int) -> Double {
        if word == index { return 0 }
        return word == previousIndex ? 80 : -80
    }

    private func offset(for word: Int) -> CGFloat {
        if word == index { return 0 }
        return (word == previousIndex ? -0.7 : 0.7) * size
    }
}

// MARK: - Typed headline

private struct TypedHeadline: View {
    @Environment(\.theme) private var theme

    let fixed: String
    let typed: String
    let visible: Int
    let size: CGFloat
    let maxWidth: CGFloat
    let animateCaret: Bool

    private var advance: CGFloat { size * 0.6 }
    private var caretIndex: Int { fixed.count + 1 + min(max(visible, 0), typed.count) }

    var body: some View {
        let lines = Self.wrap(fixed + " " + typed, maxWidth: maxWidth, advance: advance)
        VStack(spacing: 0) {
            ForEach(lines.indices, id: \.self) { index in
                line(lines[index], isCaretLine: caretLine(lines) == index)
            }
        }
        .frame(width: maxWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fixed + " " + typed)
    }

    private func caretLine(_ lines: [HeadlineLine]) -> Int {
        // A caret sitting on a soft wrap belongs to the end of the line before it,
        // where the browser hangs the space that caused the break.
        for (index, line) in lines.enumerated() where caretIndex <= line.start + line.text.count + 1 {
            return index
        }
        return max(lines.count - 1, 0)
    }

    private func line(_ line: HeadlineLine, isCaretLine: Bool) -> some View {
        let count = line.text.count
        let shown = min(max(caretIndex - line.start, 0), count)
        let prefix = String(line.text.prefix(shown))
        let suffix = String(line.text.dropFirst(shown))
        let lineWidth = CGFloat(count) * advance
        let caretX = (maxWidth - lineWidth) / 2 + CGFloat(shown) * advance

        return ZStack(alignment: .topLeading) {
            (Text(prefix).foregroundColor(theme.ink) + Text(suffix).foregroundColor(.clear))
                .font(Fonts.script(size))
                .frame(width: maxWidth, alignment: .center)

            if isCaretLine {
                HeadlineCaret(size: size, animated: animateCaret)
                    .offset(x: caretX, y: size * 0.06)
            }
        }
        .frame(width: maxWidth, height: size * 1.14, alignment: .topLeading)
    }

    struct HeadlineLine {
        let text: String
        let start: Int
    }

    /// Balanced wrapping (the site's `text-wrap: balance`) over a monospaced measure.
    static func wrap(_ text: String, maxWidth: CGFloat, advance: CGFloat) -> [HeadlineLine] {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [HeadlineLine(text: "", start: 0)] }

        let charWidth = max(advance, 1)
        let maxChars = max(1, Int(floor(maxWidth / charWidth)))
        let widths = words.map { CGFloat($0.count) }
        let space = CGFloat(1)

        // Minimum raggedness over every line, so the block balances like the browser.
        var cost = [Double](repeating: .infinity, count: words.count + 1)
        var breaks = [Int](repeating: 0, count: words.count + 1)
        cost[words.count] = 0

        for start in stride(from: words.count - 1, through: 0, by: -1) {
            var lineWidth: CGFloat = 0
            for end in start..<words.count {
                lineWidth += widths[end] + (end > start ? space : 0)
                if lineWidth > CGFloat(maxChars) && end > start { break }
                let slack = Double(CGFloat(maxChars) - lineWidth)
                let candidate = slack * slack + cost[end + 1]
                if candidate < cost[start] {
                    cost[start] = candidate
                    breaks[start] = end + 1
                }
            }
            if cost[start] == .infinity {
                cost[start] = 0
                breaks[start] = start + 1
            }
        }

        var lines: [HeadlineLine] = []
        var cursor = 0
        var wordIndex = 0
        while wordIndex < words.count {
            let end = breaks[wordIndex]
            let text = words[wordIndex..<end].joined(separator: " ")
            lines.append(HeadlineLine(text: text, start: cursor))
            cursor += text.count + 1
            wordIndex = end
        }
        return lines
    }
}

private struct HeadlineCaret: View {
    @Environment(\.theme) private var theme
    let size: CGFloat
    let animated: Bool

    var body: some View {
        if animated {
            TimelineView(.periodic(from: .now, by: 0.53)) { context in
                caret(on: Int(context.date.timeIntervalSinceReferenceDate / 0.53) % 2 == 0)
            }
        } else {
            caret(on: true)
        }
    }

    private func caret(on: Bool) -> some View {
        Rectangle()
            .fill(theme.ink)
            .frame(width: size * 0.07, height: size * 0.9)
            .opacity(on ? 1 : 0)
    }
}
