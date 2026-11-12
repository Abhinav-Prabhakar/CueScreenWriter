import SwiftUI
import AppKit
import Combine
import CueKit

// MARK: - Art palette

/// Fixed colours inside the illustrations. The site keeps these outside the lamp tokens:
/// character rails, the music cover gradient and the pinned artwork do not re-light.
enum ArtColor {
    static let maya = Color(hex: 0xD0664A)
    static let jo = Color(hex: 0x6C9A70)
    static let driver = Color(hex: 0xC99A3E)
    static let purple = Color(hex: 0x5B3F8C)
    static let rose = Color(hex: 0xC2577A)
    static let amber = Color(hex: 0xE59A4E)
    static let live = Color(hex: 0xE0662F)
    static let sageTint = Color(hex: 0x6C9A70)
}

// MARK: - Line boxes

/// CSS line heights are larger than the fonts' natural line boxes. `siteLines` makes a
/// multi-line block occupy exactly `lineCount × size × lineHeight` by adding the difference
/// as inter-line spacing and, once, below the last line.
func siteUILines(_ size: CGFloat, _ lineHeight: CGFloat) -> CGFloat {
    max(0, size * lineHeight - size * 1.3)
}

func siteScriptLines(_ size: CGFloat, _ lineHeight: CGFloat) -> CGFloat {
    max(0, size * lineHeight - size * 1.123)
}

extension View {
    /// Multi-line text with a CSS `line-height`.
    func siteLines(_ size: CGFloat, _ lineHeight: CGFloat, script: Bool = false) -> some View {
        let pad = script ? siteScriptLines(size, lineHeight) : siteUILines(size, lineHeight)
        return lineSpacing(pad).padding(.bottom, pad)
    }

    /// A single line forced to a CSS line box, keeping the text vertically centred inside it.
    func siteLine(_ size: CGFloat, _ lineHeight: CGFloat, script: Bool = false) -> some View {
        let natural = size * (script ? 1.123 : 1.3)
        let pad = max(0, (size * lineHeight - natural) / 2)
        return padding(.vertical, pad)
    }
}

// MARK: - Lamp feature

struct LampShots: View {
    @Environment(SiteModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var systemReduce

    private var reduce: Bool { systemReduce || model.reduceMotion }

    var body: some View {
        VStack(spacing: 22) {
            LampTabs()
            stack
        }
        .frame(maxWidth: .infinity)
    }

    private var stack: some View {
        Color.clear
            .aspectRatio(2800.0 / 1560.0, contentMode: .fit)
            .frame(maxWidth: 960)
            .overlay {
                ZStack {
                    ForEach(Lamp.allCases) { lamp in
                        shot(lamp)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: theme.hair, radius: 0, x: 0, y: 1)
            .shadow(color: theme.shadow, radius: 70, x: 0, y: 40)
            .shadow(color: theme.shadow.opacity(0.65), radius: 30, x: 0, y: 14)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Cue's writing screen with the lamp set to \(SiteCopy.lampTitles[model.lamp.lamp] ?? "")")
    }

    @ViewBuilder
    private func shot(_ lamp: Lamp) -> some View {
        Group {
            if let image = Assets.shot("editor-\(lamp.rawValue)") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                theme.stack
            }
        }
        .opacity(model.lamp.lamp == lamp ? 1 : 0)
        .animation(
            reduce ? .linear(duration: 0.01) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.6),
            value: model.lamp.lamp
        )
        .accessibilityHidden(model.lamp.lamp != lamp)
    }
}

/// The lamp feature's own chooser: unlike `SegmentedLamp` (glass on glass), the selected pill
/// inverts to ink with desk-coloured text.
struct LampTabs: View {
    @Environment(SiteModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var systemReduce

    private var reduce: Bool { systemReduce || model.reduceMotion }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Lamp.allCases) { lamp in
                Button {
                    withAnimation(reduce ? .linear(duration: 0.01) : .easeInOut(duration: 0.16)) {
                        model.lamp.choose(lamp)
                    }
                } label: {
                    Text(lamp.title)
                        .font(Fonts.ui(14))
                        .foregroundStyle(model.lamp.lamp == lamp ? theme.desk : theme.ink2)
                        .frame(height: 35)
                        .padding(.horizontal, 16)
                        .background {
                            if model.lamp.lamp == lamp {
                                Capsule().fill(theme.ink)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.lamp.lamp == lamp ? .isSelected : [])
            }
        }
        .padding(4)
        .background(theme.glass, in: .capsule)
        .overlay { Capsule().strokeBorder(theme.hair, lineWidth: 1) }
        .overlay(alignment: .top) {
            Capsule().fill(theme.glassEdge).frame(height: 1).padding(.horizontal, 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lamp")
    }
}

// MARK: - Lamp off

struct LampOffSwitch: View {
    @Environment(SiteModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var systemReduce

    private var reduce: Bool { systemReduce || model.reduceMotion }

    var body: some View {
        Toggle(isOn: Binding(
            get: { model.lit },
            set: { model.setLit($0) }
        )) {
            Text(model.lit ? "Lamp on" : "Lamp off")
                .font(Fonts.ui(15))
                .foregroundStyle(theme.ink2)
        }
        .toggleStyle(LampSwitchStyle())
        .animation(reduce ? .linear(duration: 0.01) : .easeInOut(duration: 0.32), value: model.lit)
        .accessibilityLabel("Lamp")
        .accessibilityValue(model.lit ? "On" : "Off")
    }
}

struct LampSwitchStyle: ToggleStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                track(on: configuration.isOn)
                configuration.label
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }

    private func track(on: Bool) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(on ? Color(hex: Hex.orange, opacity: 0.55) : theme.ink.opacity(0.14))
                .overlay {
                    Capsule().strokeBorder(theme.shadow.opacity(0.25), lineWidth: 0.5)
                }
                .frame(width: 52, height: 30)

            Circle()
                .fill(theme.paper)
                .frame(width: 24, height: 24)
                .shadow(
                    color: on ? Color(hex: Hex.orange, opacity: 0.55) : .clear,
                    radius: 14, x: 0, y: 0
                )
                .shadow(color: theme.shadow.opacity(0.8), radius: 3, x: 0, y: 1)
                .offset(x: on ? 25 : 3, y: 0)
        }
        .frame(width: 52, height: 30)
    }
}

// MARK: - Music

private let songLength: Double = 245
private let musicBarCount = 34

