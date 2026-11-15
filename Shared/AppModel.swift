import Foundation
import Combine
#if os(macOS)
import AppKit
#endif

@MainActor
final class AppModel: ObservableObject {
    @Published var credentials: XtreamCredentials?
    @Published var account: AccountInfo?
    @Published var categories: [ChannelCategory] = []
    @Published var categoryTree: [CategoryGrouping.Node] = []
    @Published var channels: [Channel] = []
    @Published var channelsByCategory: [String: [Channel]] = [:]
    @Published var channelByID: [Int: Channel] = [:]
    @Published var games: [Game] = []
    /// Every game fetched, including leagues switched off in Settings.
    private var allGames: [Game] = []
    @Published var leagueLogos: [String: URL] = [:]
    @Published var matches: [String: [StreamMatch]] = [:]
    @Published var guide: [String: [Programme]] = [:]
    @Published var guideLinks: [String: String] = [:]
    @Published var extraBroadcasts: [String: [Broadcast]] = [:]
    @Published var guideStatus: String?
    @Published var guideUpdated: Date?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastRefresh: Date?
    @Published var nowPlaying: NowPlaying?
    @Published var notice: String?
    /// The channel that was playing when full screen closed, so the mini player can pick it up.
    @Published var lastPlayedChannelID: Int?
    /// How many mini players are on screen (game screen, guide).
    var miniPlayers = 0
    /// The channel the mini player is showing right now.
    var previewChannel: Channel?
    /// Set when you switch tabs while a mini player is playing: it keeps playing (sound in the background),
    /// and the next screen with a mini player picks it up instead of starting something else.
    @Published var backgroundChannel: Channel?
    /// Real resolutions seen while playing, by channel id, so stream lists show "720p" instead of a guess.
    @Published var measuredQuality: [Int: String] = [:]

    private var indexed: [Matcher.IndexedChannel] = []
    private var scoreTask: Task<Void, Never>?
    private var accountTask: Task<Void, Never>?
    private var accountCheck: Task<Void, Never>?
    private var guideTask: Task<Void, Never>?

    init() {
        credentials = CredentialStore.load()
        PlaybackController.shared.onChange = { [weak self] in self?.checkConnectionsSoon() }
        let saved = UserDefaults.standard.dictionary(forKey: Prefs.measuredQuality) as? [String: String] ?? [:]
        measuredQuality = Dictionary(uniqueKeysWithValues: saved.compactMap { k, v in Int(k).map { ($0, v) } })
    }

    func recordQuality(_ channelID: Int, _ label: String) {
        guard measuredQuality[channelID] != label else { return }
        measuredQuality[channelID] = label
        let saved = Dictionary(uniqueKeysWithValues: measuredQuality.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(saved, forKey: Prefs.measuredQuality)
        Task { await rematch() }
    }

    // MARK: Account

    /// Returns nil on success, or a message to show on the login screen.
    func signIn(server: String, username: String, password: String) async -> String? {
        let creds = XtreamCredentials(server: server, username: username, password: password)
        do {
            account = try await XtreamClient(creds: creds).login()
        } catch {
            return error.localizedDescription
        }
        CredentialStore.save(creds)
        credentials = creds
        return nil
    }

    func signOut() {
        scoreTask?.cancel()
        guideTask?.cancel()
        accountTask?.cancel()
        CredentialStore.delete()
        try? FileManager.default.removeItem(at: Self.guideFile)
        try? FileManager.default.removeItem(at: Self.channelsFile)
        savedAt = nil
        credentials = nil
        account = nil
        categories = []
        categoryTree = []
        channels = []
        channelsByCategory = [:]
        channelByID = [:]
        games = []
        allGames = []
        matches = [:]
        guide = [:]
        guideLinks = [:]
        extraBroadcasts = [:]
        indexed = []
        nowPlaying = nil
        PlaybackController.shared.stop()
        errorMessage = nil
        lastRefresh = nil
        guideUpdated = nil
    }

    // MARK: Refresh

    /// Runs every time the app opens, and from the refresh buttons.
    /// Saved copy of the channel list, reused until it's older than the refresh interval.
    private struct SavedChannels: Codable {
        let savedAt: Date
        let account: AccountInfo?
        let categories: [ChannelCategory]
        let channels: [Channel]
    }

    static var channelsFile: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("Courtside", isDirectory: true).appendingPathComponent("channels.json")
    }

    private var refreshInterval: TimeInterval {
        Double(max(UserDefaults.standard.integer(forKey: Prefs.refreshHours), 1)) * 3600
    }

    /// When the saved channels and guide were last downloaded.
    @Published var savedAt: Date?
    /// True only while channels are actually being downloaded from the provider (not for score updates).
    @Published var downloadingChannels = false

    private func apply(categories cats: [ChannelCategory], channels list: [Channel]) async {
        categories = cats
        categoryTree = CategoryGrouping.build(cats)
        channels = list
        channelsByCategory = Dictionary(grouping: list, by: \.categoryID)
        channelByID = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        indexed = await Task.detached(priority: .userInitiated) { Matcher.index(list) }.value
    }

