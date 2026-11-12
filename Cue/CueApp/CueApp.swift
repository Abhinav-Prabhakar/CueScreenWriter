import SwiftUI
import AppKit
import CueKit

@main
struct CueApp: App {
    @State private var model = AppModel()

    init() {
        Fonts.register()
    }

    var body: some Scene {
        WindowGroup("Cue") {
            AppRoot()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(model.theme.colorScheme)
        }
        .defaultSize(width: 1200, height: 778)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Script") { model.newScript() }
                    .keyboardShortcut("n")
                Button("Open Library") { model.route = .library }
                    .keyboardShortcut("0", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") { model.sidebarVisible.toggle() }
                    .keyboardShortcut("\\", modifiers: [.command, .option])
                Button("Add Note…") { model.beginNote() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .importExport) {
                Button("Import Script…") {
                    if let error = model.importScriptPanel() {
                        let alert = NSAlert()
                        alert.alertStyle = .warning
                        alert.messageText = "Couldn’t import that file"
                        alert.informativeText = error
                        alert.runModal()
                    }
                }
                .keyboardShortcut("o")
            }
            CommandMenu("Desk") {
                Button("Add Sticky Note") { model.addSticky() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Pin a Photo…") { model.pinPhotoPanel() }
                Divider()
                Button("Show Help") { model.showHelpSheet() }
                    .keyboardShortcut("/", modifiers: .command)
                Button("Save Now") { model.flush() }
                    .keyboardShortcut("s")
            }
            CommandMenu("Lamp") {
                Button("Daylight") { model.lamp.choose(.daylight) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("Evening") { model.lamp.choose(.evening) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("Night") { model.lamp.choose(.night) }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Button("Auto") { model.lamp.useAuto() }
                    .keyboardShortcut("0", modifiers: [.command, .option])
                Divider()
                Button(model.lit ? "Turn Lamp Off" : "Turn Lamp On") { model.toggleLit() }
                    .keyboardShortcut("l", modifiers: [.command, .option])
            }
            CommandGroup(after: .saveItem) {
                Button("Export PDF…") { model.exportPDF() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Export Fountain…") { model.exportFountain() }
                    .keyboardShortcut("e", modifiers: [.command, .option])
            }
        }
    }
}

struct AppRoot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            model.theme.desk.ignoresSafeArea()
            switch model.route {
            case .library:
                LibraryView()
                    .transition(.opacity)
            case .writing:
                WritingView()
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if model.route == .writing {
                ToolbarView()
            }
        }
        // The theme must wrap the toolbar too: applying it before `.overlay`
        // leaves the overlay on the default (Daylight) palette, which made the
        // night title render in ink on the dark desk.
        .theme(model.theme)
        .animation(.cueFade, value: model.route)
        .ignoresSafeArea()
    }
}
