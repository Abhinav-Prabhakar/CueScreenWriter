import SwiftUI
import AppKit
import CueKit

struct LandingView: View {
    @Environment(SiteModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { reader in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        HeroSection()
                        TrySection()
                        FeaturesSection()
                        QuestionsSection()
                        SiteFooter()
                    }
                }
                .scrollIndicators(.never)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                    model.scrollY = y
                }
                .onScrollGeometryChange(for: CGSize.self) { $0.containerSize } action: { _, _ in
                    // The scroll container is inset by the fixed header *and* the hidden
                    // title-bar safe area, so it is shorter than the site's `vh`. The
                    // geometry reader's size is the content area below the header; adding
                    // the header back in HeroSection restores the true window height.
                    model.viewport = proxy.size
                }
                .onAppear {
                    model.viewport = proxy.size
                    model.reduceMotion = reduceMotion
                    model.lamp.start()
                }
                .onChange(of: proxy.size) { _, size in model.viewport = size }
                .onChange(of: reduceMotion) { _, value in model.reduceMotion = value }
                .environment(\.siteWidth, proxy.size.width)
                .environment(\.siteScrollY, model.scrollY)
                .environment(\.siteViewportHeight, proxy.size.height)
            }
        }
        .background { DeskBackground() }
        .background {
            WindowHeightReader { height in
                if abs(model.windowHeight - height) > 0.5 { model.windowHeight = height }
            }
            .frame(width: 0, height: 0)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HeaderBar()
                .zIndex(10)
        }
        .theme(model.theme)
        .preferredColorScheme(model.theme.colorScheme)
        .background(themeColor)
    }

    private var themeColor: Color { model.theme.desk }
}

/// Reports the window's full height (title bar included). `GeometryReader` sees only the
/// content area below the header and the traffic-light safe area, but the site's `vh`
/// measurements are against the whole window.
private struct WindowHeightReader: NSViewRepresentable {
    var onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    final class Coordinator {
        let onChange: (CGFloat) -> Void
        private weak var window: NSWindow?
        private var observer: NSObjectProtocol?

        init(onChange: @escaping (CGFloat) -> Void) {
            self.onChange = onChange
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        func attach(to view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, let window = view.window else { return }
                self.window = window
                if self.observer == nil {
                    self.observer = NotificationCenter.default.addObserver(
                        forName: NSWindow.didResizeNotification,
                        object: window,
                        queue: .main
                    ) { [weak self] _ in self?.report() }
                }
                self.report()
            }
        }

        private func report() {
            guard let window else { return }
            onChange(window.frame.height)
        }
    }
}

private struct SiteScrollKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct SiteViewportKey: EnvironmentKey {
    static let defaultValue: CGFloat = 900
}

extension EnvironmentValues {
    var siteScrollY: CGFloat {
        get { self[SiteScrollKey.self] }
        set { self[SiteScrollKey.self] = newValue }
    }
    var siteViewportHeight: CGFloat {
        get { self[SiteViewportKey.self] }
        set { self[SiteViewportKey.self] = newValue }
    }
}