    /// Opening the app: channels and the guide come from the saved copy when it's recent enough
    /// (6 hours by default); scores are always fetched. `force` downloads everything now.
    func refresh(force: Bool = false) async {
        guard let creds = credentials, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // 1. Saved channels, instantly.
        var stale = true
        if channels.isEmpty, let data = try? Data(contentsOf: Self.channelsFile),
           let saved = try? JSONDecoder().decode(SavedChannels.self, from: data) {
            await apply(categories: saved.categories, channels: saved.channels)
            account = saved.account ?? account
            savedAt = saved.savedAt
        }
        if let savedAt, !force, !channels.isEmpty, Date().timeIntervalSince(savedAt) < refreshInterval {
            stale = false
        }

        async let gamesTask = ScheduleClient().schedule(for: League.all)

        // 2. Channels from the provider only when the saved copy is too old (or you asked).
        if stale {
            downloadingChannels = true
            defer { downloadingChannels = false }
            let client = XtreamClient(creds: creds)
            do {
                async let accountTask = client.login()
                async let liveTask = client.live()
                account = try await accountTask
                let (cats, list) = try await liveTask
                await apply(categories: cats, channels: list)
                let now = Date()
                savedAt = now
                let saved = SavedChannels(savedAt: now, account: account, categories: cats, channels: list)
                if let data = try? JSONEncoder().encode(saved) {
                    try? FileManager.default.createDirectory(at: Self.channelsFile.deletingLastPathComponent(),
                                                             withIntermediateDirectories: true)
                    try? data.write(to: Self.channelsFile, options: .atomic)
                }
            } catch {
                if channels.isEmpty {
                    errorMessage = error.localizedDescription
                    return
                }
                errorMessage = "Couldn't reach your provider, so this is the saved channel list. \(error.localizedDescription)"
            }
        }

        // 3. Scores, always.
        do {
            let result = try await gamesTask
            allGames = result.games
            games = Self.visible(allGames)
            leagueLogos.merge(result.logos) { _, new in new }
        } catch {
            errorMessage = "Couldn't load today's schedule. Channels and the guide still work."
        }

        await rematch()
        lastRefresh = Date()

        // Canadian and international broadcasters from the second source, then match again.
        let todays = games
        Task {
            extraBroadcasts = await BroadcastSources.fetch(for: todays)
            await rematch()
        }

        guideTask?.cancel()
        let download = stale
        guideTask = Task { await loadGuide(download: download) }
        startScoreUpdates()
        startAccountUpdates()
    }

