import AppKit
import SwiftUI
import CueKit

/// Cue's Touch Bar: sound, light, and the three things a writer reaches for
/// without leaving the page. The bar is built once per window; the controller
/// owns every item so the sheet and the bar stay in step.
@MainActor
final class CueTouchBarController: NSObject, NSTouchBarDelegate {
    static let play = NSTouchBarItem.Identifier("com.abhinavprabhakar.cue.tb.play")
    static let next = NSTouchBarItem.Identifier("com.abhinavprabhakar.cue.tb.next")
    static let lamp = NSTouchBarItem.Identifier("com.abhinavprabhakar.cue.tb.lamp")
    static let note = NSTouchBarItem.Identifier("com.abhinavprabhakar.cue.tb.note")
    static let sticky = NSTouchBarItem.Identifier("com.abhinavprabhakar.cue.tb.sticky")
    static let titlePage = NSTouchBarItem.Identifier("com.abhinavprabhakar.cue.tb.title")
    static let sidebar = NSTouchBarItem.Identifier("com.abhinavprabhakar.cue.tb.sidebar")
    static let sounds = NSTouchBarItem.Identifier("com.abhinavprabhakar.cue.tb.sounds")
    static let lampDay = NSTouchBarItem.Identifier("com.abhinavprabhakar.cue.tb.lamp.day")
    static let lampEvening = NSTouchBarItem.Identifier("com.abhinavprabhakar.cue.tb.lamp.evening")
    static let lampNight = NSTouchBarItem.Identifier("com.abhinavprabhakar.cue.tb.lamp.night")
    static let lampAuto = NSTouchBarItem.Identifier("com.abhinavprabhakar.cue.tb.lamp.auto")

    weak var model: AppModel?
    let touchBar = NSTouchBar()
    private var playItem: NSButtonTouchBarItem?

    init(model: AppModel) {
        self.model = model
        super.init()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [
            Self.play, Self.next, Self.lamp,
            .flexibleSpace,
            Self.note, Self.sticky, Self.titlePage,
            .flexibleSpace,
            Self.sidebar, Self.sounds
        ]
        touchBar.principalItemIdentifier = Self.play
    }

