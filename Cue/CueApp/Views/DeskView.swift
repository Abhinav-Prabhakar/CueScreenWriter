import SwiftUI
import AppKit
import CueKit
import UniformTypeIdentifiers

// MARK: - Shared materials

/// The desk: a flat warm surface with the lamp's elliptical pool of light above it.
struct CueDeskBackground: View {
    var glow: Double = 1
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.desk
            // The lamp keeps everything on the desk a touch warm, even away
            // from the pool of light. Keep the wash faint: the reference desk
            // stays a neutral cream at the corners.
            Color(hex: Hex.orange)
                .opacity(theme.colorScheme == .dark ? 0.02 : 0.015)
            CueLampGlow(intensity: glow)
        }
        .ignoresSafeArea()
    }
}

/// The radial lamp light. The reference is `ellipse 62% 58% at 50% -6%`, so the
/// gradient is drawn as a scaled ellipse rather than a circle. The app's lamp is
/// a little broader than the site's: the reference desk stays warm past the
/// paper's right edge, and the pool reaches further down the window.
struct CueLampGlow: View {
    var intensity: Double = 1
    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { context, size in
            let radiusX = size.width * 0.62
            let radiusY = size.height * 0.60
            guard radiusX > 0, radiusY > 0 else { return }

            let centre = CGPoint(x: size.width * 0.5, y: -size.height * 0.06)
            let stops = Gradient(stops: [
                .init(color: Color(hex: Hex.orange, opacity: theme.light * intensity), location: 0),
                .init(color: Color(hex: Hex.orange, opacity: theme.light * 0.68 * intensity), location: 0.32),
                .init(color: Color(hex: Hex.orange, opacity: 0), location: 0.80)
            ])

            context.drawLayer { layer in
                layer.translateBy(x: centre.x, y: centre.y)
                layer.scaleBy(x: 1, y: radiusY / radiusX)
                let outer = radiusX * 1.3
                let circle = Path(ellipseIn: CGRect(x: -outer, y: -outer,
                                                    width: outer * 2, height: outer * 2))
                layer.fill(circle,
                           with: .radialGradient(stops,
                                                 center: .zero,
                                                 startRadius: 0,
                                                 endRadius: outer))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Paper: a sheet, a 6 pt radius, a warm ambient shadow and a tighter contact shadow.
struct CuePaper<Content: View>: View {
    var radius: CGFloat = 6
    var soft: Bool = false
    private let content: () -> Content
    @Environment(\.theme) private var theme

    init(radius: CGFloat = 6, soft: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.radius = radius
        self.soft = soft
        self.content = content
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape
                .fill(theme.paper)
                .shadow(color: theme.shadow, radius: soft ? 16 : 30, x: 0, y: soft ? 8 : 22)
                .shadow(color: theme.shadow.opacity(0.6), radius: soft ? 6 : 12, x: 0, y: soft ? 3 : 8)
            content()
        }
        .overlay {
            shape.strokeBorder(theme.hair, lineWidth: 1)
        }
    }
}

/// Glass: a translucent sheet with a 20 pt blur, a hairline and an inner top highlight.
struct CueGlassBackground: View {
    var radius: CGFloat = 16
    var elevated: Bool = true
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(.ultraThinMaterial)
            .overlay { shape.fill(theme.glass) }
            .overlay {
                // Pull the glass toward the desk so it reads as a warm sheet,
                // not a white system panel, in Daylight and Evening.
                shape.fill(theme.desk.opacity(theme.colorScheme == .dark ? 0.30 : 0.52))
            }
            .overlay {
                shape.fill(Color(hex: Hex.orange).opacity(theme.colorScheme == .dark ? 0.05 : 0.04))
            }
            .overlay { shape.strokeBorder(theme.hair, lineWidth: 1) }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [theme.glassEdge, theme.glassEdge.opacity(0.16), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .clipShape(shape)
            .shadow(color: elevated ? theme.shadow : .clear,
                    radius: elevated ? 20 : 0,
                    x: 0,
                    y: elevated ? 10 : 0)
    }
}

// MARK: - Desk

/// Everything loose on the desk: stickies on the left, pinned photographs on the
/// right, the title-page strip at the bottom left and the music capsule at the
/// bottom right. The page is not part of this layer.
struct DeskView: View {
    var pageRect: CGRect = .zero
    var onTitlePage: () -> Void = {}

    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var editingSticky: CueSticky?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let page = pageRect == .zero ? defaultPageRect(in: size) : pageRect
            let hasLeftDesk = !model.sidebarVisible
            let showsExtras = hasLeftDesk && model.current.deskExtras
            let stickyWidth = max(160, size.width * 0.153)

            ZStack(alignment: .topLeading) {
                // The reference's sidebar-open captures show an empty desk: the
                // loose paper only lives on the desk when the sidebar is away, so
                // it never hides under the glass card.
                if hasLeftDesk {
                    ForEach(model.current.stickies) { sticky in
                        StickyOnDesk(sticky: sticky,
                                     width: stickyWidth,
                                     desk: size,
                                     onMove: { point in model.moveSticky(sticky, to: point) },
                                     onEdit: { editingSticky = sticky },
                                     onDelete: { model.deleteSticky(sticky) })
                    }
                }

                if showsExtras {
                    ForEach(model.current.pins) { pin in
                        PinOnDesk(pin: pin,
                                  image: model.pinImage(pin),
                                  desk: size,
                                  onMove: { point in model.movePin(pin, to: point) },
                                  onDelete: { model.deletePin(pin) })
                    }
                }

                if showsExtras {
                    CueTitlePageStrip(title: model.title,
                                      author: model.current.titlePage.author,
                                      action: onTitlePage)
                        .position(x: 30 + 98, y: size.height - 26 - 31)
                }

                let capsuleWidth = min(size.width - 56, size.width * 0.2575)
                let capsuleHeight: CGFloat = size.width > 1400 ? 56 : 60
                MusicCapsule()
                    .frame(width: capsuleWidth, height: capsuleHeight)
                    .position(x: size.width - size.width * 0.0175 - capsuleWidth / 2,
                              y: size.height - 30 - capsuleHeight / 2)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .animation(reduceMotion ? nil : .cueHover, value: model.sidebarVisible)
        .sheet(item: $editingSticky) { sticky in
            StickyEditorView(sticky: sticky) { updated in
                model.updateSticky(updated)
            } onDelete: {
                model.deleteSticky(sticky)
            }
            .environment(model)
            .theme(model.theme)
            .preferredColorScheme(model.theme.colorScheme)
        }
    }

    private func defaultPageRect(in size: CGSize) -> CGRect {
        let width = size.width * 0.467
        return CGRect(x: (size.width - width) / 2,
                      y: size.height * 0.12 - 16,
                      width: width,
                      height: width * 11 / 8.5)
    }

    private func choosePin() {
        let panel = NSOpenPanel()
        panel.title = "Pin a Photo"
        panel.message = "Choose an image to keep beside the page."
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.addPin(from: url, at: CGPoint(x: 0.10, y: 0.18))
    }

    private func dropPin(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data,
                      let image = NSImage(data: data),
                      let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { return }
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString).png")
                try? png.write(to: temp)
                Task { @MainActor in
                    model.addPin(from: temp, at: CGPoint(x: 0.10, y: 0.18))
                }
            }
            return true
        }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                model.addPin(from: url, at: CGPoint(x: 0.10, y: 0.18))
            }
        }
        return true
    }
}

