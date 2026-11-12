import SwiftUI
import AppKit
import CueKit

// MARK: - Section

struct FeaturesSection: View {
    @Environment(SiteModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.siteViewportHeight) private var viewportHeight

    private var width: CGFloat { max(model.viewport.width, 320) }
    private var gutter: CGFloat { SiteMath.gutter(width) }
    private var contentWidth: CGFloat { SiteMath.content(width) }
    private var gap: CGFloat { SiteMath.featureGap(width) }
    private var columnGap: CGFloat { SiteMath.columnGap(width) }
    private var stacked: Bool { SiteMath.isSingleColumn(width) }
    private var h2Size: CGFloat { SiteMath.h2(width) }

    var body: some View {
        VStack(spacing: gap) {
            intro
            DeskSettle()
            ForEach(SiteCopy.features) { feature in
                FeatureBlock(
                    feature: feature,
                    contentWidth: contentWidth,
                    h2Size: h2Size,
                    columnGap: columnGap,
                    stacked: stacked
                )
            }
        }
        .padding(.vertical, 40)
        .frame(maxWidth: SiteMath.contentMax)
        .padding(.horizontal, gutter)
        .frame(maxWidth: .infinity)
        .modifier(SiteAnchor(id: "features"))
    }

    private var intro: some View {
        VStack(spacing: 0) {
            Slug(text: SiteCopy.featuresSlug)
                .siteLine(14, 1.55, script: true)
                .padding(.bottom, 14)

            Text(SiteCopy.featuresTitle)
                .font(Fonts.script(h2Size))
                .tracking(-h2Size * 0.01)
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)

            Text(SiteCopy.featuresNote)
                .font(Fonts.ui(17))
                .foregroundStyle(theme.ink2)
                .multilineTextAlignment(.center)
                .siteLines(17, 1.55)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - One feature

private struct FeatureBlock: View {
    @Environment(\.theme) private var theme

    let feature: SiteCopy.Feature
    let contentWidth: CGFloat
    let h2Size: CGFloat
    let columnGap: CGFloat
    let stacked: Bool

    var body: some View {
        Group {
            if feature.id == "full-ui" {
                FullUIStage()
            } else if feature.id == "extras" {
                ExtrasList()
            } else if feature.wide {
                wide
            } else if stacked {
                stackedLayout
            } else {
                columns
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Layouts

    private var wide: some View {
        VStack(spacing: columnGap) {
            copy
                .frame(maxWidth: 612)
                .frame(maxWidth: .infinity)
            media
        }
    }

    private var stackedLayout: some View {
        VStack(spacing: feature.id == "sticky" ? 64 : columnGap) {
            copy
            media
                .frame(maxWidth: .infinity)
        }
    }

    private var columns: some View {
        FractionalColumns(
            fractions: feature.flipped ? [7, 5] : [5, 7],
            spacing: columnGap
        ) {
            if feature.flipped {
                media
                copy
            } else {
                copy
                media
            }
        }
    }

    // MARK: Text

    private var copy: some View {
        VStack(alignment: feature.wide ? .center : .leading, spacing: 0) {
            Slug(text: feature.slug)
                .siteLine(14, 1.55, script: true)
                .padding(.bottom, 20)

            FeatureHeading(
                title: feature.title,
                size: h2Size,
                aligned: feature.wide ? .center : .leading,
                balanced: feature.wide || !stacked
            )
            .padding(.bottom, 24)

            Text(feature.body)
                .font(Fonts.ui(17))
                .foregroundStyle(theme.ink2)
                .multilineTextAlignment(feature.wide ? .center : .leading)
                .siteLines(17, 1.7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: feature.wide ? .center : .leading)
    }

    // MARK: Media

    @ViewBuilder
    private var media: some View {
        switch feature.id {
        case "lamp":
            LampShots()
        case "lamp-off":
            LampOffSwitch()
                .frame(maxWidth: .infinity)
        case "music":
            MusicStage()
        case "title":
            TitleStage()
        case "pins":
            PinsStage()
        case "sticky":
            StickyStack()
        case "snippet":
            SnippetStage()
        case "panel":
            PanelStage()
        default:
            EmptyView()
        }
    }
}

// MARK: - Heading

/// The site's h2 uses `text-wrap: balance`, which SwiftUI lacks. On the two-column layout
/// these are the balanced breaks the reference renders; at ≤860 the single column is wide
/// enough to let SwiftUI wrap naturally.
struct FeatureHeading: View {
    @Environment(\.theme) private var theme

    let title: String
    let size: CGFloat
    let aligned: HorizontalAlignment
    let balanced: Bool

    private static let lines: [String: [String]] = [
        "A lamp that keeps your hours.": ["A lamp that", "keeps your hours."],
        "Or switch it off.": ["Or switch it off."],
        "Your music, beside the page.": ["Your music,", "beside the page."],
        "Your title, the way you see it.": ["Your title, the", "way you see it."],
        "Pin up what you’re seeing.": ["Pin up what", "you’re seeing."],
        "Room for the mess.": ["Room for the mess."],
        "Formatting that stays out of your way.": ["Formatting", "that stays out", "of your way."],
        "Every scene and character, a glance away.": ["Every scene", "and character,", "a glance away."]
    ]

    var body: some View {
        Group {
            if balanced, let lines = Self.lines[title] {
                VStack(alignment: aligned, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(Fonts.script(size))
                            .tracking(-size * 0.01)
                            .foregroundStyle(theme.ink)
                    }
                }
            } else {
                Text(title)
                    .font(Fonts.script(size))
                    .tracking(-size * 0.01)
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(aligned == .center ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Layout

/// `grid-template-columns: minmax(0, 5fr) minmax(0, 7fr)` with centred items.
struct FractionalColumns: Layout {
    var fractions: [CGFloat]
    var spacing: CGFloat

    private func widths(_ total: CGFloat) -> [CGFloat] {
        let available = max(0, total - spacing * CGFloat(fractions.count - 1))
        let sum = fractions.reduce(0, +)
        return fractions.map { available * $0 / max(1, sum) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let columns = widths(width)
        let heights = subviews.enumerated().map { index, subview in
            subview.sizeThatFits(
                ProposedViewSize(width: columns[min(index, columns.count - 1)], height: nil)
            ).height
        }
        return CGSize(width: width, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = widths(bounds.width)
        var x = bounds.minX

        for (index, subview) in subviews.enumerated() {
            let column = columns[min(index, columns.count - 1)]
            let height = subview.sizeThatFits(ProposedViewSize(width: column, height: nil)).height
            subview.place(
                at: CGPoint(x: x, y: bounds.midY - height / 2),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: column, height: height)
            )
            x += column + spacing
        }
    }
}

// MARK: - Section anchors

/// Registers a section's document top for the header's anchor navigation.
struct SiteAnchor: ViewModifier {
    @Environment(SiteModel.self) private var model

    let id: String

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.frame(in: .global).minY
                    } action: { top in
                        model.register(
                            id,
                            top: top - SiteMath.headerHeight + model.scrollY
                        )
                    }
            }
        }
    }
}
