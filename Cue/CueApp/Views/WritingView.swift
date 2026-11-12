import SwiftUI
import AppKit
import CueKit

/// The writing screen: desk, lamp light, one sheet of paper, a glass sidebar and
/// the loose objects around the page. The editor scrolls inside the page; the
/// chrome never scrolls.
struct WritingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTitlePage = false

    var body: some View {
        @Bindable var bindable = model

        GeometryReader { proxy in
            let size = proxy.size
            let pageWidth = size.width * 0.467
            let pageHeight = pageWidth * 11 / 8.5
            // The sheet sits just below the toolbar band in every reference
            // capture; the scrolled captures show it higher only because the
            // document has been scrolled, not because the layout changes.
            // Fitted from 1200×750 (74) and 1600×1000 (104).
            let pageTop = size.height * 0.12 - 16
            let pageRect = CGRect(
                x: (size.width - pageWidth) / 2,
                y: pageTop,
                width: pageWidth,
                height: pageHeight
            )
            // The sidebar is a column with a practical floor: it does not shrink
            // to a rail as the window narrows (the page is what gives).
            let sidebarWidth = max(310, size.width * 0.2025)
            let sidebarHeight = max(0, size.height - 60)

            ZStack(alignment: .topLeading) {
                CueDeskBackground(glow: model.lit ? 1 : 0)
                    .animation(reduceMotion ? .linear(duration: 0.01) : .cueLamp,
                               value: model.lit)

                // The desk itself takes right-clicks and dropped files. It sits
                // *under* the page, so the editor's own menu wins over the text.
                Color.clear
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Add Sticky Note") {
                            model.addSticky(at: CGPoint(x: 0.15, y: 0.52))
                        }
                        Button("Pin a Photo…") { model.pinPhotoPanel() }
                        Divider()
                        Button("Add Note…") { model.beginNote() }
                        Button("Open Title Page…") { showTitlePage = true }
                    }
                    .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
                        model.dropPin(providers)
                    }

                paper(script: $bindable.currentScript, pageRect: pageRect)

                DeskView(pageRect: pageRect) {
                    showTitlePage = true
                }

                if model.sidebarVisible {
                    SidebarView {
                        showTitlePage = true
                    }
                    .frame(width: sidebarWidth, height: sidebarHeight)
                    .position(x: size.width * 0.008125 + sidebarWidth / 2,
                              y: 45 + sidebarHeight / 2)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5),
                       value: model.sidebarVisible)
        }
        .sheet(isPresented: $showTitlePage) {
            TitlePageView()
                .environment(model)
                .theme(model.theme)
                .preferredColorScheme(model.theme.colorScheme)
        }
        .sheet(item: $bindable.noteDraft) { draft in
            NoteComposerView(draft: draft)
                .environment(model)
                .theme(model.theme)
                .preferredColorScheme(model.theme.colorScheme)
        }
        .sheet(isPresented: $bindable.showHelp) {
            HelpView()
                .environment(model)
                .theme(model.theme)
                .preferredColorScheme(model.theme.colorScheme)
        }
        .onChange(of: model.currentScript) { _, _ in
            model.scriptChanged()
        }
    }

    private func paper(script: Binding<Script>, pageRect: CGRect) -> some View {
        let metrics = PageMetrics(pageWidth: pageRect.width)
        return CuePaper(radius: 6) {
            ScriptEditorView(
                script: script,
                theme: model.theme,
                sceneOffset: model.current.sceneNumberOffset,
                pageOffset: model.current.pageNumberOffset,
                declaredPages: model.current.declaredPages,
                scrollRequest: model.scrollRequest,
                onPosition: { position in
                    model.position = position
                },
                onSelection: { selected, line, paragraph in
                    model.updateSelection(text: selected, line: line, paragraph: paragraph)
                },
                onRequestNote: {
                    model.beginNote()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, metrics.topPadding)
            .padding(.bottom, metrics.bottomPadding)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .overlay(alignment: .topTrailing) {
            // An excerpt that starts on a later page has no in-flow page break,
            // so the furniture cannot reach up into the top margin. Draw the
            // current page number on the sheet itself.
            if model.current.pageNumberOffset > 0, model.position.page > 1 {
                Text("\(model.position.page).")
                    .font(Fonts.script(metrics.inch * (12.0 / 72.0) * 0.85))
                    .foregroundStyle(theme.ink2)
                    .padding(.top, metrics.inch * 0.5)
                    .padding(.trailing, pageRect.width * 0.12)
            }
        }
        .frame(width: pageRect.width, height: pageRect.height)
        .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
            model.dropPin(providers)
        }
        .position(x: pageRect.midX, y: pageRect.midY)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Page, \(model.title)")
    }
}
