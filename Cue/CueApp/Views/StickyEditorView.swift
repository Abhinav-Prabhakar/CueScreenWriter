import SwiftUI
import AppKit
import CueKit

/// Editing a sticky happens on the desk, in the note itself. No sheet, no
/// second dialog: the paper becomes editable, and tint, cross-out and delete
/// live in a small strip along its bottom edge.
struct StickyInlineEditor: View {
    var sticky: CueSticky
    var width: CGFloat
    var height: CGFloat
    var onChange: (CueSticky) -> Void
    var onDelete: () -> Void
    var onDone: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: CueSticky
    @FocusState private var focused: Bool

    init(sticky: CueSticky,
         width: CGFloat,
         height: CGFloat,
         onChange: @escaping (CueSticky) -> Void,
         onDelete: @escaping () -> Void,
         onDone: @escaping () -> Void) {
        self.sticky = sticky
        self.width = width
        self.height = height
        self.onChange = onChange
        self.onDelete = onDelete
        self.onDone = onDone
        _draft = State(initialValue: sticky)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $draft.text)
                .font(Fonts.ui(15))
                .foregroundStyle(theme.ink)
                .strikethrough(draft.strike, color: theme.ink.opacity(0.75))
                .scrollContentBackground(.hidden)
                .lineSpacing(2)
                .padding(.horizontal, 13)
                .padding(.top, 14)
                .focused($focused)
                .overlay(alignment: .topLeading) {
                    if draft.text.isEmpty {
                        Text("Write it down…")
                            .font(Fonts.ui(15))
                            .foregroundStyle(theme.ink2.opacity(0.62))
                            .padding(.leading, 18)
                            .padding(.top, 14)
                            .allowsHitTesting(false)
                    }
                }

            Divider().overlay(theme.hair)

            HStack(spacing: 4) {
                ForEach(0..<Hex.noteTints.count, id: \.self) { index in
                    Button {
                        draft.tint = index
                        onChange(draft)
                    } label: {
                        Circle()
                            .fill(NoteTint.color(index))
                            .frame(width: 13, height: 13)
                            .overlay {
                                Circle().strokeBorder(theme.ink.opacity(draft.tint == index ? 0.65 : 0.12),
                                                      lineWidth: draft.tint == index ? 1.5 : 1)
                            }
                            .frame(width: 18, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tint \(index + 1)")
                    .accessibilityAddTraits(draft.tint == index ? .isSelected : [])
                }

                Spacer(minLength: 2)

                iconButton("strikethrough",
                           label: draft.strike ? "Uncross" : "Cross out",
                           active: draft.strike) {
                    draft.strike.toggle()
                    onChange(draft)
                }

                iconButton("trash", label: "Delete sticky") {
                    onDelete()
                }

                iconButton("checkmark", label: "Done", active: true) {
                    finish()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(theme.paper.opacity(0.28))
        }
        .frame(width: width, height: height)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color(hex: Hex.orange).opacity(0.42), lineWidth: 1)
        }
        .shadow(color: theme.shadow.opacity(0.72), radius: 22, x: 0, y: 12)
        .background(OutsideClickMonitor(onOutside: finish))
        .onAppear { focused = true }
        .onChange(of: draft.text) { _, _ in onChange(draft) }
        .onExitCommand { finish() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editing sticky note")
    }

    private func iconButton(_ system: String,
                            label: String,
                            active: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? theme.ink : theme.ink2)
                .frame(width: 21, height: 21)
                .background(active ? theme.desk.opacity(0.7) : .clear,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func finish() {
        let clean = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            onDelete()
        } else {
            onChange(draft)
            onDone()
        }
    }

    private var background: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.ultraThinMaterial)
            if theme.colorScheme == .dark {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: 0x5E3E1D).opacity(0.9))
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: Hex.orange).opacity(0.14))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.paper.opacity(0.55))
            }
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(NoteTint.color(draft.tint).opacity(0.10))
        }
    }
}

/// Commits when a click lands anywhere outside the editor's own frame. AppKit's
/// local event monitor is the reliable way to catch a click on the desk, the
/// toolbar or the page without installing a full-screen invisible layer.
private struct OutsideClickMonitor: NSViewRepresentable {
    var onOutside: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onOutside = onOutside
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onOutside = onOutside
    }

    final class MonitorView: NSView {
        var onOutside: () -> Void = {}
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if !self.bounds.contains(point) {
                    self.onOutside()
                }
                return event
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
