import AppKit
import AVFoundation
import Observation

/// The little soundtrack beside the page.
///
/// Cue ships with fourteen rooms rather than reaching into another app's
/// library: focus beds, weather, and places to work. Every one is synthesised
/// on this Mac, in memory, and looped. No audio files inflate the app and no
/// network is involved. Tracks are rendered lazily the first time they are
/// chosen, so a large library costs nothing until it is used.
@MainActor
@Observable
final class AmbientPlayer {
    enum Category: String, CaseIterable, Identifiable {
        case focus = "Focus"
        case weather = "Weather"
        case places = "Places"

        var id: String { rawValue }
    }

    enum Texture {
        case nightDrive, roomTone, tapeHiss, deepDesk
        case rainGlass, heavyRain, thunder, windPines, lowTide
        case cafe, library, nightTrain, fireplace, harbour
    }

    struct Track: Identifiable {
        var id: Int
        var title: String
        var subtitle: String
        var category: Category
        var palette: [UInt32]
        var texture: Texture
    }

    let tracks: [Track] = [
        .init(id: 0, title: "Night Drive", subtitle: "Warm pad, slow road",
              category: .focus, palette: [0x5B3F8C, 0xC2577A, 0xE59A4E], texture: .nightDrive),
        .init(id: 1, title: "Room Tone", subtitle: "Just the desk and you",
              category: .focus, palette: [0x6E5A47, 0xA98C6B, 0xD8B98A], texture: .roomTone),
        .init(id: 2, title: "Tape Hiss", subtitle: "Old tape, warm motor",
              category: .focus, palette: [0x6A6250, 0xB7A47E, 0xE1D2AC], texture: .tapeHiss),
        .init(id: 3, title: "Deep Desk", subtitle: "A low, closed room",
              category: .focus, palette: [0x3E4A56, 0x71808C, 0xB9C2C4], texture: .deepDesk),

        .init(id: 4, title: "Rain on Glass", subtitle: "Weather for the window",
              category: .weather, palette: [0x3C6C78, 0x7FA8A6, 0xD8C7A8], texture: .rainGlass),
        .init(id: 5, title: "Heavy Rain", subtitle: "A gutter, a downpour",
              category: .weather, palette: [0x2F5663, 0x6C929A, 0xC9BFA9], texture: .heavyRain),
        .init(id: 6, title: "Distant Thunder", subtitle: "Far off, moving closer",
              category: .weather, palette: [0x394654, 0x64707F, 0xC0A98C], texture: .thunder),
        .init(id: 7, title: "Wind in Pines", subtitle: "A high, open window",
              category: .weather, palette: [0x40594B, 0x7C9478, 0xD2C6A4], texture: .windPines),
        .init(id: 8, title: "Low Tide", subtitle: "Water pulling back",
              category: .weather, palette: [0x3D5D62, 0x83A09B, 0xD9CBB0], texture: .lowTide),

        .init(id: 9, title: "Café Murmur", subtitle: "Cups, chairs, other lives",
              category: .places, palette: [0x7A5641, 0xB98A64, 0xE3C7A2], texture: .cafe),
        .init(id: 10, title: "The Library", subtitle: "Pages, dust, quiet",
              category: .places, palette: [0x5A5146, 0x968773, 0xD3C5AE], texture: .library),
        .init(id: 11, title: "Night Train", subtitle: "Steady rails under you",
              category: .places, palette: [0x41465B, 0x7A7890, 0xC9BFA8], texture: .nightTrain),
        .init(id: 12, title: "Fireplace", subtitle: "A chair, a low fire",
              category: .places, palette: [0x79472F, 0xC07845, 0xE8B879], texture: .fireplace),
        .init(id: 13, title: "Harbour Fog", subtitle: "A horn beyond the pier",
              category: .places, palette: [0x455A60, 0x7E9593, 0xCFC5B1], texture: .harbour)
    ]

    private(set) var playing = false
    private(set) var trackIndex = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var preparing: Set<Int> = []

    var volume: Float {
        didSet {
            let clamped = min(1, max(0, volume))
            if clamped != volume { volume = clamped; return }
            player?.volume = clamped
            UserDefaults.standard.set(Double(clamped), forKey: "cue.sound.volume")
        }
    }

