import SwiftUI

/// EPG, laid out like the Mac guide: categories down the left (grouped), the mini player and what's on at the
/// top, and the channels with what's on now and next below. Moving onto a channel previews it; clicking it
/// goes full screen, where up/down flips through the category.
struct TVLiveView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.guideCategory) private var selectedID = ""
    @AppStorage(Prefs.guideGrouped) private var grouped = true
    /// The groups you've opened in the category list (ids, outermost first).
    @State private var path: [String] = []
    /// The channel playing in the mini player: only one you clicked.
    @FocusState private var focusedCategory: String?
    @State private var search = ""
    @State private var hits: [EPGSearch.Hit] = []
    /// Result groups opened or closed by hand (otherwise they follow Hit.startsOpen).
    @State private var flipped: Set<String> = []
    @FocusState private var focusedChannel: Int?

    struct Entry: Identifiable, Hashable {
        let id: String
        let name: String
        let categories: [ChannelCategory]
    }


    /// Every provider category (or merged group of them) you can pick, at any depth.
    private var allEntries: [Entry] {
        guard grouped else {
            return model.categories
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { Entry(id: $0.id, name: $0.name, categories: [$0]) }
        }
        func leaves(_ nodes: [CategoryGrouping.Node]) -> [Entry] {
            nodes.flatMap { $0.isGroup ? leaves($0.children) : [Entry(id: $0.id, name: $0.name, categories: $0.categories)] }
        }
        return leaves(model.categoryTree)
    }

    /// The groups you've opened, outermost first ("Country", then "Foreign").
    private var openNodes: [CategoryGrouping.Node] {
        var out: [CategoryGrouping.Node] = []
        var level = model.categoryTree
        for id in path {
            guard let node = level.first(where: { $0.id == id }) else { break }
            out.append(node)
            level = node.children
        }
        return out
    }

    /// What the left column lists right now: the top level, or the inside of the open group.
    private var levelNodes: [CategoryGrouping.Node] {
        openNodes.last?.children ?? model.categoryTree
    }

    /// "Favourites" at the top of the list: your favourite channels from every category.
    private static let favoritesID = "fav"

    private var selected: Entry? {
        if selectedID == Self.favoritesID, !model.favoriteChannels.isEmpty {
            return Entry(id: Self.favoritesID, name: "Favourites", categories: [])
        }
        if selectedID.hasPrefix("g:"), let node = CategoryGrouping.find(String(selectedID.dropFirst(2)), in: model.categoryTree) {
            return Entry(id: selectedID, name: node.name, categories: node.categories)
        }
        return allEntries.first { $0.id == selectedID } ?? allEntries.first
    }

    /// The row to land on when coming down from the tabs: the selected category if it's showing, otherwise the
    /// first row of the list.
    private var categoryTarget: String? {
        if path.isEmpty, let id = selected?.id,
           id == Self.favoritesID || favoriteEntries.contains(where: { $0.id == id }) { return id }
        guard grouped else { return selected?.id }
        if let id = selected?.id, levelNodes.contains(where: { ($0.isGroup ? "g:" + $0.id : $0.id) == id }) { return id }
        guard let first = levelNodes.first else { return nil }
        return first.isGroup ? "g:" + first.id : first.id
    }

    private func channelCount(_ categories: [ChannelCategory]) -> Int {
        categories.reduce(0) { $0 + (model.channelsByCategory[$1.id]?.count ?? 0) }
    }

    private var channels: [Channel] {
        guard let selected else { return [] }
        if selected.id == Self.favoritesID { return model.favoriteChannelList }
        return model.favoritesFirst(selected.categories.flatMap { model.channelsByCategory[$0.id] ?? [] })
    }

    /// Favourite categories and groups, shown first at the top of the list (a group shows all its channels).
    private var favoriteEntries: [Entry] {
        model.favoriteCategoryNodes.map { node in
            Entry(id: node.isGroup ? "g:" + node.id : node.id, name: node.name, categories: node.categories)
        }
    }

    /// What the mini player plays: the channel you clicked, or what's still playing from Home.
    private var playingChannel: Channel? { model.pinned?.channel }

    var body: some View {
        if model.channels.isEmpty {
            VStack(spacing: 20) {
                if model.isLoading || model.downloadingChannels { ProgressView() }
                Text(model.downloadingChannels || model.guideDownloading ? "Refreshing EPG…" : (model.errorMessage ?? "No channels yet."))
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 50) {
                // Categories on top of the player in the bottom-left corner (what's playing is in the bar along the
                // bottom); the schedule starts at the top.
                categoryList
                    .focusSection()
                    .frame(width: TVLayout.sidebar)
                .padding(.bottom, model.pinned != nil ? TVLayout.playerInset : TVLayout.margin)
                channelList
                    .focusSection()
            }
            .padding(.horizontal, TVLayout.margin)
            // Pressing down from Home / EPG / Settings starts on the category list.
            .defaultFocus($focusedCategory, categoryTarget, priority: .userInitiated)
            .onChange(of: focusedCategory) {
                // Moving onto a category shows its channels; moving onto a group ("g:" ids) shows all of the group's
                // channels, and clicking it opens it.
                if let focusedCategory, focusedCategory != selectedID {
                    selectedID = focusedCategory
                }
            }
            // Back from full screen: focus goes back to the channel you were watching, not up to the tabs.
            .onChange(of: model.nowPlaying == nil) {
                guard model.nowPlaying == nil, let id = model.lastPlayedChannelID else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    focusedChannel = id
                }
            }
            // The remote's keyboard hands the text over when you press Done, so search right away.
            .onChange(of: search) { runSearch() }
            .onChange(of: grouped) { runSearch() }
            .onAppear { runSearch() }
        }
    }

    // MARK: Categories

    private var categoryList: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 4) {
                // One search for categories and channels; results show on the right.
                TextField("Filter", text: $search)
                    .font(.system(size: 24))
                    // Done on the keyboard goes to the first result.
                    .onSubmit {
                        runSearch()
                        if let first = hits.first?.channels.first?.id {
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(150))
                                focusedChannel = first
                            }
                        }
                    }
                    .padding(.bottom, 6)
                Button {
                    grouped.toggle()
                    path = []
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 22))
                        Text("Auto-Group")
                            .font(.system(size: 22, weight: .medium))
                        Spacer()
                        Text(grouped ? "On" : "Off")
                            .font(.system(size: 21, weight: .semibold))
                            .opacity(0.75)
                    }
                }
                .buttonStyle(TVRowButtonStyle())
                .padding(.bottom, 6)

                // Favourites first (hold the select button on a category or channel to add or remove one).
                if path.isEmpty {
                    if !model.favoriteChannels.isEmpty {
                        categoryRow(Entry(id: Self.favoritesID, name: "Favourites", categories: []),
                                    count: model.favoriteChannelList.count, symbol: "heart.fill")
                    }
                    ForEach(favoriteEntries) { entry in
                        categoryRow(entry)
                    }
                    if !favoriteEntries.isEmpty || !model.favoriteChannels.isEmpty {
                        Rectangle().fill(Theme.raised).frame(height: 2).padding(.horizontal, 16).padding(.vertical, 8)
                    }
                }
                if grouped {
                    // Groups first: click one to open it, Back (or the top row) to go up a level.
                    if !path.isEmpty {
                        Button {
                            path.removeLast()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 20, weight: .semibold))
                                Text(openNodes.map(\.name).joined(separator: " › "))
                                    .font(.system(size: 24, weight: .bold))
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                        .buttonStyle(TVRowButtonStyle())
                    }
                    // At the top, favourites are already listed above; inside a group they come first.
                    ForEach(path.isEmpty ? levelNodes.filter { !model.isFavorite(category: $0.id) }
                                         : model.favoritesFirst(levelNodes)) { node in
                        if node.isGroup {
                            Button {
                                path.append(node.id)
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 20))
                                        .opacity(0.7)
                                    Text(node.name)
                                        .font(.system(size: 24, weight: .semibold))
                                        .lineLimit(1)
                                    if model.isFavorite(category: node.id) {
                                        Image(systemName: "heart.fill").font(.system(size: 18)).foregroundStyle(Theme.accent)
                                    }
                                    Spacer(minLength: 8)
                                    Text("\(node.categories.count)")
                                        .font(.system(size: 19))
                                        .opacity(0.55)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 18, weight: .semibold))
                                        .opacity(0.6)
                                }
                            }
                            .buttonStyle(TVRowButtonStyle(selected: selected?.id == "g:" + node.id))
                            .focused($focusedCategory, equals: "g:" + node.id)
                            .contextMenu { favoriteButton(category: node.id); hideButton(category: node.id, name: node.name) }
                        } else {
                            categoryRow(Entry(id: node.id, name: node.name, categories: node.categories))
                        }
                    }
                } else {
                    ForEach(allEntries.filter { !model.isFavorite(category: $0.id) }) { entry in
                        categoryRow(entry)
                    }
                }
            }
            .padding(.vertical, 20)
        }
        // Use the full width: no Apple TV side insets on top of our own small margin.
        .ignoresSafeArea(.container, edges: .horizontal)
        .onExitCommand(perform: path.isEmpty ? nil : { path.removeLast() })
    }

    private func categoryRow(_ entry: Entry, count: Int? = nil, symbol: String? = nil) -> some View {
        let key = entry.id.hasPrefix("g:") ? String(entry.id.dropFirst(2)) : entry.id
        let favorite = entry.id != Self.favoritesID && model.isFavorite(category: key)
        return Button {
            selectedID = entry.id
        } label: {
            HStack(spacing: 14) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(Theme.accent)
                }
                Text(entry.name)
                    .font(.system(size: 24, weight: .medium))
                    .lineLimit(1)
                if favorite {
                    Image(systemName: "heart.fill").font(.system(size: 18)).foregroundStyle(Theme.accent)
                }
                Spacer(minLength: 8)
                Text("\(count ?? channelCount(entry.categories))")
                    .font(.system(size: 19))
                    .opacity(0.55)
            }
        }
        .buttonStyle(TVRowButtonStyle(selected: entry.id == selected?.id))
        .focused($focusedCategory, equals: entry.id)
        .contextMenu {
            if entry.id != Self.favoritesID {
                favoriteButton(category: key)
                hideButton(category: key, name: entry.name)
            }
        }
    }

    /// Hold the select button on a row: add it to favourites (listed first), or take it off.
    private func favoriteButton(category id: String) -> some View {
        let on = model.isFavorite(category: id)
        return Button(on ? "Remove from Favourites" : "Add to Favourites", systemImage: on ? "heart.slash" : "heart") {
            model.toggleFavorite(category: id)
        }
    }

    /// Hold the select button on a row: hide it (Settings › Hidden shows it again).
    private func hideButton(category id: String, name: String) -> some View {
        Button("Hide", systemImage: "eye.slash") {
            if model.isFavorite(category: id) { model.toggleFavorite(category: id) }
            model.setCategoryHidden(id, true)
            model.notice = "\(name) is hidden. Settings › Hidden brings it back."
        }
    }

    private func hideButton(channel: Channel) -> some View {
        Button("Hide", systemImage: "eye.slash") {
            if model.isFavorite(channel: channel.id) { model.toggleFavorite(channel: channel.id) }
            model.setChannelHidden(channel.id, true)
            model.notice = "\(channel.name) is hidden. Settings › Hidden brings it back."
        }
    }

    private func favoriteButton(channel id: Int) -> some View {
        let on = model.isFavorite(channel: id)
        return Button(on ? "Remove from Favourites" : "Add to Favourites", systemImage: on ? "heart.slash" : "heart") {
            model.toggleFavorite(channel: id)
        }
    }

    // MARK: Channels

    private var channelList: some View {
        // Redrawn every minute so the time line and the guide's start move along.
        TimelineView(.everyMinute) { context in
            let now = context.date
            let start = TVGuide.windowStart(now)
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    TVGuideHeader(title: searching ? "Results for \u{201C}\(search.trimmingCharacters(in: .whitespaces))\u{201D}" : (selected?.name ?? ""),
                                  start: start, now: now)
                    if searching {
                        searchResults(start: start, now: now)
                    }
                    ForEach(searching ? [] : channels) { channel in
                        guideButton(channel, lineup: channels, start: start, now: now)
                    }
                }
                .padding(.vertical, 10)
            }
            // Use the full width: no Apple TV side insets on top of our own small margin.
            .ignoresSafeArea(.container, edges: .horizontal)
            // Runs to the bottom of the screen, under the now-playing bar (the last row can scroll clear of it).
            .contentMargins(.bottom, model.pinned != nil ? TVLayout.barHeight + TVLayout.margin : TVLayout.margin, for: .scrollContent)
        }
    }

    /// A channel in the guide: the first click previews it in the corner, a second click goes full screen.
    private func guideButton(_ channel: Channel, lineup: [Channel], start: Date, now: Date) -> some View {
        Button {
            if channel.id == playingChannel?.id {
                model.play(channel, lineup: lineup)
            } else {
                model.pin(channel, lineup: lineup)
            }
        } label: {
            TVGuideRow(channel: channel, playing: channel.id == playingChannel?.id, start: start, now: now)
        }
        .buttonStyle(TVGuideButtonStyle())
        .focused($focusedChannel, equals: channel.id)
        .contextMenu { favoriteButton(channel: channel.id); hideButton(channel: channel) }
    }

    private var searching: Bool { search.trimmingCharacters(in: .whitespaces).count >= 2 }

    private func runSearch() {
        hits = searching ? EPGSearch.run(search, model: model, grouped: grouped) : []
        flipped = []
    }

    private func isOpen(_ hit: EPGSearch.Hit) -> Bool {
        hit.startsOpen(totalHits: hits.count) != flipped.contains(hit.id)
    }

    /// Search results: a header per category (click to fold it), then its matching channels.
    @ViewBuilder
    private func searchResults(start: Date, now: Date) -> some View {
        if hits.isEmpty {
            Text("Nothing matches \"\(search)\".")
                .font(.system(size: 24))
                .foregroundStyle(Theme.muted)
                .padding(22)
        }
        ForEach(hits) { hit in
            Button {
                if flipped.contains(hit.id) { flipped.remove(hit.id) } else { flipped.insert(hit.id) }
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: isOpen(hit) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.category.name).font(.system(size: 24, weight: .bold)).lineLimit(1)
                        if !hit.path.isEmpty {
                            Text(hit.path).font(.system(size: 18)).opacity(0.6).lineLimit(1)
                        }
                    }
                    Spacer()
                    Text("\(hit.channels.count)").font(.system(size: 20)).opacity(0.6)
                }
            }
            .buttonStyle(TVRowButtonStyle())
            if isOpen(hit) {
                ForEach(hit.channels) { channel in
                    guideButton(channel, lineup: hit.channels, start: start, now: now)
                }
            }
        }
    }
}

