import SwiftUI
import AppKit
import Observation
import CueKit

// MARK: - The mock inside the MacBook

/// The hero's mock app. Authored at 1440 × 900 stage pixels and scaled uniformly to the
/// screen, never reflowed. It carries its own lamp, so the page's lamp cannot tint it.
struct HeroMock: View {
    @Environment(SiteModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    let screenWidth: CGFloat
    let isActive: Bool

    @State private var driver = HeroMockDriver()

    private var reduceMotion: Bool { systemReduceMotion || model.reduceMotion }
    private var scale: CGFloat { screenWidth / 1440 }

    var body: some View {
        HeroMockStage(driver: driver)
            .frame(width: 1440, height: 900)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: screenWidth, height: screenWidth * 900 / 1440, alignment: .topLeading)
            .clipped()
            .theme(Theme.of(driver.lamp))
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel("Cue’s writing screen: a screenplay page for INT. APARTMENT - NIGHT, with the scenes panel open.")
            .task(id: reduceMotion) {
                await driver.run(reduceMotion: reduceMotion)
            }
            .onChange(of: isActive, initial: true) { _, active in
                driver.visible = active
            }
    }
}

// MARK: - Script data

struct MockLine: Identifiable, Equatable {
    let id: Int
    var type: ElementType
    var text: String
}

enum HeroStep {
    case wait(Double)
    case new(ElementType)
    case type(String, Double)
    case ghost(String)
    case accept
    case paren(String)
    case choose(Int)
    case menu(Int)
    case caret(Bool)
    case sidebar(Bool)
    case lamp(Lamp)
    case fade(Bool)
}

enum HeroScript {
    static let chooserTypes: [ElementType] = [.action, .character, .scene, .transition]
    static let times = ["- DAY", "- NIGHT", "MORNING", "EVENING", "CONTINUOUS", "LATER"]

    static let steps: [HeroStep] = [
        .wait(900),
        .new(.scene),
        .type("INT. APARTMENT", 9),
        .wait(300),
        .menu(1),
        .wait(200),
        .new(.action),
        .type("A small room lit by a single desk lamp. Rain on the window. DANIEL (30s, tired, kind) sits at a typewriter he no longer uses.", 62),
        .wait(350),
        .choose(0),
        .type("The door opens. AMY (30s) shakes the rain from her coat.", 62),
        .wait(350),
        .choose(1),
        .type("AMY", 9),
        .wait(200),
        .new(.dialogue),
        .type("You’re still up.", 26),
        .wait(300),
        .choose(1),
        .type("D", 6),
        .ghost("ANIEL"),
        .wait(500),
        .accept,
        .wait(200),
        .new(.dialogue),
        .paren("not looking up"),
        .new(.dialogue),
        .type("I’m still up.", 26),
        .wait(300),
        .choose(0),
        .type("She crosses to the lamp. Warm light on both of them.", 62),
        .wait(300),
        .choose(1),
        .type("A", 6),
        .ghost("MY"),
        .wait(400),
        .accept,
        .wait(150),
        .new(.dialogue),
        .type("Did you write anything?", 26),
        .wait(300),
        .choose(1),
        .type("D", 6),
        .ghost("ANIEL"),
        .wait(350),
        .accept,
        .wait(150),
        .new(.dialogue),
        .type("One line. It’s a good line, though.", 26),
        .wait(300),
        .choose(3),
        .type("CUT TO:", 10),
        .wait(900),
        .caret(false),
        .sidebar(true),
        .wait(2200),
        .lamp(.evening),
        .wait(1600),
        .lamp(.night),
        .wait(3200),
        .fade(true),
        .wait(700)
    ]

    /// The hand-authored still shown under Reduce Motion: eight lines, sidebar open, no caret.
    static let stillLines: [(ElementType, String)] = [
        (.scene, "INT. APARTMENT - NIGHT"),
        (.action, "A small room lit by a single desk lamp. Rain on the window. DANIEL (30s, tired, kind) sits at a typewriter he no longer uses."),
        (.action, "The door opens. AMY (30s) shakes the rain from her coat."),
        (.character, "AMY"),
        (.dialogue, "You’re still up."),
        (.character, "DANIEL"),
        (.paren, "(not looking up)"),
        (.dialogue, "I’m still up.")
    ]
}

// MARK: - Driver

@MainActor
@Observable
final class HeroMockDriver {
    var els: [MockLine] = []
    var ghost = ""
    var chooser: Int?
    var menu: Int?
    var sidebar = false
    var lamp: Lamp = .daylight
    var caret = true
    var fade = false

