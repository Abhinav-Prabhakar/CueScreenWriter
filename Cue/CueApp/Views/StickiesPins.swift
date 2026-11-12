import SwiftUI
import AppKit
import CueKit

// MARK: - Sticky note

/// A lit square of paper on the desk. Translucent, so the desk and the lamp show
/// through it; the tint comes from the theme's paper and the lamp's orange, never
/// from a fixed Post-it yellow.
struct CueStickyNote: View {
    var lines: [String]
    var footnote: String? = nil
    var strike: Bool = false
    var rotation: Double = 0

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var isNight: Bool { theme.colorScheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 1.5) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .strikethrough(strike, color: theme.ink.opacity(0.8))
                }
            }
            if let footnote {
                Text(footnote)
                    .padding(.top, 1)
            }
            Spacer(minLength: 0)
        }
        .font(Fonts.ui(15))
        .foregroundStyle(theme.ink)
        .lineSpacing(1.5)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 17)
        .padding(.vertical, 26)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .background {
            // The lamp catching the edge of the paper: a soft amber pool just
            // outside the note, not a hard shadow.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: Hex.orange).opacity(isNight ? 0.10 : 0.12))
                .blur(radius: 26)
                .padding(-6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color(hex: Hex.orange).opacity(isNight ? 0.15 : 0.16), lineWidth: 1)
        }
        .shadow(color: theme.shadow.opacity(0.65), radius: 22, x: 0, y: 12)
        .rotationEffect(.degrees(reduceMotion ? 0 : (hovering ? 0 : rotation)))
        .offset(y: reduceMotion ? 0 : (hovering ? -4 : 0))
        .scaleEffect(reduceMotion ? 1 : (hovering ? 1.014 : 1))
        .animation(reduceMotion ? nil : .cueHover, value: hovering)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sticky note: " + (lines + (footnote.map { [$0] } ?? [])).joined(separator: " "))
    }

    private var background: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.ultraThinMaterial)
            if isNight {
                // The desk under the note is almost black, so the lit square is
                // set explicitly rather than built from grey paper tokens.
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: 0x5E3E1D).opacity(0.92))
                RadialGradient(
                    colors: [.clear, Color(hex: 0x2A1605).opacity(0.26)],
                    center: .center,
                    startRadius: 30,
                    endRadius: 180
                )
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: Hex.orange).opacity(0.13))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.paper.opacity(0.46))
                RadialGradient(
                    colors: [Color(hex: Hex.orange).opacity(0.10), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 220
                )
            }
        }
    }
}

// MARK: - Pinned photograph

struct CuePinnedPhoto: View {
    enum Kind { case dusk, fog }

    var kind: Kind
    var image: NSImage? = nil
    var rotation: Double = 0

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var isNight: Bool { theme.colorScheme == .dark }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                CueLandscape(kind: kind)
            }
        }
            .overlay {
                Color(hex: Hex.nightDesk)
                    .opacity(isNight ? 0.24 : 0)
                    .blendMode(.multiply)
            }
            .overlay {
                LinearGradient(
                    colors: [Color(hex: Hex.orange).opacity(isNight ? 0.10 : 0), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(theme.hair, lineWidth: 1)
            }
            .shadow(color: theme.shadow, radius: 14, x: 0, y: 8)
            .overlay(alignment: .top) {
                pinHead.offset(y: -5)
            }
            .rotationEffect(.degrees(reduceMotion ? 0 : (hovering ? 0 : rotation)))
            .offset(y: reduceMotion ? 0 : (hovering ? -4 : 0))
            .scaleEffect(reduceMotion ? 1 : (hovering ? 1.02 : 1))
            .animation(reduceMotion ? nil : .cueHover, value: hovering)
            .onHover { hovering = $0 }
            .accessibilityLabel(image == nil ? "Pinned reference photograph" : "Pinned photograph")
    }

    private var pinHead: some View {
        ZStack {
            Rectangle()
                .fill(theme.ink2.opacity(0.45))
                .frame(width: 1, height: 7)
                .offset(y: 4)
            Circle()
                .fill(theme.stack)
                .overlay { Circle().strokeBorder(theme.hair, lineWidth: 1) }
                .frame(width: 11, height: 11)
                .shadow(color: theme.shadow, radius: 3, x: 0, y: 2)
        }
    }
}

/// Two small drawn landscapes, used in place of the reference photographs.
struct CueLandscape: View {
    var kind: CuePinnedPhoto.Kind

    var body: some View {
        Canvas { context, size in
            switch kind {
            case .dusk: drawDusk(context: &context, size: size)
            case .fog: drawFog(context: &context, size: size)
            }
        }
        .drawingGroup()
    }

