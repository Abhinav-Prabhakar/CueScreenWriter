import SwiftUI
import AppKit
import CueKit

/// The floating now-playing capsule. A glass pill on the desk, not a toolbar:
/// artwork doubles as play/pause, the waveform takes its colours from the track,
/// and the time advances once per second.
struct MusicCapsule: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var music: MusicState { model.music }

    var body: some View {
        if !music.title.isEmpty {
            ViewThatFits(in: .horizontal) {
                capsuleContent(waveWidth: 118, showsTransport: true, valueWidth: 128)
                capsuleContent(waveWidth: 66, showsTransport: false, valueWidth: 112)
            }
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                CueGlassBackground(radius: 30, elevated: true)
            }
            .offset(y: reduceMotion ? 0 : (hovering ? -2 : 0))
            .animation(reduceMotion ? nil : .cueHover, value: hovering)
            .onHover { hovering = $0 }
            .task(id: model.audio.playing) {
                guard model.audio.playing else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled, model.audio.playing else { return }
                    model.syncMusic()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Now playing, \(music.title)")
        }
    }

    private func capsuleContent(waveWidth: CGFloat,
                                showsTransport: Bool,
                                valueWidth: CGFloat) -> some View {
        HStack(spacing: 9) {
            playButton

            Button {
                model.showSound()
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: Hex.orange))
                            .frame(width: 7, height: 7)
                        Text(music.title)
                            .font(Fonts.ui(15, weight: .semibold))
                            .foregroundStyle(theme.ink)
                            .lineLimit(1)
                    }
                    Text(model.audio.isPreparing
                         ? "Making the room…"
                         : "\(music.subtitle) · \(Self.clock(music.time))")
                        .font(Fonts.ui(12.5))
                        .foregroundStyle(theme.ink2)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .frame(width: valueWidth, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open the sound library")
            .accessibilityLabel("Now playing \(music.title). Open the sound library")

            Spacer(minLength: 0)

            waveform
                .frame(width: waveWidth, height: 30)

            if showsTransport {
                HStack(spacing: 8) {
                    transport(system: "chevron.backward.2", label: "Previous track") {
                        musicSkip(-1)
                    }
                    transport(system: "chevron.forward.2", label: "Next track") {
                        musicSkip(1)
                    }
                    transport(system: "music.note.list", label: "Sound library") {
                        model.showSound()
                    }
                }
            }
        }
    }

    // MARK: Controls

    private var playButton: some View {
        Button {
            model.toggleMusic()
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [music.palette.first ?? Color(hex: 0x5B3F8C),
                                     music.palette.dropFirst().first ?? Color(hex: 0xC2577A)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        // The reference artwork is a deep navy-to-violet wash,
                        // not a bright chip: keep the gradient dark so the white
                        // pause glyph reads the same way.
                        Circle()
                            .fill(Color.black.opacity(0.28))
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(.white.opacity(0.14))
                            .frame(width: 18, height: 18)
                            .blur(radius: 6)
                            .offset(x: 6, y: 4)
                    }
                    .shadow(color: theme.shadow.opacity(0.7), radius: 6, x: 0, y: 3)

                if model.audio.isPreparing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if music.playing {
                    HStack(spacing: 4) {
                        Capsule().fill(.white).frame(width: 3, height: 16)
                        Capsule().fill(.white).frame(width: 3, height: 16)
                    }
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: 1)
                }
            }
            .frame(width: 62, height: 62)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(music.playing ? "Pause" : "Play")
    }

    private func transport(system: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.ink2)
                .frame(width: 18, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func musicSkip(_ direction: Int) {
        model.skipMusic(direction)
    }

    // MARK: Waveform

    @ViewBuilder
    private var waveform: some View {
        if reduceMotion {
            CueWaveform(phase: 0,
                        progress: progress,
                        palette: music.palette,
                        playing: false,
                        idleColour: theme.ink2,
                        reduceMotion: true)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !music.playing)) { timeline in
                CueWaveform(phase: timeline.date.timeIntervalSinceReferenceDate,
                            progress: progress,
                            palette: music.palette,
                            playing: music.playing,
                            idleColour: theme.ink2,
                            reduceMotion: false)
            }
        }
    }

    private var progress: Double {
        guard music.duration > 0 else { return 0 }
        return min(1, max(0, Double(music.time) / Double(music.duration)))
    }

    static func clock(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        return String(format: "%d:%02d", safe / 60, safe % 60)
    }
}

/// The fixed silhouette, animated with a small per-bar sine offset. Bars left of
/// the playhead are in the track's colours; bars to the right are quiet ink.
private struct CueWaveform: View {
    var phase: TimeInterval
    var progress: Double
    var palette: [Color]
    var playing: Bool
    var idleColour: Color
    var reduceMotion: Bool

    private static let silhouette: [CGFloat] = [
        0.30, 0.46, 0.82, 0.58, 0.36, 0.64, 0.92, 0.72,
        0.44, 0.86, 0.56, 0.34, 0.52, 0.78, 0.62, 0.40,
        0.70, 0.95, 0.66, 0.48, 0.28, 0.54, 0.82, 0.60,
        0.38, 0.74, 0.90, 0.56, 0.42, 0.68, 0.50, 0.26,
        0.44, 0.60
    ]

    var body: some View {
        Canvas { context, size in
            let count = Self.silhouette.count
            let slot = size.width / CGFloat(count)
            let barWidth = max(1.6, slot * 0.52)
            let played = Int((progress * Double(count)).rounded())

            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: palette.isEmpty ? [Color(hex: 0x5B3F8C)] : palette),
                startPoint: CGPoint(x: 0, y: size.height / 2),
                endPoint: CGPoint(x: size.width, y: size.height / 2)
            )

            for index in 0..<count {
                let base = Self.silhouette[index]
                let wobble: CGFloat
                if playing && !reduceMotion {
                    wobble = CGFloat(sin(phase * 2.1 + Double(index) * 0.55)) * 0.13
                } else {
                    wobble = 0
                }

                let fraction = max(0.08, min(1, base + wobble))
                let height = max(2, size.height * (index < played ? fraction : fraction * 0.78))
                let x = CGFloat(index) * slot + (slot - barWidth) / 2
                let rect = CGRect(x: x, y: (size.height - height) / 2,
                                  width: barWidth, height: height)
                let bar = Path(roundedRect: rect, cornerRadius: barWidth / 2)

                if index < played {
                    context.fill(bar, with: shading)
                } else {
                    // Unplayed bars keep a wash of their own colour rather than
                    // going grey: the capsule stays a piece of artwork at rest.
                    let tint = palette.isEmpty
                        ? idleColour
                        : palette[index % palette.count]
                    context.fill(bar, with: .color(tint.opacity(0.26)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