/// A channel row in the EPG: logo and name, what's on now (with progress), and what's next.
struct TVChannelRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.isFocused) private var focused
    let channel: Channel
    var playing = false
    /// The stream's quality (4K, 1080p…), on the game screen.
    var badge: String? = nil
    /// A set width for the name keeps it on one line (the game screen); otherwise it can wrap onto two.
    var nameWidth: CGFloat? = nil
    /// The EPG shows what's next; the game screen and channel sports show the stream's tags there instead.
    var showNext = true

    var body: some View {
        let now = model.currentProgramme(channel)
        let next = showNext ? now.flatMap { n in model.guide[channel.epgID]?.first { $0.start >= n.end } } : nil
        let quality = (badge?.isEmpty == false ? badge : nil) ?? model.measuredQuality[channel.id]
        let fps = model.measuredFrameRate[channel.id] ?? 0
        let sound = model.measuredAudio[channel.id]
        // Fixed columns on every screen (channel, now, next), one line each; on the row you're on, text that doesn't
        // fit scrolls inside its column.
        HStack(spacing: 0) {
            HStack(spacing: 16) {
                TVChannelIcon(url: channel.icon, size: 48)
                TVScrollingText(text: channel.name, font: .system(size: 23, weight: .semibold), active: focused)
                    .foregroundStyle(playing && !focused ? Theme.accent : (focused ? Theme.bg : Theme.text))
                if playing {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(focused ? Theme.bg : Theme.accent)
                }
                if model.isFavorite(channel: channel.id) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(width: Self.channelWidth, alignment: .leading)
            .clipped()

            VStack(alignment: .leading, spacing: 6) {
                TVScrollingText(text: now?.title ?? "–", font: .system(size: 22, weight: .medium), active: focused)
                if let now {
                    ProgressView(value: progress(now))
                }
            }
            .padding(.horizontal, 24)
            // Up to its full width, narrower where the screen has less room (the game screen), so a row never runs
            // off the screen.
            .frame(minWidth: 0, maxWidth: Self.nowWidth, alignment: .leading)

            if showNext {
                TVScrollingText(text: next.map { "\($0.start.formatted(date: .omitted, time: .shortened))  \($0.title)" } ?? "",
                                font: .system(size: 21), active: focused)
                    .opacity(0.65)
                    .padding(.trailing, 24)
                    .frame(width: Self.nextWidth, alignment: .leading)
            }
            // What it really played at, once it has (resolution, frame rate, sound).
            HStack(spacing: 8) {
                if let quality, !quality.isEmpty {
                    TVBadge(text: quality, fill: quality == "4K" ? Theme.accent : Theme.raised,
                            color: quality == "4K" ? Theme.onAccent : Theme.soft)
                }
                if fps > 0 { TVBadge(text: PlaybackController.fpsLabel(fps)) }
                if let sound { TVBadge(text: sound) }
            }
            .fixedSize()
            Spacer(minLength: 0)
        }
    }

    /// The same column widths on every screen: channel (with its logo), what's on now, what's next.
    static let channelWidth: CGFloat = 420
    static let nowWidth: CGFloat = 580
    static let nextWidth: CGFloat = 420

    private func progress(_ p: Programme) -> Double {
        let total = p.end.timeIntervalSince(p.start)
        guard total > 0 else { return 0 }
        return min(max(Date().timeIntervalSince(p.start) / total, 0), 1)
    }
}

