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
        WindowGroup("Cue", id: "main") {
            AppRoot()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(model.theme.colorScheme)
        }
        .defaultSize(width: 1200, height: 778)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await model.updates.check(manual: true) }
                }
                .keyboardShortcut("u")
            }
            CommandGroup(replacing: .newItem) {
                Button("New Script") { model.newScript() }
                    .keyboardShortcut("n")
                Button("Rename Script…") { model.beginTitleRename() }
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
                Button("Sound Library…") { model.showSound() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
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

        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra("Cue", systemImage: "eye") {
            CueMenuBarContent()
                .environment(model)
        }
        .menuBarExtraStyle(.menu)
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
        .overlay(alignment: .top) {
            UpdateBanner()
                .padding(.top, model.route == .writing ? 82 : 18)
        }
        // The theme must wrap the toolbar too: applying it before `.overlay`
        // leaves the overlay on the default (Daylight) palette, which made the
        // night title render in ink on the dark desk.
        .theme(model.theme)
        .animation(.cueFade, value: model.route)
        .animation(.cueFade, value: model.updates.phase)
        .ignoresSafeArea()
        .background {
            CueTouchBarInstaller(model: model)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
        .sheet(isPresented: Binding(get: { model.showSoundLibrary },
                                    set: { model.showSoundLibrary = $0 })) {
            SoundLibraryView()
                .environment(model)
                .theme(model.theme)
                .preferredColorScheme(model.theme.colorScheme)
        }
        .sheet(isPresented: Binding(get: { model.updates.showSheet },
                                    set: { model.updates.showSheet = $0 })) {
            UpdateSheet()
                .environment(model)
                .theme(model.theme)
                .preferredColorScheme(model.theme.colorScheme)
        }
        .task {
            await model.updates.automaticCheckIfDue()
        }
    }
}

/// The menu bar's own little control room: open Cue, play the room tone, change
/// the light, or ask for an update without hunting through the app menu.
private struct CueMenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Cue") { showApp() }
            .keyboardShortcut("o")

        Divider()

        Button(model.music.playing ? "Pause \(model.music.title)" : "Play \(model.music.title)") {
            model.toggleMusic()
        }
        Button("Sound Library…") {
            model.showSound()
            showApp()
        }
        Button("Next Room") { model.skipMusic(1) }

        Divider()

        Menu("Lamp") {
            Button("Daylight") { model.lamp.choose(.daylight) }
            Button("Evening") { model.lamp.choose(.evening) }
            Button("Night") { model.lamp.choose(.night) }
            Button("Follow the Time of Day") { model.lamp.useAuto() }
            Divider()
            Button(model.lit ? "Turn Lamp Off" : "Turn Lamp On") { model.toggleLit() }
        }

        Divider()

        if model.updates.phase == .ready {
            Button("Restart to Update…") {
                model.flush()
                model.updates.installAndRelaunch()
            }
        }
        Button(model.updates.isBusy ? "Checking for Updates…" : "Check for Updates…") {
            Task { await model.updates.check(manual: true) }
        }
        .disabled(model.updates.isBusy)

        Divider()

        Text("Cue \(UpdateController.currentVersion)")
    }

    private func showApp() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }
}