struct MusicStage: View {
    @Environment(SiteModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var systemReduce

    @State private var playing = true
    @State private var seconds = 48
    @State private var stageWidth: CGFloat = 616

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var reduce: Bool { systemReduce || model.reduceMotion }
    private var progress: Int { Int((Double(seconds) / songLength * Double(musicBarCount)).rounded()) }

    var body: some View {
        VStack(spacing: 18) {
            capsule
                .frame(width: min(470, stageWidth))
            Text("Try the button. Nothing plays here; in Cue it’s your own music.")
                .font(Fonts.ui(13))
                .foregroundStyle(theme.ink2)
                .multilineTextAlignment(.center)
                .siteLines(13, 1.55)
                .frame(maxWidth: 470)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stageWidth = $0 }
        .onReceive(tick) { _ in
            guard playing else { return }
            seconds = (seconds + 1) % Int(songLength)
        }
    }

    private var capsule: some View {
        HStack(spacing: 14) {
            Button {
                playing.toggle()
            } label: {
                Circle()
                    .fill(LinearGradient(
                        colors: [ArtColor.purple, ArtColor.rose],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 52, height: 52)
                    .overlay {
                        if playing {
                            HStack(spacing: 2.8) {
                                RoundedRectangle(cornerRadius: 1).frame(width: 2.6, height: 10)
                                RoundedRectangle(cornerRadius: 1).frame(width: 2.6, height: 10)
                            }
                            .foregroundStyle(.white)
                        } else {
                            PlayGlyph()
                                .fill(.white)
                                .frame(width: 18, height: 18)
                        }
                    }
                    .shadow(color: ArtColor.purple.opacity(0.6), radius: 16, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "Pause" : "Play")

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Circle().fill(ArtColor.live).frame(width: 8, height: 8)
                    Text("Night Drive").font(Fonts.ui(15, weight: .semibold))
                }
                .foregroundStyle(theme.ink)
                .lineLimit(1)

                Text("\(timecode(seconds)) / \(timecode(Int(songLength)))")
                    .font(Fonts.ui(13))
                    .monospacedDigit()
                    .foregroundStyle(theme.ink2)
                    .lineLimit(1)
            }
            .fixedSize()

            Waveform(playing: playing, progress: progress, paused: !playing || reduce)
                .frame(height: 34)

            HStack(spacing: 6) {
                SkipGlyph(direction: .back)
                SkipGlyph(direction: .forward)
            }
            .foregroundStyle(theme.ink2)
            .accessibilityHidden(true)
        }
        .padding(.leading, 10)
        .padding(.trailing, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: .capsule)
        .background(theme.glass, in: .capsule)
        .overlay { Capsule().strokeBorder(theme.hair, lineWidth: 1) }
        .overlay(alignment: .top) {
            Capsule().fill(theme.glassEdge).frame(height: 1).padding(.horizontal, 24)
        }
        .clipShape(.capsule)
        .shadow(color: theme.shadow, radius: 48, x: 0, y: 24)
        .shadow(color: theme.shadow.opacity(0.7), radius: 16, x: 0, y: 8)
        .animation(.easeInOut(duration: 0.6), value: progress)
    }

    private func timecode(_ value: Int) -> String {
        "\(value / 60):\(String(format: "%02d", value % 60))"
    }
}

private struct Waveform: View {
    let playing: Bool
    let progress: Int
    let paused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: paused)) { context in
            Canvas { canvas, size in
                let t = context.date.timeIntervalSinceReferenceDate
                let gap: CGFloat = 2.5
                let available = size.width - gap * CGFloat(musicBarCount - 1)
                let barWidth = min(3, max(0.8, available / CGFloat(musicBarCount)))
                let total = barWidth * CGFloat(musicBarCount) + gap * CGFloat(musicBarCount - 1)
                let x0 = (size.width - total) / 2

                for index in 0..<musicBarCount {
                    let fraction = Double(index) / Double(musicBarCount - 1)
                    let color = barColor(fraction)
                    let value: Double
                    if paused {
                        value = 0.30
                    } else {
                        let duration = 0.9 + Double((index * 13) % 7) * 0.12
                        let delay = -Double((index * 37) % 11) * 0.11
                        let phase = ((t - delay) / duration).truncatingRemainder(dividingBy: 1)
                        let p = phase < 0 ? phase + 1 : phase
                        value = p < 0.5
                            ? 0.22 + 0.66 * (p / 0.5)
                            : 0.88 - 0.48 * ((p - 0.5) / 0.5)
                    }
                    let height = max(2, CGFloat(value) * size.height)
                    let rect = CGRect(
                        x: x0 + CGFloat(index) * (barWidth + gap),
                        y: (size.height - height) / 2,
                        width: barWidth,
                        height: height
                    )
                    canvas.fill(
                        Path(roundedRect: rect, cornerRadius: 1),
                        with: .color(color.opacity(index < progress ? 1 : 0.32))
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func barColor(_ t: Double) -> Color {
        if t < 0.5 {
            return ArtColor.purple.mixed(with: ArtColor.rose, amount: t * 2)
        }
        return ArtColor.rose.mixed(with: ArtColor.amber, amount: (t - 0.5) * 2)
    }
}

private struct PlayGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 5 * s, y: rect.minY + 3.2 * s))
        p.addLine(to: CGPoint(x: rect.minX + 5 * s, y: rect.minY + 12.8 * s))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + 6 * s, y: rect.minY + 13.3 * s),
            control: CGPoint(x: rect.minX + 5 * s, y: rect.minY + 13.3 * s)
        )
        p.addLine(to: CGPoint(x: rect.minX + 13.4 * s, y: rect.minY + 8.5 * s))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + 13.4 * s, y: rect.minY + 7.5 * s),
            control: CGPoint(x: rect.minX + 14.4 * s, y: rect.minY + 8 * s)
        )
        p.addLine(to: CGPoint(x: rect.minX + 6 * s, y: rect.minY + 2.7 * s))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + 5 * s, y: rect.minY + 3.2 * s),
            control: CGPoint(x: rect.minX + 5 * s, y: rect.minY + 2.7 * s)
        )
        p.closeSubpath()
        return p
    }
}

private struct SkipGlyph: View {
    enum Direction { case back, forward }
    let direction: Direction

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 16
            var path = Path()
            if direction == .back {
                path.move(to: CGPoint(x: 8 * s, y: 4 * s))
                path.addLine(to: CGPoint(x: 4 * s, y: 8 * s))
                path.addLine(to: CGPoint(x: 8 * s, y: 12 * s))
                path.move(to: CGPoint(x: 12 * s, y: 4 * s))
                path.addLine(to: CGPoint(x: 8 * s, y: 8 * s))
                path.addLine(to: CGPoint(x: 12 * s, y: 12 * s))
            } else {
                path.move(to: CGPoint(x: 8 * s, y: 4 * s))
                path.addLine(to: CGPoint(x: 12 * s, y: 8 * s))
                path.addLine(to: CGPoint(x: 8 * s, y: 12 * s))
                path.move(to: CGPoint(x: 4 * s, y: 4 * s))
                path.addLine(to: CGPoint(x: 8 * s, y: 8 * s))
                path.addLine(to: CGPoint(x: 4 * s, y: 12 * s))
            }
            context.stroke(
                path,
                with: .foreground,
                style: StrokeStyle(lineWidth: 1.5 * s, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: 16, height: 16)
    }
}

// MARK: - Title page

