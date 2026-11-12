import SwiftUI
import AppKit
import Observation

// MARK: - Hex source of truth

public enum Hex {
    public static let desk: UInt32 = 0xECE9E4
    public static let paper: UInt32 = 0xFFFDF9
    public static let stack: UInt32 = 0xF3EFE9
    public static let ink: UInt32 = 0x2B2825
    public static let ink2: UInt32 = 0x6B655D
    public static let orange: UInt32 = 0xFFA349
    public static let ember: UInt32 = 0x9C5206
    public static let cream: UInt32 = 0xFDF0D5
    public static let choice: UInt32 = 0xD9402F
    public static let choiceText: UInt32 = 0xC93A2A

    public static let eveningDesk: UInt32 = 0xE8DFD4
    public static let eveningPaper: UInt32 = 0xFFFAF2
    public static let eveningStack: UInt32 = 0xEFE5D8
    public static let eveningShadow: UInt32 = 0x5C331A

    public static let nightDesk: UInt32 = 0x14110E
    public static let nightPaper: UInt32 = 0x24211D
    public static let nightStack: UInt32 = 0x1A1714
    public static let nightInk: UInt32 = 0xE6DFD4
    public static let nightInk2: UInt32 = 0x9A9186

    public static let characters: [UInt32] = [
        0xD0664A, 0x6C9A70, 0xC99A3E, 0xA8607C,
        0x4E9396, 0xB8744C, 0x8A8B4A, 0xC47489
    ]

    /// Marker colours for margin notes and stickies.
    public static let noteTints: [UInt32] = [
        0xF2D98B, 0xA9D6D2, 0xE5B7C4, 0xC7D8A8
    ]
}

public enum NoteTint {
    public static func color(_ index: Int) -> Color {
        Color(hex: Hex.noteTints[abs(index) % Hex.noteTints.count])
    }
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Screenplay character colours, by first-appearance index.
    static func character(_ index: Int) -> Color {
        Color(hex: Hex.characters[index % Hex.characters.count])
    }
}

public extension NSColor {
    convenience init(hex: UInt32, opacity: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: opacity
        )
    }
}

// MARK: - Lamp

public enum Lamp: String, CaseIterable, Codable, Sendable, Identifiable {
    case daylight, evening, night

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .daylight: "Daylight"
        case .evening: "Evening"
        case .night: "Night"
        }
    }

    public var colorScheme: ColorScheme { self == .night ? .dark : .light }
}

@MainActor
@Observable
public final class LampController {
    public enum Choice: Equatable {
        case auto
        case manual(Lamp)
    }

    public private(set) var choice: Choice = .auto
    public private(set) var lamp: Lamp = .daylight
    /// The page can turn the lamp off; the app binds this to ⌥⌘L.
    public var lit: Bool = true

    private var timer: Task<Void, Never>?
    private let defaults: UserDefaults?
    private let persist: Bool

    public init(persist: Bool = false) {
        self.persist = persist
        self.defaults = persist ? .standard : nil
        if persist, let raw = defaults?.string(forKey: "lamp.choice") {
            if raw == "auto" {
                choice = .auto
            } else if let value = Lamp(rawValue: raw) {
                choice = .manual(value)
            }
            lit = defaults?.object(forKey: "lamp.lit") as? Bool ?? true
        }
        lamp = choice == .auto ? Self.schedule(for: Date()) : {
            if case .manual(let value) = choice { return value }
            return .daylight
        }()
    }

    public var isAuto: Bool { choice == .auto }

    public var label: String {
        isAuto ? "Auto · \(lamp.title)" : lamp.title
    }

    public func start() {
        guard timer == nil else { return }
        apply(Self.schedule(for: Date()), animated: false)
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, case .auto = self.choice else { continue }
                self.apply(Self.schedule(for: Date()))
            }
        }
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    public func choose(_ lamp: Lamp) {
        choice = .manual(lamp)
        lit = true
        persistChoice()
        apply(lamp)
    }

    public func useAuto() {
        choice = .auto
        lit = true
        persistChoice()
        apply(Self.schedule(for: Date()))
    }

    /// Cycles the header button: Daylight → Evening → Night → Auto.
    public func next() {
        switch choice {
        case .auto:
            choose(lamp == .daylight ? .evening : (lamp == .evening ? .night : .daylight))
        case .manual(let value):
            switch value {
            case .daylight: choose(.evening)
            case .evening: choose(.night)
            case .night: useAuto()
            }
        }
    }

    public func setLit(_ on: Bool) {
        lit = on
        defaults?.set(on, forKey: "lamp.lit")
    }

    private func apply(_ lamp: Lamp, animated: Bool = true) {
        guard lamp != self.lamp else { return }
        if animated {
            withAnimation(.cueLamp) { self.lamp = lamp }
        } else {
            self.lamp = lamp
        }
    }

    private func persistChoice() {
        guard persist else { return }
        switch choice {
        case .auto: defaults?.set("auto", forKey: "lamp.choice")
        case .manual(let lamp): defaults?.set(lamp.rawValue, forKey: "lamp.choice")
        }
    }

    /// 7 ≤ hour < 17 daylight, 17 ≤ hour < 21 evening, otherwise night.
    public static func schedule(for date: Date) -> Lamp {
        switch Calendar.current.component(.hour, from: date) {
        case 7..<17: .daylight
        case 17..<21: .evening
        default: .night
        }
    }
}

