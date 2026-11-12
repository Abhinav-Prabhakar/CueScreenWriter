import SwiftUI
import CueKit

@main
struct CueSiteApp: App {
    @State private var model = SiteModel()

    init() {
        Fonts.register()
    }

    var body: some Scene {
        WindowGroup("Cue · Screenwriting for Mac") {
            LandingView()
                .environment(model)
                .frame(minWidth: 390, minHeight: 600)
                .preferredColorScheme(model.theme.colorScheme)
        }
        .defaultSize(width: 1440, height: 928)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after: .toolbar) {
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
        }
    }
}

@MainActor
@Observable
final class SiteModel {
    let lamp = LampController(persist: false)

    var lit = true
    var scrollY: CGFloat = 0
    var viewport = CGSize(width: 1440, height: 900)
    var sectionTops: [String: CGFloat] = [:]
    var typedProgress: CGFloat = 1
    var reduceMotion = false
    /// Full window height. The scroll container is inset by the header and the
    /// title-bar safe area, but the site measures `vh` against the whole window.
    var windowHeight: CGFloat = 0

    var theme: Theme { Theme.of(lamp.lamp) }

    var width: CGFloat { viewport.width }

    init() {
        lamp.start()
    }

    func toggleLit() {
        withAnimation(reduceMotion ? .linear(duration: 0.01) : .cueLamp) {
            lit.toggle()
        }
    }

    func setLit(_ on: Bool) {
        guard lit != on else { return }
        toggleLit()
    }

    func register(_ id: String, top: CGFloat) {
        sectionTops[id] = top
    }

    func scroll(to id: String, proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .cue) {
            proxy.scrollTo(id, anchor: .top)
        }
    }

    var macBookWidth: CGFloat {
        SiteMath.macBookWidth(width, viewportHeight: max(windowHeight, viewport.height + SiteMath.headerHeight))
    }
}