    private var player: AVAudioPlayer?
    private var clock: Task<Void, Never>?
    private var cache: [Int: Data] = [:]
    private var lastStart = Date()
    private var wantsPlay = false

    init() {
        let saved = UserDefaults.standard.object(forKey: "cue.sound.volume") as? Double
        volume = Float(saved ?? 0.55)
        prewarm(trackIndex)
    }

    /// Rendering a room takes a moment. Do it at launch, off the main actor, so
    /// the first press of play is instant.
    private func prewarm(_ index: Int) {
        guard tracks.indices.contains(index),
              cache[index] == nil,
              !preparing.contains(index) else { return }
        preparing.insert(index)
        Task.detached(priority: .utility) { [weak self] in
            let data = Self.render(track: index)
            await MainActor.run {
                guard let self else { return }
                self.cache[index] = data
                self.preparing.remove(index)
                if index == self.trackIndex, self.wantsPlay {
                    self.startPlayback()
                }
            }
        }
    }

    var track: Track { tracks[min(trackIndex, tracks.count - 1)] }

    var duration: TimeInterval { player?.duration ?? 90 }

    var isPreparing: Bool { preparing.contains(trackIndex) }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    func tracks(in category: Category) -> [Track] {
        tracks.filter { $0.category == category }
    }

    // MARK: Transport

    func toggle() {
        playing ? pause() : play()
    }

    func play() {
        wantsPlay = true
        if cache[trackIndex] == nil {
            prewarm(trackIndex)
            return
        }
        startPlayback()
    }

    func pause() {
        wantsPlay = false
        player?.pause()
        playing = false
        clock?.cancel()
        clock = nil
    }

    func skip(_ direction: Int) {
        let wasPlaying = playing
        select((trackIndex + direction + tracks.count) % tracks.count, play: wasPlaying)
    }

    /// Choosing from the library starts the room immediately: a silent row is
    /// indistinguishable from a broken one.
    func select(_ index: Int, play shouldPlay: Bool = true) {
        guard tracks.indices.contains(index) else { return }
        let changed = index != trackIndex
        player?.stop()
        player = nil
        if changed {
            elapsed = 0
            lastStart = Date()
        }
        trackIndex = index
        wantsPlay = shouldPlay
        playing = false
        clock?.cancel()
        clock = nil

        if cache[index] == nil {
            prewarm(index)
        } else if shouldPlay {
            startPlayback()
        }
    }

    func setVolume(_ value: Float) {
        volume = min(1, max(0, value))
    }

    private func startPlayback() {
        guard ensurePlayer() else { return }
        guard let player else { return }
        player.play()
        playing = true
        lastStart = Date()
        startClock()
    }