    /// Set from the view: offscreen or hidden freezes the clock, as the site's waits do.
    var visible = true

    private var nextID = 0

    func run(reduceMotion: Bool) async {
        if reduceMotion {
            showStill()
            return
        }
        while !Task.isCancelled {
            reset()
            for step in HeroScript.steps {
                if Task.isCancelled { return }
                await perform(step)
            }
        }
    }

    private func reset() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            els = []
            ghost = ""
            chooser = nil
            menu = nil
            caret = true
        }
        nextID = 0
        // The site lets these transition back rather than snapping: the panel slides
        // shut, the lamp warms up and the screen fades back in under the first wait.
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5)) { sidebar = false }
        withAnimation(.cueLamp) { lamp = .daylight }
        withAnimation(.cueFade) { fade = false }
    }

    private func showStill() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            els = HeroScript.stillLines.enumerated().map { index, line in
                MockLine(id: index, type: line.0, text: line.1)
            }
            ghost = ""
            chooser = nil
            menu = nil
            sidebar = true
            lamp = .daylight
            caret = false
            fade = false
        }
        nextID = HeroScript.stillLines.count
    }

    private func perform(_ step: HeroStep) async {
        switch step {
        case .wait(let ms):
            await pause(ms)

        case .new(let type):
            append(type)

        case .type(let text, let cps):
            for character in text {
                if Task.isCancelled { return }
                appendCharacter(character)
                let base = 1000.0 / cps
                let delay: Double
                if character == " " {
                    delay = base * 0.7
                } else if character == "." || character == "," {
                    delay = base * 2.2
                } else {
                    delay = base * Double.random(in: 0.6...1.4)
                }
                await pause(delay)
            }

        case .ghost(let text):
            ghost = text

        case .accept:
            if let last = els.indices.last {
                els[last].text += ghost
            }
            ghost = ""

        case .paren(let phrase):
            if let last = els.indices.last {
                els[last].type = .paren
                els[last].text = "()"
            }
            await pause(250)
            if !phrase.isEmpty {
                for count in 1...phrase.count {
                    if Task.isCancelled { return }
                    if let last = els.indices.last {
                        els[last].text = "(" + String(phrase.prefix(count)) + ")"
                    }
                    await pause(1000.0 / 16)
                }
            }
            await pause(250)

        case .choose(let index):
            append(.new)
            chooser = 0
            await pause(500)
            if index > 0 {
                for step in 1...index {
                    chooser = step
                    await pause(260)
                }
            }
            await pause(220)
            if let last = els.indices.last {
                els[last].type = HeroScript.chooserTypes[index]
            }
            chooser = nil
            await pause(120)

        case .menu(let steps):
            menu = 0
            await pause(600)
            if steps > 0 {
                for step in 1...steps {
                    menu = step
                    await pause(300)
                }
            }
            await pause(300)
            if let last = els.indices.last {
                let time = HeroScript.times[steps].replacingOccurrences(of: "- ", with: "")
                els[last].text += " - " + time
            }
            menu = nil

        case .caret(let on):
            caret = on

        case .sidebar(let open):
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5)) {
                sidebar = open
            }

        case .lamp(let value):
            withAnimation(.cueLamp) { lamp = value }

        case .fade(let on):
            withAnimation(.cueFade) { fade = on }
        }
    }

    private func append(_ type: ElementType) {
        els.append(MockLine(id: nextID, type: type, text: ""))
        nextID += 1
    }

    private func appendCharacter(_ character: Character) {
        if els.isEmpty {
            append(.new)
        }
        guard let last = els.indices.last else { return }
        els[last].text.append(character)
    }

    /// Visibility-aware wait: only visible, foreground time counts down.
    private func pause(_ milliseconds: Double) async {
        var left = milliseconds
        var last = Date()
        while left > 0 {
            if Task.isCancelled { return }
            let chunk = min(max(left, 1), 120)
            try? await Task.sleep(nanoseconds: UInt64(chunk * 1_000_000))
            let now = Date()
            let elapsed = now.timeIntervalSince(last) * 1000
            last = now
            if visible && !NSApplication.shared.isHidden {
                left -= elapsed
            }
        }
    }
}

// MARK: - Stage

