import SwiftUI
import AppKit
import Observation
import CueKit

// MARK: - Script

/// The demo's opening script. Copy lives in `SiteCopy` so the hyphen in
/// `INT. KITCHEN TABLE - 2 AM` cannot drift from the rest of the site.
enum DemoScript {
    static func initial() -> [Element] {
        SiteCopy.demoInitial.map { Element(type: $0.0, text: $0.1) }
    }
}

// MARK: - Small value types

struct DemoCaret: Equatable {
    var line: Int
    var offset: Int

    static let start = DemoCaret(line: 0, offset: 0)
}

enum DemoMenu: Equatable {
    case chooser
    case time
}

struct HintItem: Equatable {
    var key: String
    var text: String
}

enum HintState: Equatable {
    case unfocused
    case timeMenu
    case chooser
    case ghost
    case scene
    case action
    case character
    case dialogue
    case paren
    case transition
}

struct RetypeResult {
    var text: String
    var type: ElementType
    var caretOffset: Int?
}

// MARK: - UTF-16 helpers

// The web engine works in JavaScript string offsets (UTF-16 code units).
// TextKit and NSString use the same units, so keep all caret maths there.
extension String {
    var demoUTF16Count: Int { (self as NSString).length }

    func demoPrefix(_ count: Int) -> String {
        let n = min(max(count, 0), demoUTF16Count)
        return (self as NSString).substring(to: n)
    }

    func demoSuffix(_ count: Int) -> String {
        let n = min(max(count, 0), demoUTF16Count)
        return (self as NSString).substring(from: n)
    }
}

// MARK: - Model

@MainActor
@Observable
final class DemoModel {
    private(set) var lines: [Element]
    private(set) var caret: DemoCaret
    private(set) var chooserIndex: Int = 0
    private(set) var timeIndex: Int = 0
    private(set) var menu: DemoMenu?
    private(set) var menuLine: UUID?
    private(set) var ghost: Ghost?
    private(set) var seenTimeMenu: Bool = false
    private(set) var pageIsFocused: Bool = false
    private(set) var selectionIsEmpty: Bool = true
    private(set) var derived: ScriptDerived

    init() {
        let initial = DemoScript.initial()
        lines = initial
        caret = DemoCaret(line: max(initial.count - 1, 0), offset: 0)
        derived = ScriptAnalysis.derive(initial)
    }

    // MARK: Basic accessors

    var currentLine: Element? {
        guard lines.indices.contains(caret.line) else { return nil }
        return lines[caret.line]
    }

    var currentType: ElementType { currentLine?.type ?? .new }

    var isChooserOpen: Bool { menu == .chooser }
    var isTimeMenuOpen: Bool { menu == .time }

    /// The type a line paints as. A still-`new` line previews its inferred type;
    /// an empty focused new line previews the chooser's highlighted option.
    func displayType(for index: Int) -> ElementType {
        guard lines.indices.contains(index) else { return .new }
        let line = lines[index]
        if line.type == .new {
            if line.text.isEmpty {
                if pageIsFocused, caret.line == index, menu != .time {
                    return Formatter.choices[chooserIndex]
                }
                return .new
            }
            let inferred = Formatter.inferType(line.text)
            return inferred == .action ? .new : inferred
        }
        return line.type
    }

    func displayTypeForCurrentLine() -> ElementType {
        displayType(for: caret.line)
    }

    /// The text shown in an empty line. The web computes this from
    /// (empty, focused, is last, type) in exactly that order.
    func placeholder(for index: Int) -> String? {
        guard lines.indices.contains(index) else { return nil }
        let line = lines[index]
        guard line.text.isEmpty else { return nil }

        let focused = pageIsFocused && caret.line == index
        if focused {
            switch displayType(for: index) {
            case .scene: return "I or E"
            case .character: return "NAME"
            case .dialogue: return "What they say…"
            case .transition: return "CUT TO:"
            case .action, .new: return "What happens…"
            case .paren: return nil
            }
        }

        guard index == lines.count - 1 else { return nil }
        return line.type == .scene
            ? "Type I for INT. or E for EXT."
            : "Click here and keep writing…"
    }

    // MARK: Derived state

    private func clampCaret() {
        guard !lines.isEmpty else {
            caret = .start
            return
        }
        let line = min(max(caret.line, 0), lines.count - 1)
        let length = lines[line].text.demoUTF16Count
        caret = DemoCaret(line: line, offset: min(max(caret.offset, 0), length))
    }