struct TitleStage: View {
    @Environment(SiteModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var systemReduce

    @State private var graphic = true
    @State private var stageWidth: CGFloat = 616

    private let tick = Timer.publish(every: 3.2, on: .main, in: .common).autoconnect()
    private var reduce: Bool { systemReduce || model.reduceMotion }
    private var pageWidth: CGFloat { min(380, stageWidth) }
    private var pageHeight: CGFloat { pageWidth * 11 / 8.5 }

    var body: some View {
        VStack(spacing: 16) {
            page
            Text(graphic ? "With a title graphic" : "Typed")
                .font(Fonts.ui(13))
                .foregroundStyle(theme.ink2)
                .siteLine(13, 1.55)
                .animation(nil, value: graphic)
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stageWidth = $0 }
        .onReceive(tick) { _ in
            guard !reduce else { return }
            graphic.toggle()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Harrow Light title page, \(graphic ? "with a title graphic" : "typed")")
    }

    private var page: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.paper)
                .shadow(color: theme.hair, radius: 0, x: 0, y: 1)
                .shadow(color: theme.shadow, radius: 70, x: 0, y: 40)
                .shadow(color: theme.shadow.opacity(0.65), radius: 30, x: 0, y: 14)

            VStack(spacing: 0) {
                if graphic {
                    TitleArt()
                        .padding(.bottom, 26)
                } else {
                    Text("HARROW LIGHT")
                        .font(Fonts.script(17))
                        .underline()
                        .foregroundStyle(theme.ink)
                        .padding(.top, 64)
                        .padding(.bottom, 52)
                }

                Text("Written by")
                    .font(Fonts.script(14))
                    .foregroundStyle(theme.ink)
                    .padding(.bottom, 10)
                Text("A. Writer")
                    .font(Fonts.script(14))
                    .foregroundStyle(theme.ink)
            }
            .frame(width: pageWidth * 0.78)
            .offset(y: -pageHeight * 0.12)
        }
        .frame(width: pageWidth, height: pageHeight)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct TitleArt: View {
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 320
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    let orange = Color(hex: Hex.orange)
                    let ink = theme.ink

                    var left = Path()
                    left.move(to: CGPoint(x: 160, y: 34))
                    left.addLine(to: CGPoint(x: 18, y: 14))
                    left.addLine(to: CGPoint(x: 18, y: 40))
                    left.closeSubpath()
                    ctx.fill(left, with: .linearGradient(
                        Gradient(stops: [
                            .init(color: orange.opacity(0.75), location: 0),
                            .init(color: orange.opacity(0), location: 1)
                        ]),
                        startPoint: CGPoint(x: 160, y: 34),
                        endPoint: CGPoint(x: 18, y: 27)
                    ))

                    var right = Path()
                    right.move(to: CGPoint(x: 160, y: 34))
                    right.addLine(to: CGPoint(x: 302, y: 22))
                    right.addLine(to: CGPoint(x: 302, y: 50))
                    right.closeSubpath()
                    ctx.fill(right, with: .linearGradient(
                        Gradient(stops: [
                            .init(color: orange.opacity(0.75), location: 0),
                            .init(color: orange.opacity(0), location: 1)
                        ]),
                        startPoint: CGPoint(x: 160, y: 34),
                        endPoint: CGPoint(x: 302, y: 36)
                    ))

                    var tower = Path()
                    tower.addRect(CGRect(x: 153, y: 30, width: 14, height: 8))
                    tower.move(to: CGPoint(x: 151, y: 39))
                    tower.addLine(to: CGPoint(x: 169, y: 39))
                    tower.addLine(to: CGPoint(x: 172, y: 85))
                    tower.addLine(to: CGPoint(x: 148, y: 85))
                    tower.closeSubpath()
                    ctx.fill(tower, with: .color(ink))

                    var roof = Path()
                    roof.move(to: CGPoint(x: 156, y: 25))
                    roof.addLine(to: CGPoint(x: 160, y: 20))
                    roof.addLine(to: CGPoint(x: 164, y: 25))
                    roof.closeSubpath()
                    ctx.fill(roof, with: .color(ink))

                    ctx.fill(
                        Path(ellipseIn: CGRect(x: 156.8, y: 30.8, width: 6.4, height: 6.4)),
                        with: .color(orange)
                    )

                    var horizon = Path()
                    horizon.move(to: CGPoint(x: 110, y: 87))
                    horizon.addLine(to: CGPoint(x: 210, y: 87))
                    ctx.stroke(horizon, with: .color(ink), lineWidth: 1.2)
                }

                Text("HARROW")
                    .font(Fonts.ui(38, weight: .heavy))
                    .tracking(9)
                    .foregroundStyle(theme.ink)
                    .position(x: 160, y: 113)

                Text("LIGHT")
                    .font(Fonts.ui(15))
                    .tracking(14)
                    .foregroundStyle(theme.ink)
                    .position(x: 160, y: 151)
            }
            .frame(width: 320, height: 170)
            .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(320.0 / 170.0, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Pins

struct PinsStage: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var systemReduce
    @Environment(SiteModel.self) private var model

    @State private var hoverA = false
    @State private var hoverB = false
    private var reduce: Bool { systemReduce || model.reduceMotion }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                page(width: width)

                pin(
                    artwork: AnyView(NightSeaArt()),
                    aspect: 240.0 / 160.0,
                    width: width * 0.52,
                    hovered: $hoverA
                )
                .frame(width: width * 0.52, height: width * 0.52 / 1.5)
                .rotationEffect(.degrees(hoverA ? 0 : 2.5))
                .offset(x: width * 0.48, y: hoverA ? -6 : 0)
                .zIndex(hoverA ? 2 : 0)

                pin(
                    artwork: AnyView(LighthouseArt()),
                    aspect: 160.0 / 200.0,
                    width: width * 0.30,
                    hovered: $hoverB
                )
                .frame(width: width * 0.30, height: width * 0.30 * 200 / 160)
                .rotationEffect(.degrees(hoverB ? 0 : -3))
                .offset(x: width * 0.56, y: 430 * 0.46 - (hoverB ? 6 : 0))
                .zIndex(hoverB ? 2 : 0)
            }
            .animation(reduce ? .linear(duration: 0.01) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32), value: hoverA)
            .animation(reduce ? .linear(duration: 0.01) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32), value: hoverB)
        }
        .frame(height: 430)
        .accessibilityHidden(true)
    }

    private func page(width: CGFloat) -> some View {
        let pageWidth = width * 0.64
        return VStack(alignment: .leading, spacing: 0) {
            Text("EXT. NORTH SEA - NIGHT")
                .font(Fonts.script(13.5, bold: true))
            Text("Fog. Not a bank of it, not a wall. A whole country of fog, grey on black, lying flat on a sea that barely breathes.")
            Text("A single running light crawls through it. Green. Then red as the boat turns.")
        }
        .font(Fonts.script(13.5))
        .lineSpacing(13.5 * 0.25)
        .foregroundStyle(theme.ink)
        .padding(.top, 40)
        .padding(.leading, width * 0.15)
        .padding(.trailing, 30)
        .frame(width: pageWidth, height: 410, alignment: .topLeading)
        .background(theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: theme.hair, radius: 0, x: 0, y: 1)
        .shadow(color: theme.shadow, radius: 60, x: 0, y: 30)
        .mask {
            LinearGradient(
                stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .offset(y: 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func pin(artwork: AnyView, aspect: CGFloat, width: CGFloat, hovered: Binding<Bool>) -> some View {
        ZStack(alignment: .top) {
            artwork
                .frame(width: width, height: width / aspect)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

            PinHead()
                .offset(y: -4)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            hovered.wrappedValue = inside
        }
        .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
        .shadow(color: theme.shadow, radius: hovered.wrappedValue ? 36 : 26, x: 0, y: hovered.wrappedValue ? 36 : 26)
    }
}

private struct PinHead: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Circle()
            .fill(theme.ink.opacity(0.55))
            .frame(width: 9, height: 9)
            .overlay {
                Circle().fill(.white.opacity(0.45)).frame(width: 3, height: 3).offset(y: -1)
            }
            .shadow(color: theme.shadow, radius: 2, x: 0, y: 1)
    }
}

private struct NightSeaArt: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 240
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            ctx.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(hex: 0x2B3138), location: 0),
                        .init(color: Color(hex: 0x59636B), location: 0.62),
                        .init(color: Color(hex: 0x1C2227), location: 1)
                    ]),
                    startPoint: .zero, endPoint: P(0, 160)
                )
            )

            ctx.fill(Path(CGRect(x: 0, y: 96 * s, width: 240 * s, height: 64 * s)),
                     with: .color(Color(hex: 0x161B1F).opacity(0.7)))

            var w1 = Path()
            w1.move(to: P(0, 92))
            w1.addQuadCurve(to: P(120, 92), control: P(60, 84))
            w1.addQuadCurve(to: P(240, 90), control: P(180, 100))
            w1.addLine(to: P(240, 104))
            w1.addLine(to: P(0, 104))
            w1.closeSubpath()
            ctx.fill(w1, with: .color(Color(hex: 0x8C979E).opacity(0.35)))

            var w2 = Path()
            w2.move(to: P(0, 70))
            w2.addQuadCurve(to: P(160, 72), control: P(80, 60))
            w2.addQuadCurve(to: P(240, 66), control: P(200, 78))
            w2.addLine(to: P(240, 80))
            w2.addLine(to: P(0, 80))
            w2.closeSubpath()
            ctx.fill(w2, with: .color(Color(hex: 0xB5BEC3).opacity(0.18)))

            ctx.fill(
                Path(ellipseIn: CGRect(x: (78 - 7) * s, y: (100 - 7) * s, width: 14 * s, height: 14 * s)),
                with: .color(Color(hex: 0x7EE08A).opacity(0.18))
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: (78 - 2.2) * s, y: (100 - 2.2) * s, width: 4.4 * s, height: 4.4 * s)),
                with: .color(Color(hex: 0x7EE08A))
            )

            var hull = Path()
            hull.move(to: P(66, 104))
            hull.addLine(to: P(92, 104))
            hull.addLine(to: P(89, 108))
            hull.addLine(to: P(70, 108))
            hull.closeSubpath()
            ctx.fill(hull, with: .color(Color(hex: 0x0E1215)))
        }
        .aspectRatio(240.0 / 160.0, contentMode: .fill)
    }
}