// MARK: - Theme

public struct Theme: Sendable {
    public var desk: Color
    public var paper: Color
    public var stack: Color
    public var ink: Color
    public var ink2: Color
    public var hair: Color
    public var glass: Color
    public var glassEdge: Color
    public var shadow: Color
    public var selection: Color
    public var mark: Color
    public var pupil: Color
    public var light: Double
    public var colorScheme: ColorScheme

    public static let daylight = Theme(
        desk: Color(hex: Hex.desk), paper: Color(hex: Hex.paper), stack: Color(hex: Hex.stack),
        ink: Color(hex: Hex.ink), ink2: Color(hex: Hex.ink2),
        hair: Color(hex: Hex.ink, opacity: 0.10),
        glass: Color.white.opacity(0.40), glassEdge: Color.white.opacity(0.72),
        shadow: Color(hex: 0x523824, opacity: 0.16),
        selection: Color(hex: Hex.ink, opacity: 0.12),
        mark: Color(hex: Hex.ink), pupil: Color(hex: Hex.ink),
        light: 0.47, colorScheme: .light
    )

    public static let evening = Theme(
        desk: Color(hex: Hex.eveningDesk), paper: Color(hex: Hex.eveningPaper),
        stack: Color(hex: Hex.eveningStack),
        ink: Color(hex: Hex.ink), ink2: Color(hex: Hex.ink2),
        hair: Color(hex: Hex.ink, opacity: 0.10),
        glass: Color.white.opacity(0.34), glassEdge: Color.white.opacity(0.66),
        shadow: Color(hex: Hex.eveningShadow, opacity: 0.20),
        selection: Color(hex: Hex.ink, opacity: 0.12),
        mark: Color(hex: Hex.ink), pupil: Color(hex: Hex.ink),
        light: 0.62, colorScheme: .light
    )

    public static let night = Theme(
        desk: Color(hex: Hex.nightDesk), paper: Color(hex: Hex.nightPaper),
        stack: Color(hex: Hex.nightStack),
        ink: Color(hex: Hex.nightInk), ink2: Color(hex: Hex.nightInk2),
        hair: Color(hex: Hex.nightInk, opacity: 0.10),
        glass: Color(hex: Hex.nightDesk, opacity: 0.50), glassEdge: Color.white.opacity(0.12),
        shadow: Color.black.opacity(0.55),
        selection: Color(hex: Hex.nightInk, opacity: 0.16),
        mark: Color(hex: Hex.cream), pupil: Color(hex: Hex.orange),
        light: 0.13, colorScheme: .dark
    )

    public static func of(_ lamp: Lamp) -> Theme {
        switch lamp {
        case .daylight: .daylight
        case .evening: .evening
        case .night: .night
        }
    }

    public var nsInk: NSColor { NSColor(ink) }
    public var nsInk2: NSColor { NSColor(ink2) }
    public var nsPaper: NSColor { NSColor(paper) }
    public var nsDesk: NSColor { NSColor(desk) }
    public var nsSelection: NSColor { NSColor(selection) }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.daylight
}

public extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

public extension View {
    func theme(_ theme: Theme) -> some View { environment(\.theme, theme) }
}

// MARK: - Math

public func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
    min(max(value, lower), upper)
}

public func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

// MARK: - Motion

public extension Animation {
    static let cue = Animation.timingCurve(0.2, 0.8, 0.2, 1)
    static let cueLamp = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 1.2)
    static let cueMenu = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.16)
    static let cueFAQ = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32)
    static let cueFade = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.6)
    static let cueHover = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32)
}

public enum Motion {
    public static let ease = Animation.cue
}

// MARK: - Assets

public enum Assets {
    public static func image(_ name: String, ext: String = "jpg") -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return NSImage(contentsOf: url)
    }

    public static func shot(_ name: String) -> NSImage? { image(name) }

    public static func fontURL(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "ttf")
    }
}
