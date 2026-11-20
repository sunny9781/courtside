import AppKit
import Foundation

/// Keeps the Mac app up to date from the courtside repo's releases.
///
/// Every build publishes a release with Courtside.zip and latest.json, e.g.
///   { "build": 12, "version": "1.18", "url": "https://github.com/.../Courtside.zip", "notes": "..." }
/// On launch (and every 15 minutes) the app compares `build` with its own build number. When a newer one
/// exists it downloads the zip in the background, then offers "Restart to update". If you just quit instead,
/// it installs on the way out, so the next launch is the new version. Because the app downloads
/// the file itself, macOS doesn't flag it, so there is no "Open Anyway" step after the first install.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case downloading(String)
        case ready(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date?

    /// The newest release's latest.json (GitHub redirects "latest" to the newest release).
    private let feed = URL(string: "https://github.com/sunny9781/courtside/releases/latest/download/latest.json")!
    private var installing = false
    private var stagedApp: URL?
    /// Build number of the downloaded update, so a newer one replaces it before you restart.
    private var stagedBuild = 0
    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
    }

    /// Builds made in Xcode on your Mac have build number 1; those never update themselves, so a
    /// development copy doesn't get replaced by the published one while you're testing.
    var isDevelopmentBuild: Bool { currentBuild <= 1 }

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    func start() {
        guard timer == nil else { return }
        Task { await check() }
        // Every 15 minutes: a tiny file, and it means "Restart to update" always has the newest build.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppUpdater.shared.installOnQuit() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
            Task { @MainActor in await AppUpdater.shared.check() }
        }
    }

    /// Always looks at the newest published build. If several came out since this one, it goes straight to the
    /// newest; if an update is already downloaded and a newer one appears, the newer one replaces it.
    func check(userInitiated: Bool = false) async {
        if case .downloading = state { return }
        if isDevelopmentBuild && !userInitiated { return }

        let wasReady = state
        if !isReady { state = .checking }
        do {
            // The time in the address gets past GitHub's few-minutes cache of the file.
            var request = URLRequest(url: URL(string: feed.absoluteString + "?t=\(Int(Date().timeIntervalSince1970))")!)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: request)
            let latest = try JSONDecoder().decode(Latest.self, from: data)
            lastChecked = Date()

            guard latest.build > max(currentBuild, stagedBuild), let zipURL = URL(string: latest.url) else {
                if !isReady { state = .upToDate }
                return
            }
            state = .downloading(latest.version)
            stagedApp = try await download(zipURL)
            stagedBuild = latest.build
            state = .ready(latest.version)
        } catch {
            lastChecked = Date()
            if case .ready = wasReady { state = wasReady; return }   // keep the update already downloaded
            state = userInitiated ? .failed("Couldn't check for updates.") : .idle
        }
    }

    /// Downloads and unzips the new app into a temporary folder.
    nonisolated private func download(_ url: URL) async throws -> URL {
        let (file, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CourtsideUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let zip = folder.appendingPathComponent("Courtside.zip")
        try FileManager.default.moveItem(at: file, to: zip)

        try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, folder.path])
        let app = folder.appendingPathComponent("Courtside.app")
        guard FileManager.default.fileExists(atPath: app.path) else { throw URLError(.cannotDecodeContentData) }
        // Never install a broken copy (2.5 was published without its program after a failed build, and macOS
        // then said the app was damaged): it must have its program and a valid signature.
        let program = app.appendingPathComponent("Contents/MacOS/Courtside")
        guard FileManager.default.isExecutableFile(atPath: program.path) else { throw URLError(.cannotDecodeContentData) }
        try Self.run("/usr/bin/codesign", ["--verify", "--deep", app.path])
        return app
    }

    /// Where the new copy goes. Normally that's wherever this copy lives. If macOS is running the app from a
    /// temporary read-only spot (it does this for downloaded apps that were never moved), use Applications.
    private var installLocation: URL {
        let here = Bundle.main.bundleURL
        if here.path.contains("/AppTranslocation/") {
            return URL(fileURLWithPath: "/Applications/Courtside.app")
        }
        return here
    }

    /// Quits, swaps in the new copy and opens it again.
    /// Checks once more for anything newer (a few seconds at most), then installs and restarts.
    func restartToUpdate() {
        Task { @MainActor in
            // Whichever finishes first: the check (and a download, if something newer turned up) or 20 seconds.
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.check() }
                group.addTask { try? await Task.sleep(for: .seconds(20)) }
                await group.next()
                group.cancelAll()
            }
            self.install()
        }
    }

    private func install() {
        guard startInstaller(reopen: true) else {
            state = .failed("Couldn't install the update.")
            return
        }
        NSApp.terminate(nil)
    }

    /// Quitting with an update downloaded: install it on the way out (without reopening).
    func installOnQuit() {
        _ = startInstaller(reopen: false)
    }

    /// Starts a tiny helper that waits for this app to quit, then swaps in the new copy (and opens it if asked).
    private func startInstaller(reopen: Bool) -> Bool {
        guard isReady, !installing, let stagedApp else { return false }
        let target = installLocation.path
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(target)"
        /usr/bin/ditto "\(stagedApp.path)" "\(target)"
        /usr/bin/xattr -dr com.apple.quarantine "\(target)" 2>/dev/null
        \(reopen ? "/usr/bin/open \"\(target)\"" : "true")
        """
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script]
        do {
            try helper.run()
            installing = true
            return true
        } catch {
            return false
        }
    }

    nonisolated private static func run(_ tool: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw URLError(.cannotDecodeContentData) }
    }

    private struct Latest: Decodable {
        let build: Int
        let version: String
        let url: String
        let notes: String?
    }
}
