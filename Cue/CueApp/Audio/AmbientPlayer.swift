import AppKit
import AVFoundation
import Observation

/// The little soundtrack beside the page.
///
/// Cue ships with three room-tones rather than reaching into another app's
/// library: a warm night drive, rain on the window, and a plain room hum. They
/// are generated once, in memory, and looped; no audio files inflate the app and
/// no network is involved. The capsule shows real playback state.
@MainActor
@Observable
final class AmbientPlayer {
    struct Track: Identifiable {
        var id: Int
        var title: String
        var subtitle: String
        var palette: [UInt32]
    }

    let tracks: [Track] = [
        .init(id: 0, title: "Night Drive", subtitle: "Warm pad, slow road",
              palette: [0x5B3F8C, 0xC2577A, 0xE59A4E]),
        .init(id: 1, title: "Rain on Glass", subtitle: "Weather for the window",
              palette: [0x3C6C78, 0x7FA8A6, 0xD8C7A8]),
        .init(id: 2, title: "Room Tone", subtitle: "Just the desk and you",
              palette: [0x6E5A47, 0xA98C6B, 0xD8B98A])
    ]

    private(set) var playing = false
    private(set) var trackIndex = 0
    private(set) var elapsed: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var clock: Task<Void, Never>?
    private var cache: [Int: Data] = [:]
    private var lastStart = Date()

    init() {
        prewarm(trackIndex)
    }

    /// Rendering a room tone takes a moment. Do it at launch, off the main
    /// actor, so the first press of play is instant.
    private func prewarm(_ index: Int) {
        Task.detached(priority: .utility) { [weak self] in
            let data = Self.render(track: index)
            await MainActor.run {
                self?.cache[index] = data
            }
        }
    }

    var track: Track { tracks[trackIndex] }

    var duration: TimeInterval { player?.duration ?? 120 }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    func toggle() {
        playing ? pause() : play()
    }

    func play() {
        ensurePlayer()
        guard let player else { return }
        player.play()
        playing = true
        lastStart = Date()
        startClock()
    }

    func pause() {
        player?.pause()
        playing = false
        clock?.cancel()
        clock = nil
    }

    func skip(_ direction: Int) {
        trackIndex = (trackIndex + direction + tracks.count) % tracks.count
        let wasPlaying = playing
        player?.stop()
        player = nil
        elapsed = 0
        lastStart = Date()
        if cache[trackIndex] == nil { prewarm(trackIndex) }
        if wasPlaying { play() }
    }

    func select(_ index: Int) {
        guard tracks.indices.contains(index) else { return }
        let wasPlaying = playing
        trackIndex = index
        player?.stop()
        player = nil
        elapsed = 0
        lastStart = Date()
        if cache[trackIndex] == nil { prewarm(trackIndex) }
        if wasPlaying { play() }
    }

    func setVolume(_ value: Float) {
        player?.volume = min(1, max(0, value))
    }

    // MARK: Transport

    private func ensurePlayer() {
        if let player { return }
        let data = cache[trackIndex] ?? Self.render(track: trackIndex)
        cache[trackIndex] = data
        do {
            let created = try AVAudioPlayer(data: data)
            created.numberOfLoops = -1
            created.volume = 0.55
            created.prepareToPlay()
            player = created
        } catch {
            NSLog("Cue: could not start the room tone: \(error.localizedDescription)")
        }
    }

    private func startClock() {
        clock?.cancel()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.playing else { return }
                self.elapsed = (self.elapsed + 0.25).truncatingRemainder(dividingBy: max(self.duration, 1))
            }
        }
    }

    // MARK: Synthesis

    /// A small mono WAV. Three textures share one generator: tonal beds for the
    /// night drive, shaped noise for rain, and a near-silent hum for the room.
    nonisolated private static func render(track: Int) -> Data {
        let rate = 22_050
        let seconds = 120
        let frames = rate * seconds
        var samples = [Int16](repeating: 0, count: frames)

        var seed: UInt64 = 0x9E3779B97F4A7C15
        func noise() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let value = Double((seed >> 33) & 0x7FFF_FFFF) / Double(0x7FFF_FFFF)
            return value * 2 - 1
        }

        var low = 0.0
        var brown = 0.0

        for index in 0..<frames {
            let time = Double(index) / Double(rate)
            var value = 0.0
            let white = noise()
            low += (white - low) * 0.02
            brown = brown * 0.995 + white * 0.005

            switch track {
            case 0:
                // A slow Am chord with a breathing filter.
                let chord = [110.0, 164.81, 220.0, 261.63, 329.63]
                let breathe = 0.55 + 0.45 * sin(time * 0.08)
                for (voice, frequency) in chord.enumerated() {
                    let detune = 1 + Double(voice) * 0.0007
                    value += sin(2 * .pi * frequency * detune * time) * 0.055 * breathe
                }
                value += low * 0.035
                let pulse = pow(max(0, sin(time * 1.1)), 18) * 0.04
                value += sin(2 * .pi * 55 * time) * pulse
            case 1:
                // Rain: band-limited hiss, a slower wash, occasional droplets.
                let drop = max(0, sin(time * 8.3 + sin(time * 1.7) * 3)) * low
                value = low * 0.12 + brown * 0.18 + drop * 0.045
                value += sin(2 * .pi * 180 * time) * 0.003
            default:
                value = brown * 0.16 + low * 0.015
                value += sin(2 * .pi * 60 * time) * 0.006
            }

            let fadeIn = min(1, time / 2.5)
            let fadeOut = min(1, (Double(seconds) - time) / 2.5)
            let envelope = max(0, min(fadeIn, fadeOut))
            let scaled = tanh(value * 2.2) * 0.72 * envelope
            samples[index] = Int16(max(-1, min(1, scaled)) * Double(Int16.max))
        }

        return waveData(samples: samples, sampleRate: rate)
    }

    nonisolated private static func waveData(samples: [Int16], sampleRate: Int) -> Data {
        let byteCount = samples.count * 2
        var data = Data(capacity: 44 + byteCount)

        func append(_ string: String) {
            data.append(contentsOf: Array(string.utf8))
        }
        func append32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func append16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }

        append("RIFF")
        append32(UInt32(36 + byteCount))
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(1)
        append16(1)
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))
        append16(2)
        append16(16)
        append("data")
        append32(UInt32(byteCount))

        for sample in samples {
            var little = sample.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        return data
    }
}
