import AppKit
import Foundation
import Observation
import CueKit

/// Checks GitHub Releases, downloads a newer build, and swaps it in when Cue
/// quits. There is no third-party updater and no analytics: one request a month,
/// plus whatever the writer asks for from the menu.
@MainActor
@Observable
final class UpdateController {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case downloading
        case ready
        case failed(String)
    }

    struct Release: Identifiable, Equatable {
        var id: String { tag }
        var tag: String
        var version: String
        var notes: String
        var pageURL: URL
        var downloadURL: URL
    }

    private enum Keys {
        static let lastCheck = "cue.update.lastCheck"
        static let autoCheck = "cue.update.automatic"
        static let skipped = "cue.update.skippedVersion"
    }

    static let repository = "Abhinav-Prabhakar/CueScreenWriter"
    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    var phase: Phase = .idle
    var available: Release?
    var showSheet = false
    var bannerDismissed = false
    var automatic: Bool {
        get { UserDefaults.standard.object(forKey: Keys.autoCheck) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.autoCheck) }
    }

    var lastCheck: Date? {
        get { UserDefaults.standard.object(forKey: Keys.lastCheck) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastCheck) }
    }

    private var preparedApp: URL?
    private var installing = false
    private var automaticAttempted = false

    var isBusy: Bool { phase == .checking || phase == .downloading }
    var isReady: Bool { phase == .ready && preparedApp != nil }

    var statusLine: String {
        switch phase {
        case .idle:
            return lastCheck.map { "Last checked \(Self.relative.string(for: $0) ?? "recently")" } ?? "Not checked yet"
        case .checking: return "Checking GitHub…"
        case .upToDate: return "You’re up to date."
        case .downloading: return available.map { "Downloading Cue \($0.version)…" } ?? "Downloading…"
        case .ready: return available.map { "Cue \($0.version) is ready." } ?? "An update is ready."
        case .failed(let message): return message
        }
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    // MARK: - Checking

    /// Called once per launch. It gives the network one month of quiet between
    /// checks; a failed or skipped check still counts as the month's check, so
    /// an offline Mac doesn't hammer GitHub at every launch.
    func automaticCheckIfDue() async {
        guard automatic, !automaticAttempted else { return }
        automaticAttempted = true
        guard UpdateSchedule.shouldCheck(lastCheck: lastCheck) else { return }
        await check(manual: false)
    }

    func check(manual: Bool) async {
        guard phase != .checking, phase != .downloading else { return }
        if manual {
            showSheet = true
            bannerDismissed = false
        }
        phase = .checking
        lastCheck = Date()

        do {
            let release = try await latestRelease()
            guard UpdateSchedule.isNewer(release.tag, than: Self.currentVersion) else {
                if manual { phase = .upToDate }
                else { phase = .idle }
                return
            }

            let skipped = UserDefaults.standard.string(forKey: Keys.skipped)
            available = release
            if !manual, skipped == release.version {
                phase = .idle
                return
            }

            phase = .downloading
            try await downloadAndPrepare(release)
            phase = .ready
            available = release
        } catch {
            phase = .failed(Self.message(for: error))
            if !manual {
                // An automatic failure is not worth interrupting the writer.
                NSLog("Cue update check failed: \(error.localizedDescription)")
            }
        }
    }

    func skipAvailableVersion() {
        if let available {
            UserDefaults.standard.set(available.version, forKey: Keys.skipped)
        }
        phase = .idle
        bannerDismissed = true
    }

    func dismissSheet() {
        showSheet = false
        if phase == .upToDate || phase == .failed("") { phase = .idle }
    }

    // MARK: - GitHub

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let body: String?
        let html_url: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }

    private func latestRelease() async throws -> Release {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest") else {
            throw UpdateError.badResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Cue/\(Self.currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.badResponse
        }
        let decoded = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !decoded.draft, !decoded.prerelease else { throw UpdateError.noRelease }

        guard let asset = decoded.assets.first(where: { $0.name == "Cue.zip" })
            ?? decoded.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }),
              let download = URL(string: asset.browser_download_url),
              let page = URL(string: decoded.html_url) else {
            throw UpdateError.noDownload
        }

        return Release(tag: decoded.tag_name,
                       version: (SemanticVersion(decoded.tag_name) ?? SemanticVersion(major: 0, minor: 0, patch: 0)).description,
                       notes: decoded.body ?? "",
                       pageURL: page,
                       downloadURL: download)
    }

    // MARK: - Download and stage

    private var updatesDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Cue/Updates", isDirectory: true)
    }

    private func downloadAndPrepare(_ release: Release) async throws {
        let manager = FileManager.default
        let folder = updatesDirectory.appendingPathComponent(release.version, isDirectory: true)
        try? manager.removeItem(at: folder)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)

        let (temporary, response) = try await URLSession.shared.download(from: release.downloadURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.badResponse
        }
        let archive = folder.appendingPathComponent("Cue.zip")
        try manager.moveItem(at: temporary, to: archive)

        let stage = folder.appendingPathComponent("stage", isDirectory: true)
        try manager.createDirectory(at: stage, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, stage.path])

        guard let app = locateApp(in: stage) else { throw UpdateError.noApp }
        let identifier = Bundle(url: app)?.bundleIdentifier
        let version = Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard identifier == Bundle.main.bundleIdentifier else { throw UpdateError.wrongApp }
        guard version == release.version else { throw UpdateError.wrongVersion }

        let prepared = folder.appendingPathComponent("Cue.app")
        try? manager.removeItem(at: prepared)
        try manager.moveItem(at: app, to: prepared)
        try? manager.removeItem(at: stage)
        try? manager.removeItem(at: archive)
        try? manager.removeItem(at: updatesDirectory.appendingPathComponent("install.sh"))
        preparedApp = prepared
    }

    private func locateApp(in folder: URL) -> URL? {
        let direct = folder.appendingPathComponent("Cue.app")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder,
                                                                     includingPropertiesForKeys: nil)) ?? []
        return contents.first { $0.pathExtension == "app" }
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.unpack }
    }

    // MARK: - Install

    /// Called by the app's Quit command and by the "Restart" button. The helper
    /// waits for this process to exit, replaces the bundle, clears quarantine,
    /// and reopens Cue. If the bundle isn't writable, Finder reveals the
    /// downloaded copy instead.
    func installAndRelaunch() {
        guard let preparedApp, !installing else { return }
        let destination = Bundle.main.bundleURL
        let parent = destination.deletingLastPathComponent()

        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            NSWorkspace.shared.activateFileViewerSelecting([preparedApp])
            phase = .failed("Cue can’t replace itself in this folder. The new copy has been revealed in Finder.")
            showSheet = true
            return
        }

        let script = updatesDirectory.appendingPathComponent("install.sh")
        let stagingRoot = preparedApp.deletingLastPathComponent()
        let content = """
        #!/bin/sh
        pid="$1"; src="$2"; dst="$3"; stage="$4"
        while kill -0 "$pid" 2>/dev/null; do sleep 0.3; done
        tmp="$dst.updating"
        rm -rf "$tmp"
        if /usr/bin/ditto "$src" "$tmp"; then
          rm -rf "$dst"
          mv "$tmp" "$dst"
          /usr/bin/xattr -dr com.apple.quarantine "$dst" 2>/dev/null
          /usr/bin/open "$dst"
        fi
        rm -rf "$stage"
        """
        do {
            try content.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        } catch {
            phase = .failed("Couldn’t prepare the update: \(error.localizedDescription)")
            showSheet = true
            return
        }

        installing = true
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path,
                             String(ProcessInfo.processInfo.processIdentifier),
                             preparedApp.path,
                             destination.path,
                             stagingRoot.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            installing = false
            phase = .failed("Couldn’t start the installer: \(error.localizedDescription)")
            showSheet = true
            return
        }

        NSApp.terminate(nil)
    }

    /// Installs quietly when the writer quits, so a downloaded update completes
    /// in the background without another dialog.
    func installOnQuitIfNeeded() {
        guard isReady, !installing else { return }
        installAndRelaunch()
    }

    // MARK: - Helpers

    private enum UpdateError: LocalizedError {
        case badResponse, noRelease, noDownload, unpack, noApp, wrongApp, wrongVersion

        var errorDescription: String? {
            switch self {
            case .badResponse: return "GitHub didn’t answer. Try again in a moment."
            case .noRelease: return "No published release was found."
            case .noDownload: return "This release has no download yet."
            case .unpack: return "The download couldn’t be opened."
            case .noApp: return "The download didn’t contain Cue."
            case .wrongApp: return "That download isn’t Cue."
            case .wrongVersion: return "The download’s version didn’t match its release."
            }
        }
    }

    private static func message(for error: Error) -> String {
        if error is URLError { return "Couldn’t reach GitHub. Check your connection and try again." }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
