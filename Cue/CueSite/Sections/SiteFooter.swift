import SwiftUI
import AppKit
import CueKit

struct SiteFooter: View {
    @Environment(SiteModel.self) private var model
    @Environment(\.theme) private var theme

    @State private var hovered: String?

    private var width: CGFloat { max(model.viewport.width, 320) }
    private var gutter: CGFloat { SiteMath.gutter(width) }
    private var signOffSize: CGFloat { clamp(width * 0.05, 32, 56) }
    private var wrapsMeta: Bool { width <= 640 }

    var body: some View {
        VStack(spacing: 0) {
            Text(SiteCopy.fadeOut)
                .font(Fonts.script(17, bold: true))
                .foregroundStyle(theme.ink2)
                .siteLine(17, 1.55, script: true)
                .frame(maxWidth: 1120, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 70)

            Text(SiteCopy.signOff)
                .font(Fonts.script(signOffSize))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
                .siteLine(signOffSize, 1.55, script: true)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 80)

            meta
                .frame(maxWidth: 1120)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 60)
        .padding(.bottom, 40)
        .padding(.horizontal, gutter)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var meta: some View {
        let content = Group {
            if wrapsMeta {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        Text(SiteCopy.footerTitle)
                        Spacer(minLength: 8)
                        links
                    }
                    Text(SiteCopy.copyright)
                }
            } else {
                HStack(spacing: 16) {
                    Text(SiteCopy.footerTitle)
                    Spacer(minLength: 16)
                    links
                    Spacer(minLength: 16)
                    Text(SiteCopy.copyright)
                }
            }
        }

        VStack(spacing: 0) {
            Hairline()
            content
                .font(Fonts.ui(13))
                .foregroundStyle(theme.ink2)
                .siteLine(13, 1.55)
                .padding(.top, 20)
        }
    }

    private var links: some View {
        HStack(spacing: 18) {
            link("Support", url: "https://github.com/Abhinav-Prabhakar/CueScreenWriter/issues")
            link("Privacy", url: "https://abhinav-prabhakar.github.io/CueScreenWriter/privacy.html")
        }
    }

    private func link(_ title: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Text(title)
                .foregroundStyle(hovered == title ? theme.ink : theme.ink2)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside {
                hovered = title
            } else if hovered == title {
                hovered = nil
            }
        }
    }
}
