import SwiftUI
import AppKit
import CueKit

struct QuestionsSection: View {
    @Environment(SiteModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var systemReduce

    /// `nil` means every answer is closed. The site starts with item 0 open; this build keeps
    /// the first click honest and opens none, which is also the documented accessible state.
    @State private var open: Int?

    private var width: CGFloat { max(model.viewport.width, 320) }
    private var gutter: CGFloat { SiteMath.gutter(width) }
    private var reduce: Bool { systemReduce || model.reduceMotion }
    private var h2Size: CGFloat { SiteMath.h2(width) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Slug(text: SiteCopy.questionsSlug)
                .siteLine(14, 1.55, script: true)
                .padding(.bottom, 14)

            Text(SiteCopy.questionsTitle)
                .font(Fonts.script(h2Size))
                .tracking(-h2Size * 0.01)
                .foregroundStyle(theme.ink)
                .padding(.bottom, 16)

            VStack(spacing: 0) {
                ForEach(Array(SiteCopy.qa.enumerated()), id: \.offset) { index, item in
                    row(index: index, question: item.0, answer: item.1)
                }
            }
            .overlay(alignment: .top) { Hairline() }
            .animation(reduce ? .linear(duration: 0.01) : .cueFAQ, value: open)
        }
        .frame(maxWidth: 760)
        .padding(.horizontal, gutter)
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
        .padding(.bottom, 80)
        .modifier(SiteAnchor(id: "questions"))
    }

    private func row(index: Int, question: String, answer: String) -> some View {
        let isOpen = open == index
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduce ? .linear(duration: 0.01) : .cueFAQ) {
                    open = isOpen ? nil : index
                }
            } label: {
                HStack(alignment: .center, spacing: 16) {
                    Text(question)
                        .font(Fonts.ui(17, weight: .medium))
                        .foregroundStyle(theme.ink)
                        .multilineTextAlignment(.leading)
                        .siteLine(17, 1.55)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(isOpen ? "−" : "+")
                        .font(Fonts.ui(20))
                        .foregroundStyle(theme.ink2)
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            .accessibilityHint(isOpen ? "Collapses the answer" : "Expands the answer")

            if isOpen {
                Text(answer)
                    .font(Fonts.ui(17))
                    .foregroundStyle(theme.ink2)
                    .multilineTextAlignment(.leading)
                    .siteLines(17, 1.55)
                    .padding(.bottom, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .clipped()
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) { Hairline() }
    }
}
