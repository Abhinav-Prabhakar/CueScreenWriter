import Foundation

public enum ElementType: String, CaseIterable, Codable, Sendable {
    case scene, action, character, paren, dialogue, transition, new

    public var isUppercase: Bool {
        self == .scene || self == .character || self == .transition
    }

    public var accessibilityName: String {
        switch self {
        case .scene: "Scene line"
        case .action: "Action line"
        case .character: "Character line"
        case .paren: "Parenthetical line"
        case .dialogue: "Dialogue line"
        case .transition: "Transition line"
        case .new: "New line"
        }
    }

    public var next: ElementType {
        switch self {
        case .scene: .action
        case .character: .dialogue
        case .paren: .dialogue
        case .transition: .scene
        case .dialogue, .action, .new: .new
        }
    }
}

public struct Element: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var type: ElementType
    public var text: String

    public init(id: UUID = UUID(), type: ElementType, text: String = "") {
        self.id = id
        self.type = type
        self.text = text
    }
}

public struct Script: Equatable, Codable, Sendable {    public var title: String
    public var sceneNumbers: Bool
    public var elements: [Element]

    public init(title: String = "Untitled", sceneNumbers: Bool = true, elements: [Element]) {
        self.title = title
        self.sceneNumbers = sceneNumbers
        self.elements = elements
    }

    public static func demo() -> Script {
        Script(title: "One Good Line", elements: SiteCopy.demoInitial.map { Element(type: $0.0, text: $0.1) })
    }

    public var plainText: String {
        elements.map(\.text).joined(separator: "\n")
    }
}

// MARK: - Pure formatting rules

public enum Formatter {
    public static let scenePrefixPattern = #"^(INT|EXT|I\/E|INT\/EXT)[./ ]"#
    public static let choices: [ElementType] = [.action, .character, .scene, .transition]

    public static func hasLetter(_ text: String) -> Bool {
        text.range(of: "[A-Za-z]", options: .regularExpression) != nil
    }

    public static func isUpper(_ text: String) -> Bool {
        hasLetter(text) && text == text.uppercased()
    }

    public static func isScenePrefix(_ text: String) -> Bool {
        text.range(of: scenePrefixPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The demo's `hi()`.
    public static func inferType(_ raw: String) -> ElementType {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if isScenePrefix(text) { return .scene }
        if isUpper(text), text.range(of: #"(TO:|FADE OUT\.|FADE TO BLACK\.)$"#, options: .regularExpression) != nil {
            return .transition
        }
        if isUpper(text), text.replacingOccurrences(of: "[^A-Z]", with: "", options: .regularExpression).count >= 2 {
            return .character
        }
        return .action
    }

    /// `Ur()` — the place key of a scene heading: extension removed, time removed.
    public static func placeKey(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"\(.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+-\s+.*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// The scene's location after the INT./EXT. prefix, extension and time removed.
    public static func placeRemainder(_ raw: String) -> String? {
        guard let range = raw.range(of: scenePrefixPattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        var rest = String(raw[range.upperBound...])
        rest = rest.replacingOccurrences(of: #"\(.*$"#, with: "", options: .regularExpression)
        rest = rest.replacingOccurrences(of: #"\s+-\s+.*$"#, with: "", options: .regularExpression)
        return rest.trimmingCharacters(in: .whitespaces)
    }

    public static func sceneTimeSuffix(_ text: String) -> String? {
        guard let range = text.range(of: #"\s-\s*[A-Z]+$"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}

public enum SceneTime: String, CaseIterable, Sendable, Identifiable {
    case day = "DAY"
    case night = "NIGHT"
    case morning = "MORNING"
    case evening = "EVENING"
    case continuous = "CONTINUOUS"
    case later = "LATER"

    public var id: String { rawValue }

    public var menuLabel: String {
        switch self {
        case .day: "- DAY"
        case .night: "- NIGHT"
        default: rawValue
        }
    }
}

// MARK: - Ghost

public struct Ghost: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case character, scene, place }
    public var text: String
    public var kind: Kind

    public init(text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }
}

public struct GhostRules: Sendable {
    public var names: [String]
    public var places: [String]

    public init(names: [String], places: [String]) {
        self.names = names
        self.places = places
    }

    public func suggest(line: Element, lines: [Element]) -> Ghost? {
        let text = line.text
        // A scene prefix wins over a character name: typing "IN" is far more
        // often the start of INT. than the start of INGRID.
        if line.type == .new || line.type == .action || line.type == .scene {
            let upper = text.uppercased()
            if ["I", "IN", "INT"].contains(upper), text == upper {
                return Ghost(text: String("INT. ".dropFirst(text.count)), kind: .scene)
            }
            if ["E", "EX", "EXT"].contains(upper), text == upper {
                return Ghost(text: String("EXT. ".dropFirst(text.count)), kind: .scene)
            }
        }

        if (line.type == .new || line.type == .character), !text.isEmpty,
           Formatter.isUpper(text), !text.contains("(") {
            if let match = names.first(where: { $0 != text && $0.hasPrefix(text) }) {
                return Ghost(text: String(match.dropFirst(text.count)), kind: .character)
            }
        }

        if line.type == .scene, !text.contains(" -") {
            let partial = Formatter.placeKey(text)
            guard partial.count >= 4 else { return nil }
            let candidates = places.filter { place in
                if place != partial { return true }
                return lines.filter { $0.type == .scene && Formatter.placeKey($0.text) == place }.count > 1
            }
            if !candidates.contains(partial),
               let match = candidates.first(where: { $0.hasPrefix(partial) && $0 != partial }) {
                return Ghost(text: String(match.dropFirst(partial.count)), kind: .place)
            }
        }
        return nil
    }
}

// MARK: - Derived script data

public struct ScriptDerived: Equatable, Sendable {
    public var colours: [String: Int] = [:]
    public var names: [String] = []
    public var places: [String] = []
    public var speakerOf: [UUID: String] = [:]
    public var sceneNo: [UUID: Int] = [:]
    public var speechRange: [String: ClosedRange<Int>] = [:]

    public init() {}
}

public enum ScriptAnalysis {    public static func derive(_ elements: [Element]) -> ScriptDerived {
        var out = ScriptDerived()
        var speaker: String?
        var scene = 0

        for element in elements {
            if element.type == .character, !element.text.trimmingCharacters(in: .whitespaces).isEmpty {
                let name = cueName(element.text)
                if out.colours[name] == nil {
                    out.colours[name] = out.names.count % Hex.characters.count
                    out.names.append(name)
                }
                speaker = name
            } else if element.type != .paren, element.type != .dialogue {
                speaker = nil
            }

            if let speaker, element.type == .character || element.type == .paren || element.type == .dialogue {
                out.speakerOf[element.id] = speaker
            }

            if element.type == .scene {
                scene += 1
                out.sceneNo[element.id] = scene
                let place = Formatter.placeKey(element.text)
                if !place.isEmpty, !out.places.contains(place) { out.places.append(place) }
            }
        }
        return out
    }

    public static func cueName(_ text: String) -> String {
        text.replacingOccurrences(of: #"\(.*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
    }

    public static func colourIndex(for name: String, in derived: ScriptDerived) -> Int {
        derived.colours[name] ?? 0
    }
}

public struct EditorPosition: Equatable, Sendable {
    public var scene: Int
    public var page: Int
    public var pages: Int

    public init(scene: Int = 1, page: Int = 1, pages: Int = 1) {
        self.scene = scene
        self.page = page
        self.pages = pages
    }
}