private struct LighthouseArt: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 160
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            ctx.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(hex: 0x3A2E4A), location: 0),
                        .init(color: Color(hex: 0xC46E52), location: 0.55),
                        .init(color: Color(hex: 0xF2B474), location: 1)
                    ]),
                    startPoint: .zero, endPoint: P(0, 200)
                )
            )

            var beam = Path()
            beam.move(to: P(86, 70))
            beam.addLine(to: P(160, 52))
            beam.addLine(to: P(160, 84))
            beam.closeSubpath()
            ctx.fill(beam, with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color(hex: 0xFFE2A8).opacity(0.8), location: 0),
                    .init(color: Color(hex: 0xFFE2A8).opacity(0), location: 1)
                ]),
                startPoint: P(86, 70), endPoint: P(160, 68)
            ))

            var land = Path()
            land.move(to: P(0, 170))
            land.addQuadCurve(to: P(70, 160), control: P(40, 150))
            land.addQuadCurve(to: P(160, 150), control: P(115, 170))
            land.addLine(to: P(160, 200))
            land.addLine(to: P(0, 200))
            land.closeSubpath()
            ctx.fill(land, with: .color(Color(hex: 0x2A1F26)))

            var tower = Path()
            tower.addRect(CGRect(x: 80 * s, y: 66 * s, width: 12 * s, height: 8 * s))
            tower.move(to: P(78, 75))
            tower.addLine(to: P(94, 75))
            tower.addLine(to: P(98, 157))
            tower.addLine(to: P(74, 157))
            tower.closeSubpath()
            ctx.fill(tower, with: .color(Color(hex: 0x2A1F26)))

            ctx.fill(
                Path(ellipseIn: CGRect(x: (86 - 3) * s, y: (70 - 3) * s, width: 6 * s, height: 6 * s)),
                with: .color(Color(hex: 0xFFE2A8))
            )
        }
        .aspectRatio(160.0 / 200.0, contentMode: .fill)
    }
}

// MARK: - Sticky notes

private struct StickyNote {
    let text: String
    let x: CGFloat
    let y: CGFloat
    let rotation: Double
    let beat: Double
    let tinted: Bool
    let struckLine: Int?
}

private let stickyNotes: [StickyNote] = [
    .init(text: "Does Amy already know about the line?\n\nTry the scene without the lamp.",
          x: 6, y: 0, rotation: -3, beat: 5.2, tinted: false, struckLine: nil),
    .init(text: "The typewriter: pay it off in the last scene?",
          x: 46, y: 14, rotation: 2.5, beat: 4.4, tinted: true, struckLine: nil),
    .init(text: "Fix the cold open\nCall Jo about the cabin\nRename the old lady",
          x: 18, y: 46, rotation: 1.5, beat: 6.0, tinted: false, struckLine: 0)
]

struct StickyStack: View {
    @Environment(SiteModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var systemReduce

    private var reduce: Bool { systemReduce || model.reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduce)) { context in
            GeometryReader { proxy in
                let width = proxy.size.width
                let t = context.date.timeIntervalSinceReferenceDate

                ZStack(alignment: .topLeading) {
                    ForEach(Array(stickyNotes.enumerated()), id: \.offset) { index, note in
                        StickyNoteView(
                            note: note,
                            width: width * 0.5,
                            time: t,
                            reduce: reduce,
                            delay: -Double(index) * 1.3
                        )
                        .offset(x: width * note.x / 100, y: 440 * note.y / 100)
                    }
                }
            }
        }
        .frame(height: 440)
        .accessibilityHidden(true)
    }
}

private struct StickyNoteView: View {
    @Environment(\.theme) private var theme
    @Environment(SiteModel.self) private var model

    let note: StickyNote
    let width: CGFloat
    let time: TimeInterval
    let reduce: Bool
    let delay: Double

    @State private var hovered = false
    private var night: Bool { model.lamp.lamp == .night }

    private var sway: (rotation: Double, lift: CGFloat) {
        guard !reduce else { return (note.rotation, 0) }
        var cycle = ((time - delay) / note.beat).truncatingRemainder(dividingBy: 2)
        if cycle < 0 { cycle += 2 }
        if cycle > 1 { cycle = 2 - cycle }
        let eased = cycle * cycle * (3 - 2 * cycle)
        return (note.rotation - 1.4 + 2.8 * eased, -3 * CGFloat(eased))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(note.text.components(separatedBy: "\n").enumerated()), id: \.offset) { index, line in
                Text(line.isEmpty ? " " : line)
                    .font(Fonts.ui(15))
                    .strikethrough(note.struckLine == index)
                    .foregroundStyle(note.struckLine == index ? theme.ink2 : theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .lineSpacing(15 * 0.45)
        .padding(.top, 18)
        .padding(.horizontal, 18)
        .padding(.bottom, 22)
        .frame(width: width, alignment: .topLeading)
        .frame(minHeight: 190, alignment: .topLeading)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(note.tinted ? tintedFace : face)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(night ? Color(hex: Hex.orange, opacity: 0.32) : theme.hair, lineWidth: 1)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(theme.glassEdge).frame(height: 1).padding(.horizontal, 1)
        }
        .shadow(
            color: night ? Color(hex: Hex.orange, opacity: 0.35) : theme.shadow,
            radius: hovered ? 50 : 34, x: 0, y: hovered ? 30 : 18
        )
        .offset(y: sway.lift + (hovered ? -8 : 0))
        .rotationEffect(.degrees(sway.rotation), anchor: .top)
        .onHover { hovered = $0 }
        .animation(
            reduce ? .linear(duration: 0.01) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32),
            value: hovered
        )
    }

    private var face: Color {
        if night { return Color(hex: 0x2A241D, opacity: 0.78) }
        // `color-mix(in srgb, var(--cream) 62%, var(--glass))` over the desk resolves to
        // roughly #FAF1DF. The material underneath keeps it translucent without greying it.
        return Color(hex: 0xFBF3E0, opacity: 0.9)
    }

    private var tintedFace: Color {
        if night { return Color(hex: 0x2A241D, opacity: 0.82) }
        // var(--tint) #6C9A70 at 22 % over the cream face: a soft sage, not a second cream.
        return Color(hex: 0xD9E3C6, opacity: 0.92)
    }
}

// MARK: - Snippet

