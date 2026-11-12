import SwiftUI
import AppKit
import CueKit

/// A standard macOS Settings window: small, native, and mostly for things that
/// do not belong in the writing room.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            SoundSettings()
                .tabItem { Label("Sound", systemImage: "speaker.wave.2") }
            UpdateSettings()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }
        .frame(width: 500, height: 360)
        .environment(model)
        .theme(model.theme)
        .preferredColorScheme(model.theme.colorScheme)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    private var lampSelection: Binding<Lamp?> {
        Binding(
            get: { model.lamp.isAuto ? nil : model.lamp.lamp },
            set: { value in
                if let value { model.lamp.choose(value) } else { model.lamp.useAuto() }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Light", selection: lampSelection) {
                    Text("Daylight").tag(Optional(Lamp.daylight))
                    Text("Evening").tag(Optional(Lamp.evening))
                    Text("Night").tag(Optional(Lamp.night))
                    Text("Follow the time of day").tag(Optional<Lamp>.none)
                }
                Toggle("Keep the lamp on", isOn: Binding(get: { model.lit },
                                                        set: { model.lit = $0 }))
                Toggle("Show the sidebar", isOn: Binding(get: { model.sidebarVisible },
                                                         set: { model.sidebarVisible = $0 }))
            }

            Section {
                LabeledContent("Scripts") {
                    Button("Show in Finder") {
                        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                           in: .userDomainMask).first
                        let folder = base?.appendingPathComponent("Cue", isDirectory: true)
                        if let folder { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    }
                }
                LabeledContent("Library") {
                    Text("\(model.documents.count) scripts")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct SoundSettings: View {
    @Environment(AppModel.self) private var model

    private var audio: AmbientPlayer { model.audio }

    var body: some View {
        Form {
            Section("Now") {
                LabeledContent("Room") {
                    Text(audio.track.title)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Volume") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(get: { Double(audio.volume) },
                                              set: { audio.setVolume(Float($0)) }),
                               in: 0...1)
                            .tint(Color(hex: Hex.orange))
                            .frame(width: 180)
                        Text("\(Int(audio.volume * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                HStack {
                    Button(audio.playing ? "Pause" : "Play") { model.toggleMusic() }
                    Button("Sound Library…") { model.showSound() }
                }
            }

            Section {
                Text("\(audio.tracks.count) rooms are synthesised on this Mac. Nothing is streamed or downloaded.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct UpdateSettings: View {
    @Environment(AppModel.self) private var model

    private var updates: UpdateController { model.updates }

    var body: some View {
        Form {
            Section {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updates.automatic },
                    set: { updates.automatic = $0 }
                ))
                LabeledContent("Last checked") {
                    Text(updates.lastCheck.map {
                        $0.formatted(date: .abbreviated, time: .shortened)
                    } ?? "Never")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Version") {
                    Text(UpdateController.currentVersion)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Button(updates.isBusy ? "Working…" : "Check Now") {
                        Task { await updates.check(manual: true) }
                    }
                    .disabled(updates.isBusy)
                    Button("Release Notes") {
                        if let url = URL(string: "https://github.com/\(UpdateController.repository)/releases") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                Text("Cue asks GitHub Releases once a month. A manual check is always allowed. Downloads install in the background and finish when Cue quits.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