// MARK: Timeline guide

/// The EPG's timeline: a channel column on the left, then two and a half hours of programmes laid out by time,
/// coloured by sport, with a line at the current time. The row you're on opens up to two lines.
enum TVGuide {
    static let channelWidth: CGFloat = 220
    static let span: TimeInterval = 150 * 60
    static let rowHeight: CGFloat = 92
    static let gap: CGFloat = 8

    /// The guide starts at the last half hour, so up to 30 minutes of what's on is behind the line.
    static func windowStart(_ now: Date) -> Date {
        let t = now.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (t / 1800).rounded(.down) * 1800)
    }

    /// A shade per sport (white text reads on all of them).
    static func fill(_ sport: Sport) -> Color {
        switch sport {
        case .basketball: return Color(hex: 0x8A4214)
        case .hockey: return Color(hex: 0x22508F)
        case .football: return Color(hex: 0x267040)
        case .soccer: return Color(hex: 0x177375)
        case .motorsport: return Color(hex: 0x8A2532)
        case .cricket: return Color(hex: 0x75600F)
        case .baseball: return Color(hex: 0x76305A)
        case .fighting: return Color(hex: 0x6A4A2E)
        case .tennis: return Color(hex: 0x557018)
        case .golf: return Color(hex: 0x3A6430)
        case .rugby: return Color(hex: 0x52408A)
        case .aussieRules: return Color(hex: 0x7A5016)
        case .lacrosse: return Color(hex: 0x2E5F7A)
        case .pickleball: return Color(hex: 0x687A16)
        }
    }

    /// Channels whose sport can't be told still get a colour of their own (the same one every time), like UHF.
    private static let channelFills: [UInt32] = [0x5B3A8C, 0x2C5D8A, 0x7A3B5E, 0x2F6F6A, 0x6E5320, 0x3E5C2E, 0x803A2A, 0x46508A]

    @MainActor static func fill(title: String, channel: Channel, games: [Game]) -> Color {
        if let s = sport(title: title, channel: channel, games: games) { return fill(s) }
        var h: UInt32 = 5381
        for b in channel.name.utf8 { h = (h &* 33) &+ UInt32(b) }
        return Color(hex: channelFills[Int(h % UInt32(channelFills.count))])
    }

    private static let words: [(Sport, [String])] = [
        (.basketball, ["nba", "wnba", "basketball", "ncaab", "euroleague", "march madness"]),
        (.hockey, ["nhl", "hockey", "hockey night", "ahl", "ohl", "whl", "khl", "stanley cup"]),
        (.football, ["nfl", "cfl", "ncaaf", "college football", "super bowl", "redzone", "red zone", "grey cup"]),
        (.baseball, ["mlb", "baseball", "world series"]),
        (.soccer, ["soccer", "epl", "premier league", "champions league", "europa league", "conference league", "la liga",
                   "laliga", "serie a", "bundesliga", "ligue 1", "mls", "uefa", "fifa", "fa cup", "world cup", "eredivisie"]),
        (.fighting, ["ufc", "boxing", "mma", "wwe", "aew", "pfl", "fight night"]),
        (.tennis, ["tennis", "atp", "wta", "wimbledon"]),
        (.motorsport, ["f1", "formula 1", "formula one", "nascar", "indycar", "motogp", "grand prix", "motorsport"]),
        (.golf, ["golf", "pga", "lpga"]),
        (.rugby, ["rugby", "six nations", "urc"]),
        (.aussieRules, ["afl"]),
        (.lacrosse, ["lacrosse", "nll", "pll"]),
        (.cricket, ["cricket", "ipl", "bbl", "t20", "odi", "test match", "psl"]),
        (.pickleball, ["pickleball", "ppa"])
    ]

    @MainActor private static var cache: [String: Sport?] = [:]

    /// The sport a programme is about: from its title (league or sport words, or a team playing today), else the
    /// channel's name ("NBA TV"), else the channel's category ("USA | NHL").
    @MainActor static func sport(title: String, channel: Channel, games: [Game]) -> Sport? {
        if let hit = guess(title) { return hit }
        if let hit = team(title, games: games) { return hit }
        if let hit = guess(channel.name) { return hit }
        return guess(channel.categoryName)
    }

    @MainActor private static var teams: [String: Sport] = [:]
    @MainActor private static var teamsFrom = -1
    @MainActor private static var teamCache: [String: Sport?] = [:]

    /// Team names from the scoreboard ("raptors", "toronto raptors") and their sport; a nickname two sports share
    /// ("kings", "panthers") is left out.
    @MainActor private static func team(_ title: String, games: [Game]) -> Sport? {
        if teamsFrom != games.count {
            var map: [String: Sport] = [:]
            var clash: Set<String> = []
            for g in games where !g.isEvent {
                for t in [g.away, g.home] {
                    for n in [t.name, t.nickname, t.shortName] {
                        let key = normalized(n).trimmingCharacters(in: .whitespaces)
                        guard key.count >= 4 else { continue }
                        if let had = map[key], had != g.league.sport { clash.insert(key) }
                        map[key] = g.league.sport
                    }
                }
            }
            for k in clash { map[k] = nil }
            teams = map
            teamsFrom = games.count
            teamCache = [:]
        }
        if let hit = teamCache[title] { return hit }
        let clean = normalized(title)
        let found = teams.first { clean.contains(" \($0.key) ") }?.value
        if teamCache.count > 4000 { teamCache.removeAll() }
        teamCache[title] = found
        return found
    }

    /// Lower case, letters and digits only, single spaces, with a space at each end (so whole words match).
    private static func normalized(_ text: String) -> String {
        let letters = String(text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " })
        return " " + letters.split(separator: " ").joined(separator: " ") + " "
    }

    @MainActor private static func guess(_ text: String) -> Sport? {
        if let hit = cache[text] { return hit }
        let clean = normalized(text)
        let found = words.first { entry in entry.1.contains { clean.contains(" \($0) ") } }?.0
        if cache.count > 4000 { cache.removeAll() }
        cache[text] = found
        return found
    }

    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    static func left(_ seconds: TimeInterval) -> String {
        let m = max(Int(seconds / 60), 0)
        return m >= 60 ? "\(m / 60)h \(m % 60)m left" : "\(m)m left"
    }
}