    private func refresh() {
        clampCaret()
        derived = ScriptAnalysis.derive(lines)

        guard pageIsFocused, lines.indices.contains(caret.line) else {
            menu = nil
            menuLine = nil
            ghost = nil
            return
        }

        let line = lines[caret.line]

        if menu == .time {
            if let id = menuLine, lines.contains(where: { $0.id == id }) {
                ghost = nil
                return
            }
            menu = nil
            menuLine = nil
        }

        if line.type == .new, line.text.isEmpty {
            menu = .chooser
            menuLine = line.id
        } else if menu == .chooser {
            menu = nil
            menuLine = nil
        }

        if menu == nil, selectionIsEmpty, caret.offset == line.text.demoUTF16Count {
            ghost = GhostRules(names: derived.names, places: derived.places)
                .suggest(line: line, lines: lines)
        } else {
            ghost = nil
        }
    }

    // MARK: Editor → model

    func setEditing(lines newLines: [Element], caret newCaret: DemoCaret,
                    focused: Bool, selectionIsEmpty empty: Bool) {
        lines = newLines.isEmpty ? [Element(type: .new, text: "")] : newLines
        caret = newCaret
        pageIsFocused = focused
        selectionIsEmpty = empty
        // Typing closes the time menu; this mirrors `onChange`.
        if menu == .time {
            menu = nil
            menuLine = nil
        }
        refresh()
    }

    func updateCaret(line: Int, offset: Int, selectionIsEmpty empty: Bool, focused: Bool) {
        caret = DemoCaret(line: line, offset: offset)
        selectionIsEmpty = empty
        pageIsFocused = focused
        refresh()
    }

    func setFocused(_ focused: Bool) {
        pageIsFocused = focused
        if !focused {
            menu = nil
            menuLine = nil
            ghost = nil
        } else {
            refresh()
        }
    }

    func focus(line: Int, offset: Int) {
        pageIsFocused = true
        selectionIsEmpty = true
        caret = DemoCaret(line: line, offset: offset)
        refresh()
    }

    // MARK: Typing

    /// The web's `change()` decision table. Pure: the editor writes the result
    /// back into the text view, which keeps undo/IME in AppKit's hands.
    func retype(lineIndex: Int, oldText: String, rawText: String) -> RetypeResult {
        var text = rawText.replacingOccurrences(of: "\n", with: "")
        var type = lines.indices.contains(lineIndex) ? lines[lineIndex].type : .new
        var caretOffset: Int?

        // Scene: typing i/e in an empty slug expands to INT./EXT.
        if type == .scene, oldText.isEmpty, text.demoUTF16Count == 1 {
            let first = text.lowercased()
            if first == "i" { text = "INT. " }
            if first == "e" { text = "EXT. " }
        }

        // Scene: typing / after INT. or EXT. swaps the prefix.
        if type == .scene,
           text.range(of: #"^(INT|EXT)\. /$"#,
                       options: [.regularExpression, .caseInsensitive]) != nil {
            let prefix = String(text.prefix(4))
            text = prefix + "/" + (text.uppercased().hasPrefix("I") ? "EXT. " : "INT. ")
        }

        // Dialogue: "(" on an empty line becomes a parenthetical with the
        // caret inside the parentheses.
        if type == .dialogue, oldText.isEmpty, text == "(" {
            return RetypeResult(text: "()", type: .paren, caretOffset: 1)
        }

        // The chooser's highlighted type wins for the first character.
        if type == .new, oldText.isEmpty, chooserIndex != 0 {
            type = Formatter.choices[chooserIndex]
        }

        // Scene expansion again, now that the chooser may have changed type.
        if type == .scene, oldText.isEmpty, text.demoUTF16Count == 1 {
            let first = text.lowercased()
            if first == "i" { text = "INT. " }
            if first == "e" { text = "EXT. " }
        }

        // New line: lowercase implies action; a scene prefix implies scene.
        if type == .new, text.range(of: "[a-z]", options: .regularExpression) != nil,
           !Formatter.isScenePrefix(text) {
            type = .action
        }
        if type == .new, Formatter.isScenePrefix(text) {
            type = .scene
        }

        if type.isUppercase {
            text = text.uppercased()
        }

        if text != rawText {
            caretOffset = text.demoUTF16Count
        }

        return RetypeResult(text: text, type: type, caretOffset: caretOffset)
    }

    // MARK: Chooser

    func cycleChooser(forward: Bool) {
        let count = Formatter.choices.count
        chooserIndex = (chooserIndex + (forward ? 1 : count - 1)) % count
        if let line = currentLine, line.type == .new, line.text.isEmpty, pageIsFocused {
            menu = .chooser
            menuLine = line.id
        }
        refresh()
    }

    func setChooserIndex(_ index: Int) {
        guard menu == .chooser else { return }
        chooserIndex = min(max(index, 0), Formatter.choices.count - 1)
        refresh()
    }