    static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: name) ?? NSImage(size: NSSize(width: 18, height: 18))
    }

    func refresh() {
        guard let model else { return }
        let symbol = model.music.playing ? "pause.fill" : "play.fill"
        playItem?.image = NSImage(systemSymbolName: symbol,
                                  accessibilityDescription: model.music.playing ? "Pause" : "Play")
    }

    func touchBar(_ touchBar: NSTouchBar,
                  makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard let model else { return nil }

        switch identifier {
        case Self.play:
            let item = NSButtonTouchBarItem(
                identifier: identifier,
                image: Self.symbol(model.music.playing ? "pause.fill" : "play.fill"),
                target: self,
                action: #selector(togglePlay)
            )
            playItem = item
            return item

        case Self.next:
            return NSButtonTouchBarItem(
                identifier: identifier,
                image: Self.symbol("forward.end.fill"),
                target: self,
                action: #selector(nextTrack)
            )

        case Self.lamp:
            let item = NSPopoverTouchBarItem(identifier: identifier)
            item.collapsedRepresentationLabel = "Lamp"
            let button = NSButton(title: "Lamp", target: nil, action: nil)
            button.bezelStyle = .rounded
            button.image = NSImage(systemSymbolName: "lamp.desk", accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            item.collapsedRepresentation = button
            item.popoverTouchBar = lampBar()
            return item

        case Self.note:
            return NSButtonTouchBarItem(
                identifier: identifier,
                image: Self.symbol("text.bubble"),
                target: self,
                action: #selector(addNote)
            )

        case Self.sticky:
            return NSButtonTouchBarItem(
                identifier: identifier,
                image: Self.symbol("note.text"),
                target: self,
                action: #selector(addSticky)
            )

        case Self.titlePage:
            return NSButtonTouchBarItem(
                identifier: identifier,
                image: Self.symbol("doc.text"),
                target: self,
                action: #selector(openTitlePage)
            )

        case Self.sidebar:
            return NSButtonTouchBarItem(
                identifier: identifier,
                image: Self.symbol("sidebar.leading"),
                target: self,
                action: #selector(toggleSidebar)
            )

        case Self.sounds:
            let item = NSPopoverTouchBarItem(identifier: identifier)
            item.collapsedRepresentationLabel = "Sounds"
            let button = NSButton(title: "Sounds", target: nil, action: nil)
            button.bezelStyle = .rounded
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            item.collapsedRepresentation = button
            item.popoverTouchBar = soundBar()
            return item

        default:
            return nestedItem(for: identifier)
        }
    }

    /// The nested bars are built separately so their buttons can carry an index
    /// in `tag` without a parallel lookup table.
    private func lampBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [
            Self.lampDay, Self.lampEvening, Self.lampNight, Self.lampAuto
        ]
        return bar
    }

    private func soundBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = soundBarIdentifiers
        return bar
    }

    private var soundBarIdentifiers: [NSTouchBarItem.Identifier] {
        guard let model else { return [] }
        return model.audio.tracks.map { Self.trackIdentifier($0.id) }
    }

    static func trackIdentifier(_ index: Int) -> NSTouchBarItem.Identifier {
        NSTouchBarItem.Identifier("com.abhinavprabhakar.cue.tb.track.\(index)")
    }

    private func nestedItem(for identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard let model else { return nil }

        if identifier == Self.lampDay || identifier == Self.lampEvening
            || identifier == Self.lampNight || identifier == Self.lampAuto {
            let title: String
            let tag: Int
            switch identifier {
            case Self.lampDay: title = "Daylight"; tag = 0
            case Self.lampEvening: title = "Evening"; tag = 1
            case Self.lampNight: title = "Night"; tag = 2
            default: title = "Auto"; tag = 3
            }
            let button = NSButton(title: title, target: self, action: #selector(chooseLamp(_:)))
            button.tag = tag
            button.bezelStyle = .rounded
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = button
            return item
        }

        let raw = identifier.rawValue
        if raw.hasPrefix("com.abhinavprabhakar.cue.tb.track."),
           let index = Int(raw.split(separator: ".").last ?? ""),
           model.audio.tracks.indices.contains(index) {
            let track = model.audio.tracks[index]
            let button = NSButton(title: track.title, target: self, action: #selector(chooseTrack(_:)))
            button.tag = index
            button.bezelStyle = .rounded
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = button
            return item
        }

        return nil
    }

    // MARK: Actions

    @objc private func togglePlay() {
        guard let model else { return }
        model.toggleMusic()
        refresh()
    }

    @objc private func nextTrack() {
        guard let model else { return }
        model.skipMusic(1)
        refresh()
    }

    @objc private func addNote() {
        model?.beginNote()
    }

    @objc private func addSticky() {
        model?.addSticky(at: CGPoint(x: 0.18, y: 0.46), beginEditing: true)
    }

    @objc private func openTitlePage() {
        model?.showTitlePage = true
    }

    @objc private func toggleSidebar() {
        model?.sidebarVisible.toggle()
    }

    @objc private func chooseLamp(_ sender: NSButton) {
        switch sender.tag {
        case 0: model?.lamp.choose(.daylight)
        case 1: model?.lamp.choose(.evening)
        case 2: model?.lamp.choose(.night)
        default: model?.lamp.useAuto()
        }
    }

    @objc private func chooseTrack(_ sender: NSButton) {
        guard let model, model.audio.tracks.indices.contains(sender.tag) else { return }
        model.selectTrack(sender.tag)
        refresh()
    }
}

// MARK: - Installer

/// Attaches the bar to the hosting window. A real Touch Bar shows it; a Mac
/// without one simply ignores the assignment.
struct CueTouchBarInstaller: NSViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> CueTouchBarController {
        CueTouchBarController(model: model)
    }

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.controller = context.coordinator
        return view
    }

    func updateNSView(_ view: HostView, context: Context) {
        view.controller = context.coordinator
        view.install()
        context.coordinator.refresh()
    }

    final class HostView: NSView {
        weak var controller: CueTouchBarController?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            install()
        }

        func install() {
            guard let controller, let window else { return }
            if window.touchBar !== controller.touchBar {
                window.touchBar = controller.touchBar
            }
        }
    }
}