struct SnippetStage: View {
    @Environment(SiteModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var systemReduce

    @State private var stageWidth: CGFloat = 616
    @State private var start = Date()

    private var reduce: Bool { systemReduce || model.reduceMotion }

    private var pageWidth: CGFloat { stageWidth * 1.38 }
    private var inch: CGFloat { pageWidth / 8.5 }
    private var fontSize: CGFloat { max(12.5, inch * 0.1667) }
    private var pageHeight: CGFloat { 17 * fontSize }
    private var stageHeight: CGFloat { pageHeight + 20 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduce)) { context in
            let t = reduce
                ? 2101.0
                : (context.date.timeIntervalSince(start) * 1000)
                    .truncatingRemainder(dividingBy: 7665)
            snippet(at: t)
        }
        .frame(height: stageHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stageWidth = $0 }
        .accessibilityHidden(true)
    }

    private func snippet(at time: Double) -> some View {
        let menu: Int? = time < 900 ? nil : (time < 3300 ? (time < 2100 ? 0 : 1) : nil)
        let nameCount = time >= 3300 ? min(4, Int((time - 3300) / 110) + 1) : 0
        let name = String("MAYA".prefix(nameCount))
        let lineCount = time >= 4240 ? min(15, Int((time - 4240) / 55) + 1) : 0
        let line = String("Fine. Two pages.".prefix(lineCount))
        let finishedName = time >= 4240

        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        Text("1")
                            .font(Fonts.script(fontSize * 0.85))
                            .foregroundStyle(theme.ink2)
                            .frame(width: pageWidth * 0.10, alignment: .leading)
                        Text("INT. KITCHEN TABLE - 2 AM")
                            .font(Fonts.script(fontSize, bold: true))
                            .foregroundStyle(theme.ink)
                    }

                    Text("A laptop glows. MAYA (30s) stares at a blinking cursor.")
                        .padding(.top, fontSize)
                    Text("The cat does not believe her.")
                        .padding(.top, fontSize)

                    if nameCount == 0 {
                        HStack(alignment: .top, spacing: 16) {
                            if let menu {
                                chooser(selected: menu)
                            }
                            Caret(color: theme.ink, height: fontSize * 1.05, reduce: reduce)
                        }
                        .padding(.top, fontSize)
                        .padding(.leading, menu == nil ? pageWidth * 0.1765 : pageWidth * 0.085)
                    } else {
                        speech(name: name, line: finishedName ? line : nil, lineVisible: lineCount > 0)
                            .padding(.top, fontSize)
                    }
                }
                .font(Fonts.script(fontSize))
                .foregroundStyle(theme.ink)
                .padding(.top, inch * 0.5)
                .padding(.bottom, inch * 0.4)
                .padding(.leading, pageWidth * 0.1765)
                .padding(.trailing, pageWidth * 0.1176)
                .frame(width: pageWidth, alignment: .topLeading)
                .frame(minHeight: pageHeight, alignment: .topLeading)
                .background(theme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(width: pageWidth, height: stageHeight, alignment: .topLeading)
        }
        .frame(width: stageWidth, height: stageHeight, alignment: .topLeading)
        .clipped()
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.74),
                    .init(color: .clear, location: 0.99)
                ],
                startPoint: .leading, endPoint: .trailing
            )
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.86),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .padding(.bottom, 20)
        .shadow(color: theme.shadow, radius: 30, x: 0, y: 30)
    }

    private func speech(name: String, line: String?, lineVisible: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name)
                .padding(.leading, pageWidth * 0.435)
            if let line, lineVisible {
                HStack(alignment: .top, spacing: 0) {
                    Text(line)
                    Caret(color: theme.ink, height: fontSize * 1.05, reduce: reduce)
                }
                .padding(.leading, pageWidth * 0.294)
                .frame(maxWidth: pageWidth * 0.766, alignment: .leading)
            } else {
                HStack(spacing: 0) {
                    Caret(color: theme.ink, height: fontSize * 1.05, reduce: reduce)
                }
                .padding(.leading, pageWidth * 0.435)
            }
        }
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(ArtColor.maya)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .offset(x: pageWidth * 0.1447 - pageWidth * 0.1765, y: -fontSize * 1.25)
        }
    }

    private func chooser(selected: Int) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            ForEach(Array(["Action", "Character", "Scene", "Transition"].enumerated()), id: \.offset) { index, title in
                Text(index == selected ? "\(title) •" : title)
                    .font(Fonts.ui(max(10, fontSize * 0.68), weight: index == selected ? .semibold : .regular))
                    .tracking(max(10, fontSize * 0.68) * 0.08)
                    .textCase(.uppercase)
                    .foregroundStyle(index == selected ? Color(hex: Hex.choice) : theme.ink2)
                    .opacity(index == selected ? 1 : 0.75)
            }
        }
        .lineSpacing(0)
        .fixedSize()
    }
}

private struct Caret: View {
    let color: Color
    let height: CGFloat
    let reduce: Bool
    @State private var visible = true
    private let timer = Timer.publish(every: 0.53, on: .main, in: .common).autoconnect()

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 1.5, height: height)
            .opacity(visible || reduce ? 1 : 0)
            .onReceive(timer) { _ in
                if !reduce { visible.toggle() }
            }
    }
}

// MARK: - Panel

private let panelScenes: [(String, String, String, [(String, Color)])] = [
    ("1", "EXT. NORTH SEA — NIGHT", "2/8", []),
    ("2", "INT. MARIGOLD — WHEELHOUSE", "1 5/8", [("Elias", ArtColor.maya), ("Ingrid", ArtColor.jo)]),
    ("3", "EXT. MARIGOLD — DECK — NIGHT", "5/8", [("Elias", ArtColor.maya)]),
    ("4", "INT. HARROW LIGHTHOUSE", "6/8", [("Ingrid", ArtColor.jo)]),
    ("5", "EXT. NORTH SEA — NIGHT", "1/8", [])
]

private let panelCast: [(String, Color, Int, Bool)] = [
    ("Elias", ArtColor.maya, 57, true),
    ("Ingrid", ArtColor.jo, 49, false)
]

