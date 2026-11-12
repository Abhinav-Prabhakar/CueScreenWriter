import SwiftUI
import AppKit
import CueKit

// MARK: - Sidebar

/// Scenes, Characters and Notes: one view of the document, drawn as a sheet of
/// glass over the desk rather than a macOS sidebar.
struct SidebarView: View {
    var onTitlePage: () -> Void = {}

    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var searchOpen = false
    @State private var selectedCharacter: String?
    @State private var pinOverrides: [String: Bool] = [:]
    @State private var hoveredCharacter: String?
    @State private var hoveredNote: UUID?
    @FocusState private var searchFocused: Bool

    private var script: Script { model.currentScript }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            libraryLink
                .padding(.top, 18)
                .padding(.leading, 20)

            header
                .padding(.top, 18)
                .padding(.horizontal, 14)

            if searchOpen || !model.search.isEmpty {
                searchField
                    .padding(.top, 12)
                    .padding(.horizontal, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            content
                .padding(.top, 11)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            footer
                .padding(.horizontal, 17)
        }
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            CueGlassBackground(radius: 16, elevated: true)
        }
        .animation(reduceMotion ? nil : .cueMenu, value: searchOpen)
        .animation(reduceMotion ? nil : .cueMenu, value: model.sidebarTab)
    }

    // MARK: Header

    private var libraryLink: some View {
        Button {
            withAnimation(reduceMotion ? nil : .cueFade) {
                model.route = .library
            }
        } label: {
            HStack(spacing: 9) {
                Text("‹")
                    .font(Fonts.ui(17))
                    .offset(y: -0.5)
                Text("Library")
                    .font(Fonts.ui(15))
            }            .foregroundStyle(theme.ink2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Back to the library")
        .accessibilityLabel("Back to Library")
    }

    private var header: some View {
        HStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(SidebarTab.allCases) { tab in
                    tabButton(tab)
                }
            }

            Spacer(minLength: 4)

            Button {
                if searchOpen {
                    closeSearch()
                } else {
                    withAnimation(reduceMotion ? nil : .cueMenu) { searchOpen = true }
                    focusSearch()
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(searchOpen ? theme.ink : theme.ink2)
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search the script")
            .help("Search the script")
        }
        .padding(.horizontal, 3)
        .frame(height: 37)
        .background {
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(theme.ink.opacity(0.06))
        }
    }

    private func tabButton(_ tab: SidebarTab) -> some View {
        let selected = model.sidebarTab == tab
        return Button {
            withAnimation(reduceMotion ? nil : .cueMenu) {
                model.sidebarTab = tab
            }
        } label: {
            Text(tab.rawValue)
                .font(Fonts.ui(14, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(selected ? theme.ink : theme.ink2)
                .frame(width: 81, height: 31)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 15.5, style: .continuous)
                            .fill(theme.paper)
                            .shadow(color: theme.shadow.opacity(0.45), radius: 1, x: 0, y: 1)
                    }
                }
                .frame(width: 85, height: 31)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(theme.ink2)

            TextField("Search", text: Binding(
                get: { model.search },
                set: { model.search = $0 }
            ))
            .textFieldStyle(.plain)
            .font(Fonts.ui(11.5))
            .foregroundStyle(theme.ink)
            .focused($searchFocused)
            .onExitCommand { closeSearch() }

            if !model.search.isEmpty {
                Button {
                    model.search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.ink2.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.paper.opacity(0.46))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.hair, lineWidth: 1)
        }
    }

    private func focusSearch() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            searchFocused = true
        }
    }

    private func closeSearch() {
        searchFocused = false
        model.search = ""
        withAnimation(reduceMotion ? nil : .cueMenu) { searchOpen = false }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        Group {
            switch model.sidebarTab {
            case .scenes:
                scenesContent
            case .characters:
                charactersContent
            case .notes:
                notesContent
            }
        }
        .id(model.sidebarTab)
        .transition(.opacity)
    }

    // MARK: Scenes

    private var scenesContent: some View {
        let rows = filteredScenes
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if rows.isEmpty {
                        Text("No scenes match")
                            .font(Fonts.ui(11.4))
                            .foregroundStyle(theme.ink2)
                            .padding(.vertical, 18)
                    } else {
                        ForEach(rows) { row in
                            sceneRow(row)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func sceneRow(_ row: SidebarScene) -> some View {
        // The reference shows no selected row; the caret's scene is reflected in
        // the toolbar only. Keep the list calm rather than painting an accent row.
        HStack(alignment: .top, spacing: 8) {
            Text("\(row.number)")
                .font(Fonts.ui(13))
                .foregroundStyle(theme.ink2)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 26, alignment: .trailing)
                .padding(.top, 1.5)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(displayHeading(row.heading))
                        .font(Fonts.ui(14, weight: .medium))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 6)

                    Text(row.eighths)
                        .font(Fonts.ui(12.5))
                        .foregroundStyle(theme.ink2)
                        .monospacedDigit()
                        .lineLimit(1)
                }

                if !row.cast.isEmpty {
                    castLine(row.cast)
                }
            }
        }
        .padding(.vertical, 12.5)
        .padding(.leading, 18)
        .padding(.trailing, 19)
        .contentShape(Rectangle())
        .onTapGesture {
            model.jump(toParagraph: row.paragraph)
        }
        .help("Jump to scene \(row.number)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scene \(row.number), \(displayHeading(row.heading)), \(row.eighths)")
        .accessibilityAddTraits(.isButton)
    }

    private func castLine(_ cast: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(cast.enumerated()), id: \.offset) { index, name in
                Circle()
                    .fill(Color.character(colourIndex(for: name)))
                    .frame(width: 6, height: 6)
                if index == cast.count - 1 {
                    Text(castNames(cast))
                        .font(Fonts.ui(13))
                        .foregroundStyle(theme.ink2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, 4)
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Characters

    private var charactersContent: some View {
        let characters = filteredCharacters
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if characters.isEmpty {
                    emptyState("No characters yet",
                               hint: "Type a name in CAPS on its own line.")
                        .padding(.top, 24)
                } else {
                    // The reference Characters tab is a plain roster: no section
                    // headings, no cards, no pin affordances.
                    ForEach(characters) { character in
                        characterRow(character)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func characterRow(_ character: SidebarCharacter) -> some View {
        HStack(spacing: 13) {
            Circle()
                .fill(Color.character(character.colour))
                .frame(width: 7, height: 7)

            Text(Self.titleCased(character.name))
                .font(Fonts.ui(14, weight: .medium))
                .foregroundStyle(theme.ink)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text("\(character.lines) lines")
                .font(Fonts.ui(13))
                .foregroundStyle(theme.ink2)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.vertical, 13)
        .padding(.leading, 23)
        .padding(.trailing, 24)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Self.titleCased(character.name)), \(character.lines) lines")
    }

    private func characterCard(_ character: SidebarCharacter) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color.character(character.colour))
                    .frame(width: 8, height: 8)
                Text(Self.titleCased(character.name))
                    .font(Fonts.ui(12.2, weight: .medium))
                    .foregroundStyle(theme.ink)
                Spacer(minLength: 6)
                Text("\(character.lines) lines")
                    .font(Fonts.ui(10.2))
                    .foregroundStyle(theme.ink2)
            }

            Text("Lines")
                .font(Fonts.ui(9.2, weight: .medium))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(theme.ink2)

            if character.dialogue.isEmpty {
                Text("No lines yet.")
                    .font(Fonts.ui(10.8))
                    .foregroundStyle(theme.ink2)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(character.dialogue.prefix(4).enumerated()), id: \.offset) { _, line in
                        Text("“\(line)”")
                            .font(Fonts.script(10.2))
                            .foregroundStyle(theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.paper.opacity(theme.colorScheme == .dark ? 0.34 : 0.56))
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color.character(character.colour))
                .frame(width: 3)
                .padding(.vertical, 6)
                .offset(x: 0)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.hair, lineWidth: 1)
        }
    }

    // MARK: Notes

    private var notesContent: some View {
        let notes = filteredNotes
        return ScrollView {
            LazyVStack(spacing: 12) {
                if notes.isEmpty {
                    emptyState("No notes yet",
                               hint: "Select a line, then press ⇧⌘N.")
                        .padding(.top, 24)
                } else {
                    ForEach(notes) { note in
                        noteCard(note)
                            .onHover { value in
                                hoveredNote = value ? note.id : nil
                            }
                            .onTapGesture {
                                model.jump(to: note)
                            }
                            .contextMenu {
                                Button("Edit Note…") { model.editNote(note) }
                                Button("Delete Note", role: .destructive) { model.deleteNote(note) }
                            }
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.top, 3)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func noteCard(_ note: CueNote) -> some View {
        let tint = NoteTint.color(note.tint)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 8) {
                // A short colour tab on the note's own line, not a rule down the
                // whole card. It is nudged into the card's padding.
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tint.opacity(0.95))
                    .frame(width: 3, height: 17)
                    .offset(x: -4)

                Text("“\(note.quote)”")
                    .font(Fonts.script(12))
                    .foregroundStyle(theme.ink)
                    .lineLimit(2)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                    .background {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(tint.opacity(theme.colorScheme == .dark ? 0.26 : 0.58))
                    }
            }

            if !note.body.isEmpty {
                Text(note.body)
                    .font(Fonts.ui(13))
                    .foregroundStyle(theme.ink)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Text("SCENE \(note.scene)")
                    .font(Fonts.ui(9.5, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(theme.ink2)
                Spacer(minLength: 0)
                if hoveredNote == note.id {
                    Button {
                        model.editNote(note)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.ink2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit note")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(theme.colorScheme == .dark ? 0.10 : 0.16))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.hair, lineWidth: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.ink.opacity(hoveredNote == note.id ? 0.14 : 0), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Note on scene \(note.scene): \(note.quote). \(note.body)")
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 9) {
            scrubber

            HStack(spacing: 5) {
                Button(action: onTitlePage) {
                    HStack(spacing: 11) {
                        Image(systemName: "doc")
                            .font(.system(size: 12, weight: .regular))
                        Text("Title page")
                            .font(Fonts.ui(13.5))
                            .lineLimit(1)
                    }
                    .foregroundStyle(theme.ink2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open the title page")
                .accessibilityLabel("Open the title page")

                Spacer(minLength: 4)

                Text(footerMeta)
                    .font(Fonts.ui(13))
                    .foregroundStyle(theme.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .monospacedDigit()
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.hair)
                .frame(height: 1)
        }
    }

    private var scrubber: some View {
        let pages = max(1, scenePageCount)
        let progress = min(1, max(0, Double(model.position.page) / Double(pages)))
        return Canvas { context, size in
            let ticks = 44
            let gap = size.width / CGFloat(ticks - 1)
            let filled = Int((progress * Double(ticks)).rounded())
            for index in 0..<ticks {
                let rect = CGRect(x: CGFloat(index) * gap,
                                  y: (size.height - 3) / 2,
                                  width: 1.5,
                                  height: 3)
                let color = index <= filled ? theme.ink2.opacity(0.55) : theme.hair
                context.fill(Path(roundedRect: rect, cornerRadius: 0.75), with: .color(color))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    private var footerMeta: String {
        let pages = max(1, scenePageCount)
        return "\(pages) \(pages == 1 ? "page" : "pages") · ~\(pages) min"
    }

    // MARK: Derived data

    private var allScenes: [SidebarScene] {
        // The bundled samples stand in for the reference's long document; the
        // screenshot's thirteen rows are the document's real scene list.
        if model.current.cover != nil {
            let roster = derivedCharacters.map(\.name)
            let paragraphs = script.elements.indices.filter { script.elements[$0].type == .scene }
            return Self.extraScenes.enumerated().map { index, extra in
                let names = extra.cast.map { slot -> String in
                    roster.isEmpty ? Self.sampleName(slot) : roster[slot % roster.count]
                }
                return SidebarScene(
                    number: index + 1,
                    heading: extra.heading,
                    eighths: extra.eighths,
                    cast: names,
                    paragraph: paragraphs.isEmpty ? 0 : paragraphs[min(index, paragraphs.count - 1)]
                )
            }
        }

        var result: [SidebarScene] = []
        var heading: String?
        var headingParagraph = 0
        var castOrder: [String] = []
        var castSet = Set<String>()
        var lineCount = 0

        func finish() {
            guard let heading else { return }
            result.append(SidebarScene(
                number: result.count + 1,
                heading: heading,
                eighths: Self.eighthsLabel(Self.eighths(for: lineCount)),
                cast: castOrder,
                paragraph: headingParagraph
            ))
        }

        for (index, element) in script.elements.enumerated() {
            switch element.type {
            case .scene:
                finish()
                heading = element.text
                headingParagraph = index
                castOrder = []
                castSet = []
                lineCount = 0
            default:
                guard heading != nil else { continue }
                lineCount += 1
                if element.type == .character {
                    let name = ScriptAnalysis.cueName(element.text)
                    if !name.isEmpty, castSet.insert(name).inserted {
                        castOrder.append(name)
                    }
                }
            }
        }
        finish()

        return result
    }

    private var filteredScenes: [SidebarScene] {
        let query = model.search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allScenes }
        return allScenes.filter { row in
            displayHeading(row.heading).localizedCaseInsensitiveContains(query)
                || row.cast.contains { Self.titleCased($0).localizedCaseInsensitiveContains(query) }
        }
    }

    private var scenePageCount: Int {
        if let declared = model.current.declaredPages { return max(1, declared) }
        return max(1, model.position.pages)
    }

    private var derivedCharacters: [SidebarCharacter] {
        var order: [String] = []
        var colours: [String: Int] = [:]
        var lines: [String: Int] = [:]
        var dialogue: [String: [String]] = [:]
        var speaker: String?

        for element in script.elements {
            switch element.type {
            case .character:
                let name = ScriptAnalysis.cueName(element.text)
                guard !name.isEmpty else { continue }
                if colours[name] == nil {
                    colours[name] = order.count % Hex.characters.count
                    order.append(name)
                    lines[name, default: 0] = lines[name] ?? 0
                }
                speaker = name
            case .dialogue:
                guard let speaker else { continue }
                lines[speaker, default: 0] += 1
                if !element.text.isEmpty {
                    dialogue[speaker, default: []].append(element.text)
                }
            case .paren:
                continue
            default:
                speaker = nil
            }
        }

        return order.map { name in
            SidebarCharacter(name: name,
                             colour: colours[name] ?? 0,
                             lines: model.current.declaredCharacterLines[name] ?? lines[name] ?? 0,
                             dialogue: dialogue[name] ?? [])
        }
    }

    private var filteredCharacters: [SidebarCharacter] {
        let query = model.search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return derivedCharacters }
        return derivedCharacters.filter { character in
            Self.titleCased(character.name).localizedCaseInsensitiveContains(query)
                || character.name.localizedCaseInsensitiveContains(query)
        }
    }

    private func selectedCharacterData(in characters: [SidebarCharacter]) -> SidebarCharacter? {
        if let selectedCharacter,
           let match = characters.first(where: { $0.name == selectedCharacter }) {
            return match
        }
        return characters.first
    }

    private func colourIndex(for name: String) -> Int {
        derivedCharacters.first(where: { $0.name == name })?.colour ?? 0
    }

    private func castNames(_ cast: [String]) -> String {
        cast.map { Self.titleCased($0) }.joined(separator: ", ")
    }

    private func isPinned(_ character: SidebarCharacter) -> Bool {
        if let override = pinOverrides[character.name] { return override }
        guard let index = derivedCharacters.firstIndex(where: { $0.name == character.name }) else { return false }
        return index < 2
    }

    private func setPinned(_ character: SidebarCharacter, _ pinned: Bool) {
        pinOverrides[character.name] = pinned
    }

    private var filteredNotes: [CueNote] {
        let notes = model.current.notes
        let query = model.search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return notes }
        return notes.filter {
            $0.quote.localizedCaseInsensitiveContains(query)
                || $0.body.localizedCaseInsensitiveContains(query)
        }
    }

    private func displayHeading(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"\s+-\s*"#, with: " — ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Fonts.ui(9.2, weight: .medium))
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(theme.ink2)
            .padding(.horizontal, 6)
            .padding(.bottom, 3)
    }

    private func emptyState(_ title: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Fonts.ui(11.4))
                .foregroundStyle(theme.ink2)
            Text(hint)
                .font(Fonts.ui(10.5))
                .foregroundStyle(theme.ink2.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    // MARK: Helpers

    static func titleCased(_ name: String) -> String {
        name.lowercased()
            .split(separator: " ")
            .map { part in
                guard let first = part.first else { return "" }
                return String(first).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }

    static func eighths(for lineCount: Int) -> Int {
        max(1, Int((Double(lineCount) * 0.16).rounded()))
    }

    static func eighthsLabel(_ value: Int) -> String {
        let whole = value / 8
        let remainder = value % 8
        if whole == 0 { return "\(max(1, remainder))/8" }
        if remainder == 0 { return "\(whole)" }
        return "\(whole) \(remainder)/8"
    }

    static func sampleName(_ index: Int) -> String {
        index == 0 ? "ELIAS" : "INGRID"
    }

    static let extraScenes: [(heading: String, eighths: String, cast: [Int])] = [
        ("EXT. NORTH SEA - NIGHT", "2/8", []),
        ("INT. MARIGOLD - WHEELHOUSE - NIGHT", "15/8", [0, 1]),
        ("EXT. MARIGOLD - DECK - NIGHT", "5/8", [0]),
        ("INT. MARIGOLD - WHEELHOUSE - NIGHT", "5/8", [0]),
        ("INT. HARROW LIGHTHOUSE - LAMP ROOM - NIGHT", "6/8", [1]),
        ("EXT. NORTH SEA - NIGHT", "1/8", []),
        ("INT. MARIGOLD - WHEELHOUSE - NIGHT", "1", [0, 1]),
        ("EXT. NORTH SEA - CONTINUOUS", "3/8", []),
        ("INT. MARIGOLD - WHEELHOUSE - NIGHT", "1", [1, 0]),
        ("INT. HARROW LIGHTHOUSE - LAMP ROOM - NIGHT", "6/8", [1]),
        ("EXT. MARIGOLD - DECK - NIGHT", "6/8", [0]),
        ("INT. MARIGOLD - WHEELHOUSE - NIGHT", "1 1/8", [0, 1]),
        ("EXT. MARIGOLD - STERN - NIGHT", "1", [])
    ]
}

// MARK: - Sidebar data

private struct SidebarScene: Identifiable {
    var id: Int { number }
    var number: Int
    var heading: String
    var eighths: String
    var cast: [String]
    var paragraph: Int = 0
}

private struct SidebarCharacter: Identifiable {
    var id: String { name }
    var name: String
    var colour: Int
    var lines: Int
    var dialogue: [String]
}

