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
    @State private var focusedChannelID: Int?
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

    /// The channel in the info panel: the one you're on, or what's playing.
    private var infoChannel: Channel? {
        if let id = focusedChannelID, let channel = model.channelByID[id] { return channel }
        return playingChannel
    }

    /// What the mini player plays: the channel you clicked, or what's still playing from Home.
    private var playingChannel: Channel? { model.pinned?.channel }

    var body: some View {
        if model.channels.isEmpty {
            VStack(spacing: 20) {
                if model.isLoading || model.downloadingChannels { ProgressView() }
                Text(model.downloadingChannels ? "Downloading channels…" : (model.errorMessage ?? "No channels yet."))
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 50) {
                // Categories, then what's playing in its own section just above the player in the bottom-left
                // corner; the schedule starts at the top.
                VStack(alignment: .leading, spacing: 0) {
                    categoryList
                        .focusSection()
                    if let playing = playingChannel { nowPlayingPanel(playing) }
                }
                .frame(width: TVLayout.sidebar)
                .padding(.bottom, model.pinned != nil ? TVLayout.playerInset : 0)
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
            .onChange(of: focusedChannel) {
                if let focusedChannel { focusedChannelID = focusedChannel }
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
                    .onSubmit { runSearch() }
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

    // MARK: Mini player and programme

    /// What's playing, between the categories and the player: the channel, what's on now (times and progress), and
    /// what's next. As tall as it needs to be.
    private func nowPlayingPanel(_ channel: Channel) -> some View {
        let now = model.currentProgramme(channel)
        let next = now.flatMap { nextProgramme(channel, after: $0) }
        return VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(Theme.raised).frame(height: 2).padding(.bottom, 10)
            Label(channel.name, systemImage: "speaker.wave.2.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.soft)
                .lineLimit(1)
            Text(now?.title.isEmpty == false ? now!.title : "No guide information")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
            if let now {
                Text("\(now.start.formatted(date: .omitted, time: .shortened)) – \(now.end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.muted)
                ProgressView(value: progress(now)).tint(Theme.accent)
            }
            if let next {
                Text("Next: \(next.start.formatted(date: .omitted, time: .shortened))  \(next.title)")
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
    }

    /// Two lines about the channel you're on: what's on now (and until when), then what's next. What's playing
    /// is in the player strip at the top.
    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let channel = infoChannel {
                let now = model.currentProgramme(channel)
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(now?.title.isEmpty == false ? now!.title : channel.name)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if let now {
                        Text("\(now.start.formatted(date: .omitted, time: .shortened)) – \(now.end.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 21))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 16) {
                    Text(channel.name).foregroundStyle(Theme.soft)
                    if let now, let next = nextProgramme(channel, after: now) {
                        Text("Next: \(next.title) at \(next.start.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    Text(channel.id == playingChannel?.id ? "Click again for full screen" : "Click to play")
                        .foregroundStyle(Theme.muted.opacity(0.8))
                }
                .font(.system(size: 20))
                .lineLimit(1)
            } else {
                Text("Click a channel to play it in the player at the top. Click it again for full screen.")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(height: 80, alignment: .top)
    }

    // MARK: Channels

    private var channelList: some View {
        let nameWidth = TVLayout.nameWidth(searching ? hits.flatMap(\.channels) : channels)
        return ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text(searching ? "Results for \u{201C}\(search.trimmingCharacters(in: .whitespaces))\u{201D}" : (selected?.name ?? ""))
                        .frame(width: nameWidth + 22, alignment: .leading)
                    Text("NOW").frame(maxWidth: .infinity, alignment: .leading)
                    Text("NEXT").frame(width: 360, alignment: .leading)
                }
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 22)
                .padding(.bottom, 6)

                if search.trimmingCharacters(in: .whitespaces).count >= 2 {
                    searchResults
                }
                ForEach(search.trimmingCharacters(in: .whitespaces).count >= 2 ? [] : channels) { channel in
                    Button {
                        if channel.id == playingChannel?.id {
                            model.play(channel, lineup: channels)
                        } else {
                            model.pin(channel, lineup: channels)
                        }
                    } label: {
                        TVChannelRow(channel: channel, playing: channel.id == playingChannel?.id, nameWidth: nameWidth)
                    }
                    .buttonStyle(TVRowButtonStyle())
                    .focused($focusedChannel, equals: channel.id)
                    .contextMenu { favoriteButton(channel: channel.id); hideButton(channel: channel) }
                }
            }
            .padding(.vertical, 10)
        }
        // Use the full width: no Apple TV side insets on top of our own small margin.
        .ignoresSafeArea(.container, edges: .horizontal)
        // Runs to the bottom of the screen, under the now-playing bar (the last row can scroll clear of it).
        .contentMargins(.bottom, model.pinned != nil ? TVLayout.barHeight + TVLayout.margin : 0, for: .scrollContent)
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
    private var searchResults: some View {
        let nameWidth = TVLayout.nameWidth(hits.flatMap(\.channels))
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
                    Button {
                        if channel.id == playingChannel?.id {
                            model.play(channel, lineup: hit.channels)
                        } else {
                            model.pin(channel, lineup: hit.channels)
                        }
                    } label: {
                        TVChannelRow(channel: channel, playing: channel.id == playingChannel?.id, nameWidth: nameWidth)
                    }
                    .buttonStyle(TVRowButtonStyle())
                    .focused($focusedChannel, equals: channel.id)
                    .contextMenu { favoriteButton(channel: channel.id); hideButton(channel: channel) }
                }
            }
        }
    }

    private func progress(_ p: Programme) -> Double {
        let total = p.end.timeIntervalSince(p.start)
        guard total > 0 else { return 0 }
        return min(max(Date().timeIntervalSince(p.start) / total, 0), 1)
    }

    private func nextProgramme(_ channel: Channel, after now: Programme) -> Programme? {
        model.guide[channel.epgID]?.first { $0.start >= now.end }
    }
}

/// A channel row in the EPG: logo and name, what's on now (with progress), and what's next.
struct TVChannelRow: View {
    @EnvironmentObject var model: AppModel
    let channel: Channel
    var playing = false
    /// The stream's quality (4K, 1080p…), on the game screen.
    var badge: String? = nil
    /// A set width for the name keeps it on one line (the game screen); otherwise it can wrap onto two.
    var nameWidth: CGFloat? = nil

    var body: some View {
        let now = model.currentProgramme(channel)
        let next = now.flatMap { n in model.guide[channel.epgID]?.first { $0.start >= n.end } }
        HStack(spacing: 0) {
            HStack(spacing: 16) {
                TVChannelIcon(url: channel.icon, size: 48)
                Text(channel.name)
                    .font(.system(size: 23, weight: .semibold))
                    .lineLimit(nameWidth == nil ? 2 : 1)
                if playing {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 18))
                }
                if model.isFavorite(channel: channel.id) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(width: nameWidth ?? 408, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(now?.title ?? "–")
                    .font(.system(size: 22, weight: .medium))
                    .lineLimit(1)
                if let now {
                    ProgressView(value: progress(now))
                        .frame(maxWidth: 360)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(next.map { "\($0.start.formatted(date: .omitted, time: .shortened))  \($0.title)" } ?? "")
                .font(.system(size: 21))
                .opacity(0.65)
                .lineLimit(1)
                .frame(width: 360, alignment: .leading)
            if let badge, !badge.isEmpty {
                TVBadge(text: badge, fill: badge == "4K" ? Theme.accent : Theme.raised,
                        color: badge == "4K" ? Theme.onAccent : Theme.soft)
            }
        }
    }

    private func progress(_ p: Programme) -> Double {
        let total = p.end.timeIntervalSince(p.start)
        guard total > 0 else { return 0 }
        return min(max(Date().timeIntervalSince(p.start) / total, 0), 1)
    }
}