    private func ensurePlayer() -> Bool {
        if player != nil { return true }
        guard let data = cache[trackIndex] else { return false }
        do {
            let created = try AVAudioPlayer(data: data)
            created.numberOfLoops = -1
            created.volume = volume
            created.prepareToPlay()
            player = created
            return true
        } catch {
            NSLog("Cue: could not start the room tone: \(error.localizedDescription)")
            return false
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

    /// A small mono WAV. Every room shares one generator: tonal beds for the
    /// night drive, shaped noise for weather, and small events — cups, pages,
    /// rails, fire — for the places.
    nonisolated private static func render(track: Int) -> Data {
        let rate = 22_050
        let seconds = 90
        let frames = rate * seconds
        var samples = [Int16](repeating: 0, count: frames)

        var seed: UInt64 = 0x9E3779B97F4A7C15 &+ UInt64(track + 1) &* 0x9E3779B1
        func noise() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let value = Double((seed >> 33) & 0x7FFF_FFFF) / Double(0x7FFF_FFFF)
            return value * 2 - 1
        }

        var low = 0.0
        var brown = 0.0
        var pop = 0.0
        var spark = 0.0

        func sine(_ frequency: Double, _ time: Double) -> Double {
            sin(2 * .pi * frequency * time)
        }

        for index in 0..<frames {
            let time = Double(index) / Double(rate)
            var value = 0.0
            let white = noise()
            low += (white - low) * 0.02
            brown = brown * 0.995 + white * 0.005
            pop *= 0.995
            spark *= 0.93

            switch track {
            case 0:
                // A slow Am chord with a breathing filter.
                let chord = [110.0, 164.81, 220.0, 261.63, 329.63]
                let breathe = 0.55 + 0.45 * sin(time * 0.08)
                for (voice, frequency) in chord.enumerated() {
                    value += sine(frequency * (1 + Double(voice) * 0.0007), time) * 0.055 * breathe
                }
                value += low * 0.035
                let pulse = pow(max(0, sin(time * 1.1)), 18) * 0.04
                value += sine(55, time) * pulse

            case 1:
                value = brown * 0.16 + low * 0.015 + sine(60, time) * 0.006

            case 2:
                // Tape: a high, soft hiss over a motor with a slow wow.
                let high = (white - low) * 0.5
                let wow = 1 + 0.002 * sin(0.6 * time)
                value = high * 0.055 + low * 0.025 + sine(55 * wow, time) * 0.004
                value += spark * 0.02

            case 3:
                value = sine(45, time) * 0.03 + brown * 0.15 + low * 0.008
                value += sine(90, time) * 0.006

            case 4:
                // Rain: band-limited hiss, a slower wash, occasional droplets.
                let drop = max(0, sin(time * 8.3 + sin(time * 1.7) * 3)) * low
                value = low * 0.12 + brown * 0.18 + drop * 0.045
                value += sine(180, time) * 0.003

            case 5:
                let drop = max(0, sin(time * 11.7 + sin(time * 2.3) * 4)) * low
                value = low * 0.20 + brown * 0.24 + drop * 0.07
                value += sine(92, time) * 0.004

            case 6:
                let drop = max(0, sin(time * 8.3 + sin(time * 1.7) * 3)) * low
                value = low * 0.13 + brown * 0.19 + drop * 0.04
                let cycle = time.truncatingRemainder(dividingBy: 26)
                if cycle < 7 {
                    let envelope = exp(-cycle * 0.55) * (0.35 + 0.65 * (1 - cycle / 7))
                    value += sine(36 + sin(cycle * 0.9) * 3, time) * 0.22 * envelope
                    value += brown * 0.35 * envelope
                }

            case 7:
                let gust = 0.35 + 0.65 * (0.5 + 0.5 * sin(time * 0.11 + sin(time * 0.037) * 2))
                value = low * 0.20 * gust + (white - low) * 0.018 * gust
                value += sine(420 + sin(time * 0.2) * 40, time) * 0.003 * gust

            case 8:
                let swell = 0.5 + 0.5 * sin(2 * .pi * time / 18)
                value = low * 0.11 * swell + brown * 0.16 * (1 - swell * 0.35)
                value += sine(180, time) * 0.002 * swell

            case 9:
                // Café: a warm wash, a murmur band, and the occasional cup.
                value = brown * 0.11 + low * 0.07
                value += (white - low) * 0.012 * (0.5 + 0.5 * sin(time * 0.7))
                let cycle = time.truncatingRemainder(dividingBy: 7.3)
                if cycle < 1.4 {
                    let envelope = exp(-cycle * 4.2)
                    value += (sine(2350, time) + sine(3120, time) * 0.5) * 0.018 * envelope
                }

            case 10:
                value = brown * 0.07 + low * 0.005
                let cycle = time.truncatingRemainder(dividingBy: 17)
                if cycle < 0.6 {
                    let envelope = exp(-cycle * 7)
                    value += (white - low) * 0.10 * envelope
                }

            case 11:
                value = sine(42, time) * 0.07 + brown * 0.19 + low * 0.02
                let click = time.truncatingRemainder(dividingBy: 1.05)
                if click < 0.06 {
                    value += (white - low) * 0.08 * exp(-click * 60)
                }
                value += sine(84, time) * 0.004

            case 12:
                value = brown * 0.10 + low * 0.03
                if white > 0.996 { pop = 0.45 }
                if white < -0.9985 { spark = 0.30 }
                value += pop * sine(1400, time) * 0.20
                value += spark * (white - low) * 0.35
                value += sine(58, time) * 0.006

            case 13:
                value = low * 0.13 + brown * 0.14
                let cycle = time.truncatingRemainder(dividingBy: 34)
                if cycle < 6 {
                    let envelope = min(1, cycle / 1.2) * min(1, (6 - cycle) / 2.5)
                    value += (sine(98, time) + sine(147, time) * 0.55) * 0.10 * envelope
                }
                value += sine(220, time) * 0.002

            default:
                value = brown * 0.16 + low * 0.015
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