private struct HeroMockStage: View {
    @Environment(\.theme) private var theme
    let driver: HeroMockDriver

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(theme.desk)
            MockLight(light: theme.light)
            MockToolbar(sidebar: driver.sidebar, lamp: driver.lamp)
                .offset(y: 40)
            MockPage(driver: driver)
                .offset(x: (1440 - 690) / 2, y: 92)
            MockSidebar(sidebar: driver.sidebar)
                .offset(x: driver.sidebar ? 0 : -340, y: 0)
                .offset(x: 16, y: 16)
                .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5), value: driver.sidebar)
        }
        .frame(width: 1440, height: 900)
        .clipped()
        .opacity(driver.fade ? 0 : 1)
    }
}

private struct MockLight: View {
    let light: Double

    var body: some View {
        Canvas { context, size in
            context.translateBy(x: size.width * 0.5, y: -size.height * 0.08)
            context.scaleBy(x: size.width * 0.6, y: size.height * 0.7)
            let gradient = Gradient(stops: [
                .init(color: Color(hex: Hex.orange, opacity: light), location: 0),
                .init(color: Color(hex: Hex.orange, opacity: light * 0.45), location: 0.40),
                .init(color: Color(hex: Hex.orange, opacity: 0), location: 0.75)
            ])
            context.fill(
                Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: 1)
            )
        }
        .frame(width: 1440, height: 900)
        .allowsHitTesting(false)
    }
}

private struct MockToolbar: View {
    @Environment(\.theme) private var theme
    let sidebar: Bool
    let lamp: Lamp

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Text("‹ Library")
                    .opacity(sidebar ? 0 : 1)
                    .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32), value: sidebar)
                Spacer(minLength: 0)
                HStack(spacing: 26) {
                    Text("○ Saved")
                    Text("▯")
                    Text("⚲ " + lamp.title)
                }
            }
            .padding(.leading, 60)
            .padding(.trailing, 44)

            HStack(spacing: 8) {
                Text("One Good Line")
                    .foregroundStyle(theme.ink)
                    .fontWeight(.medium)
                Text("Scene 1 · Page 1 of 1")
                    .foregroundStyle(theme.ink2)
            }
        }
        .font(Fonts.ui(15))
        .foregroundStyle(theme.ink2)
        .frame(width: 1440, height: 32)
    }
}

// MARK: - Page

private let mockScriptSize: CGFloat = 13.53
private let mockPageWidth: CGFloat = 690
private let mockPageHeight: CGFloat = 1000

private struct MockPage: View {
    @Environment(\.theme) private var theme
    let driver: HeroMockDriver

    var body: some View {
        let speakers = speakerColours()
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.paper)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(driver.els.enumerated()), id: \.element.id) { index, line in
                    MockLineView(
                        line: line,
                        isLast: index == driver.els.count - 1,
                        ghost: driver.ghost,
                        chooser: driver.chooser,
                        menu: driver.menu,
                        showCaret: driver.caret,
                        speaker: speakers[index]
                    )
                    .padding(.top, margin(index: index, type: line.type))
                    .zIndex(zIndex(line: line, index: index))
                }
            }
            .padding(.top, mockScriptSize * 5.4)
            .frame(width: mockPageWidth, alignment: .topLeading)
        }
        .frame(width: mockPageWidth, height: mockPageHeight, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: theme.shadow, radius: 30, x: 0, y: 30)
        .shadow(color: theme.shadow, radius: 12, x: 0, y: 12)
    }

    private func margin(index: Int, type: ElementType) -> CGFloat {
        guard index > 0 else { return 0 }
        switch type {
        case .scene: return mockScriptSize * 2
        case .paren, .dialogue: return 0
        default: return mockScriptSize
        }
    }

    private func zIndex(line: MockLine, index: Int) -> Double {
        guard index == driver.els.count - 1 else { return 0 }
        if driver.menu != nil { return 3 }
        if driver.chooser != nil { return 2 }
        return 0
    }

    /// Mirrors the source: the last character with text names the rail for every
    /// character, parenthetical and dialogue line that follows it.
    private func speakerColours() -> [Color?] {
        var current: String?
        return driver.els.map { line in
            if line.type == .character, !line.text.isEmpty {
                let name = line.text.replacingOccurrences(of: "\\(.*$", with: "", options: .regularExpression)
                current = name.trimmingCharacters(in: .whitespaces)
            } else if line.type != .paren && line.type != .dialogue {
                current = nil
            }
            guard line.type == .character || line.type == .paren || line.type == .dialogue else {
                return nil
            }
            return current.flatMap { Self.cast[$0] }
        }
    }

    private static let cast: [String: Color] = [
        "AMY": Color(hex: 0xD0664A),
        "DANIEL": Color(hex: 0x6C9A70)
    ]
}

