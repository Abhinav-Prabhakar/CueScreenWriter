import SwiftUI
import AppKit
import CueKit

// MARK: - Glyphs

/// A desk lamp, reused in the toolbar and the library. It is deliberately not a
/// lightbulb: an idea is not a lamp.
///
/// The system's own `lamp.desk` symbol is the reference glyph. A custom
/// `Canvas`/`Shape` does not survive being flattened into a menu label, which
/// left the lamp invisible beside "Daylight".
struct CueLampGlyph: View {
    var body: some View {
        Image(systemName: "lamp.floor")
            .font(.system(size: 13.5, weight: .regular))
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }
}

// MARK: - Toolbar controls

struct CueToolbarButton: View {
    var system: String
    var label: String
    var size: CGFloat = 12
    var active: Bool = false
    var action: () -> Void

    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(active || hovering ? theme.ink : theme.ink2)
                .frame(width: 22, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(.cueHover) { hovering = value }
        }
        .help(label)
        .accessibilityLabel(label)
    }
}

struct CueLampButton: View {
    var showsTitle: Bool = true
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var hovering = false

    private var selection: Binding<Lamp?> {
        Binding(
            get: { model.lamp.isAuto ? nil : model.lamp.lamp },
            set: { value in
                if let value {
                    model.lamp.choose(value)
                } else {
                    model.lamp.useAuto()
                }
            }
        )
    }

    var body: some View {
        Menu {
            Picker("Lamp", selection: selection) {
                Text("Daylight").tag(Optional(Lamp.daylight))
                Text("Evening").tag(Optional(Lamp.evening))
                Text("Night").tag(Optional(Lamp.night))
                Text("Follow the time of day").tag(Optional<Lamp>.none)
            }
            .pickerStyle(.inline)

            Divider()

            Button(model.lit ? "Turn Lamp Off" : "Turn Lamp On") {
                model.toggleLit()
            }
        } label: {
            HStack(spacing: 6) {
                CueLampGlyph()
                if showsTitle {
                    Text(model.lamp.lamp.title)
                        .font(Fonts.ui(14.5))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(hovering ? theme.ink : theme.ink2)
            .opacity(model.lit ? 1 : 0.55)
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { value in
            withAnimation(.cueHover) { hovering = value }
        }
        .help("Lamp: \(model.lamp.label)")
        .accessibilityLabel("Lamp, \(model.lamp.lamp.title)")
    }
}

// MARK: - Toolbar

struct ToolbarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draftTitle = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // The centred title belongs to the top of the document; the
                // scrolled reference captures drop it while the sheet is part
                // way through the script.
                titleReadout
                    .frame(maxWidth: max(180, proxy.size.width - 660))

                HStack(spacing: 0) {
                    // With the sidebar open the back link lives in the sidebar
                    // card; the toolbar keeps only the right-hand controls.
                    if !model.sidebarVisible {
                        libraryLink
                            .padding(.leading, 80)
                    }
                    Spacer(minLength: 12)
                    controls
                        .padding(.trailing, 30)
                }
            }
            .frame(width: proxy.size.width, height: 32)
        }
        .frame(height: 32)
        .padding(.top, 46)
        .frame(maxWidth: .infinity)
    }

    // MARK: Centre

    private var titleReadout: some View {
        HStack(spacing: 11) {
            if model.isRenamingTitle {
                TextField("Script title", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(Fonts.ui(15, weight: .medium))
                    .foregroundStyle(theme.ink)
                    .focused($titleFocused)
                    .frame(width: 230)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(theme.desk.opacity(0.6),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color(hex: Hex.orange).opacity(0.55), lineWidth: 1)
                    }
                    .onSubmit { commitTitle() }
                    .onExitCommand { cancelTitle() }
                    .onChange(of: titleFocused) { _, focused in
                        if !focused { commitTitle() }
                    }
                    .onAppear { titleFocused = true }
                    .accessibilityLabel("Script title")
            } else {
                Text(model.title)
                    .font(Fonts.ui(15, weight: .medium))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture(count: 2) { beginTitleRename() }
                    .help("Double-click to rename")
                    .accessibilityAddTraits(.isButton)
            }

            Text("Scene \(model.position.scene) · Page \(model.position.page) of \(model.position.pages)")
                .font(Fonts.ui(15))
                .foregroundStyle(theme.ink2)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(model.title), scene \(model.position.scene), page \(model.position.page) of \(model.position.pages)")
        .onChange(of: model.isRenamingTitle) { _, renaming in
            if renaming {
                draftTitle = model.title
                titleFocused = true
            }
        }
    }

    private func beginTitleRename() {
        draftTitle = model.title
        model.isRenamingTitle = true
    }

    private func commitTitle() {
        guard model.isRenamingTitle else { return }
        let clean = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty, clean != model.title {
            model.setTitle(clean)
        } else {
            model.isRenamingTitle = false
        }
    }

    private func cancelTitle() {
        model.isRenamingTitle = false
    }

    // MARK: Left

    private var libraryLink: some View {
        Button {
            withAnimation(reduceMotion ? nil : .cueFade) {
                model.route = .library
            }
        } label: {
            HStack(spacing: 8) {
                Text("‹")
                    .font(Fonts.ui(16))
                    .offset(y: -0.5)
                Text("Library")
                    .font(Fonts.ui(15))
            }
            .foregroundStyle(theme.ink2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Back to the library")
        .accessibilityLabel("Back to Library")
    }

    // MARK: Right

    private var controls: some View {
        HStack(spacing: 16) {
            savedState

            CueToolbarButton(
                system: "sidebar.leading",
                label: model.sidebarVisible ? "Hide sidebar" : "Show sidebar",
                size: 14.5,
                active: model.sidebarVisible
            ) {
                withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5)) {
                    model.sidebarVisible.toggle()
                }
            }

            CueToolbarButton(
                system: "note.text",
                label: "Add a note on this line",
                size: 13.5
            ) {
                model.beginNote()
            }

            if model.updates.phase == .ready {
                Button {
                    model.updates.showSheet = true
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: Hex.orange))
                        .frame(width: 22, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("An update is ready")
                .accessibilityLabel("Update ready, Cue \(model.updates.available?.version ?? "")")
            }

            CueLampButton(showsTitle: true)

            CueToolbarButton(
                system: "arrow.up.left.and.arrow.down.right",
                label: model.fullScreen ? "Leave full screen" : "Full screen",
                size: 14,
                active: model.fullScreen
            ) {
                model.fullScreen.toggle()
                withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5)) {
                    model.sidebarVisible = !model.fullScreen
                }
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
        }
        .frame(height: 26)
    }

    private var savedState: some View {
        HStack(spacing: 6) {
            Circle()
                .strokeBorder(theme.ink2, lineWidth: 1)
                .background {
                    Circle()
                        .fill(theme.ink2)
                        .opacity(model.saveState == .saving ? 1 : 0)
                }
                .frame(width: 7, height: 7)

            Text(model.saveState == .saved ? "Saved" : "Saving")
                .font(Fonts.ui(14))
                .foregroundStyle(theme.ink2)
                .monospacedDigit()
        }
        .opacity(model.saveState == .saved ? 1 : 0.7)
        .animation(.cueFade, value: model.saveState)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.saveState == .saved ? "Saved" : "Saving")
    }
}
