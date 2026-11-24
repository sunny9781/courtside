import SwiftUI

/// EPG, laid out like the Mac guide: categories down the left (grouped), the mini player and what's on at the
/// top, and the channels with what's on now and next below. Moving onto a channel previews it; clicking it
/// goes full screen, where up/down flips through the category.
struct TVLiveView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: TVNav
    /// The category you're on: kept in memory while you're on the EPG and saved when you leave it (2.28), so moving
    /// through the list doesn't write settings on every stop.
    @State private var selectedID = UserDefaults.standard.string(forKey: Prefs.guideCategory) ?? ""
    @Environment(\.scenePhase) private var scenePhase
    /// The selected category's channels (favourites first), worked out once when the category or the channels
    /// change, not on every press in the category list.
    @State private var guideChannels: [Channel] = []
    @AppStorage(Prefs.guideGrouped) private var grouped = true
    /// The groups you've opened in the category list (ids, outermost first); kept while you're on other tabs.
    private var path: [String] {
        get { nav.guidePath }
        nonmutating set { nav.guidePath = newValue }
    }
    /// The channel playing in the mini player: only one you clicked.
    @FocusState private var focusedCategory: String?
    /// A category waiting for you to stop on it (2.25): moving through the list only draws the one you end up on.
    @State private var pendingCategory: Task<Void, Never>?
    @State private var waitingCategory: String?
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

    /// What decides `guideChannels`: the category, the downloaded channels, favourites and grouping.
    private var channelsKey: String {
        "\(selectedID)|\(model.channelsVersion)|\(model.favoriteChannels.count)|\(model.favoriteChannels.last ?? 0)|\(grouped)"
    }

    private func saveSelection() { UserDefaults.standard.set(selectedID, forKey: Prefs.guideCategory) }

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
            // Worked out once per redraw (the rows used to each look the selection up again).
            let current = selected
            HStack(alignment: .top, spacing: 50) {
                // Categories on top of the player in the bottom-left corner (what's playing is in the bar along the
                // bottom); the schedule starts at the top.
                categoryList(current?.id)
                    .focusSection()
                    .frame(width: TVLayout.sidebar)
                .padding(.bottom, model.pinned != nil ? TVLayout.playerInset : TVLayout.margin)
                Group {
                    if searching {
                        channelList
                    } else {
                        // Its own view, redrawn only when what it shows changes (2.28): moving through the
                        // categories on the left no longer redraws the guide on every press.
                        TVGuideChannels(title: current?.name ?? "", channels: guideChannels,
                                        playingID: playingChannel?.id)
                            .equatable()
                    }
                }
                .focusSection()
            }
            .padding(.trailing, TVLayout.margin)
            // Pressing down from Home / EPG / Settings starts on the category list.
            .defaultFocus($focusedCategory, categoryTarget, priority: .userInitiated)
            // Back from the channels: to the category you're in on the left.
            .onChange(of: nav.sideRequest) { focusedCategory = categoryTarget }
            .onDisappear { nav.sideFocused = false; saveSelection() }
            .onAppear { guideChannels = channels }
            .onChange(of: channelsKey) { guideChannels = channels }
            .onChange(of: scenePhase) { if scenePhase != .active { saveSelection() } }
            .onChange(of: focusedCategory) {
                nav.sideFocused = focusedCategory != nil
                // Moving onto a category shows its channels once you stop on it (a quarter second), so passing several
                // categories doesn't draw each one's guide; moving right into the channels shows it straight away.
                // A group ("g:" ids) shows all of the group's channels, and clicking it opens it.
                pendingCategory?.cancel()
                guard let focusedCategory else {
                    if let waitingCategory { selectedID = waitingCategory }
                    waitingCategory = nil
                    return
                }
                guard focusedCategory != selectedID else { waitingCategory = nil; return }
                waitingCategory = focusedCategory
                pendingCategory = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    waitingCategory = nil
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

    private func categoryList(_ currentID: String?) -> some View {
        ScrollViewReader { proxy in
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 4) {
                // One search for categories and channels; results show on the right.
                TextField("Filter", text: $search)
                    .id("catTop")
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
                        categoryRow(Entry(id: Self.favoritesID, name: "Favourites", categories: []), currentID: currentID,
                                    count: model.favoriteChannels.count, symbol: "heart.fill")
                    }
                    ForEach(favoriteEntries) { entry in
                        categoryRow(entry, currentID: currentID)
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
                            .buttonStyle(TVRowButtonStyle(selected: currentID == "g:" + node.id))
                            .focused($focusedCategory, equals: "g:" + node.id)
                            .id("g:" + node.id)
                            .contextMenu { favoriteButton(category: node.id); hideButton(category: node.id, name: node.name) }
                        } else {
                            categoryRow(Entry(id: node.id, name: node.name, categories: node.categories), currentID: currentID)
                        }
                    }
                } else {
                    ForEach(allEntries.filter { !model.isFavorite(category: $0.id) }) { entry in
                        categoryRow(entry, currentID: currentID)
                    }
                }
            }
            .padding(.vertical, 20)
        }
        // Use the full width: no Apple TV side insets on top of our own small margin.
        .ignoresSafeArea(.container, edges: .horizontal)
        // Back on the categories inside a group goes up a level; at the top, up to the tabs (TVShell).
        .onExitCommand(perform: path.isEmpty ? nil : { path.removeLast() })
        // Opening or leaving a group swaps the rows (2.46): the list kept its old scroll position, so a group opened
        // from far down (Sports › NBA) showed a blank list until you moved. Back to the top, then focus the first
        // row inside (or, going up, the group you came out of).
        .onChange(of: nav.guidePath) { old, new in
            proxy.scrollTo("catTop", anchor: .top)
            let target: String?
            if new.count < old.count, let left = old.last {
                target = "g:" + left
            } else if let first = (new.isEmpty ? levelNodes.filter { !model.isFavorite(category: $0.id) }
                                               : model.favoritesFirst(levelNodes)).first {
                target = first.isGroup ? "g:" + first.id : first.id
            } else {
                target = nil
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                focusedCategory = target
                if let target { proxy.scrollTo(target, anchor: .center) }
            }
        }
        }
    }

    private func categoryRow(_ entry: Entry, currentID: String?, count: Int? = nil, symbol: String? = nil) -> some View {
        let key = entry.id.hasPrefix("g:") ? String(entry.id.dropFirst(2)) : entry.id
        let favorite = entry.id != Self.favoritesID && model.isFavorite(category: key)
        return Button {
            pendingCategory?.cancel()
            waitingCategory = nil
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
        .buttonStyle(TVRowButtonStyle(selected: entry.id == currentID))
        .focused($focusedCategory, equals: entry.id)
        .id(entry.id)
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
                    TVGuideHeader(title: "Results for \u{201C}\(search.trimmingCharacters(in: .whitespaces))\u{201D}",
                                  start: start, now: now)
                    searchResults(start: start, now: now)
                }
                .padding(.vertical, 10)
            }
            // Use the full width: no Apple TV side insets on top of our own small margin.
            .ignoresSafeArea(.container, edges: .horizontal)
            .contentMargins(.bottom, TVLayout.margin, for: .scrollContent)
            // Ends level with the bottom of the corner player (2.21, like Android), not under the now-playing bar.
            .padding(.bottom, model.pinned != nil ? TVLayout.barHeight + TVLayout.margin : 0)
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
        .contextMenu { WatchAlongsideButton(channel: channel); favoriteButton(channel: channel.id); hideButton(channel: channel) }
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

