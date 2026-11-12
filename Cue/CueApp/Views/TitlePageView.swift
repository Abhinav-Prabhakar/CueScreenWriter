import SwiftUI
import AppKit
import CueKit
import UniformTypeIdentifiers

/// The title page: a standard screenplay opening sheet, editable in place. The
/// preview is the real page; the right-hand column edits the title, credit,
/// author, contact block and draft date. A title graphic can replace the typed
/// title, on the page, the shelf cover and the exported PDF.
struct TitlePageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var title = ""
    @State private var page = CueTitlePage()
    @State private var graphic: NSImage?
    @State private var loaded = false

    var body: some View {
        ZStack {
            CueDeskBackground(glow: 0.8)

            HStack(spacing: 26) {
                GeometryReader { proxy in
                    let size = proxy.size
                    let pageWidth = min(430, min(size.width - 30, (size.height - 20) * 8.5 / 11))
                    let pageHeight = pageWidth * 11 / 8.5

                    CuePaper(radius: 6) {
                        titlePageBody(width: pageWidth)
                    }
                    .frame(width: pageWidth, height: pageHeight)
                    .position(x: size.width / 2, y: size.height / 2)
                }
                .frame(minWidth: 430)

                inspector
                    .frame(width: 300)
            }
            .padding(.horizontal, 30)
            .padding(.top, 56)
            .padding(.bottom, 28)

            VStack {
                HStack {
                    Text("Title page")
                        .font(Fonts.ui(12, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(theme.ink2)
                    Spacer()
                    Button("Done") {
                        model.updateTitlePage(page)
                        if title != model.title { model.setTitle(title) }
                        model.flush()
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(Fonts.ui(13, weight: .medium))
                    .foregroundStyle(theme.ink)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close the title page")
                }
                .padding(.horizontal, 30)
                .padding(.top, 22)
                Spacer()
            }
        }
        .frame(minWidth: 860, minHeight: 640)
        .animation(reduceMotion ? nil : .cue, value: title)
        .onAppear(perform: load)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Title page for \(title)")
    }

    private func load() {
        guard !loaded else { return }
        title = model.title
        page = model.current.titlePage
        graphic = model.titleGraphic()
        loaded = true
    }

    // MARK: - Inspector

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("The sheet")
                .font(Fonts.ui(18, weight: .semibold))
                .foregroundStyle(theme.ink)
            Text("Everything here prints with the script.")
                .font(Fonts.ui(12.5))
                .foregroundStyle(theme.ink2)
                .padding(.top, 3)
                .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    field("TITLE") {
                        TextField("Title", text: $title)
                            .textFieldStyle(.plain)
                            .font(Fonts.script(15, bold: true))
                    }

                    field("CREDIT") {
                        TextField("written by", text: $page.credit)
                            .textFieldStyle(.plain)
                            .font(Fonts.script(13))
                    }

                    field("AUTHOR") {
                        TextField("A. Writer", text: $page.author)
                            .textFieldStyle(.plain)
                            .font(Fonts.ui(13))
                    }

                    field("CONTACT") {
                        TextEditor(text: $page.contact)
                            .font(Fonts.ui(12.5))
                            .scrollContentBackground(.hidden)
                            .frame(height: 88)
                    }

                    field("DRAFT DATE") {
                        TextField("Draft date: 3 Nov 2026", text: $page.draftDate)
                            .textFieldStyle(.plain)
                            .font(Fonts.ui(12.5))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("TITLE GRAPHIC")
                            .font(Fonts.ui(9.5, weight: .medium))
                            .tracking(1.1)
                            .foregroundStyle(theme.ink2)

                        if graphic != nil {
                            HStack(spacing: 10) {
                                Button("Replace…") { chooseGraphic() }
                                    .buttonStyle(.plain)
                                    .font(Fonts.ui(12.5, weight: .medium))
                                    .foregroundStyle(theme.ink)
                                Button("Remove") {
                                    model.clearTitleGraphic()
                                    graphic = nil
                                }
                                .buttonStyle(.plain)
                                .font(Fonts.ui(12.5))
                                .foregroundStyle(theme.ink2)
                            }
                        } else {
                            Button {
                                chooseGraphic()
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 11))
                                    Text("Choose an image…")
                                        .font(Fonts.ui(12.5))
                                }
                                .foregroundStyle(theme.ink2)
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(theme.hair, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 10)
            }
            .scrollIndicators(.hidden)

            Text("Saved automatically")
                .font(Fonts.ui(11))
                .foregroundStyle(theme.ink2.opacity(0.7))
                .padding(.top, 10)
        }
        .padding(18)
        .background {
            CueGlassBackground(radius: 14, elevated: true)
        }
        .onChange(of: page) { _, value in
            guard loaded else { return }
            model.updateTitlePage(value)
        }
        .onChange(of: title) { _, value in
            guard loaded, value != model.title else { return }
            model.setTitle(value)
        }
    }

    private func field<Content: View>(_ label: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Fonts.ui(9.5, weight: .medium))
                .tracking(1.1)
                .foregroundStyle(theme.ink2)
            content()
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(theme.paper.opacity(theme.colorScheme == .dark ? 0.22 : 0.48))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(theme.hair, lineWidth: 1)
                }
        }
    }

    private func chooseGraphic() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Title Graphic"
        panel.message = "A PNG or JPEG logo for the title page and library cover."
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.setTitleGraphic(url)
        graphic = model.titleGraphic()
    }

    // MARK: - Page

    private func titlePageBody(width: CGFloat) -> some View {
        let inch = width / 8.5
        let base = max(8.4, inch * (12.0 / 72.0))

        return ZStack(alignment: .topLeading) {
            theme.paper

            VStack(spacing: 0) {
                if let graphic {
                    Image(nsImage: graphic)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(maxWidth: inch * 4.6, maxHeight: inch * 1.35)
                        .padding(.bottom, inch * 0.18)
                } else {
                    Text(title.uppercased())
                        .font(Fonts.script(base * 1.62, bold: true))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }

                Text(page.credit)
                    .font(Fonts.script(base))
                    .foregroundStyle(theme.ink2)
                    .padding(.top, inch * 0.88)

                Text(page.author.uppercased())
                    .font(Fonts.script(base))
                    .padding(.top, inch * 0.42)
            }
            .foregroundStyle(theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, inch)
            .padding(.top, inch * 3.25)

            HStack(alignment: .bottom) {
                Text(page.contact)
                Spacer(minLength: inch * 0.5)
                Text(page.draftDate)
            }
            .font(Fonts.script(base * 0.95))
            .foregroundStyle(theme.ink)
            .lineSpacing(2)
            .padding(.horizontal, inch)
            .padding(.bottom, inch * 0.95)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). Written by \(page.author). \(page.contact.replacingOccurrences(of: "\n", with: ", ")). \(page.draftDate).")
    }
}