    func commitChoice(_ index: Int) {
        guard lines.indices.contains(caret.line) else { return }
        let safe = min(max(index, 0), Formatter.choices.count - 1)
        chooserIndex = safe
        lines[caret.line].type = Formatter.choices[safe]
        lines[caret.line].text = ""
        caret.offset = 0
        pageIsFocused = true
        selectionIsEmpty = true
        menu = nil
        menuLine = nil
        refresh()
    }

    // MARK: Action → character

    func promoteAction() {
        guard lines.indices.contains(caret.line), lines[caret.line].type == .action else { return }
        lines[caret.line].type = .character
        lines[caret.line].text = lines[caret.line].text.uppercased()
        caret.offset = lines[caret.line].text.demoUTF16Count
        selectionIsEmpty = true
        refresh()
    }

    // MARK: Ghost

    func acceptGhost() {
        guard let ghost, lines.indices.contains(caret.line) else { return }
        let line = lines[caret.line]
        let text = (line.text + ghost.text).uppercased()
        let type: ElementType
        switch ghost.kind {
        case .scene: type = .scene
        case .character: type = .character
        case .place: type = line.type
        }
        lines[caret.line].text = text
        lines[caret.line].type = type
        caret.offset = text.demoUTF16Count
        selectionIsEmpty = true
        menu = nil
        menuLine = nil
        refresh()
    }

    // MARK: Time menu

    func cycleTime(forward: Bool) {
        let count = SceneTime.allCases.count
        timeIndex = (timeIndex + (forward ? 1 : count - 1)) % count
        refresh()
    }

    func setTimeIndex(_ index: Int) {
        guard menu == .time else { return }
        timeIndex = min(max(index, 0), SceneTime.allCases.count - 1)
    }

    func openTimeMenu() {
        guard lines.indices.contains(caret.line) else { return }
        timeIndex = 0
        menu = .time
        menuLine = lines[caret.line].id
        ghost = nil
    }

    func chooseTime(_ time: SceneTime, keepCaret: Bool) {
        guard lines.indices.contains(caret.line) else { return }
        let base = lines[caret.line].text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s*-\s*$"#, with: "", options: .regularExpression)
        let text = "\(base) - \(time.rawValue)"
        lines[caret.line].text = text
        lines[caret.line].type = .scene
        menu = nil
        menuLine = nil

        if keepCaret {
            caret.offset = text.demoUTF16Count
        } else {
            let next = Element(type: .action, text: "")
            lines.insert(next, at: caret.line + 1)
            caret = DemoCaret(line: caret.line + 1, offset: 0)
        }
        selectionIsEmpty = true
        refresh()
    }

    func dismissTimeMenu(seen: Bool) {
        if seen { seenTimeMenu = true }
        menu = nil
        menuLine = nil
        refresh()
    }

    // MARK: Return

    func enter() {
        guard lines.indices.contains(caret.line) else { return }
        let index = caret.line
        let line = lines[index]
        let location = min(max(caret.offset, 0), line.text.demoUTF16Count)

        var before = line.text.demoPrefix(location)
        var after = line.text.demoSuffix(location)
        var type = line.type

        if type == .paren {
            before = line.text.trimmingCharacters(in: .whitespaces)
            after = ""
        }

        if type == .new {
            if line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines[index].type = Formatter.choices[chooserIndex]
                lines[index].text = ""
                caret = DemoCaret(line: index, offset: 0)
                selectionIsEmpty = true
                menu = nil
                menuLine = nil
                refresh()
                return
            }
            type = Formatter.inferType(line.text)
            if type.isUppercase { before = before.uppercased() }
        }

        if type == .scene {
            guard !before.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            let hasTime = before.range(of: #"\s-\s*\S"#, options: .regularExpression) != nil
            // `placeRemainder` strips INT./EXT. as well as any extension and time,
            // which is what the web's `Ur()` does. A bare `INT. ` has no place and
            // must not offer the time menu.
            let place = Formatter.placeRemainder(before) ?? ""
            if !hasTime, after.isEmpty, !place.isEmpty, !seenTimeMenu {
                lines[index].type = .scene
                lines[index].text = before
                caret = DemoCaret(line: index, offset: before.demoUTF16Count)
                selectionIsEmpty = true
                openTimeMenu()
                refresh()
                return
            }
        }

        if line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           type == .action || type == .dialogue || type == .character {
            lines[index].type = .new
            lines[index].text = ""
            chooserIndex = 0
            caret = DemoCaret(line: index, offset: 0)
            selectionIsEmpty = true
            menu = nil
            menuLine = nil
            refresh()
            return
        }

        if type == .paren {
            if !before.isEmpty, !before.hasSuffix(")") { before += ")" }
            if before == "()" {
                lines[index].type = .dialogue
                lines[index].text = ""
                caret = DemoCaret(line: index, offset: 0)
                selectionIsEmpty = true
                refresh()
                return
            }
        }

        let nextType = type.next
        lines[index].type = type
        lines[index].text = before
        let next = Element(type: nextType, text: after)
        lines.insert(next, at: index + 1)
        chooserIndex = 0
        caret = DemoCaret(line: index + 1, offset: 0)
        selectionIsEmpty = true
        menu = nil
        menuLine = nil
        refresh()
    }

