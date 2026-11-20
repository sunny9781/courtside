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
    @Published var channels: [Channel] = [] { didSet { redZoneCache = nil } }
    private var redZoneCache: [Channel]?

    /// NFL RedZone channels (their name says RedZone or Red Zone), worked out once per channel list.
    func redZoneChannels() -> [Channel] {
        if let redZoneCache { return redZoneCache }
        let list = channels.filter { let n = $0.name.lowercased(); return n.contains("redzone") || n.contains("red zone") }
        redZoneCache = list
        return list
    }
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
    @Published var nowPlaying: NowPlaying? { didSet { streamsChanged() } }
    /// What the pinned player at the top is playing (iPhone/iPad and Mac). Nil hides it.
    @Published var pinned: NowPlaying? { didSet { streamsChanged() } }
    /// Mac: the pinned player is showing in its own window.
    @Published var poppedOut = false

    /// The game the pinned player's stream was started from, if any (its score shows beside the video).
    var pinnedGame: Game? {
        guard let item = pinned, let title = item.gameTitle else { return nil }
        return games.first { $0.title == title && pinnedIsFrom(gameID: $0.id) }
    }

    /// Whether the pinned player is playing one of this game's streams.
    func pinnedIsFrom(gameID: String) -> Bool {
        guard let id = pinned?.channel.id else { return false }
        return (matches[gameID] ?? []).contains { $0.channel.id == id }
    }
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
    /// Frame rates seen while playing, by channel id ("60 fps" on stream lists once a stream has been watched).
    @Published var measuredFrameRate: [Int: Double] = [:]
    /// EPG favourites, in the order they were added: channels by id, categories by id (a provider category, or a
    /// "__node:" group). Favourites are listed first.
    @Published private(set) var favoriteChannels: [Int] =
        (UserDefaults.standard.string(forKey: Prefs.favoriteChannels) ?? "").split(separator: ",").compactMap { Int($0) }
    /// Hidden categories, groups and channels (Settings › Hidden shows them again).
    @Published private(set) var hiddenChannelIDs: [Int] =
        (UserDefaults.standard.string(forKey: Prefs.hiddenChannels) ?? "").split(separator: ",").compactMap { Int($0) }
    @Published private(set) var hiddenCategoryIDs: [String] =
        (UserDefaults.standard.string(forKey: Prefs.hiddenCategories) ?? "").split(separator: "\n").map(String.init)
    /// Leagues whose games have been fetched today (a sport shown again is fetched on the next minute's update).
    private var fetchedLeagues: Set<String> = []
    @Published private(set) var favoriteCategories: [String] =
        (UserDefaults.standard.string(forKey: Prefs.favoriteCategories) ?? "").split(separator: "\n").map(String.init)

    private var indexed: [Matcher.IndexedChannel] = []
    private var scoreTask: Task<Void, Never>?
    private var accountTask: Task<Void, Never>?
    private var accountCheck: Task<Void, Never>?
    private var guideTask: Task<Void, Never>?

    init() {
        credentials = CredentialStore.load()
        PlaybackController.shared.onChange = { [weak self] in self?.checkConnectionsSoon() }
        PlaybackController.shared.onRepeatedFreezing = { [weak self] in self?.skipFrozenStream() }
        if DemoData.isOn { loadDemo() }
        let saved = UserDefaults.standard.dictionary(forKey: Prefs.measuredQuality) as? [String: String] ?? [:]
        measuredQuality = Dictionary(uniqueKeysWithValues: saved.compactMap { k, v in Int(k).map { ($0, v) } })
        let fps = UserDefaults.standard.dictionary(forKey: Prefs.measuredFrameRate) as? [String: Double] ?? [:]
        measuredFrameRate = Dictionary(uniqueKeysWithValues: fps.compactMap { k, v in Int(k).map { ($0, v) } })
    }

    /// Sample data for screenshots (`-demo`), with no network and no real login.
    private func loadDemo() {
        let d = DemoData.build()
        credentials = XtreamCredentials(server: "demo", username: "demo", password: "")
        account = AccountInfo(status: "Active", expires: Date().addingTimeInterval(86400 * 120), maxConnections: 2, activeConnections: 1)
        categories = d.categories
        categoryTree = CategoryGrouping.build(d.categories)
        channels = d.channels
        channelsByCategory = Dictionary(grouping: d.channels, by: \.categoryID)
        channelByID = Dictionary(uniqueKeysWithValues: d.channels.map { ($0.id, $0) })
        allGames = d.games
        games = d.games
        leagueLogos = d.logos
        matches = d.matches
        guide = d.guide
        savedAt = Date()
        lastRefresh = Date()
    }

    // MARK: Favourites

    func isFavorite(channel id: Int) -> Bool { favoriteChannels.contains(id) }
    func isFavorite(category id: String) -> Bool { favoriteCategories.contains(id) }

    func toggleFavorite(channel id: Int) {
        if let i = favoriteChannels.firstIndex(of: id) { favoriteChannels.remove(at: i) } else { favoriteChannels.append(id) }
        UserDefaults.standard.set(favoriteChannels.map(String.init).joined(separator: ","), forKey: Prefs.favoriteChannels)
    }

    func toggleFavorite(category id: String) {
        if let i = favoriteCategories.firstIndex(of: id) { favoriteCategories.remove(at: i) } else { favoriteCategories.append(id) }
        UserDefaults.standard.set(favoriteCategories.joined(separator: "\n"), forKey: Prefs.favoriteCategories)
    }

    /// Favourite channels that still exist, in the order added.
    var favoriteChannelList: [Channel] { favoriteChannels.compactMap { channelByID[$0] } }

    /// Favourite categories and groups that still exist, in the order added.
    var favoriteCategoryNodes: [CategoryGrouping.Node] {
        favoriteCategories.compactMap { id in
            if let node = CategoryGrouping.find(id, in: categoryTree) { return node }
            return categories.first { $0.id == id }.map { CategoryGrouping.Node(id: $0.id, name: $0.name, children: [], categories: [$0]) }
        }
    }

    /// The same channels with favourites first (otherwise in their order).
    func favoritesFirst(_ channels: [Channel]) -> [Channel] {
        guard !favoriteChannels.isEmpty else { return channels }
        return channels.filter { isFavorite(channel: $0.id) } + channels.filter { !isFavorite(channel: $0.id) }
    }

    /// The same categories or groups with favourites first.
    func favoritesFirst(_ nodes: [CategoryGrouping.Node]) -> [CategoryGrouping.Node] {
        guard !favoriteCategories.isEmpty else { return nodes }
        return nodes.filter { isFavorite(category: $0.id) } + nodes.filter { !isFavorite(category: $0.id) }
    }

    /// The sound each channel played with ("Stereo", "5.1 Dolby"), shown with its quality and frame rate.
    @Published var measuredAudio: [Int: String] = [:]

    func recordAudio(_ channelID: Int, _ label: String) {
        guard !label.isEmpty, measuredAudio[channelID] != label else { return }
        measuredAudio[channelID] = label
    }

    func recordFrameRate(_ channelID: Int, _ fps: Double) {
        guard fps > 0, measuredFrameRate[channelID] != fps else { return }
        measuredFrameRate[channelID] = fps
        let saved = Dictionary(uniqueKeysWithValues: measuredFrameRate.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(saved, forKey: Prefs.measuredFrameRate)
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

    /// Settings › Account › Edit account. The new details are checked first (nothing changes if they don't work);
    /// a different server or username starts fresh with that account's channels.
    func updateAccount(server: String, username: String, password: String) async -> String? {
        let creds = XtreamCredentials(server: server, username: username, password: password)
        let fresh: AccountInfo
        do {
            fresh = try await XtreamClient(creds: creds).login()
        } catch {
            return error.localizedDescription
        }
        let sameAccount = creds.server == credentials?.server && creds.username == credentials?.username
        if !sameAccount { signOut() }
        CredentialStore.save(creds)
        credentials = creds
        account = fresh
        if !sameAccount { await refresh(force: true) }
        return nil
    }

    func signOut() {
        scoreTask?.cancel()
        guideTask?.cancel()
        accountTask?.cancel()
        CredentialStore.delete()
        try? FileManager.default.removeItem(at: Self.guideFile)
        try? FileManager.default.removeItem(at: Self.savedGuideFile)
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
    /// The guide is downloading: how far along (0...1, nil when the provider doesn't say the size) and megabytes so far.
    @Published var guideDownloading = false
    @Published var guideProgress: Double?
    @Published var guideMegabytes = 0
    /// The download is done and the file is being read (no provider connection in use): "Reading EPG…", not 100%.
    @Published var guideReading = false
    /// A refresh waits for the stream to stop, so only one connection to the provider is ever in use.
    @Published var refreshWaiting = false
    private var channelsPending = false
    private var guidePending = false

    /// A stream is open (in the corner or full screen): downloads wait until it's closed.
    var streamOpen: Bool { pinned != nil || nowPlaying != nil }

    /// A stream started or stopped: a guide download under way pauses for it, and anything waiting starts once
    /// nothing plays.
    private func streamsChanged() {
        if streamOpen {
            // Only the download itself uses a connection; reading the file afterwards carries on.
            if guideDownloading && !guideReading {
                ConnLog.add("Paused the guide download (a stream started)")
                guideTask?.cancel()
                guidePending = true
                refreshWaiting = true
            }
            return
        }
        guard channelsPending || guidePending else { return }
        Task { @MainActor in
            // A moment for the provider to see the stream closed.
            try? await Task.sleep(for: .seconds(2))
            guard !self.streamOpen else { return }
            if self.channelsPending {
                self.channelsPending = false
                self.guidePending = false
                self.refreshWaiting = false
                await self.refresh(force: true)
            } else if self.guidePending {
                self.guidePending = false
                self.refreshWaiting = false
                self.guideTask?.cancel()
                self.guideTask = Task { await self.loadGuide(download: true) }
            }
        }
    }

    /// Everything from the provider, before Settings filters (adult categories) are applied.
    private var rawCategories: [ChannelCategory] = []
    private var rawChannels: [Channel] = []

    private func apply(categories cats: [ChannelCategory], channels list: [Channel]) async {
        rawCategories = cats
        rawChannels = list
        await applyFilters()
    }

    static func isAdult(_ name: String) -> Bool {
        name.range(of: "adult", options: .caseInsensitive) != nil
    }

    /// A category with "adult" in its name goes into Settings › Hidden the first time it's seen, like one you hid
    /// yourself: showing it again there sticks. (Someone who had the old "Adult categories" switch on keeps them.)
    private func hideNewAdultCategories() {
        let d = UserDefaults.standard
        let handled = Set((d.string(forKey: Prefs.adultHandled) ?? "").split(separator: "\n").map(String.init))
        let fresh = rawCategories.filter { Self.isAdult($0.name) && !handled.contains($0.id) }.map(\.id)
        guard !fresh.isEmpty else { return }
        if d.bool(forKey: Prefs.hideAdult) {
            for id in fresh where !hiddenCategoryIDs.contains(id) { hiddenCategoryIDs.append(id) }
            d.set(hiddenCategoryIDs.joined(separator: "\n"), forKey: Prefs.hiddenCategories)
        }
        d.set((Array(handled) + fresh).joined(separator: "\n"), forKey: Prefs.adultHandled)
    }

    /// Hides what's in Settings › Hidden everywhere (EPG, game streams). Called again when that changes.
    func applyFilters() async {
        hideNewAdultCategories()
        let hiddenCats = Set(hiddenCategoryIDs)
        let hiddenChans = Set(hiddenChannelIDs)
        let cats = rawCategories.filter { !hiddenCats.contains($0.id) }
        let kept = Set(cats.map(\.id))
        let list = rawChannels.filter { kept.contains($0.categoryID) && !hiddenChans.contains($0.id) }
        // Hidden groups ("__node:" ids) leave the tree; their categories stay wherever else they're listed.
        func prune(_ nodes: [CategoryGrouping.Node]) -> [CategoryGrouping.Node] {
            nodes.filter { !hiddenCats.contains($0.id) }.map {
                $0.isGroup ? CategoryGrouping.Node(id: $0.id, name: $0.name, children: prune($0.children), categories: $0.categories) : $0
            }
        }
        categories = cats
        categoryTree = prune(CategoryGrouping.build(cats))
        channels = list
        channelsByCategory = Dictionary(grouping: list, by: \.categoryID)
        channelByID = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        indexed = await Task.detached(priority: .userInitiated) { Matcher.index(list) }.value
    }

    /// Opening the app: channels and the guide come from the saved copy when it's recent enough
    /// (6 hours by default); scores are always fetched. `force` downloads everything now.
    func refresh(force: Bool = false) async {
        if DemoData.isOn { return }
        guard let creds = credentials, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Today's scores start downloading straight away; nothing below waits for them until step 3.
        let fetching = League.active
        async let gamesTask = ScheduleClient().schedule(for: fetching)

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

        // The saved guide right after the saved channels, so the EPG fills in without waiting for today's scores.
        if guide.isEmpty, !channels.isEmpty { await loadSavedGuide() }

        // 2. Channels from the provider only when the saved copy is too old (or you asked), and never while a stream
        // plays (that would be a second connection): then it waits until the stream stops.
        if stale && streamOpen && !channels.isEmpty {
            ConnLog.add("Waiting for the stream to stop before downloading the channels")
            channelsPending = true
            refreshWaiting = true
            stale = false
        }
        if stale {
            ConnLog.add("Downloading the channels")
            downloadingChannels = true
            defer { downloadingChannels = false; ConnLog.add("Finished the channels") }
            let client = XtreamClient(creds: creds)
            do {
                account = try await client.login()
                let (cats, list) = try await client.live()
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
            fetchedLeagues = Set(fetching.map(\.id))
            // Guide-built events (pickleball) stay put until rematch rebuilds them, so their cards don't blink.
            games = Self.visible(allGames) + games.filter { $0.id.hasPrefix("guide-") }
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

    /// Live scores every minute while a game is live or starts within 15 minutes; otherwise every 5 minutes (nothing
    /// changes then but the odd start time). Only leagues that still have games to play today.
    private func startScoreUpdates() {
        scoreTask?.cancel()
        scoreTask = Task { [weak self] in
            var last = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self else { return }
                let busy = self.allGames.contains { g in
                    g.state == .live || (g.state == .upcoming && (g.start ?? .distantFuture) < Date().addingTimeInterval(15 * 60))
                }
                if !busy && Date().timeIntervalSince(last) < 290 { continue }
                last = Date()
                // Leagues with games still to play, and any switched back on since (not fetched yet today).
                let on = League.active
                let missing = on.filter { !self.fetchedLeagues.contains($0.id) }
                let active = Set(self.allGames.filter { $0.state != .finished }.map(\.league)).union(missing)
                    .filter { on.contains($0) }
                guard !active.isEmpty else { continue }
                self.fetchedLeagues.formUnion(missing.map(\.id))
                if let fresh = try? await ScheduleClient().games(for: Array(active)) {
                    let freshIDs = Set(fresh.map(\.id))
                    let kept = self.allGames.filter { !active.contains($0.league) && !freshIDs.contains($0.id) }
                    self.allGames = (kept + fresh).sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
                    self.games = Self.visible(self.allGames) + self.games.filter { $0.id.hasPrefix("guide-") }
                    await self.rematch()
                }
            }
        }
    }

    /// Connections in use change whenever any device on the account starts or stops a stream: the count is
    /// checked when the app opens and then every minute while something plays (like the Android TV app).
    private func startAccountUpdates() {
        accountTask?.cancel()
        accountTask = Task { [weak self] in
            await self?.refreshAccount()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled else { return }
                if self.pinned != nil || self.nowPlaying != nil { await self.refreshAccount() }
            }
        }
    }

    func refreshAccount() async {
        guard !DemoData.isOn, let creds = credentials else { return }
        // The provider's own count, as it reports it (shown in Settings).
        if let fresh = try? await XtreamClient(creds: creds).login() {
            account = fresh
            ConnLog.add("Provider says \(fresh.activeConnections.map(String.init) ?? "?")/\(fresh.maxConnections.map(String.init) ?? "?") in use")
        }
    }

    /// Re-checks the count a few seconds after a stream starts or stops, once the provider has noticed.
    func checkConnectionsSoon() {
        accountCheck?.cancel()
        // Providers take a while to notice a closed stream, so checking right after flipping counts the old one
        // too (2/2 while only one plays). Each switch restarts the 20-second wait.
        accountCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            await self?.refreshAccount()
        }
    }

    func rematch() async {
        guard !DemoData.isOn else { return }   // sample data comes with its own matches
        let idx = indexed
        // Guide-built events (pickleball) are rebuilt below, so they're left out of the normal matching.
        let gs = games.filter { !$0.id.hasPrefix("guide-") }
        let gd = guide
        let extras = extraBroadcasts
        let measured = measuredQuality
        let recent = Set(recentChannelIDs)
        let now = Date()
        let result = await Task.detached(priority: .userInitiated) {
            Matcher.matchAll(games: gs, channels: idx, guide: gd, extras: extras, measured: measured, recent: recent, now: now)
        }.value
        var allMatches = result.matches

        // Sports with no schedule feed: events from the guide.
        var guideGames: [Game] = []
        for league in League.active where league.path.isEmpty {
            let found = await Task.detached(priority: .utility) {
                Matcher.guideEvents(league: league, words: [league.name.lowercased()] + Array(league.keywords), channels: idx, guide: gd,
                                    measured: measured, now: now)
            }.value
            guideGames += found.games
            allMatches.merge(found.matches) { _, new in new }
        }
        if !guideGames.isEmpty || games.contains(where: { $0.id.hasPrefix("guide-") }) {
            games = (gs + guideGames).sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
        }
        matches = allMatches
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
        let on = Set(League.active.map(\.id))
        return list.filter { on.contains($0.league.id) }
    }

    /// A sport or league was hidden or shown: hidden ones are switched off (not fetched, not matched); one shown
    /// again is fetched straight away.
    func sportsChanged() {
        games = Self.visible(allGames) + games.filter { $0.id.hasPrefix("guide-") && League.active.contains($0.league) }
        let missing = League.active.filter { !fetchedLeagues.contains($0.id) && !$0.path.isEmpty }
        Task {
            if !missing.isEmpty, let fresh = try? await ScheduleClient().games(for: missing) {
                fetchedLeagues.formUnion(missing.map(\.id))
                let ids = Set(fresh.map(\.id))
                allGames = (allGames.filter { !ids.contains($0.id) } + fresh).sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
                games = Self.visible(allGames) + games.filter { $0.id.hasPrefix("guide-") }
            }
            await rematch()
        }
    }

    // MARK: Hidden categories and channels

    func setChannelHidden(_ id: Int, _ hidden: Bool) {
        hiddenChannelIDs.removeAll { $0 == id }
        if hidden { hiddenChannelIDs.append(id) }
        UserDefaults.standard.set(hiddenChannelIDs.map(String.init).joined(separator: ","), forKey: Prefs.hiddenChannels)
        Task { await applyFilters(); await rematch() }
    }

    func setCategoryHidden(_ id: String, _ hidden: Bool) {
        hiddenCategoryIDs.removeAll { $0 == id }
        if hidden { hiddenCategoryIDs.append(id) }
        UserDefaults.standard.set(hiddenCategoryIDs.joined(separator: "\n"), forKey: Prefs.hiddenCategories)
        Task { await applyFilters(); await rematch() }
    }

    /// Hidden channels with their names, in the order hidden.
    var hiddenChannelNames: [(id: Int, name: String)] {
        let byID = Dictionary(rawChannels.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return hiddenChannelIDs.map { ($0, byID[$0] ?? "Channel \($0)") }
    }

    /// Hidden categories and groups with their names ("Sports › 4K" for a group).
    var hiddenCategoryNames: [(id: String, name: String)] {
        let byID = Dictionary(rawCategories.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return hiddenCategoryIDs.map { id in
            (id, byID[id] ?? String(id.dropFirst(CategoryGrouping.nodePrefix.count)).replacingOccurrences(of: "/", with: " › "))
        }
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

    /// The small saved guide: only the programmes the app shows, already read, so opening the app doesn't have to
    /// read the provider's whole XMLTV file again. Kept next to channels.json.
    nonisolated static var savedGuideFile: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("Courtside", isDirectory: true).appendingPathComponent("guide.json")
    }

    private struct SavedGuide: Codable {
        let savedAt: Date
        let programmes: [String: [Programme]]
    }

    /// From an hour ago to the end of what Settings shows ahead.
    private var guideWindow: (from: Date, to: Date) {
        let hours = Double(max(UserDefaults.standard.integer(forKey: Prefs.guideHours), 2))
        return (Date().addingTimeInterval(-3600), Date().addingTimeInterval(hours * 3600))
    }

    /// The saved copy also covers the time until the next refresh, so it's still complete when the app reopens later.
    private var savedGuideEnd: Date { guideWindow.to.addingTimeInterval(refreshInterval) }

    nonisolated private static func trimmed(_ all: [String: [Programme]], wanted: Set<String>,
                                            from: Date, to: Date) -> [String: [Programme]] {
        var out: [String: [Programme]] = [:]
        for (id, list) in all where wanted.contains(id) {
            let kept = list.filter { $0.start < to && $0.end > from }
            if !kept.isEmpty { out[id] = kept }
        }
        return out
    }

    nonisolated private static func writeSavedGuide(_ programmes: [String: [Programme]], savedAt: Date) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(SavedGuide(savedAt: savedAt, programmes: programmes)) else { return false }
        try? FileManager.default.createDirectory(at: savedGuideFile.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        return (try? data.write(to: savedGuideFile, options: .atomic)) != nil
    }

    /// Shows the saved guide (no download). Returns false when there's none to show.
    @discardableResult
    private func loadSavedGuide() async -> Bool {
        let wanted = Set(channels.map(\.epgID).filter { !$0.isEmpty })
        guard !wanted.isEmpty else { return false }
        let (from, to) = guideWindow
        let end = savedGuideEnd
        let json = Self.savedGuideFile
        let xml = Self.guideFile
        let loaded: (guide: [String: [Programme]], savedAt: Date?)? = await Task.detached(priority: .userInitiated) {
            if let data = try? Data(contentsOf: json) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                if let saved = try? decoder.decode(SavedGuide.self, from: data) {
                    return (Self.trimmed(saved.programmes, wanted: wanted, from: from, to: to), saved.savedAt)
                }
            }
            // Older versions kept only the provider's whole file: read it this once and save the small copy.
            guard FileManager.default.fileExists(atPath: xml.path),
                  let all = try? XtreamClient.parseGuide(file: xml, wanted: wanted, from: from, to: end) else { return nil }
            let date = (try? xml.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if Self.writeSavedGuide(all, savedAt: date ?? Date()) { try? FileManager.default.removeItem(at: xml) }
            return (Self.trimmed(all, wanted: wanted, from: from, to: to), date)
        }.value
        // A download that finished in the meantime is newer: keep it.
        guard let loaded, !loaded.guide.isEmpty, guide.isEmpty else { return false }
        guide = loaded.guide
        guideUpdated = loaded.savedAt
        await rematch()
        return true
    }

    /// Shows the saved guide instantly, and downloads a fresh one when asked or when there's no saved guide.
    func loadGuide(download: Bool = true) async {
        guard let creds = credentials else { return }
        let wanted = Set(channels.map(\.epgID).filter { !$0.isEmpty })
        guard !wanted.isEmpty else {
            guideStatus = "Your provider doesn't link its channels to a guide."
            return
        }
        if guide.isEmpty { await loadSavedGuide() }
        if !download && !guide.isEmpty { return }   // the saved guide is recent enough

        if streamOpen {
            ConnLog.add("Waiting for the stream to stop before downloading the guide")
            guidePending = true
            refreshWaiting = true
            return
        }
        let (from, to) = guideWindow
        let end = savedGuideEnd
        let file = Self.guideFile
        guideStatus = "Updating the guide…"
        ConnLog.add("Downloading the guide")
        guideDownloading = true
        guideProgress = nil
        guideMegabytes = 0
        guideReading = false
        defer { guideDownloading = false; guideReading = false }
        do {
            try await XtreamClient(creds: creds).downloadGuide(to: file) { read, total in
                Task { @MainActor [weak self] in
                    self?.guideMegabytes = Int(read / 1_048_576)
                    self?.guideProgress = total > 0 ? min(1, Double(read) / Double(total)) : nil
                }
            }
            guideReading = true
            ConnLog.add("Downloaded the guide; reading it")
            let fresh = try await Task.detached(priority: .utility) { () throws -> [String: [Programme]] in
                let all = try XtreamClient.parseGuide(file: file, wanted: wanted, from: from, to: end)
                // Keep only the small copy: the provider's file is large and only needed once.
                if Self.writeSavedGuide(all, savedAt: Date()) { try? FileManager.default.removeItem(at: file) }
                return Self.trimmed(all, wanted: wanted, from: from, to: to)
            }.value
            ConnLog.add("Finished the guide")
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

    /// Recently watched channels rank higher next time the streams are matched. The list isn't re-sorted
    /// straight away, so streams don't jump around while you tap through them.
    private func remember(_ id: Int) {
        recentChannelIDs = [id] + recentChannelIDs.filter { $0 != id }
    }

    /// The lineup is what up/down flips through while watching.
    func play(_ channel: Channel, gameTitle: String? = nil, lineup: [Channel] = []) {
        // Mac: while the player has its own window, "watch" plays it there and leaves the app alone.
        if poppedOut {
            pin(channel, gameTitle: gameTitle, lineup: lineup)
            return
        }
        remember(channel.id)
        nowPlaying = NowPlaying(channel: channel, gameTitle: gameTitle, lineup: lineup.isEmpty ? [channel] : lineup)
    }

    /// Plays a stream in the pinned player at the top.
    func pin(_ channel: Channel, gameTitle: String? = nil, lineup: [Channel] = []) {
        remember(channel.id)
        pinned = NowPlaying(channel: channel, gameTitle: gameTitle, lineup: lineup.isEmpty ? [channel] : lineup)
    }

    /// Previous/next stream in the pinned player.
    func stepPinned(_ delta: Int) {
        guard let current = pinned, current.lineup.count > 1 else { return }
        let index = current.lineup.firstIndex(where: { $0.id == current.channel.id }) ?? 0
        let count = current.lineup.count
        let next = current.lineup[((index + delta) % count + count) % count]
        remember(next.id)
        pinned = NowPlaying(channel: next, gameTitle: current.gameTitle, lineup: current.lineup)
    }

    func switchStream(to channel: Channel) {
        guard let current = nowPlaying, channel.id != current.channel.id else { return }
        remember(channel.id)
        nowPlaying = NowPlaying(channel: channel, gameTitle: current.gameTitle, lineup: current.lineup)
    }

    /// Up/down while watching: -1 is the previous stream, +1 the next, wrapping around.
    /// The stream kept freezing even after restarting it: say so and move to the next one (full screen or the
    /// player at the top), if there is one.
    func skipFrozenStream() {
        if let current = nowPlaying {
            guard current.lineup.count > 1 else {
                notice = "\(current.channel.name) keeps freezing. Try another channel."
                return
            }
            step(1)
            notice = "\(current.channel.name) kept freezing, so this is the next stream"
        } else if let current = pinned {
            guard current.lineup.count > 1 else {
                notice = "\(current.channel.name) keeps freezing. Try another channel."
                return
            }
            stepPinned(1)
            notice = "\(current.channel.name) kept freezing, so this is the next stream"
        }
    }

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
        let closing = nowPlaying
        nowPlaying = nil
        // The stream you were last on carries on in the pinned player.
        if let closing {
            pinned = closing
            return
        }
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

    /// Apple TV: whether to play a channel with the HDR player (KSPlayer: FFmpeg reads the same TS stream VLC would,
    /// VideoToolbox decodes, HDR10 / HLG / Dolby Vision reach the TV as HDR). VLCKit 3 turns HDR into a dark standard
    /// picture. 4K channels only; on by default, Settings › Playback can turn it off.
    func wantsHDRPlayer(_ channel: Channel) -> Bool {
        #if os(tvOS)
        guard PlaybackController.hasHDRPlayer,
              UserDefaults.standard.object(forKey: Prefs.hdrPlayerFor4K) as? Bool ?? true else { return false }
        return CategoryGrouping.isUHD(channel.name) || CategoryGrouping.isUHD(channel.categoryName)
            || measuredQuality[channel.id] == "4K"
        #else
        return false
        #endif
    }

    /// Starts `channel` on the shared player: the HDR player for 4K on Apple TV (VLC if it shows nothing), VLC
    /// otherwise. Both read the same TS stream, so the provider only ever sees one connection.
    func startStream(_ channel: Channel, on controller: PlaybackController, bufferMs: Int) {
        guard let url = streamURL(for: channel, hls: !PlaybackController.usesVLC) else { return }
        controller.play(url, bufferMs: bufferMs, hdrPlayer: wantsHDRPlayer(channel))
    }

    func streamURL(for channel: Channel, hls: Bool) -> URL? {
        guard let creds = credentials else { return nil }
        return XtreamClient(creds: creds).streamURL(for: channel, hls: hls)
    }
}