/// The guide for the selected category (2.28): its own view, compared by what it shows, so moving through the
/// category list on the left doesn't redraw it. The first click on a channel previews it in the corner, a second
/// goes full screen.
struct TVGuideChannels: View, Equatable {
    @EnvironmentObject var model: AppModel
    let title: String
    let channels: [Channel]
    let playingID: Int?
    @FocusState private var focusedChannel: Int?

    static func == (a: Self, b: Self) -> Bool {
        a.title == b.title && a.playingID == b.playingID && a.channels.map(\.id) == b.channels.map(\.id)
    }

    var body: some View {
        // Redrawn every minute so the time line and the guide's start move along.
        TimelineView(.everyMinute) { context in
            let now = context.date
            let start = TVGuide.windowStart(now)
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    TVGuideHeader(title: title, start: start, now: now)
                    ForEach(channels) { channel in
                        Button {
                            if channel.id == playingID {
                                model.play(channel, lineup: channels)
                            } else {
                                model.pin(channel, lineup: channels)
                            }
                        } label: {
                            TVGuideRow(channel: channel, playing: channel.id == playingID, start: start, now: now)
                        }
                        .buttonStyle(TVGuideButtonStyle())
                        .focused($focusedChannel, equals: channel.id)
                        .contextMenu {
                            WatchAlongsideButton(channel: channel)
                            let on = model.isFavorite(channel: channel.id)
                            Button(on ? "Remove from Favourites" : "Add to Favourites", systemImage: on ? "heart.slash" : "heart") {
                                model.toggleFavorite(channel: channel.id)
                            }
                            Button("Hide", systemImage: "eye.slash") {
                                if model.isFavorite(channel: channel.id) { model.toggleFavorite(channel: channel.id) }
                                model.setChannelHidden(channel.id, true)
                                model.notice = "\(channel.name) is hidden. Settings › Hidden brings it back."
                            }
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            // Use the full width: no Apple TV side insets on top of our own small margin.
            .ignoresSafeArea(.container, edges: .horizontal)
            .contentMargins(.bottom, TVLayout.margin, for: .scrollContent)
            // Ends level with the bottom of the corner player (2.21, like Android), not under the now-playing bar.
            .padding(.bottom, model.pinned != nil ? TVLayout.barHeight + TVLayout.margin : 0)
        }
        // Back from full screen: focus goes back to the channel you were watching.
        .onChange(of: model.nowPlaying == nil) {
            guard model.nowPlaying == nil, let id = model.lastPlayedChannelID, channels.contains(where: { $0.id == id }) else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                focusedChannel = id
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
        let range = model.measuredHDR[channel.id]
        // Fixed columns on every screen (channel, now, next), one line each; on the row you're on, text that doesn't
        // fit scrolls inside its column.
        HStack(spacing: 0) {
            HStack(spacing: 16) {
                TVChannelIcon(url: channel.icon, size: 48)
                if showNext {
                    TVScrollingText(text: channel.name, font: .system(size: 23, weight: .semibold), active: focused)
                        .foregroundStyle(playing && !focused ? Theme.accent : (focused ? Theme.bg : Theme.text))
                    ReliabilityDot(channelID: channel.id, size: 12, bare: true)
                } else {
                    // Game screen and channel sports (2.21): long names wrap onto a second line.
                    Text(channel.name)
                        .font(.system(size: 23, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(playing && !focused ? Theme.accent : (focused ? Theme.bg : Theme.text))
                }
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
                if showNext {
                    TVScrollingText(text: now?.title ?? "–", font: .system(size: 22, weight: .medium), active: focused)
                } else {
                    Text(now?.title ?? "–")
                        .font(.system(size: 22, weight: .medium))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
            // What it really played at, once it has (resolution, frame rate, sound): on the game screen and
            // channel sports only (the EPG leaves it to the now-playing bar).
            HStack(spacing: 8) {
                if !showNext, let quality, !quality.isEmpty {
                    TVBadge(text: quality, fill: quality == "4K" ? Theme.accent : Theme.raised,
                            color: quality == "4K" ? Theme.onAccent : Theme.soft)
                }
                if !showNext, let range { TVBadge(text: range) }
                if !showNext, fps > 0 { TVBadge(text: PlaybackController.fpsLabel(fps)) }
                if !showNext, let sound { TVBadge(text: sound) }
                if !showNext { ReliabilityDot(channelID: channel.id, size: 14, padding: 9) }
            }
            .fixedSize()
            // Game screen (2.47): the tags in a fixed slot, so what's on and its progress bar are as wide on every
            // stream whatever tags it has, and the rows line up.
            .frame(width: showNext ? nil : 330, alignment: .trailing)
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
    /// Half as wide again since 2.21 (was 220), with a bigger logo and name, like Android.
    static let channelWidth: CGFloat = 330
    static let span: TimeInterval = 150 * 60
    static let rowHeight: CGFloat = 92
    static let gap: CGFloat = 8

    /// The guide starts at the last half hour, so up to 30 minutes of what's on is behind the line.
    static func windowStart(_ now: Date) -> Date {
        let t = now.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (t / 1800).rounded(.down) * 1800)
    }

    static func fill(_ sport: Sport) -> Color { GuideColour.fill(sport) }
    @MainActor static func fill(title: String, channel: Channel, games: [Game]) -> Color {
        GuideColour.fill(title: title, channel: channel, games: games)
    }
    @MainActor static func sport(title: String, channel: Channel, games: [Game]) -> Sport? {
        GuideColour.sport(title: title, channel: channel, games: games)
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
        let programmes = Array((model.guide[channel.epgID] ?? []).overlapping(start, end))
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
        return HStack(spacing: 12) {
            TVChannelIcon(url: channel.icon, size: 56)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(channel.name)
                        .font(.system(size: 22, weight: .semibold))
                        .lineLimit(3)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(playing && !focused ? Theme.accent : (focused ? Theme.bg : Theme.text))
                    ReliabilityDot(channelID: channel.id, size: 12, bare: true)
                    if model.isFavorite(channel: channel.id) {
                        Image(systemName: "heart.fill").font(.system(size: 15)).foregroundStyle(Theme.accent)
                    }
                }
                // No resolution / frame rate / sound tags here: the now-playing bar shows them.
            }
        }
        .padding(.horizontal, 10)
        .frame(width: TVGuide.channelWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(focused ? Theme.text : Theme.card))
        // What's playing: an orange outline on its channel and the show on now (2.21, like Android; no speaker icon).
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(playing ? Theme.accent : .clear, lineWidth: 3))
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
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(lit || (playing && isNow) ? Theme.accent : .clear,
                                                                 lineWidth: lit ? 4 : 3))
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
