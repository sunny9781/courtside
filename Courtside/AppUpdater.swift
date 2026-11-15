import AppKit
import Foundation

/// Keeps the Mac app up to date from the public courtside-releases repo.
///
/// Every build publishes `mac/latest.json` there, e.g.
///   { "build": 12, "version": "1.0.12", "url": "https://github.com/.../Courtside.zip", "notes": "..." }
/// On launch (and every few hours) the app compares `build` with its own build number. When a newer one
/// exists it downloads the zip in the background, then offers "Restart to update". Because the app downloads
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

    private let feed = URL(string: "https://raw.githubusercontent.com/sunny9781/courtside-releases/main/mac/latest.json")!
    private var stagedApp: URL?
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
        timer = Timer.scheduledTimer(withTimeInterval: 4 * 3600, repeats: true) { _ in
            Task { @MainActor in await AppUpdater.shared.check() }
        }
    }

    func check(userInitiated: Bool = false) async {
        if isReady { return }
        if case .downloading = state { return }
        if isDevelopmentBuild && !userInitiated { return }

        state = .checking
        do {
            var request = URLRequest(url: feed)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: request)
            let latest = try JSONDecoder().decode(Latest.self, from: data)
            lastChecked = Date()

            guard latest.build > currentBuild, let zipURL = URL(string: latest.url) else {
                state = .upToDate
                return
            }
            state = .downloading(latest.version)
            stagedApp = try await download(zipURL)
            state = .ready(latest.version)
        } catch {
            lastChecked = Date()
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
    func restartToUpdate() {
        guard let stagedApp else { return }
        let target = installLocation.path
        let pid = ProcessInfo.processInfo.processIdentifier

        // A tiny helper that waits for this app to quit before replacing it.
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(target)"
        /usr/bin/ditto "\(stagedApp.path)" "\(target)"
        /usr/bin/xattr -dr com.apple.quarantine "\(target)" 2>/dev/null
        /usr/bin/open "\(target)"
        """
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script]
        do {
            try helper.run()
            NSApp.terminate(nil)
        } catch {
            state = .failed("Couldn't install the update.")
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