struct PanelStage: View {
    @Environment(SiteModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var systemReduce

    @State private var tab = 0
    private let tick = Timer.publish(every: 3.8, on: .main, in: .common).autoconnect()

    private var reduce: Bool { systemReduce || model.reduceMotion }
    private var phone: Bool { SiteMath.isPhone(model.width) }
    private var stageHeight: CGFloat { phone ? 440 : 430 }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                if !phone {
                    page(width: width)
                }
                glass(width: width)
            }
            .frame(width: width, height: stageHeight, alignment: .topLeading)
        }
        .frame(height: stageHeight)
        .onReceive(tick) { _ in
            guard !reduce else { return }
            tab = tab == 0 ? 1 : 0
        }
        .onChange(of: reduce) { _, value in
            if value { tab = 0 }
        }
        .onAppear {
            if reduce { tab = 0 }
        }
        .accessibilityHidden(true)
    }

    private func page(width: CGFloat) -> some View {
        let pageWidth = width * 0.6
        let leading = max(120, min(310, width * 0.62) - width * 0.4 + 40)
        return VStack(alignment: .leading, spacing: 0) {
            Text("ELIAS").padding(.leading, 5.5 * 14).padding(.top, 14)
            panelLine("Who else would be daft enough?", color: ArtColor.maya)
            Text("INGRID (V.O.)").padding(.leading, 5.5 * 14).padding(.top, 14)
            panelLine("I had you down for home by six.", color: ArtColor.jo)
            Text("ELIAS").padding(.leading, 5.5 * 14).padding(.top, 14)
            panelLine("I had me down for home by six. The fog had other plans.", color: ArtColor.maya)
        }
        .font(Fonts.script(14))
        .lineSpacing(14 * 0.25)
        .foregroundStyle(theme.ink)
        .padding(.top, 44)
        .padding(.leading, leading)
        .frame(width: pageWidth, height: stageHeight - 36, alignment: .topLeading)
        .background(theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: theme.hair, radius: 0, x: 0, y: 1)
        .shadow(color: theme.shadow, radius: 60, x: 0, y: 30)
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading, endPoint: .trailing
            )
        }
        .offset(x: width * 0.4, y: 36)
    }

    private func panelLine(_ text: String, color: Color) -> some View {
        Text(text)
            .padding(.leading, 2.5 * 14)
            .frame(maxWidth: 16 * 14, alignment: .leading)
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(color)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .offset(y: -14 * 1.25)
            }
    }

    private func glass(width: CGFloat) -> some View {
        let glassWidth = phone ? min(360, width) : min(310, width * 0.62)
        return VStack(alignment: .leading, spacing: 0) {
            Text("‹ Library")
                .font(Fonts.ui(15))
                .foregroundStyle(theme.ink2)

            HStack(spacing: 4) {
                tabButton(0, "Scenes")
                tabButton(1, "Characters")
                Text("Notes")
                    .font(Fonts.ui(14))
                    .foregroundStyle(theme.ink2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                Spacer(minLength: 0)
            }
            .padding(3)
            .background(theme.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.top, 22)
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 0) {
                if tab == 0 {
                    ForEach(Array(panelScenes.enumerated()), id: \.offset) { _, row in
                        sceneRow(row)
                    }
                } else {
                    ForEach(Array(panelCast.enumerated()), id: \.offset) { _, row in
                        castRow(row)
                    }
                }
            }
            .id(tab)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.2), value: tab)

            Spacer(minLength: 0)
        }
        .padding(.top, 26)
        .padding(.horizontal, 18)
        .padding(.bottom, 26)
        .frame(width: glassWidth, height: stageHeight - 18, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .background(theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.hair, lineWidth: 1)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(theme.glassEdge).frame(height: 1).padding(.horizontal, 1)
        }
        .shadow(color: theme.shadow, radius: 40, x: 0, y: 20)
        .offset(x: phone ? (width - glassWidth) / 2 : 0)
    }

    private func tabButton(_ index: Int, _ title: String) -> some View {
        Text(title)
            .font(Fonts.ui(14))
            .foregroundStyle(tab == index ? theme.ink : theme.ink2)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background {
                if tab == index {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.paper)
                        .shadow(color: theme.shadow, radius: 2, x: 0, y: 1)
                }
            }
    }

    private func sceneRow(_ row: (String, String, String, [(String, Color)])) -> some View {
        let (number, title, length, cast) = row
        return HStack(alignment: .top, spacing: 4) {
            Text(number)
                .foregroundStyle(theme.ink2)
                .frame(width: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !cast.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(cast.enumerated()), id: \.offset) { _, member in
                            Circle().fill(member.1).frame(width: 7, height: 7)
                        }
                        Text(cast.map(\.0).joined(separator: ", "))
                            .foregroundStyle(theme.ink2)
                    }
                    .font(Fonts.ui(12.5))
                    .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
            Text(length)
                .foregroundStyle(theme.ink2)
        }
        .font(Fonts.ui(13.5))
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func castRow(_ row: (String, Color, Int, Bool)) -> some View {
        let (name, color, lines, pinned) = row
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7).frame(width: 18)
            HStack(spacing: 0) {
                Text(name).foregroundStyle(theme.ink).fontWeight(.medium)
                if pinned {
                    Text(" · pinned").font(Fonts.ui(12.5)).foregroundStyle(theme.ink2)
                }
            }
            Spacer(minLength: 0)
            Text("\(lines) lines").foregroundStyle(theme.ink2)
        }
        .font(Fonts.ui(13.5))
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Full UI

struct FullUIStage: View {
    @Environment(SiteModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var systemReduce

    private var reduce: Bool { systemReduce || model.reduceMotion }

    var body: some View {
        VStack(spacing: 0) {
            Slug(text: "INT. THE WHOLE DESK – ANY HOUR")
                .siteLine(14, 1.55, script: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 56)

            Color.clear
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay {
                    ZStack {
                        ForEach(Lamp.allCases) { lamp in
                            layer(lamp)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: theme.hair, radius: 0, x: 0, y: 1)
                .shadow(color: theme.shadow, radius: 90, x: 0, y: 50)
                .shadow(color: theme.shadow.opacity(0.7), radius: 34, x: 0, y: 16)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Cue's writing screen at \(SiteCopy.lampTitles[model.lamp.lamp] ?? ""): the script, the scenes panel and the music player")
        }
    }

    @ViewBuilder
    private func layer(_ lamp: Lamp) -> some View {
        Group {
            if let image = Assets.shot("full-\(lamp.rawValue)") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                theme.stack
            }
        }
        .opacity(model.lamp.lamp == lamp ? 1 : 0)
        .animation(
            reduce ? .linear(duration: 0.01) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.6),
            value: model.lamp.lamp
        )
        .accessibilityHidden(model.lamp.lamp != lamp)
    }
}

// MARK: - Extras

struct ExtrasList: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            VStack(alignment: .leading, spacing: 0) {
                Slug(text: "ALSO IN THE BAG")
                    .siteLine(14, 1.55, script: true)
                    .padding(.bottom, 14)

                ExtrasGrid(spacing: 22, columnSpacing: 40, minimum: 240) {
                    ForEach(Array(SiteCopy.extras.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.0)
                                .font(Fonts.ui(15.5, weight: .semibold))
                                .foregroundStyle(theme.ink)
                                .siteLine(15.5, 1.55)
                            Text(item.1)
                                .font(Fonts.ui(15.5))
                                .foregroundStyle(theme.ink2)
                                .siteLines(15.5, 1.55)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.top, 40)
        }
        .frame(maxWidth: .infinity)
    }
}

/// CSS `repeat(auto-fit, minmax(240px, 1fr))`, row-wise.
struct ExtrasGrid: Layout {
    var spacing: CGFloat
    var columnSpacing: CGFloat
    var minimum: CGFloat

    private func columns(for width: CGFloat) -> Int {
        max(1, Int(floor((width + columnSpacing) / (minimum + columnSpacing))))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let count = columns(for: width)
        let columnWidth = (width - columnSpacing * CGFloat(count - 1)) / CGFloat(count)
        var heights = [CGFloat](repeating: 0, count: count)
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let column = index % count
            if column == 0 && index > 0 {
                y += rowHeight + spacing
                rowHeight = 0
            }
            let height = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            heights[column] = max(heights[column], height)
            rowHeight = max(rowHeight, height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let count = columns(for: bounds.width)
        let columnWidth = (bounds.width - columnSpacing * CGFloat(count - 1)) / CGFloat(count)
        var rowTop = bounds.minY
        var rowHeight: CGFloat = 0
        var index = 0

        while index < subviews.count {
            let row = Array(subviews[index..<min(index + count, subviews.count)])
            let heights = row.map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
            rowHeight = heights.max() ?? 0
            for (column, subview) in row.enumerated() {
                subview.place(
                    at: CGPoint(x: bounds.minX + CGFloat(column) * (columnWidth + columnSpacing), y: rowTop),
                    proposal: ProposedViewSize(width: columnWidth, height: heights[column])
                )
            }
            rowTop += rowHeight + spacing
            index += count
        }
    }
}

// MARK: - Desk settle

struct DeskSettle: View {
    @Environment(SiteModel.self) private var model
    @Environment(\.siteViewportHeight) private var viewportHeight
    @Environment(\.accessibilityReduceMotion) private var systemReduce

    private var reduce: Bool { systemReduce || model.reduceMotion }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let scale = width / 1120
            let top = proxy.frame(in: .global).minY
            let head = reduce
                ? 1
                : clamp((viewportHeight - top) / (viewportHeight * 0.82), 0, 1)

            DeskArt(head: head, reduce: reduce)
                .frame(width: 1120, height: 700)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(1120.0 / 700.0, contentMode: .fit)
        .frame(maxWidth: 1120)
        .padding(.top, clamp(viewportHeight * 0.05, 32, 56))
        .accessibilityHidden(true)
    }
}

private struct DeskArt: View {
    @Environment(SiteModel.self) private var model
    @Environment(\.theme) private var theme

    let head: CGFloat
    let reduce: Bool

