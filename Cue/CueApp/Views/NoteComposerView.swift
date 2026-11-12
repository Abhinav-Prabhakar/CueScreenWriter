import SwiftUI
import CueKit

/// Compose or edit a margin note. The quote is the line the writer selected;
/// the body is the thought. Tints match the marker colours used on the page.
struct NoteComposerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var draft: NoteDraft
    @FocusState private var bodyFocused: Bool

    init(draft: NoteDraft) {
        _draft = State(initialValue: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.editing == nil ? "New note" : "Edit note")
                        .font(Fonts.ui(19, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text("Scene \(draft.scene) · kept beside the script")
                        .font(Fonts.ui(13))
                        .foregroundStyle(theme.ink2)
                }
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
            .padding(.bottom, 20)

            Text("THE LINE")
                .font(Fonts.ui(10, weight: .medium))
                .tracking(1.1)
                .foregroundStyle(theme.ink2)
                .padding(.bottom, 7)

            TextField("Quote", text: $draft.quote, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Fonts.script(13))
                .foregroundStyle(theme.ink)
                .lineLimit(1...3)
                .padding(.horizontal, 12)
                .frame(minHeight: 38)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.paper.opacity(theme.colorScheme == .dark ? 0.28 : 0.55))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.hair, lineWidth: 1)
                }
                .accessibilityLabel("Quoted line")

            Text("THE NOTE")
                .font(Fonts.ui(10, weight: .medium))
                .tracking(1.1)
                .foregroundStyle(theme.ink2)
                .padding(.top, 18)
                .padding(.bottom, 7)

            TextEditor(text: $draft.body)
                .font(Fonts.ui(14))
                .foregroundStyle(theme.ink)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 120)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.paper.opacity(theme.colorScheme == .dark ? 0.24 : 0.50))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.hair, lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    if draft.body.isEmpty {
                        Text("What are you noticing?")
                            .font(Fonts.ui(14))
                            .foregroundStyle(theme.ink2.opacity(0.55))
                            .padding(.leading, 15)
                            .padding(.top, 18)
                            .allowsHitTesting(false)
                    }
                }
                .focused($bodyFocused)
                .accessibilityLabel("Note")

            HStack(spacing: 8) {
                Text("Tint")
                    .font(Fonts.ui(12))
                    .foregroundStyle(theme.ink2)
                    .padding(.trailing, 2)
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
                    .accessibilityLabel("Note tint \(index + 1)")
                    .accessibilityAddTraits(draft.tint == index ? .isSelected : [])
                }
                Spacer()
            }
            .padding(.top, 16)

            HStack {
                if draft.editing != nil {
                    Button("Delete", role: .destructive) {
                        if let editing = draft.editing,
                           let note = model.current.notes.first(where: { $0.id == editing }) {
                            model.deleteNote(note)
                        }
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(Fonts.ui(13, weight: .medium))
                    .foregroundStyle(Color(hex: Hex.choiceText))
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .font(Fonts.ui(13))
                    .foregroundStyle(theme.ink2)
                    .padding(.horizontal, 14)
                    .frame(height: 34)

                Button(draft.editing == nil ? "Add note" : "Save note") {
                    model.noteDraft = draft
                    model.saveNoteDraft()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.plain)
                .font(Fonts.ui(13, weight: .medium))
                .foregroundStyle(theme.desk)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background(theme.ink, in: Capsule())
            }
            .padding(.top, 22)
        }
        .padding(26)
        .frame(width: 470)
        .background(theme.paper)
        .onAppear { bodyFocused = true }
    }
}

/// A compact, keyboard-first help sheet. The app is meant to be used without
/// the mouse, so the shortcuts are part of the interface, not buried in a menu.
struct HelpView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let groups: [(String, [(String, String)])] = [
        ("Writing", [
            ("Return", "Next line, with the next element suggested"),
            ("Tab", "Promote action to a character, or accept a suggestion"),
            ("⇧Tab", "Move to the previous line"),
            ("(", "Parenthetical on an empty dialogue line"),
            ("⌘⇧N", "Add a note on the selected line"),
            ("⌘Z / ⇧⌘Z", "Undo / redo")
        ]),
        ("The room", [
            ("⌥⌘\\", "Show or hide the sidebar"),
            ("⌥⌘1 / 2 / 3", "Daylight / Evening / Night"),
            ("⌥⌘0", "Follow the time of day"),
            ("⌥⌘L", "Turn the lamp on or off"),
            ("⌘⇧0", "Library"),
            ("⌘/", "This help")
        ]),
        ("Files", [
            ("⌘N", "New script"),
            ("⇧⌘E", "Export a screenplay PDF"),
            ("⌥⌘E", "Export Fountain"),
            ("⌘K", "Search the library")
        ])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Everything has a key.")
                        .font(Fonts.ui(20, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text("The mouse is optional.")
                        .font(Fonts.ui(13))
                        .foregroundStyle(theme.ink2)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.plain)
                    .font(Fonts.ui(13, weight: .medium))
                    .foregroundStyle(theme.desk)
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    .background(theme.ink, in: Capsule())
            }
            .padding(.bottom, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.0.uppercased())
                                .font(Fonts.ui(10, weight: .medium))
                                .tracking(1.1)
                                .foregroundStyle(theme.ink2)
                            ForEach(Array(group.1.enumerated()), id: \.offset) { _, row in
                                HStack(alignment: .firstTextBaseline, spacing: 16) {
                                    Text(row.0)
                                        .font(Fonts.ui(12.5, weight: .medium))
                                        .foregroundStyle(theme.ink)
                                        .frame(width: 120, alignment: .leading)
                                        .padding(.vertical, 5)
                                        .padding(.horizontal, 9)
                                        .background {
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .fill(theme.paper.opacity(theme.colorScheme == .dark ? 0.24 : 0.55))
                                                .overlay {
                                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                        .strokeBorder(theme.hair, lineWidth: 1)
                                                }
                                        }
                                    Text(row.1)
                                        .font(Fonts.ui(13))
                                        .foregroundStyle(theme.ink2)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 380)
        }
        .padding(28)
        .frame(width: 520)
        .background(theme.paper)
    }
}
