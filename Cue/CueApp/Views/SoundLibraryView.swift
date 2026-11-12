import SwiftUI
import CueKit

/// The sound library. A native list of rooms, grouped by where they put you,
/// with real playback behind every row. Everything here is generated on the
/// Mac; there is nothing to download and nothing to sign in to.
struct SoundLibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    private var audio: AmbientPlayer { model.audio }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.hair)
            List {
                ForEach(AmbientPlayer.Category.allCases) { category in
                    Section {
                        ForEach(audio.tracks(in: category)) { track in
                            row(track)
                        }
                    } header: {
                        Text(category.rawValue.uppercased())
                            .font(Fonts.ui(10.5, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(theme.ink2)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            Divider().overlay(theme.hair)
            footer
        }
        .frame(width: 390, height: 560)
        .background(theme.paper)
        .preferredColorScheme(theme.colorScheme)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            artwork
            VStack(alignment: .leading, spacing: 4) {
                Text("Sound")
                    .font(Fonts.ui(21, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text(audio.track.title)
                    .font(Fonts.ui(14, weight: .medium))
                    .foregroundStyle(theme.ink)
                Text(audio.isPreparing ? "Making the room…" : audio.track.subtitle)
                    .font(Fonts.ui(12.5))
                    .foregroundStyle(theme.ink2)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.ink2)
                    .frame(width: 26, height: 26)
                    .background(theme.desk.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close the sound library")
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var artwork: some View {
        Button { model.toggleMusic() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: palette,
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                if audio.isPreparing {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: audio.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: audio.playing ? 0 : 1)
                }
            }
            .frame(width: 62, height: 62)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 1)
            }
            .shadow(color: theme.shadow.opacity(0.6), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(audio.playing ? "Pause sound" : "Play sound")
    }

    private func row(_ track: AmbientPlayer.Track) -> some View {
        let current = track.id == audio.trackIndex
        return Button {
            audio.select(track.id, play: true)
            model.syncMusic()
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(LinearGradient(colors: track.palette.map { Color(hex: $0) },
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                    .overlay {
                        if current {
                            Image(systemName: audio.playing ? "waveform" : "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.95))
                        }
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(Fonts.ui(13.5, weight: current ? .semibold : .regular))
                        .foregroundStyle(theme.ink)
                    Text(track.subtitle)
                        .font(Fonts.ui(11.5))
                        .foregroundStyle(theme.ink2)
                }
                Spacer()
                if current {
                    Image(systemName: audio.isPreparing ? "ellipsis" : (audio.playing ? "speaker.wave.2.fill" : "pause.circle"))
                        .font(.system(size: 12))
                        .foregroundStyle(theme.ink2)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(current ? theme.desk.opacity(0.55) : Color.clear)
        .accessibilityLabel("\(track.title), \(track.subtitle)")
        .accessibilityValue(current ? (audio.playing ? "Playing" : "Selected") : "")
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.ink2)
                Slider(value: Binding(get: { Double(audio.volume) },
                                      set: { audio.setVolume(Float($0)) }),
                       in: 0...1)
                    .controlSize(.small)
                    .tint(Color(hex: Hex.orange))
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.ink2)
                Text("\(Int(audio.volume * 100))%")
                    .font(Fonts.ui(11).monospacedDigit())
                    .foregroundStyle(theme.ink2)
                    .frame(width: 34, alignment: .trailing)
            }
            HStack {
                Label("Synthesised on this Mac", systemImage: "waveform.path")
                    .font(Fonts.ui(11))
                    .foregroundStyle(theme.ink2)
                Spacer()
                if audio.playing {
                    Button("Stop") { model.toggleMusic() }
                        .buttonStyle(.plain)
                        .font(Fonts.ui(11.5, weight: .medium))
                        .foregroundStyle(theme.ink2)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var palette: [Color] {
        let colours = audio.track.palette
        return colours.isEmpty ? [theme.ink2] : colours.map { Color(hex: $0) }
    }
}
