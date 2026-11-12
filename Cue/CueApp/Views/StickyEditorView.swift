import SwiftUI
import CueKit

/// Edit a sticky without leaving the desk. The sheet is a small square of paper
/// with the same tints as the marker palette; strikethrough is a first-class
/// control because crossing something off is how a desk gets tidy.
struct StickyEditorView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CueSticky
    private let onSave: (CueSticky) -> Void
    private let onDelete: () -> Void
    @FocusState private var focused: Bool

    init(sticky: CueSticky,
         onSave: @escaping (CueSticky) -> Void,
         onDelete: @escaping () -> Void) {
        _draft = State(initialValue: sticky)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sticky note")
                    .font(Fonts.ui(19, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.ink2)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
            }
            .padding(.bottom, 14)

            TextEditor(text: $draft.text)
                .font(Fonts.ui(15))
                .foregroundStyle(theme.ink)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(height: 170)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(NoteTint.color(draft.tint).opacity(0.42))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.hair, lineWidth: 1)
                }
                .focused($focused)
                .accessibilityLabel("Sticky note text")

            HStack(spacing: 8) {
                Text("Tint")
                    .font(Fonts.ui(12))
                    .foregroundStyle(theme.ink2)
                ForEach(0..<Hex.noteTints.count, id: \.self) { index in
                    Button {
                        draft.tint = index
                    } label: {
                        Circle()
                            .fill(NoteTint.color(index))
                            .frame(width: 20, height: 20)
                            .overlay {
                                Circle()
                                    .strokeBorder(theme.ink.opacity(draft.tint == index ? 0.55 : 0.08),
                                                  lineWidth: draft.tint == index ? 1.5 : 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tint \(index + 1)")
                    .accessibilityAddTraits(draft.tint == index ? .isSelected : [])
                }

                Spacer()

                Toggle(isOn: $draft.strike) {
                    Text("Cross out")
                        .font(Fonts.ui(12.5))
                        .foregroundStyle(theme.ink2)
                }
                .toggleStyle(.checkbox)
            }
            .padding(.top, 14)

            HStack {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(Fonts.ui(13, weight: .medium))
                .foregroundStyle(Color(hex: Hex.choiceText))

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .font(Fonts.ui(13))
                    .foregroundStyle(theme.ink2)
                    .padding(.horizontal, 14)
                    .frame(height: 34)

                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.plain)
                .font(Fonts.ui(13, weight: .medium))
                .foregroundStyle(theme.desk)
                .padding(.horizontal, 18)
                .frame(height: 34)
                .background(theme.ink, in: Capsule())
            }
            .padding(.top, 20)
        }
        .padding(24)
        .frame(width: 400)
        .background(theme.paper)
        .onAppear { focused = true }
    }
}