    private func progress(_ delay: CGFloat) -> CGFloat {
        guard !reduce else { return 1 }
        let value = clamp((head - delay) / 0.5, 0, 1)
        return 1 - pow(1 - value, 3)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            window

            DeskPanel(theme: theme, night: model.lamp.lamp == .night)
                .frame(width: 225.12, height: 658.56)
                .modifier(Settle(q: progress(0.10), turn: -3, width: 1120))
                .offset(x: 10.08, y: 31.36)

            DeskPage(theme: theme)
                .frame(width: 523.04, height: 666.4)
                .modifier(Settle(q: progress(0.18), turn: 2, width: 1120))
                .offset(x: 297.92, y: 33.6)

            DeskTools(theme: theme, lamp: model.lamp.lamp)
                .modifier(Settle(q: progress(0.30), turn: 0, width: 1120))
                .offset(x: 884.8, y: 34.72)

            DeskSticky(theme: theme, night: model.lamp.lamp == .night)
                .frame(width: 168.0, height: 134.4)
                .modifier(Settle(q: progress(0.36), turn: 7, width: 1120))
                .offset(x: 856.8, y: 100.8)

            DeskPin()
                .frame(width: 123.2, height: 156.8)
                .modifier(Settle(q: progress(0.42), turn: -7, width: 1120))
                .offset(x: 890.4, y: 302.4)

            DeskMusic(theme: theme)
                .frame(width: 287.84, height: 42.56)
                .modifier(Settle(q: progress(0.50), turn: 3, width: 1120))
                .offset(x: 810.88, y: 640.64)
        }
        .frame(width: 1120, height: 700, alignment: .topLeading)
    }

    private var window: some View {
        let q = progress(0)
        return RoundedRectangle(cornerRadius: 13.44, style: .continuous)
            .fill(theme.desk)
            .overlay {
                RoundedRectangle(cornerRadius: 13.44, style: .continuous)
                    .strokeBorder(theme.hair, lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6.16) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(theme.ink.opacity(0.22)).frame(width: 7.84, height: 7.84)
                    }
                }
                .padding(.leading, 11.2)
                .padding(.top, 10.08)
            }
            .shadow(color: theme.shadow, radius: 80, x: 0, y: 20 + q * 30)
            .opacity(q)
            .scaleEffect(0.94 + q * 0.06)
            .offset(y: (1 - q) * 44.8)
    }
}

private struct Settle: ViewModifier {
    let q: CGFloat
    let turn: CGFloat
    let width: CGFloat

    func body(content: Content) -> some View {
        let r = 1 - q
        content
            .opacity(min(1, q * 1.6))
            .rotation3DEffect(.degrees(r * 16), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .rotationEffect(.degrees(r * turn))
            .scaleEffect(1 + r * 0.12)
            .offset(y: r * -0.05 * width)
            .shadow(color: .black.opacity(0.10 * r), radius: 6 + r * 70, x: 0, y: 1 + r * 50)
    }
}

private struct DeskPanel: View {
    let theme: Theme
    let night: Bool

    private let scenes: [(String, String, String, [(String, Color)], Bool)] = [
        ("1", "INT. KITCHEN TABLE — 2 AM", "4/8", [("Maya", ArtColor.maya)], false),
        ("2", "EXT. BUS STOP — DAWN", "3/8", [("Maya", ArtColor.maya), ("Jo", ArtColor.jo)], true),
        ("3", "INT. NIGHT BUS — MOVING", "1 1/8", [("Maya", ArtColor.maya), ("Jo", ArtColor.jo), ("Driver", ArtColor.driver)], false),
        ("4", "EXT. DEPOT — MORNING", "2/8", [("Jo", ArtColor.jo)], false),
        ("5", "INT. KITCHEN TABLE — LATER", "5/8", [("Maya", ArtColor.maya)], false),
        ("6", "EXT. ROOFTOP — NIGHT", "3/8", [("Maya", ArtColor.maya), ("Jo", ArtColor.jo)], false)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("‹  Library")
                .font(Fonts.ui(10.08))
                .foregroundStyle(theme.ink2)
                .padding(.leading, 4.48)

            HStack(spacing: 2.24) {
                tab("Scenes", on: true)
                tab("Characters", on: false)
                tab("Notes", on: false)
                Spacer(minLength: 0)
                Text("⌕").font(Fonts.ui(9.18)).foregroundStyle(theme.ink2)
            }
            .padding(3.36)
            .background(theme.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 8.96, style: .continuous))
            .padding(.top, 16.8)
            .padding(.bottom, 15.68)

            ForEach(Array(scenes.enumerated()), id: \.offset) { _, row in
                sceneRow(row)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 16.8)
        .padding(.horizontal, 10.08)
        .frame(width: 225.12, height: 658.56, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .background(theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: 12.32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12.32, style: .continuous)
                .strokeBorder(theme.hair, lineWidth: 1)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                Hairline()
                HStack {
                    Text("▢  Title page")
                    Spacer()
                    Text("6 pages · ~6 min")
                }
                .font(Fonts.ui(8.4))
                .foregroundStyle(theme.ink2)
                .padding(.top, 10.08)
            }
            .padding(.horizontal, 13.44)
            .padding(.bottom, 13.44)
        }
    }

    private func tab(_ title: String, on: Bool) -> some View {
        Text(title)
            .font(Fonts.ui(9.18))
            .foregroundStyle(on ? theme.ink : theme.ink2)
            .padding(.horizontal, 10.08)
            .padding(.vertical, 5.04)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 6.72, style: .continuous)
                        .fill(theme.paper)
                        .shadow(color: theme.shadow, radius: 2, x: 0, y: 1)
                }
            }
    }

    private func sceneRow(_ row: (String, String, String, [(String, Color)], Bool)) -> some View {
        let (number, title, length, cast, current) = row
        return HStack(alignment: .top, spacing: 3.36) {
            Text(number)
                .foregroundStyle(theme.ink2)
                .frame(width: 17.92, alignment: .trailing)
                .overlay(alignment: .leading) {
                    if current {
                        Circle().fill(theme.ink).frame(width: 4.26, height: 4.26).offset(x: -3.36, y: 4.6)
                    }
                }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Fonts.ui(9.18, weight: .medium))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !cast.isEmpty {
                    HStack(spacing: 2.8) {
                        ForEach(Array(cast.enumerated()), id: \.offset) { _, member in
                            Circle().fill(member.1).frame(width: 4.7, height: 4.7)
                        }
                        Text(cast.map(\.0).joined(separator: ", "))
                            .font(Fonts.ui(8.06))
                            .foregroundStyle(theme.ink2)
                    }
                    .padding(.top, 3.36)
                }
            }
            Spacer(minLength: 0)
            Text(length)
                .font(Fonts.ui(9.18))
                .foregroundStyle(theme.ink2)
        }
        .padding(.vertical, 8.4)
        .padding(.horizontal, 5.6)
        .background {
            if current {
                RoundedRectangle(cornerRadius: 7.84, style: .continuous)
                    .fill(theme.paper.opacity(0.65))
            }
        }
    }
}

