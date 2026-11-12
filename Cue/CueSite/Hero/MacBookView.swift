import SwiftUI
import CueKit

/// The hero's MacBook, drawn rather than photographed. The lid, bezel, notch and aluminium
/// base scale as one object with the illustration's width.
struct MacBookView: View {
    @Environment(\.theme) private var theme

    let width: CGFloat
    let shellLamp: Lamp
    let isActive: Bool

    private var metrics: MacBookMetrics { MacBookMetrics(width: width) }
    private var totalHeight: CGFloat { width * 590 / 882 }
    private var baseHeight: CGFloat { max(10, width * 20 / 882) }
    private var lidHeight: CGFloat { totalHeight - baseHeight }
    private var inset: CGFloat { metrics.screenInset }
    private var screenWidth: CGFloat { metrics.screenWidth }
    private var screenHeight: CGFloat { min(metrics.screenHeight, max(0, lidHeight - inset)) }
    private var night: Bool { shellLamp == .night }

    private var lidShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: width * 0.021,
            bottomLeadingRadius: width * 0.006,
            bottomTrailingRadius: width * 0.006,
            topTrailingRadius: width * 0.021,
            style: .continuous
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            lid
            base
        }
        .compositingGroup()
        .shadow(color: theme.shadow, radius: 50, x: 0, y: 40)
        .frame(width: width, height: totalHeight)
    }

    private var lid: some View {
        ZStack(alignment: .top) {
            lidShape.fill(Color(hex: 0x0B0B0C))

            HeroMock(screenWidth: screenWidth, isActive: isActive)
                .frame(width: screenWidth, height: screenHeight)
                .background(theme.desk)
                .clipShape(RoundedRectangle(cornerRadius: width * 0.0065, style: .continuous))
                .padding(.top, inset)

            UnevenRoundedRectangle(
                bottomLeadingRadius: width * 0.0075,
                bottomTrailingRadius: width * 0.0075,
                style: .continuous
            )
            .fill(Color(hex: 0x0B0B0C))
            .frame(width: metrics.notchWidth, height: metrics.notchHeight)
            .offset(y: inset)

            lidShape
                .strokeBorder(Color(hex: 0x3A3A3E), lineWidth: 1.5)

            lidShape
                .stroke(night ? Color(hex: 0x4A4A4E) : Color(hex: 0x9A9BA0), lineWidth: 1)
        }
        .frame(width: width, height: lidHeight)
    }

    private var base: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: 2,
                bottomLeadingRadius: width * 14 / 882,
                bottomTrailingRadius: width * 14 / 882,
                topTrailingRadius: 2,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    stops: night
                        ? [.init(color: Color(hex: 0x4A4A4E), location: 0),
                           .init(color: Color(hex: 0x2C2C30), location: 0.55),
                           .init(color: Color(hex: 0x1A1A1C), location: 1)]
                        : [.init(color: Color(hex: 0xE6E7E9), location: 0),
                           .init(color: Color(hex: 0xC4C5C9), location: 0.55),
                           .init(color: Color(hex: 0x9C9DA2), location: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: width * 1.12, height: baseHeight)

            UnevenRoundedRectangle(
                bottomLeadingRadius: width * 8 / 882,
                bottomTrailingRadius: width * 8 / 882,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: night
                        ? [Color(hex: 0x232326), Color(hex: 0x3A3A3E)]
                        : [Color(hex: 0xB5B6BA), Color(hex: 0xD4D5D8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: width * 1.12 * 0.15, height: baseHeight * 0.42)
        }
        .frame(width: width, height: baseHeight)
    }
}