// MARK: - Desk objects

private struct StickyOnDesk: View {
    let sticky: CueSticky
    let width: CGFloat
    let desk: CGSize
    let onMove: (CGPoint) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var drag: CGSize = .zero

    private var height: CGFloat {
        width * (sticky.footnote == nil ? 0.84 : 0.894)
    }

    var body: some View {
        CueStickyNote(lines: sticky.lines,
                      footnote: sticky.footnote,
                      strike: sticky.strike)
            .frame(width: width, height: height)
            .offset(drag)
            .position(x: sticky.x * desk.width, y: sticky.y * desk.height)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in drag = value.translation }
                    .onEnded { value in
                        let point = CGPoint(
                            x: (sticky.x * desk.width + value.translation.width) / desk.width,
                            y: (sticky.y * desk.height + value.translation.height) / desk.height
                        )
                        onMove(point)
                        drag = .zero
                    }
            )
            .onTapGesture(count: 2, perform: onEdit)
            .contextMenu {
                Button("Edit Sticky…") { onEdit() }
                Button("Delete Sticky", role: .destructive) { onDelete() }
            }
            .help("Drag to move. Double-click to edit.")
    }
}

private struct PinOnDesk: View {
    let pin: CuePin
    let image: NSImage?
    let desk: CGSize
    let onMove: (CGPoint) -> Void
    let onDelete: () -> Void

    @State private var drag: CGSize = .zero

    private var kind: CuePinnedPhoto.Kind {
        if case .fog = pin.artwork { return .fog }
        return .dusk
    }

    var body: some View {
        CuePinnedPhoto(kind: kind, image: image, rotation: pin.rotation)
            .frame(width: max(56, pin.width * desk.width),
                   height: max(64, pin.height * desk.height))
            .offset(drag)
            .position(x: pin.x * desk.width, y: pin.y * desk.height)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in drag = value.translation }
                    .onEnded { value in
                        let point = CGPoint(
                            x: (pin.x * desk.width + value.translation.width) / desk.width,
                            y: (pin.y * desk.height + value.translation.height) / desk.height
                        )
                        onMove(point)
                        drag = .zero
                    }
            )
            .contextMenu {
                Button("Remove Photo", role: .destructive) { onDelete() }
            }
            .help("Drag to move.")
    }
}
