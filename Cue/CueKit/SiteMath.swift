import SwiftUI

public enum SiteMath {
    public static let contentMax: CGFloat = 1120
    public static let headerHeight: CGFloat = 67
    public static let demoMaxWidth: CGFloat = 780
    public static let featureGapMax: CGFloat = 140
    public static let columnGapMax: CGFloat = 64

    public static func gutter(_ width: CGFloat) -> CGFloat { clamp(width * 0.04, 16, 40) }
    public static func content(_ width: CGFloat) -> CGFloat { min(contentMax, width - gutter(width) * 2) }
    public static func isSingleColumn(_ width: CGFloat) -> Bool { width <= 860 }
    public static func isPhone(_ width: CGFloat) -> Bool { width <= 640 }

    public static func featureGap(_ width: CGFloat) -> CGFloat { clamp(width * 0.12, 80, 140) }
    public static func columnGap(_ width: CGFloat) -> CGFloat { clamp(width * 0.05, 28, 64) }
    public static func heroRhythm(_ height: CGFloat) -> CGFloat { clamp(height * 0.09, 56, 88) }

    public static func h1(_ width: CGFloat) -> CGFloat { clamp(width * 0.06, 44, 72) }
    public static func h2(_ width: CGFloat) -> CGFloat { clamp(width * 0.04, 28, 40) }
    public static func lede(_ width: CGFloat) -> CGFloat { clamp(width * 0.016, 17, 19) }
    public static func promise(_ width: CGFloat) -> CGFloat { clamp(width * 0.034, 24, 40) }
    public static func scriptPromise(_ width: CGFloat) -> CGFloat { promise(width) }

    /// Hero MacBook width: min(1080, width/1.12, (vh - 300) * 1.47).
    public static func macBookWidth(_ width: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        // The laptop is a supporting object, not the whole hero. Cap it so the
        // headline still lands above the fold on a wide desktop window.
        min(1080, width / 1.12, 460, max(320, (viewportHeight - 300) * 1.47))
    }

    /// Demo page height. The original resolves 129cqw against the viewport because
    /// `.page` is the query container; reproduce that quirk for parity.
    public static func demoPageHeight(pageWidth: CGFloat, viewportWidth: CGFloat) -> CGFloat {
        if pageWidth >= 780 { return 1000 }
        return max(503, min(1000, viewportWidth * 1.29))
    }

    public static func pageWidth(container: CGFloat) -> CGFloat {
        min(demoMaxWidth, container)
    }
}

public struct PageMetrics: Sendable {
    public let pageWidth: CGFloat

    public init(pageWidth: CGFloat) { self.pageWidth = pageWidth }

    public var inch: CGFloat { pageWidth / 8.5 }
    public var scriptSize: CGFloat { max(12.5, inch * (12.0 / 72.0)) }
    public var line: CGFloat { scriptSize }
    public var topPadding: CGFloat { inch * 0.975 }
    public var bottomPadding: CGFloat { inch * 1.0 }
    public var characterIndent: CGFloat { pageWidth * 0.435 }
    public var dialogueIndent: CGFloat { pageWidth * 0.294 }
    public var parenIndent: CGFloat { pageWidth * 0.365 }
    public var defaultIndent: CGFloat { pageWidth * 0.1765 }
    public var railIndent: CGFloat { pageWidth * 0.1447 }
    public var sceneNoIndent: CGFloat { pageWidth * 0.10 }
    public var defaultRight: CGFloat { pageWidth * 0.1176 }
}

public struct MacBookMetrics: Sendable {
    public let width: CGFloat
    public init(width: CGFloat) { self.width = width }

    public var height: CGFloat { width * 590 / 882 }
    public var lidHeight: CGFloat { width * 552 / 882 }
    public var lidRadius: CGFloat { width * 0.021 }
    public var screenInset: CGFloat { width * 16.8 / 882 }
    public var screenRadius: CGFloat { width * 0.0065 }
    public var baseHeight: CGFloat { width * 38 / 882 }
    public var baseRadius: CGFloat { width * 0.0075 }
    public var notchWidth: CGFloat { width * 118 / 882 }
    public var notchHeight: CGFloat { width * 10 / 882 }
    public var screenWidth: CGFloat { width - screenInset * 2 }
    public var screenHeight: CGFloat { screenWidth * 900 / 1440 }
}

// MARK: - Container width environment

private struct SiteWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1440
}

public extension EnvironmentValues {
    var siteWidth: CGFloat {
        get { self[SiteWidthKey.self] }
        set { self[SiteWidthKey.self] = newValue }
    }
}

public extension View {
    func siteWidth(_ width: CGFloat) -> some View { environment(\.siteWidth, width) }
}

/// Reports its own width into an environment value and a binding.
public struct WidthReader<Content: View>: View {
    @Binding private var width: CGFloat
    private let content: Content

    public init(width: Binding<CGFloat>, @ViewBuilder content: () -> Content) {
        _width = width
        self.content = content()
    }

    public var body: some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