private struct MockLineView: View {
    @Environment(\.theme) private var theme
    let line: MockLine
    let isLast: Bool
    let ghost: String
    let chooser: Int?
    let menu: Int?
    let showCaret: Bool
    let speaker: Color?

    private var advance: CGFloat { mockScriptSize * 0.6 }

    private var left: CGFloat {
        switch line.type {
        case .character: return mockPageWidth * 0.435
        case .paren: return mockPageWidth * 0.365
        case .dialogue: return mockPageWidth * 0.294
        default: return mockPageWidth * 0.1765
        }
    }

    private var right: CGFloat {
        switch line.type {
        case .paren: return mockPageWidth * 0.30
        case .dialogue: return mockPageWidth * 0.294
        default: return mockPageWidth * 0.1176
        }
    }

    private var available: CGFloat { mockPageWidth - left - right }

    var body: some View {
        let wrapped = Self.wrap(line.text, maxWidth: available, advance: advance)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(wrapped.indices, id: \.self) { index in
                HStack(spacing: 0) {
                    Text(wrapped[index])
                        .font(Fonts.script(mockScriptSize, bold: line.type == .scene))
                        .foregroundStyle(theme.ink)
                        .fixedSize()
                    if isLast && index == wrapped.count - 1 {
                        if !ghost.isEmpty {
                            Text(ghost)
                                .font(Fonts.script(mockScriptSize))
                                .foregroundStyle(theme.ink2.opacity(0.55))
                                .fixedSize()
                        }
                        if showCaret && chooser == nil {
                            MockCaret(size: mockScriptSize)
                        }
                    }
                }
                .frame(
                    width: available,
                    height: mockScriptSize,
                    alignment: line.type == .transition ? .trailing : .leading
                )
            }
        }
        .padding(.leading, left)
        .padding(.trailing, right)
        .overlay(alignment: .topLeading) {
            if let speaker {
                Rectangle()
                    .fill(speaker)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .opacity(0.9)
                    .offset(x: mockPageWidth * 0.1447)
            }
        }
        .overlay(alignment: .topLeading) {
            if line.type == .scene {
                Text("1")
                    .font(Fonts.script(mockScriptSize * 0.85))
                    .foregroundStyle(theme.ink2)
                    .offset(x: mockPageWidth * 0.10)
            }
        }
        .overlay(alignment: .topLeading) {
            if let chooser, isLast {
                MockChooser(index: chooser)
                    .frame(width: mockPageWidth * 0.1765 - 14, alignment: .topTrailing)
            }
        }
        .overlay(alignment: .topLeading) {
            if let menu, isLast {
                MockTimeMenu(index: menu)
                    .offset(x: mockPageWidth * 0.1765, y: mockScriptSize + 6)
            }
        }
    }

    static func wrap(_ text: String, maxWidth: CGFloat, advance: CGFloat) -> [String] {
        let maxChars = max(1, Int(floor(maxWidth / max(advance, 1))))
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [""] }

        var lines: [String] = []
        var current = ""

        func flushLongWord(_ word: String) {
            var rest = word
            while rest.count > maxChars {
                lines.append(String(rest.prefix(maxChars)))
                rest = String(rest.dropFirst(maxChars))
            }
            current = rest
        }

        for word in words {
            if current.isEmpty {
                flushLongWord(word)
            } else if current.count + 1 + word.count <= maxChars {
                current += " " + word
            } else {
                lines.append(current)
                flushLongWord(word)
            }
        }
        if !current.isEmpty || lines.isEmpty {
            lines.append(current)
        }
        return lines
    }
}

// MARK: - Chooser and time menu

private struct MockChooser: View {
    @Environment(\.theme) private var theme
    let index: Int

    private let options = ["Action", "Character", "Scene", "Transition"]

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            ForEach(options.indices, id: \.self) { row in
                Text(row == index ? options[row].uppercased() + " •" : options[row].uppercased())
                    .font(Fonts.ui(10, weight: row == index ? .semibold : .regular))
                    .tracking(0.8)
                    .foregroundStyle(row == index ? Color(hex: Hex.choiceText) : theme.ink2.opacity(0.75))
            }
            VStack(alignment: .trailing, spacing: 0) {
                Text("⏎ choose · ⇥ next")
                Text("or just type")
            }
            .font(Fonts.ui(8.5))
            .foregroundStyle(theme.ink2.opacity(0.6))
            .padding(.top, 6)
        }
        .fixedSize()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct MockTimeMenu: View {
    @Environment(\.theme) private var theme
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(HeroScript.times.indices, id: \.self) { row in
                Text(HeroScript.times[row])
                    .font(Fonts.script(mockScriptSize, bold: row == index))
                    .foregroundStyle(row == index ? Color(hex: Hex.choiceText) : theme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        if row == index {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color(hex: Hex.choice, opacity: 0.08))
                        }
                    }
            }
        }
        .padding(6)
        .frame(minWidth: mockScriptSize * 13, alignment: .leading)
        .background(.ultraThinMaterial)
        .background(theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.hair, lineWidth: 1)
        }
        .shadow(color: theme.shadow, radius: 15, x: 0, y: 14)
        .fixedSize(horizontal: true, vertical: false)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct MockCaret: View {
    @Environment(\.theme) private var theme
    let size: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.53)) { context in
            let on = Int(context.date.timeIntervalSinceReferenceDate / 0.53) % 2 == 0
            Rectangle()
                .fill(theme.ink)
                .frame(width: 1.5, height: size * 1.05)
                .offset(y: size * 0.15)
                .opacity(on ? 1 : 0)
        }
    }
}