    private func drawDusk(context: inout GraphicsContext, size: CGSize) {
        let width = size.width
        let height = size.height

        let sky = Gradient(colors: [
            Color(hex: 0x29313F), Color(hex: 0x6A5A5E), Color(hex: 0xC0835F)
        ])
        context.fill(
            Path(CGRect(x: 0, y: 0, width: width, height: height)),
            with: .linearGradient(sky,
                                  startPoint: .zero,
                                  endPoint: CGPoint(x: 0, y: height))
        )

        let sun = CGPoint(x: width * 0.7, y: height * 0.44)
        context.fill(
            Path(ellipseIn: CGRect(x: sun.x - width * 0.16, y: sun.y - width * 0.16,
                                   width: width * 0.32, height: width * 0.32)),
            with: .radialGradient(
                Gradient(colors: [Color(hex: 0xF6C894, opacity: 0.65), .clear]),
                center: sun, startRadius: 0, endRadius: width * 0.18
            )
        )
        context.fill(
            Path(ellipseIn: CGRect(x: sun.x - 7, y: sun.y - 7, width: 14, height: 14)),
            with: .color(Color(hex: 0xF7D2A2, opacity: 0.85))
        )

        let seaTop = height * 0.54
        context.fill(
            Path(CGRect(x: 0, y: seaTop, width: width, height: height - seaTop)),
            with: .linearGradient(
                Gradient(colors: [Color(hex: 0x3B4651), Color(hex: 0x202730)]),
                startPoint: CGPoint(x: 0, y: seaTop),
                endPoint: CGPoint(x: 0, y: height)
            )
        )

        context.fill(
            Path(CGRect(x: width * 0.6, y: seaTop + 4, width: 2.5, height: height * 0.32)),
            with: .linearGradient(
                Gradient(colors: [Color(hex: 0xF3C08A, opacity: 0.65), .clear]),
                startPoint: CGPoint(x: 0, y: seaTop),
                endPoint: CGPoint(x: 0, y: height)
            )
        )

        var headland = Path()
        headland.move(to: CGPoint(x: 0, y: height * 0.62))
        headland.addCurve(to: CGPoint(x: width * 0.44, y: height * 0.66),
                          control1: CGPoint(x: width * 0.16, y: height * 0.58),
                          control2: CGPoint(x: width * 0.28, y: height * 0.64))
        headland.addLine(to: CGPoint(x: width * 0.44, y: height))
        headland.addLine(to: CGPoint(x: 0, y: height))
        headland.closeSubpath()
        context.fill(headland, with: .color(Color(hex: 0x181D24, opacity: 0.9)))

        context.fill(
            Path(CGRect(x: 0, y: height * 0.50, width: width, height: height * 0.07)),
            with: .color(.white.opacity(0.07))
        )
    }

    private func drawFog(context: inout GraphicsContext, size: CGSize) {
        let width = size.width
        let height = size.height

        context.fill(
            Path(CGRect(x: 0, y: 0, width: width, height: height)),
            with: .linearGradient(
                Gradient(colors: [Color(hex: 0x8E9794), Color(hex: 0xC3C7BE)]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: height)
            )
        )

        let seaTop = height * 0.64
        context.fill(
            Path(CGRect(x: 0, y: seaTop, width: width, height: height - seaTop)),
            with: .linearGradient(
                Gradient(colors: [Color(hex: 0x566460), Color(hex: 0x394441)]),
                startPoint: CGPoint(x: 0, y: seaTop),
                endPoint: CGPoint(x: 0, y: height)
            )
        )

        // The lighthouse: a tapered tower and a faint beam.
        let baseX = width * 0.6
        let baseY = height * 0.72
        let topY = height * 0.27
        let topHalf = width * 0.035
        let bottomHalf = width * 0.06

        var beam = Path()
        beam.move(to: CGPoint(x: baseX + topHalf, y: topY))
        beam.addLine(to: CGPoint(x: width * 1.02, y: topY - height * 0.1))
        beam.addLine(to: CGPoint(x: width * 1.02, y: topY + height * 0.16))
        beam.closeSubpath()
        context.fill(beam, with: .color(.white.opacity(0.16)))

        var tower = Path()
        tower.move(to: CGPoint(x: baseX - topHalf, y: topY))
        tower.addLine(to: CGPoint(x: baseX + topHalf, y: topY))
        tower.addLine(to: CGPoint(x: baseX + bottomHalf, y: baseY))
        tower.addLine(to: CGPoint(x: baseX - bottomHalf, y: baseY))
        tower.closeSubpath()
        context.fill(tower, with: .color(Color(hex: 0x2E3836)))

        context.fill(
            Path(CGRect(x: baseX - width * 0.052, y: topY - height * 0.06,
                        width: width * 0.104, height: height * 0.06)),
            with: .color(Color(hex: 0x222B29))
        )
        context.fill(
            Path(CGRect(x: baseX - width * 0.024, y: topY - height * 0.048,
                        width: width * 0.048, height: height * 0.03)),
            with: .color(Color(hex: 0xE8D9AC, opacity: 0.9))
        )

        for index in 0..<4 {
            let y = height * (0.18 + Double(index) * 0.14)
            context.fill(
                Path(CGRect(x: 0, y: y, width: width, height: height * 0.08)),
                with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.0), .white.opacity(0.22), .white.opacity(0.0)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: width, y: 0)
                )
            )
        }
    }
}

// MARK: - Title-page strip

/// A miniature title page on the desk's bottom left. Clicking it opens the sheet.
struct CueTitlePageStrip: View {
    var title: String
    var author: String = "A. WRITER"
    var action: () -> Void
    var width: CGFloat = 196
    var height: CGFloat = 62

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            CuePaper(soft: true) {
                VStack(spacing: 3) {
                    Text(title)
                        .font(Fonts.script(9.5, bold: true))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("written by")
                        .font(Fonts.script(5.8))
                        .foregroundStyle(theme.ink2)
                    Text(author.uppercased())
                        .font(Fonts.script(6.4))
                }
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 10)
            }
            .frame(width: width, height: height)
        }
        .buttonStyle(.plain)
        .offset(y: reduceMotion ? 0 : (hovering ? -2 : 0))
        .animation(reduceMotion ? nil : .cueHover, value: hovering)
        .onHover { hovering = $0 }
        .help("Open the title page")
        .accessibilityLabel("Open the title page")
    }
}
