import SwiftUI
import CueKit

/// A native update sheet: current version, what changed, and one clear action.
struct UpdateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    private var updates: UpdateController { model.updates }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(theme.ink)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Software Update")
                        .font(Fonts.ui(20, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text("Cue \(UpdateController.currentVersion)")
                        .font(Fonts.ui(12.5))
                        .foregroundStyle(theme.ink2)
                        .monospacedDigit()
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.ink2)
                        .frame(width: 26, height: 26)
                        .background(theme.desk.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
            }
            .padding(.bottom, 20)

            Divider().overlay(theme.hair)
                .padding(.bottom, 20)

            body(for: updates.phase)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 16)

            footer
        }
        .padding(26)
        .frame(width: 470, height: 430)
        .background(theme.paper)
    }

    @ViewBuilder
    private func body(for phase: UpdateController.Phase) -> some View {
        switch phase {
        case .idle:
            VStack(alignment: .leading, spacing: 10) {
                Text("Check for a newer build")
                    .font(Fonts.ui(16, weight: .medium))
                    .foregroundStyle(theme.ink)
                Text("Cue checks GitHub Releases once a month on its own. You can ask it to look now.")
                    .font(Fonts.ui(13))
                    .foregroundStyle(theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .checking:
            status(icon: nil, title: "Checking GitHub…",
                   detail: "Asking for the latest published release.")

        case .upToDate:
            status(icon: "checkmark.circle", title: "You’re up to date.",
                   detail: "Cue \(UpdateController.currentVersion) is the newest version.")

        case .downloading:
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Downloading Cue \(updates.available?.version ?? "")…")
                        .font(Fonts.ui(15, weight: .medium))
                        .foregroundStyle(theme.ink)
                }
                Text("It will be ready the next time you open Cue. You can keep writing.")
                    .font(Fonts.ui(12.5))
                    .foregroundStyle(theme.ink2)
            }

        case .ready:
            VStack(alignment: .leading, spacing: 14) {
                status(icon: "checkmark.circle.fill",
                       title: "Cue \(updates.available?.version ?? "") is ready.",
                       detail: "Restart to finish, or let Cue update itself the next time you quit.")
                if let notes = updates.available?.notes, !notes.isEmpty {
                    ScrollView {
                        Text(notes)
                            .font(Fonts.ui(12))
                            .foregroundStyle(theme.ink2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(12)
                    }
                    .frame(height: 128)
                    .background(theme.desk.opacity(0.45),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(theme.hair, lineWidth: 1)
                    }
                }
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                status(icon: "exclamationmark.triangle", title: "The update didn’t finish.", detail: message)
                Button("Try Again") {
                    Task { await updates.check(manual: true) }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func status(icon: String?, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(theme.ink)
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(Fonts.ui(15, weight: .medium))
                    .foregroundStyle(theme.ink)
                Text(detail)
                    .font(Fonts.ui(12.5))
                    .foregroundStyle(theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Release Notes") {
                if let url = updates.available?.pageURL {
                    NSWorkspace.shared.open(url)
                } else if let url = URL(string: "https://github.com/\(UpdateController.repository)/releases") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(Fonts.ui(12))
            .foregroundStyle(theme.ink2)

            Spacer()

            switch updates.phase {
            case .ready:
                Button("Later") { dismiss() }
                    .buttonStyle(.plain)
                    .font(Fonts.ui(13))
                    .foregroundStyle(theme.ink2)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                Button("Restart Now") {
                    model.flush()
                    updates.installAndRelaunch()
                }
                .buttonStyle(.plain)
                .font(Fonts.ui(13, weight: .medium))
                .foregroundStyle(theme.desk)
                .padding(.horizontal, 18)
                .frame(height: 34)
                .background(theme.ink, in: Capsule())
                .keyboardShortcut(.defaultAction)

            case .downloading:
                Button("Hide") { dismiss() }
                    .buttonStyle(.plain)
                    .font(Fonts.ui(13))
                    .foregroundStyle(theme.ink2)

            default:
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .font(Fonts.ui(13))
                    .foregroundStyle(theme.ink2)

                Button(updates.phase == .checking ? "Checking…" : "Check Now") {
                    Task { await updates.check(manual: true) }
                }
                .buttonStyle(.plain)
                .font(Fonts.ui(13, weight: .medium))
                .foregroundStyle(theme.desk)
                .padding(.horizontal, 18)
                .frame(height: 34)
                .background(theme.ink, in: Capsule())
                .disabled(updates.phase == .checking)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// A small, non-modal notice when an automatic update has finished downloading.
/// It never steals focus from the page.
struct UpdateBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    private var updates: UpdateController { model.updates }

    var body: some View {
        if updates.phase == .ready, !updates.bannerDismissed {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: Hex.orange))

                Text("Cue \(updates.available?.version ?? "") is ready.")
                    .font(Fonts.ui(12.5, weight: .medium))
                    .foregroundStyle(theme.ink)

                Button("Restart") {
                    model.flush()
                    updates.installAndRelaunch()
                }
                .buttonStyle(.plain)
                .font(Fonts.ui(12, weight: .semibold))
                .foregroundStyle(theme.desk)
                .padding(.horizontal, 11)
                .frame(height: 24)
                .background(theme.ink, in: Capsule())

                Button {
                    updates.bannerDismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.ink2)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss update notice")
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: 38)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(theme.hair, lineWidth: 1) }
            .shadow(color: theme.shadow.opacity(0.7), radius: 10, y: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
