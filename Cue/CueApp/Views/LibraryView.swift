import SwiftUI
import AppKit
import CueKit
import UniformTypeIdentifiers

/// The library: a shelf of title pages in the same room as the editor. Covers
/// are miniature title pages set in the actual script face; the grid is
/// deliberately narrow and generous.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var query = ""
    @State private var hoveredDocument: UUID?
    @State private var newHovering = false
    @State private var renameTarget: CueDocument?
    @State private var renameText = ""
    @State private var deleteTarget: CueDocument?
    @State private var importError: String?
    @FocusState private var searchFocused: Bool

    private var documents: [CueDocument] {
        model.documents.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private var filtered: [CueDocument] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return documents }
        return documents.filter { document in
            document.title.localizedCaseInsensitiveContains(trimmed)
                || document.script.elements.contains {
                    $0.text.localizedCaseInsensitiveContains(trimmed)
                }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // The shelf is a fixed-size object, not a fluid grid: the reference
            // keeps ~218 pt covers and 49 pt gaps at 1600, centred on the desk.
            let cardWidth: CGFloat = 218
            let gap: CGFloat = 49
            let capsuleWidth = min(size.width - 56, size.width * 0.2575)

            ZStack(alignment: .top) {
                CueDeskBackground(glow: 1.12)

                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 32)
                        .padding(.top, 45)

                    ScrollView {
                        shelf(cardWidth: cardWidth, gap: gap)
                            .padding(.top, 157)
                            .padding(.bottom, 90)
                    }
                    .scrollIndicators(.hidden)
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        guard let provider = providers.first else { return false }
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            guard let url else { return }
                            Task { @MainActor in
                                if let error = model.importFile(url) { importError = error }
                            }
                        }
                        return true
                    }
                }

                MusicCapsule()
                    .frame(width: capsuleWidth, height: 56)
                    .position(x: size.width - 28 - capsuleWidth / 2,
                              y: size.height - 30 - 28)
            }
            .frame(width: size.width, height: size.height, alignment: .top)
        }
        .alert("Rename Script", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") {
                if let target = renameTarget {
                    model.rename(target, to: renameText)
                }
                renameTarget = nil
            }
        } message: {
            Text("The title appears on the shelf, the toolbar and the title page.")
        }
        .confirmationDialog("Delete this script?",
                            isPresented: Binding(
                                get: { deleteTarget != nil },
                                set: { if !$0 { deleteTarget = nil } }
                            ),
                            presenting: deleteTarget) { target in
            Button("Delete \(target.title)", role: .destructive) {
                model.delete(target)
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { target in
            Text("“\(target.title)” will be removed from this Mac. Exported copies are not affected.")
        }
        .alert("Couldn’t import that file",
               isPresented: Binding(get: { importError != nil },
                                    set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var importButton: some View {
        Button {
            let panel = NSOpenPanel()
            panel.title = "Import a Script"
            panel.message = "Choose a Fountain file or a screenplay PDF."
            panel.allowedContentTypes = [.pdf, UTType(filenameExtension: "fountain") ?? .plainText, .plainText]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            guard panel.runModal() == .OK, let url = panel.url else { return }
            if let error = model.importFile(url) { importError = error }
        } label: {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.ink2)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Import a Fountain file or screenplay PDF")
        .accessibilityLabel("Import a script")
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 16) {
            Text("CUE.")
                .font(Fonts.ui(36, weight: .semibold))
                .tracking(-1.65)
                .foregroundStyle(theme.ink)
                .offset(x: -5)
                .accessibilityLabel("Cue")

            Spacer(minLength: 20)

            importButton

            searchField
            CueSpeakerButton(size: 14)

            CueLampButton(showsTitle: false)
        }
        .frame(height: 44)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.ink2)

            TextField("Search scripts", text: $query)
                .textFieldStyle(.plain)
                .font(Fonts.ui(14))
                .foregroundStyle(theme.ink)
                .focused($searchFocused)
                .onExitCommand { query = "" }

            Spacer(minLength: 4)

            Text("⌘K")
                .font(Fonts.ui(11))
                .foregroundStyle(theme.ink2)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(theme.hair, lineWidth: 1)
                }
        }
        .padding(.horizontal, 12)
        .frame(width: 264, height: 36)
        .background {
            CueGlassBackground(radius: 18, elevated: false)
        }
        .background {
            Button("Search scripts") { searchFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    // MARK: Shelf

    private func shelf(cardWidth: CGFloat, gap: CGFloat) -> some View {
        let gridWidth = cardWidth * 3 + gap * 2
        let columns = Array(
            repeating: GridItem(.fixed(cardWidth), spacing: gap, alignment: .topLeading),
            count: 3
        )

        return VStack(alignment: .leading, spacing: 0) {
            Text(query.trimmingCharacters(in: .whitespaces).isEmpty
                 ? "SCRIPTS \(documents.count)"
                 : "RESULTS \(filtered.count)")
                .font(Fonts.ui(13, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(theme.ink2)
                .padding(.bottom, 10)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                newScriptCard(width: cardWidth)

                ForEach(filtered) { document in
                    scriptCard(document, width: cardWidth)
                }
            }

            if filtered.isEmpty && !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("No scripts match")
                    .font(Fonts.ui(11.5))
                    .foregroundStyle(theme.ink2)
                    .padding(.top, 26)
            }
        }
        .frame(width: gridWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .contain)
    }

    // MARK: New script card

    private func newScriptCard(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Button {
                withAnimation(reduceMotion ? nil : .cueFade) {
                    model.newScript()
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme.paper)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(hex: Hex.orange).opacity(theme.colorScheme == .dark ? 0.15 : 0.26))

                    Circle()
                        .fill(theme.paper.opacity(0.72))
                        .overlay {
                            Circle().strokeBorder(theme.hair, lineWidth: 1)
                        }
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(theme.ink2)
                        }
                        .frame(width: 38, height: 38)
                }
                .frame(width: width, height: width * 11 / 8.5)
                .shadow(color: theme.shadow, radius: newHovering ? 18 : 12, x: 0, y: newHovering ? 12 : 8)
                .offset(y: reduceMotion ? 0 : (newHovering ? -2 : 0))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { value in
                withAnimation(reduceMotion ? nil : .cueHover) { newHovering = value }
            }
            .accessibilityLabel("New script")

            VStack(alignment: .leading, spacing: 5) {
                Text("New script")
                    .font(Fonts.ui(14, weight: .medium))
                    .foregroundStyle(theme.ink)
                Text("⌘N")
                    .font(Fonts.ui(13.5))
                    .foregroundStyle(theme.ink2)
            }
        }
    }

    // MARK: Script card

    private func scriptCard(_ document: CueDocument, width: CGFloat) -> some View {
        let hovering = hoveredDocument == document.id
        let pages = document.pageCount
        let scenes = document.sceneCount

        return VStack(alignment: .leading, spacing: 22) {
            Button {
                withAnimation(reduceMotion ? nil : .cueFade) {
                    model.open(document)
                }
            } label: {
                CuePaper(radius: 6, soft: true) {
                    VStack(spacing: width * 0.042) {
                        Text(document.shelfTitle ?? document.title)
                            .font(Fonts.script(width * 0.057, bold: true))
                        Text("written by")
                            .font(Fonts.script(width * 0.036))
                            .foregroundStyle(theme.ink2)
                        Text("A. Writer")
                            .font(Fonts.script(width * 0.041))
                    }
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .padding(.horizontal, width * 0.12)
                    .offset(y: -width * 0.045)
                }
                .frame(width: width, height: width * 11 / 8.5)
                .offset(y: reduceMotion ? 0 : (hovering ? -2 : 0))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                Menu {
                        Button("Rename…") {
                            renameText = document.title
                            renameTarget = document
                        }
                        Button("Duplicate") { model.duplicate(document) }
                        Divider()
                        Button("Export PDF…") { model.exportPDF(document) }
                        Button("Export Fountain…") { model.exportFountain(document) }
                        Divider()
                        Button("Delete…", role: .destructive) { deleteTarget = document }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.ink2.opacity(hoveredDocument == document.id ? 0.95 : 0.55))
                            .frame(width: 24, height: 20)
                            .background(
                                Capsule().fill(theme.paper.opacity(theme.colorScheme == .dark ? 0.30 : 0.72))
                            )
                            .overlay(
                                Capsule().strokeBorder(theme.hair, lineWidth: 1)
                            )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(8)
                .accessibilityLabel("Script actions for \(document.title)")
            }
            .onHover { value in
                withAnimation(reduceMotion ? nil : .cueHover) {
                    hoveredDocument = value ? document.id : nil
                }
            }
            .contextMenu {
                Button("Open") { model.open(document) }
                Button("Rename…") {
                    renameText = document.title
                    renameTarget = document
                }
                Button("Duplicate") { model.duplicate(document) }
                Divider()
                Button("Export PDF…") { model.exportPDF(document) }
                Button("Export Fountain…") { model.exportFountain(document) }
                Divider()
                Button("Delete…", role: .destructive) { deleteTarget = document }
            }
            .accessibilityLabel("Open \(document.title)")

            VStack(alignment: .leading, spacing: 5) {
                Text(document.shelfTitle ?? document.title)
                    .font(Fonts.ui(14, weight: .medium))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)

                Text("\(pages) \(pages == 1 ? "page" : "pages") · \(scenes) \(scenes == 1 ? "scene" : "scenes")")
                    .font(Fonts.ui(13))
                    .foregroundStyle(theme.ink2)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Derived
}
