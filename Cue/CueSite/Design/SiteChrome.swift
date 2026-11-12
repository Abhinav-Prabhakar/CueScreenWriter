import SwiftUI
import AppKit
import CueKit

// MARK: - Logo

struct CueLogo: View {
    @Environment(\.theme) private var theme
    var height: CGFloat = 26

    var body: some View {
        if let image = Assets.image("logo", ext: "png") {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(696.0 / 261.0, contentMode: .fit)
                .frame(height: height)
                .foregroundStyle(theme.ink)
                .accessibilityLabel("Cue")
        } else {
            Text("CUE")
                .font(Fonts.ui(height, weight: .bold))
                .foregroundStyle(theme.ink)
        }
    }
}

// MARK: - Layout

struct SiteSection<Content: View>: View {
    var maxWidth: CGFloat = 1120
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

struct Slug: View {
    @Environment(\.theme) private var theme
    let text: String
    var size: CGFloat = 14

    var body: some View {
        Text(text)
            .font(Fonts.script(size, bold: true))
            .tracking(size * 0.02)
            .textCase(.uppercase)
            .foregroundStyle(theme.ink2)
    }
}

struct SectionHead: View {
    @Environment(\.theme) private var theme
    let slug: String
    let title: String
    var note: String?
    var align: HorizontalAlignment = .leading
    var titleSize: CGFloat = 40

    var body: some View {
        VStack(alignment: align, spacing: 0) {
            Slug(text: slug)
                .padding(.bottom, 20)
            Text(title)
                .font(Fonts.ui(titleSize, weight: .medium))
                .tracking(-titleSize * 0.018)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note)
                    .font(Fonts.ui(15))
                    .foregroundStyle(theme.ink2)
                    .lineSpacing(15 * 0.55)
                    .padding(.top, 16)
                    .frame(maxWidth: 34 * 17, alignment: .leading)
            }
        }
    }
}

// MARK: - Controls

struct TextLink: View {
    @Environment(\.theme) private var theme
    let title: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Fonts.ui(15, weight: .medium))
                .foregroundStyle(theme.ink)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.hair).frame(height: 1).offset(y: 3)
                }
        }
        .buttonStyle(.plain)
    }
}

struct AppStoreButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(SiteCopy.downloadURL)
        } label: {
            HStack(spacing: 9) {
                Circle().fill(theme.desk).frame(width: 7, height: 7)
                Text(SiteCopy.download)
                    .font(Fonts.ui(15, weight: .medium))
            }
            .foregroundStyle(theme.desk)
            .padding(.horizontal, 20)
            .frame(height: 56)
            .background(theme.ink, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Download Cue now from GitHub Releases")
    }
}

struct Hairline: View {
    @Environment(\.theme) private var theme
    var body: some View { Rectangle().fill(theme.hair).frame(height: 1) }
}

struct GlassPanel<Content: View>: View {
    @Environment(\.theme) private var theme
    var radius: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(.ultraThinMaterial)
            .background(theme.glass)
            .overlay(alignment: .top) {
                Rectangle().fill(theme.glassEdge).frame(height: 1)
            }
            .clipShape(.rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius).strokeBorder(theme.hair, lineWidth: 1)
            }
    }
}

struct SegmentedLamp: View {
    @Environment(\.theme) private var theme
    @Environment(SiteModel.self) private var model
    var options: [Lamp] = Lamp.allCases

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { lamp in
                Button {
                    withAnimation(model.reduceMotion ? .linear(duration: 0.01) : .cue) {
                        model.lamp.choose(lamp)
                    }
                } label: {
                    Text(lamp.title)
                        .font(Fonts.ui(14, weight: .medium))
                        .foregroundStyle(model.lamp.lamp == lamp ? theme.desk : theme.ink2)
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background {
                            if model.lamp.lamp == lamp {
                                Capsule().fill(theme.ink)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.lamp.lamp == lamp ? .isSelected : [])
            }
        }
        .padding(3)
        .background(theme.glass, in: .capsule)
        .overlay { Capsule().strokeBorder(theme.hair, lineWidth: 1) }
    }
}

// MARK: - Background

struct LampGlow: View {
    let theme: Theme
    var intensity: Double = 1

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.5, y: -size.height * 0.06)
            let rx = size.width * 0.62
            let ry = size.height * 0.58
            context.translateBy(x: center.x, y: center.y)
            context.scaleBy(x: rx, y: ry)
            let gradient = Gradient(stops: [
                .init(color: Color(hex: Hex.orange, opacity: theme.light * intensity), location: 0),
                .init(color: Color(hex: Hex.orange, opacity: theme.light * 0.45 * intensity), location: 0.38),
                .init(color: .clear, location: 0.72)
            ])
            context.fill(
                Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: 1)
            )
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

struct GrainLayer: View {
    static let image: NSImage? = {
        let size = 160
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) & 0xFFFF) / 65535.0
        }
        for y in 0..<size {
            for x in 0..<size {
                let v = random()
                rep.setColor(NSColor(white: v, alpha: 0.55), atX: x, y: y)
            }
        }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        return image
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable(resizingMode: .tile)
                .opacity(0.07)
                .blendMode(.overlay)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
    }
}

struct DeskBackground: View {
    @Environment(\.theme) private var theme
    @Environment(SiteModel.self) private var model

    var body: some View {
        theme.desk
            .overlay {
                if model.lit {
                    LampGlow(theme: theme)
                }
            }
            .overlay { GrainLayer() }
            .ignoresSafeArea()
    }
}

// MARK: - Glass button

struct GlassButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(theme.glass, in: .capsule)
            .overlay { Capsule().strokeBorder(theme.hair, lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension View {
    func hairline() -> some View { overlay(alignment: .bottom) { Hairline() } }
}