    /// Live scores every minute while the app is open, for leagues that still have games to play today.
    private func startScoreUpdates() {
        scoreTask?.cancel()
        scoreTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self else { return }
                let active = Set(self.allGames.filter { $0.state != .finished }.map(\.league))
                guard !active.isEmpty else { continue }
                if let fresh = try? await ScheduleClient().games(for: Array(active)) {
                    let freshIDs = Set(fresh.map(\.id))
                    let kept = self.allGames.filter { !active.contains($0.league) && !freshIDs.contains($0.id) }
                    self.allGames = (kept + fresh).sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
                    self.games = Self.visible(self.allGames)
                    await self.rematch()
                }
            }
        }
    }

    /// Connections in use change whenever any device on the account starts or stops a stream,
    /// so the account is checked every 30 seconds while the app is open.
    private func startAccountUpdates() {
        accountTask?.cancel()
        accountTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAccount()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func refreshAccount() async {
        guard let creds = credentials else { return }
        if let fresh = try? await XtreamClient(creds: creds).login() {
            account = fresh
        }
    }

    /// Re-checks the count a few seconds after a stream starts or stops, once the provider has noticed.
    func checkConnectionsSoon() {
        accountCheck?.cancel()
        accountCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.refreshAccount()
        }
    }

    func rematch() async {
        let idx = indexed
        let gs = games
        let gd = guide
        let extras = extraBroadcasts
        let measured = measuredQuality
        let recent = Set(recentChannelIDs)
        let now = Date()
        let result = await Task.detached(priority: .userInitiated) {
            Matcher.matchAll(games: gs, channels: idx, guide: gd, extras: extras, measured: measured, recent: recent, now: now)
        }.value
        matches = result.matches
        guideLinks = result.links
    }

    /// Streams shown by default for a game: everything except local stations, unless locals are all there is.
    func mainStreams(_ gameID: String) -> [StreamMatch] {
        let all = matches[gameID] ?? []
        let main = all.filter { !$0.hidden }
        return main.isEmpty ? all : main
    }

    func streamCount(_ gameID: String) -> Int {
        mainStreams(gameID).count
    }

    private static func visible(_ list: [Game]) -> [Game] {
        let hidden = League.hiddenSaved
        return list.filter { !hidden.contains($0.league.id) }
    }

    /// Called when a league is switched on or off in Settings.
    func applyLeagueFilter() {
        games = Self.visible(allGames)
        Task { await rematch() }
    }

    /// A sport's leagues that are switched on.
    func leagues(for sport: Sport) -> [League] {
        let hidden = League.hiddenSaved
        return sport.leagues.filter { !hidden.contains($0.id) }
    }

    func games(for sport: Sport) -> [Game] {
        games.filter { $0.league.sport == sport }
    }

    // MARK: Guide

    static var guideFile: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("Courtside", isDirectory: true).appendingPathComponent("guide.xml")
    }

    func currentProgramme(_ channel: Channel, at date: Date = Date()) -> Programme? {
        guide[channel.epgID]?.first { $0.start <= date && $0.end > date }
    }

    /// Shows the saved guide instantly, and downloads a fresh one when asked or when there's no saved guide.
    func loadGuide(download: Bool = true) async {
        guard let creds = credentials else { return }
        let wanted = Set(channels.map(\.epgID).filter { !$0.isEmpty })
        guard !wanted.isEmpty else {
            guideStatus = "Your provider doesn't link its channels to a guide."
            return
        }
        let hours = Double(max(UserDefaults.standard.integer(forKey: Prefs.guideHours), 2))
        let from = Date().addingTimeInterval(-3600)
        let to = Date().addingTimeInterval(hours * 3600)
        let file = Self.guideFile

        let haveFile = FileManager.default.fileExists(atPath: file.path)
        if haveFile, (guide.isEmpty || !download),
           let cached = try? await Task.detached(priority: .userInitiated, operation: {
               try XtreamClient.parseGuide(file: file, wanted: wanted, from: from, to: to)
           }).value {
            guide = cached
            guideUpdated = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            await rematch()
            if !download { return }   // the saved guide is recent enough
        }

        guideStatus = "Updating the guide…"
        do {
            try await XtreamClient(creds: creds).downloadGuide(to: file)
            let fresh = try await Task.detached(priority: .utility, operation: {
                try XtreamClient.parseGuide(file: file, wanted: wanted, from: from, to: to)
            }).value
            guide = fresh
            guideUpdated = Date()
            guideStatus = nil
            await rematch()
        } catch {
            if !Task.isCancelled {
                guideStatus = "Couldn't update the guide. \(error.localizedDescription)"
            }
        }
    }

    // MARK: Playback

    var recentChannelIDs: [Int] {
        get { (UserDefaults.standard.array(forKey: Prefs.recentChannels) as? [Int]) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(50)), forKey: Prefs.recentChannels) }
    }

    private func remember(_ id: Int) {
        recentChannelIDs = [id] + recentChannelIDs.filter { $0 != id }
        Task { await rematch() }
    }

    /// The lineup is what up/down flips through while watching.
    func play(_ channel: Channel, gameTitle: String? = nil, lineup: [Channel] = []) {
        remember(channel.id)
        nowPlaying = NowPlaying(channel: channel, gameTitle: gameTitle, lineup: lineup.isEmpty ? [channel] : lineup)
    }

    func switchStream(to channel: Channel) {
        guard let current = nowPlaying, channel.id != current.channel.id else { return }
        remember(channel.id)
        nowPlaying = NowPlaying(channel: channel, gameTitle: current.gameTitle, lineup: current.lineup)
    }

    /// Up/down while watching: -1 is the previous stream, +1 the next, wrapping around.
    func step(_ delta: Int) {
        guard let current = nowPlaying, current.lineup.count > 1 else { return }
        let index = current.lineup.firstIndex(where: { $0.id == current.channel.id }) ?? 0
        let count = current.lineup.count
        switchStream(to: current.lineup[((index + delta) % count + count) % count])
    }

    func playerTitle(_ item: NowPlaying) -> String {
        if let title = item.gameTitle { return title }
        if let p = currentProgramme(item.channel), !p.title.isEmpty { return p.title }
        return item.channel.name
    }

    var recentChannels: [Channel] {
        recentChannelIDs.compactMap { channelByID[$0] }
    }

    func closePlayer() {
        lastPlayedChannelID = nowPlaying?.channel.id
        nowPlaying = nil
        // With a mini player underneath, the stream carries on there; otherwise stop it.
        if miniPlayers == 0 || !UserDefaults.standard.bool(forKey: Prefs.guidePreview) {
            PlaybackController.shared.stop()
        }
    }

    #if os(macOS)
    func openExternally(_ channel: Channel, apps: [String] = ["com.colliderli.iina", "org.videolan.vlc"]) {
        guard let url = streamURL(for: channel, hls: false) else { return }
        for bundleID in apps {
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }
        notice = apps.count == 1
            ? "That player isn't installed on this Mac. Change the player in Settings."
            : "Neither IINA nor VLC is installed on this Mac."
    }
    #endif

    func streamURL(for channel: Channel, hls: Bool) -> URL? {
        guard let creds = credentials else { return nil }
        return XtreamClient(creds: creds).streamURL(for: channel, hls: hls)
    }
}