    // MARK: Backspace

    /// Returns true when the model handled Backspace and the text view must not
    /// perform its native deletion.
    func backspaceCollapseOrMerge() -> Bool {
        guard lines.indices.contains(caret.line) else { return false }
        let index = caret.line
        let line = lines[index]

        if line.type == .paren, line.text == "()", caret.offset == 1 {
            lines[index].type = .dialogue
            lines[index].text = ""
            caret.offset = 0
            refresh()
            return true
        }

        if caret.offset == 0, index > 0 {
            let previous = lines[index - 1]
            let position = previous.text.demoUTF16Count
            lines[index - 1].text = previous.text + line.text
            lines.remove(at: index)
            caret = DemoCaret(line: index - 1, offset: position)
            refresh()
            return true
        }

        return false
    }

    // MARK: Escape

    func escape() {
        if menu == .time {
            dismissTimeMenu(seen: true)
            return
        }

        if lines.indices.contains(caret.line) {
            let line = lines[caret.line]
            if line.type == .new, line.text.isEmpty {
                lines[caret.line].type = .action
                menu = nil
                menuLine = nil
                refresh()
                return
            }
        }

        menu = nil
        menuLine = nil
        ghost = nil
        refresh()
    }

    // MARK: Reset

    /// `Clear` leaves a fresh scene line, focused, ready for a slug.
    func resetClear() {
        lines = [Element(type: .scene, text: "")]
        caret = .start
        chooserIndex = 0
        timeIndex = 0
        menu = nil
        menuLine = nil
        ghost = nil
        seenTimeMenu = false
        pageIsFocused = true
        selectionIsEmpty = true
        refresh()
    }

    /// `Start a blank page` leaves one empty new line with the chooser open.
    func resetBlankPage() {
        lines = [Element(type: .new, text: "")]
        caret = .start
        chooserIndex = 0
        timeIndex = 0
        menu = nil
        menuLine = nil
        ghost = nil
        seenTimeMenu = false
        pageIsFocused = true
        selectionIsEmpty = true
        refresh()
    }

    // MARK: Hints

    var hintState: HintState {
        guard pageIsFocused else { return .unfocused }
        if menu == .time { return .timeMenu }
        if menu == .chooser { return .chooser }
        if ghost != nil { return .ghost }

        switch currentType {
        case .new:
            return (currentLine?.text.isEmpty ?? true) ? .chooser : .action
        case .scene: return .scene
        case .action: return .action
        case .character: return .character
        case .dialogue: return .dialogue
        case .paren: return .paren
        case .transition: return .transition
        }
    }

    var hintItems: [HintItem] {
        switch hintState {
        case .unfocused:
            return [HintItem(key: "Click", text: "the page and type")]
        case .timeMenu:
            return [
                HintItem(key: "↑ ↓", text: "choose"),
                HintItem(key: "⏎", text: "picks the time"),
                HintItem(key: "esc", text: "keeps it as typed")
            ]
        case .chooser:
            return [
                HintItem(key: "⏎", text: "picks the highlighted one"),
                HintItem(key: "⇥", text: "moves"),
                HintItem(key: "", text: "or just start typing: CAPS for a name, I or E for a scene")
            ]
        case .ghost:
            return [
                HintItem(key: "⇥", text: "or"),
                HintItem(key: "→", text: "takes the grey suggestion")
            ]
        case .scene:
            return [HintItem(key: "⏎", text: "after the place offers the time of day")]
        case .action:
            return [
                HintItem(key: "⏎", text: "what comes next"),
                HintItem(key: "⇥", text: "makes this a character")
            ]
        case .character:
            return [HintItem(key: "⏎", text: "starts their dialogue")]
        case .dialogue:
            return [
                HintItem(key: "⏎", text: "what comes next"),
                HintItem(key: "(", text: "on an empty line adds a direction")
            ]
        case .paren:
            return [HintItem(key: "⏎", text: "back to dialogue")]
        case .transition:
            return [HintItem(key: "⏎", text: "next line")]
        }
    }

    var hintAnnouncement: String {
        hintItems.map { item in
            item.key.isEmpty ? item.text : "\(item.key) \(item.text)"
        }.joined(separator: ", ")
    }
}