private struct DeskPage: View {
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("2.")
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, -11.2)
                .padding(.bottom, 10.46 * 1.8)

            pageText("Maya, coat over pyjamas, reads the pages out loud. JO (60s), the only other person waiting, pretends not to listen.")
            speech(name: "JO", line: "Is the cat in it?", color: ArtColor.jo)
            speech(name: "MAYA", line: "The cat is the whole second act.", color: ArtColor.maya)
            speech(name: "JO", paren: "(beat)", line: "Then I’m in.", color: ArtColor.jo)

            pageText("The bus pulls in. Its doors fold open with a sigh. Neither of them moves.")

            Text("CUT TO:")
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.bottom, 10.46)

            scene
            pageText("Empty seats. Orange streetlight slides across the windows. Maya writes on her knee. Jo reads over her shoulder.")
            speech(name: "JO", line: "You spelled “pyjamas” wrong.", color: ArtColor.jo)
            speech(name: "MAYA", line: "It’s a British cat.", color: ArtColor.maya, caret: true)
        }
        .font(Fonts.script(10.26))
        .lineSpacing(10.26 * 0.02)
        .foregroundStyle(theme.ink)
        .padding(.top, 38.08)
        .padding(.leading, 92.29)
        .padding(.trailing, 61.6)
        .frame(width: 523.04, height: 666.4, alignment: .topLeading)
        .background(theme.paper)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4.48, topTrailingRadius: 4.48))
    }

    private func pageText(_ text: String) -> some View {
        Text(text)
            .padding(.bottom, 10.46)
    }

    private var scene: some View {
        Text("     INT. NIGHT BUS - MOVING")
            .fontWeight(.bold)
            .padding(.top, 21.0)
            .padding(.bottom, 10.46)
            .overlay(alignment: .topLeading) {
                Text("3")
                    .fontWeight(.regular)
                    .foregroundStyle(theme.ink2)
                    .offset(x: -31.36, y: 21.0)
            }
    }

    private func speech(name: String, paren: String? = nil, line: String, color: Color, caret: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name)
                .padding(.leading, 135.52)
            if let paren {
                Text(paren).padding(.leading, 98.56)
            }
            HStack(spacing: 0) {
                Text(line)
                if caret {
                    Rectangle().fill(theme.ink).frame(width: 1.5, height: 10.8)
                }
            }
            .padding(.leading, 61.6)
            .frame(maxWidth: 276.64, alignment: .leading)
        }
        .padding(.bottom, 10.46)
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(color)
                .frame(width: 1.79)
                .frame(maxHeight: .infinity)
                .offset(x: -17.25, y: -12.8)
        }
    }
}

private struct DeskTools: View {
    let theme: Theme
    let lamp: Lamp

    var body: some View {
        HStack(spacing: 17.92) {
            Text("○ Saved")
            Image(systemName: "sidebar.left")
            Image(systemName: "speaker.wave.1")
            HStack(spacing: 3.92) {
                LampMini().stroke(theme.ink2, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                    .frame(width: 11.76, height: 11.76)
                Text(lamp.title)
            }
            Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
        .font(Fonts.ui(10.64))
        .foregroundStyle(theme.ink2)
        .fixedSize()
    }
}

private struct LampMini: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }
        var path = Path()
        path.move(to: p(5, 2)); path.addLine(to: p(11, 2))
        path.addLine(to: p(13, 7)); path.addLine(to: p(3, 7)); path.closeSubpath()
        path.move(to: p(8, 7)); path.addLine(to: p(8, 13))
        path.move(to: p(5, 14)); path.addLine(to: p(11, 14))
        return path
    }
}

private struct DeskSticky: View {
    let theme: Theme
    let night: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Does the cat already know?")
            Text("Cut the depot scene").strikethrough().opacity(0.55)
            Text("Try the bus without the lamp.")
        }
        .font(Fonts.ui(10.64))
        .lineSpacing(10.64 * 0.4)
        .foregroundStyle(night ? Color(hex: 0xF3E6D2) : Color(hex: 0x2B2825))
        .padding(.top, 14.56)
        .padding(.horizontal, 14.56)
        .padding(.bottom, 16.8)
        .frame(width: 168.0, alignment: .topLeading)
        .frame(minHeight: 134.4, alignment: .topLeading)
        .background(night ? Color(hex: 0x4A3520) : Color(hex: Hex.cream).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 5.6, style: .continuous))
    }
}

private struct DeskPin: View {
    var body: some View {
        ZStack {
            Color(hex: Hex.paper)
            DeskPinArt()
                .padding(.top, 5.6)
                .padding(.horizontal, 5.6)
                .padding(.bottom, 20.16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }
}

private struct DeskPinArt: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 150
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            ctx.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(hex: 0x1E2433), location: 0),
                        .init(color: Color(hex: 0x4B4A63), location: 0.6),
                        .init(color: Color(hex: 0xC98A5E), location: 1)
                    ]),
                    startPoint: .zero, endPoint: P(0, 190)
                )
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: (104 - 30) * s, y: (52 - 30) * s, width: 60 * s, height: 60 * s)),
                with: .color(Color(hex: 0xF6E7C8).opacity(0.12))
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: (104 - 15) * s, y: (52 - 15) * s, width: 30 * s, height: 30 * s)),
                with: .color(Color(hex: 0xF6E7C8))
            )
            var hills = Path()
            hills.move(to: P(0, 150))
            hills.addQuadCurve(to: P(78, 140), control: P(40, 128))
            hills.addQuadCurve(to: P(150, 128), control: P(114, 158))
            hills.addLine(to: P(150, 190))
            hills.addLine(to: P(0, 190))
            hills.closeSubpath()
            ctx.fill(hills, with: .color(Color(hex: 0x231C22)))
            ctx.fill(Path(roundedRect: CGRect(x: 22 * s, y: 132 * s, width: 40 * s, height: 14 * s), cornerRadius: 3 * s),
                     with: .color(Color(hex: 0x231C22)))
            ctx.fill(Path(CGRect(x: 26 * s, y: 135 * s, width: 6 * s, height: 5 * s)), with: .color(Color(hex: 0xFFC27A)))
            ctx.fill(Path(CGRect(x: 35 * s, y: 135 * s, width: 6 * s, height: 5 * s)), with: .color(Color(hex: 0xFFC27A).opacity(0.7)))
            ctx.fill(Path(CGRect(x: 44 * s, y: 135 * s, width: 6 * s, height: 5 * s)), with: .color(Color(hex: 0xFFC27A).opacity(0.5)))
        }
        .aspectRatio(150.0 / 190.0, contentMode: .fit)
    }
}

private struct DeskMusic: View {
    let theme: Theme

    var body: some View {
        HStack(spacing: 10.08) {
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0x6A4C93), Color(hex: 0xC46E52)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 33.6, height: 33.6)
                .overlay {
                    HStack(spacing: 1.8) {
                        RoundedRectangle(cornerRadius: 0.6).frame(width: 2, height: 7)
                        RoundedRectangle(cornerRadius: 0.6).frame(width: 2, height: 7)
                    }
                    .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5.6) {
                    Circle().fill(Color(hex: Hex.orange)).frame(width: 5.6, height: 5.6)
                    Text("Night Drive").font(Fonts.ui(9.18, weight: .medium))
                }
                Text("0:47 / 2:05")
                    .font(Fonts.ui(8.26))
                    .foregroundStyle(theme.ink2)
            }
            .foregroundStyle(theme.ink)
            .fixedSize()

            HStack(spacing: 3.36) {
                ForEach(Array([4, 7, 10, 6, 12, 9, 5, 11, 8, 6, 10, 4, 7, 9, 5, 8].enumerated()), id: \.offset) { index, value in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(LinearGradient(colors: [Color(hex: 0xC46E52), Color(hex: 0x6A4C93)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(maxWidth: .infinity)
                        .frame(height: 20.16 * CGFloat(value) / 12)
                        .opacity(index < 7 ? 1 : 0.35)
                }
            }
            .frame(height: 20.16)

            Text("«  »")
                .font(Fonts.ui(9.18))
                .foregroundStyle(theme.ink2)
        }
        .padding(.leading, 4.48)
        .padding(.trailing, 12.32)
        .frame(width: 287.84, height: 42.56, alignment: .leading)
        .background(theme.glass, in: .capsule)
        .overlay { Capsule().strokeBorder(theme.hair, lineWidth: 1) }
    }
}

// MARK: - Colour blend helper

extension Color {
    /// Straight sRGB interpolation, used for the waveform's three-stop ramp.
    func mixed(with other: Color, amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .black
        let t = max(0, min(1, amount))
        return Color(
            .sRGB,
            red: a.redComponent + (b.redComponent - a.redComponent) * t,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
            opacity: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * t
        )
    }
}