// MARK: - Sidebar

private struct MockSidebar: View {
    @Environment(\.theme) private var theme
    let sidebar: Bool

    private struct Scene {
        let number: String
        let title: String
        let eighths: String
        let cast: [(Color, String)]
    }

    private static let scenes: [Scene] = [
        Scene(number: "1", title: "INT. KITCHEN TABLE — 2 AM", eighths: "4/8",
              cast: [(Color(hex: 0xD0664A), "Maya")]),
        Scene(number: "2", title: "EXT. BUS STOP — DAWN", eighths: "3/8",
              cast: [(Color(hex: 0xD0664A), "Maya"), (Color(hex: 0x6C9A70), "Jo")]),
        Scene(number: "3", title: "INT. NIGHT BUS — MOVING", eighths: "1 1/8",
              cast: [(Color(hex: 0xD0664A), "Maya"), (Color(hex: 0x6C9A70), "Jo"),
                     (Color(hex: 0xC99A3E), "Driver")]),
        Scene(number: "4", title: "EXT. DEPOT — MORNING", eighths: "2/8",
              cast: [(Color(hex: 0x6C9A70), "Jo")]),
        Scene(number: "5", title: "INT. KITCHEN TABLE — LATER", eighths: "5/8",
              cast: [(Color(hex: 0xD0664A), "Maya")]),
        Scene(number: "6", title: "EXT. ROOFTOP — NIGHT", eighths: "3/8",
              cast: [(Color(hex: 0xD0664A), "Maya"), (Color(hex: 0x6C9A70), "Jo")])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("‹ Library")
                .font(Fonts.ui(15))
                .foregroundStyle(theme.ink2)

            tabs
                .padding(.top, 22)
                .padding(.bottom, 18)

            VStack(spacing: 2) {
                ForEach(Self.scenes.indices, id: \.self) { index in
                    row(Self.scenes[index])
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                Text("▢\u{00A0} Title page")
                Spacer(minLength: 0)
                Text("6 pages · ~6 min")
            }
            .font(Fonts.ui(12))
            .foregroundStyle(theme.ink2)
            .padding(.top, 10)
            .overlay(alignment: .top) {
                Rectangle().fill(theme.hair).frame(height: 1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 26)
        .frame(width: 300, height: 868, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .background(theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.hair, lineWidth: 1)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(theme.glassEdge).frame(height: 1)
        }
        .shadow(color: theme.shadow, radius: 20, x: 0, y: 20)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            tab("Scenes", on: true)
            tab("Characters", on: false)
            tab("Notes", on: false)
        }
        .padding(3)
        .background(Color(hex: Hex.ink, opacity: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func tab(_ title: String, on: Bool) -> some View {
        Text(title)
            .font(Fonts.ui(14))
            .foregroundStyle(on ? theme.ink : theme.ink2)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.paper)
                        .shadow(color: theme.shadow, radius: 1, x: 0, y: 1)
                }
            }
    }

    private func row(_ scene: Scene) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(scene.number)
                .foregroundStyle(theme.ink2)
                .frame(width: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(scene.title)
                    .foregroundStyle(theme.ink)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(scene.cast.indices, id: \.self) { index in
                        Circle()
                            .fill(scene.cast[index].0)
                            .frame(width: 7, height: 7)
                    }
                    Text(scene.cast.map { $0.1 }.joined(separator: ", "))
                        .foregroundStyle(theme.ink2)
                        .font(Fonts.ui(13))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(scene.eighths)
                .foregroundStyle(theme.ink2)
        }
        .font(Fonts.ui(13.5))
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(theme.paper.opacity(0.70))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