/// Times along the top of the guide, with the current time in a pill over the line.
struct TVGuideHeader: View {
    let title: String
    let start: Date
    let now: Date

    var body: some View {
        HStack(spacing: TVGuide.gap) {
            Text(title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .frame(width: TVGuide.channelWidth, alignment: .leading)
            GeometryReader { geo in
                let perSecond = geo.size.width / TVGuide.span
                ZStack(alignment: .topLeading) {
                    ForEach(0..<5, id: \.self) { i in
                        Text(TVGuide.time(start.addingTimeInterval(Double(i) * 1800)))
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .offset(x: CGFloat(i) * 1800 * perSecond)
                    }
                    Text(now.formatted(date: .omitted, time: .shortened).replacingOccurrences(of: " AM", with: "")
                        .replacingOccurrences(of: " PM", with: ""))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.accent))
                        .fixedSize()
                        .offset(x: now.timeIntervalSince(start) * perSecond - 28, y: -2)
                }
            }
        }
        .frame(height: 30)
        .padding(.bottom, 4)
    }
}

/// One channel in the timeline guide. The row you're on opens up: two lines per programme, time left on what's
/// on now, and the stream's tags under the channel's name.
struct TVGuideRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.isFocused) private var focused
    let channel: Channel
    var playing = false
    let start: Date
    let now: Date

    var body: some View {
        let end = start.addingTimeInterval(TVGuide.span)
        let programmes = (model.guide[channel.epgID] ?? []).filter { $0.end > start && $0.start < end }
        HStack(spacing: TVGuide.gap) {
            tile
            GeometryReader { geo in
                let perSecond = geo.size.width / TVGuide.span
                ZStack(alignment: .topLeading) {
                    if programmes.isEmpty {
                        Text("No guide information")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 16)
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                    }
                    ForEach(programmes, id: \.self) { p in
                        cell(p, perSecond: perSecond, height: geo.size.height)
                    }
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: 3, height: geo.size.height)
                        .offset(x: now.timeIntervalSince(start) * perSecond - 1)
                }
            }
        }
        // The row you're on stays the same height (no growing as you move).
        .frame(height: TVGuide.rowHeight)
    }

    private var tile: some View {
        let quality = model.measuredQuality[channel.id]
        let fps = model.measuredFrameRate[channel.id] ?? 0
        let sound = model.measuredAudio[channel.id]
        return HStack(spacing: 10) {
            TVChannelIcon(url: channel.icon, size: 40)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(channel.name)
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(playing && !focused ? Theme.accent : (focused ? Theme.bg : Theme.text))
                    if playing {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(focused ? Theme.bg : Theme.accent)
                    }
                    if model.isFavorite(channel: channel.id) {
                        Image(systemName: "heart.fill").font(.system(size: 15)).foregroundStyle(Theme.accent)
                    }
                }
                // Always shown (not only on the row you're on), so nothing moves as you go up and down.
                Group {
                    HStack(spacing: 8) {
                        if let quality, !quality.isEmpty {
                            TVBadge(text: quality, fill: quality == "4K" ? Theme.accent : Theme.raised,
                                    color: quality == "4K" ? Theme.onAccent : Theme.soft)
                        }
                        if fps > 0 { TVBadge(text: PlaybackController.fpsLabel(fps)) }
                        if let sound { TVBadge(text: sound) }
                    }
                    .fixedSize()
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(width: TVGuide.channelWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(focused ? Theme.text : Theme.card))
    }

    @ViewBuilder
    private func cell(_ p: Programme, perSecond: CGFloat, height: CGFloat) -> some View {
        let s = max(p.start, start)
        let e = min(p.end, start.addingTimeInterval(TVGuide.span))
        let width = max(e.timeIntervalSince(s) * perSecond - TVGuide.gap / 2, 0)
        let isNow = p.start <= now && p.end > now
        let lit = focused && isNow
        let colour = TVGuide.fill(title: p.title, channel: channel, games: model.games)
        let sub = lit ? Color(hex: 0x4A4F5C) : Color.white.opacity(0.78)
        let elapsed = min(max(now.timeIntervalSince(s) * perSecond, 0), width)
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10).fill(lit ? Theme.text : colour)
            // What's already been on is a shade darker.
            Rectangle().fill(Color.black.opacity(lit ? 0.07 : 0.28)).frame(width: elapsed)
            // Times on top, then the title over up to two lines (three on the row you're on).
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 12) {
                    Text(focused && isNow ? "\(TVGuide.time(p.start)) – \(TVGuide.time(p.end))" : TVGuide.time(p.start))
                    if focused && isNow { Text(TVGuide.left(p.end.timeIntervalSince(now))) }
                }
                .font(.system(size: 16))
                .foregroundStyle(sub)
                .lineLimit(1)
                Text(p.title)
                    .font(.system(size: 20, weight: focused ? .bold : .semibold))
                    .foregroundStyle(lit ? Theme.bg : Theme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(width: width, height: height, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(lit ? Theme.accent : .clear, lineWidth: 4))
        .offset(x: s.timeIntervalSince(start) * perSecond)
    }
}

/// The timeline guide's rows: no fill or zoom of their own (the row draws its own focus).
struct TVGuideButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
