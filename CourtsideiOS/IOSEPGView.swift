import SwiftUI

/// EPG: groups → categories → channels on a native navigation stack (swipe from the left edge to go back), with
/// favourites first. Along the bottom: your favourite categories and channels, then Auto-Group and the filter.
/// Tap a channel to play it in the pinned player at the top; tap it again for full screen (swipe up/down flips
/// through the category). The heart on a row adds it to (or removes it from) favourites.
struct IOSEPGView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.guideGrouped) private var grouped = true
    @State private var search = ""
    /// Opened groups (node ids), then possibly a category ("cat:<id>") at the end.
    @State private var path: [String] = []
    /// Search results, worked out a moment after you stop typing.
    @State private var hits: [EPGSearch.Hit] = []
    /// Result groups opened or closed by hand (otherwise they follow Hit.startsOpen).
    @State private var flipped: Set<String> = []
    /// Compact height = the phone is sideways: a category's channels show as a timeline.
    @Environment(\.verticalSizeClass) private var verticalSize
    /// Each category's channels (favourites first), worked out once and kept until the channels, favourites or
    /// grouping change (2.30, like the TVs), not again on every redraw (typing in the filter, a new score…).
    @State private var cache = IOSChannelCache()

    /// What's in the pinned player.
    private var playing: Channel? { model.pinned?.channel }

    private var searching: Bool { search.trimmingCharacters(in: .whitespaces).count >= 2 }

    // MARK: Layout

    var body: some View {
        VStack(spacing: 0) {
            if model.channels.isEmpty {
                Spacer()
                Text(model.downloadingChannels ? "Downloading channels…" : (model.errorMessage ?? "No channels yet."))
                    .foregroundStyle(Theme.muted)
                Spacer()
            } else {
                NavigationStack(path: $path) {
                    page(nil)
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: String.self) { id in
                            page(id)
                                .navigationTitle(title(id))
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbarBackground(Theme.bg, for: .navigationBar)
                        }
                }
                .tint(Theme.accent)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomControls }
        .background(Theme.bg)
        .onChange(of: search) {
            // Searching covers every category, so it starts from the top.
            if searching && !path.isEmpty { path = [] }
        }
        .onChange(of: grouped) { path = [] }
        .task(id: "\(search)|\(grouped)") {
            // A moment after typing stops, search every category and channel.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            hits = EPGSearch.run(search, model: model, grouped: grouped)
            flipped = []
        }
    }

    /// One level: the top (nil), a group, or a category's channels ("cat:<id>"). Sideways, a category is a timeline.
    @ViewBuilder
    private func page(_ id: String?) -> some View {
        if verticalSize == .compact, let id, id.hasPrefix("cat:") {
            let list = channels(String(id.dropFirst(4)))
            // Redrawn only when its channels or what's playing change.
            IOSTimelinePage(channels: list, playingID: playing?.id) { tap($0, lineup: list) }
                .equatable()
        } else {
            listPage(id)
        }
    }

    private func listPage(_ id: String?) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if id == nil && searching {
                    searchResults
                } else if let id, id.hasPrefix("cat:") {
                    let list = channels(String(id.dropFirst(4)))
                    if list.isEmpty {
                        Text("No channels.").foregroundStyle(Theme.muted).padding(.top, 30)
                    }
                    // Its own view, redrawn only when its channels or what's playing change (2.30).
                    IOSCategoryChannels(channels: list, playingID: playing?.id)
                        .equatable()
                } else if let id, let group = CategoryGrouping.find(id, in: model.categoryTree) {
                    categoryRow(id: group.id, "All \(group.name) channels", count: count(group.categories), group: false,
                                heart: false, target: "cat:" + group.id)
                    nodeRows(group.children)
                } else if grouped {
                    nodeRows(model.categoryTree)
                } else {
                    let all = model.categories.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    nodeRows(all.map { CategoryGrouping.Node(id: $0.id, name: $0.name, children: [], categories: [$0]) })
                }
            }
            .padding(.bottom, 30)
        }
        .background(Theme.bg)
    }

    @ViewBuilder
    private func nodeRows(_ nodes: [CategoryGrouping.Node]) -> some View {
        ForEach(model.favoritesFirst(nodes)) { node in
            if node.isGroup {
                categoryRow(id: node.id, node.name, count: node.categories.count, group: true, target: node.id)
            } else {
                categoryRow(id: node.id, node.name, count: count(node.categories), group: false, target: "cat:" + node.id)
            }
        }
    }

    // MARK: Favourites and filter

    /// At the bottom, in easy reach of the thumb: your favourites (categories, a line, then channels), then
    /// Auto-Group and the filter box.
    private var bottomControls: some View {
        VStack(spacing: 8) {
            let cats = model.favoriteCategoryNodes
            let chans = model.favoriteChannelList
            if !cats.isEmpty || !chans.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                        ForEach(cats) { node in
                            IOSChip(selected: path.last == (node.isGroup ? node.id : "cat:" + node.id), action: {
                                search = ""
                                path = [node.isGroup ? node.id : "cat:" + node.id]
                            }) {
                                Label(node.name, systemImage: node.isGroup ? "folder.fill" : "list.bullet")
                                    .lineLimit(1)
                            }
                        }
                        if !cats.isEmpty && !chans.isEmpty {
                            Rectangle().fill(Theme.border).frame(width: 1, height: 24).padding(.horizontal, 4)
                        }
                        ForEach(chans) { channel in
                            IOSChip(selected: channel.id == playing?.id, action: { tap(channel, lineup: chans) }) {
                                HStack(spacing: 6) {
                                    IOSChannelIcon(url: channel.icon, size: 20)
                                    Text(channel.name).lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                Divider().overlay(Theme.raised)
            }
            HStack(spacing: 10) {
                IOSChip(selected: grouped, action: { grouped.toggle() }) {
                    Label("Auto-Group", systemImage: "square.stack.3d.up")
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Filter", text: $search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: Data

    private func title(_ id: String) -> String {
        let raw = id.hasPrefix("cat:") ? String(id.dropFirst(4)) : id
        if let node = CategoryGrouping.find(raw, in: model.categoryTree) { return node.name }
        return model.categories.first { $0.id == raw }?.name ?? ""
    }

    /// The channels of a category, or of every category in a group, favourites first (cached until the channels,
    /// favourites or grouping change).
    private func channels(_ id: String) -> [Channel] {
        let key = "\(model.channelsVersion)|\(model.favoriteChannels.map(String.init).joined(separator: ","))|\(grouped)"
        return cache.channels(id, key: key) { buildChannels(id) }
    }

    private func buildChannels(_ id: String) -> [Channel] {
        let cats: [ChannelCategory]
        if let node = CategoryGrouping.find(id, in: model.categoryTree) {
            cats = node.categories
        } else {
            cats = model.categories.filter { $0.id == id }
        }
        return model.favoritesFirst(cats.flatMap { model.channelsByCategory[$0.id] ?? [] })
    }

    private func count(_ categories: [ChannelCategory]) -> Int {
        categories.reduce(0) { $0 + (model.channelsByCategory[$1.id]?.count ?? 0) }
    }

    private func isOpen(_ hit: EPGSearch.Hit) -> Bool {
        hit.startsOpen(totalHits: hits.count) != flipped.contains(hit.id)
    }

    // MARK: Rows

    /// Search results: one foldable group per category, channel hits first.
    @ViewBuilder
    private var searchResults: some View {
        if hits.isEmpty {
            Text("Nothing matches \"\(search)\".").foregroundStyle(Theme.muted).padding(.top, 30)
        }
        ForEach(hits) { hit in
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if flipped.contains(hit.id) { flipped.remove(hit.id) } else { flipped.insert(hit.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(isOpen(hit) ? 90 : 0))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(hit.category.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        if !hit.path.isEmpty {
                            Text(hit.path).font(.caption2).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                    }
                    Spacer()
                    Text("\(hit.channels.count)").font(.caption).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Theme.card.opacity(0.6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen(hit) {
                ForEach(hit.channels) { channel in channelRow(channel, lineup: hit.channels) }
            }
        }
    }

    private func channelRow(_ channel: Channel, lineup: [Channel]) -> some View {
        HStack(spacing: 0) {
            Button { tap(channel, lineup: lineup) } label: {
                IOSChannelRow(channel: channel, playing: channel.id == playing?.id)
            }
            .buttonStyle(.plain)
            heart(model.isFavorite(channel: channel.id)) { model.toggleFavorite(channel: channel.id) }
        }
        .overlay(alignment: .bottom) { Divider().overlay(Theme.raised).padding(.leading, 62) }
    }

    private func categoryRow(id: String, _ name: String, count: Int, group: Bool, heart showHeart: Bool = true,
                             target: String) -> some View {
        HStack(spacing: 0) {
            Button {
                search = ""
                path.append(target)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: group ? "folder.fill" : "list.bullet")
                        .foregroundStyle(group ? Theme.accent : Theme.muted)
                        .frame(width: 24)
                    Text(name).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer()
                    Text("\(count)").font(.subheadline).foregroundStyle(Theme.muted)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                }
                .padding(.leading)
                .padding(.trailing, showHeart ? 4 : 16)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showHeart {
                heart(model.isFavorite(category: id)) { model.toggleFavorite(category: id) }
            }
        }
        .overlay(alignment: .bottom) { Divider().overlay(Theme.raised).padding(.leading, 52) }
    }

    private func heart(_ on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: on ? "heart.fill" : "heart")
                .foregroundStyle(on ? Theme.accent : Theme.muted.opacity(0.6))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 6)
        .accessibilityLabel(on ? "Remove from favourites" : "Add to favourites")
    }

    /// Tap once to play it in the pinned player at the top, tap again for full screen.
    private func tap(_ channel: Channel, lineup: [Channel]) {
        if channel.id == playing?.id {
            model.play(channel, gameTitle: model.pinned?.gameTitle, lineup: model.pinned?.lineup ?? lineup)
        } else {
            model.pin(channel, lineup: lineup.isEmpty ? [channel] : lineup)
        }
    }
}

struct IOSChannelRow: View {
    @EnvironmentObject var model: AppModel
    let channel: Channel
    var playing = false

    var body: some View {
        let now = model.currentProgramme(channel)
        let next = now.flatMap { n in model.guide[channel.epgID]?.first { $0.start >= n.end } }
        // What's on now in its sport's colour (or the channel's own), like the TV guide.
        let colour = GuideColour.fill(title: now?.title ?? "", channel: channel, games: model.games)
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(colour).frame(width: 4).padding(.vertical, 2)
            IOSChannelIcon(url: channel.icon, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(channel.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(playing ? Theme.accent : Theme.text)
                        .lineLimit(1)
                    Spacer()

                }
                if let now {
                    Text(now.title).font(.footnote).foregroundStyle(Theme.soft).lineLimit(1)
                    ProgressView(value: progress(now)).tint(Theme.accent)
                }
                if let next {
                    Text("Next: \(next.start.formatted(date: .omitted, time: .shortened)) \(next.title)")
                        .font(.caption2).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        // What's playing: an orange outline (2.21, like the TVs; no speaker icon).
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(playing ? Theme.accent : .clear, lineWidth: 2)
            .padding(.horizontal, 6))
        .contentShape(Rectangle())
    }

    private func progress(_ p: Programme) -> Double {
        let total = p.end.timeIntervalSince(p.start)
        guard total > 0 else { return 0 }
        return min(max(Date().timeIntervalSince(p.start) / total, 0), 1)
    }
}

/// The cache behind `IOSEPGView.channels`: a plain object, so filling it doesn't redraw anything.
@MainActor
final class IOSChannelCache {
    private var key = ""
    private var lists: [String: [Channel]] = [:]

    func channels(_ id: String, key: String, build: () -> [Channel]) -> [Channel] {
        if key != self.key { self.key = key; lists = [:] }
        if let list = lists[id] { return list }
        let list = build()
        lists[id] = list
        return list
    }
}

/// A category's channels as a list (2.30): compared by the channels it shows and what's playing, so the rest of the
/// EPG redrawing (the filter, the favourites along the bottom) doesn't redraw every row. Tap once to play it in the
/// pinned player, again for full screen; the heart adds it to favourites.
struct IOSCategoryChannels: View, Equatable {
    @EnvironmentObject var model: AppModel
    let channels: [Channel]
    let playingID: Int?

    static func == (a: Self, b: Self) -> Bool {
        a.playingID == b.playingID && a.channels.map(\.id) == b.channels.map(\.id)
    }

    var body: some View {
        ForEach(channels) { channel in
            HStack(spacing: 0) {
                Button { tap(channel) } label: {
                    IOSChannelRow(channel: channel, playing: channel.id == playingID)
                }
                .buttonStyle(.plain)
                let on = model.isFavorite(channel: channel.id)
                Button { model.toggleFavorite(channel: channel.id) } label: {
                    Image(systemName: on ? "heart.fill" : "heart")
                        .foregroundStyle(on ? Theme.accent : Theme.muted.opacity(0.6))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .accessibilityLabel(on ? "Remove from favourites" : "Add to favourites")
            }
            .overlay(alignment: .bottom) { Divider().overlay(Theme.raised).padding(.leading, 62) }
        }
    }

    private func tap(_ channel: Channel) {
        if channel.id == model.pinned?.channel.id {
            model.play(channel, gameTitle: model.pinned?.gameTitle, lineup: model.pinned?.lineup ?? channels)
        } else {
            model.pin(channel, lineup: channels.isEmpty ? [channel] : channels)
        }
    }
}

/// The sideways timeline, compared the same way (its tap action isn't part of the comparison).
struct IOSTimelinePage: View, Equatable {
    let channels: [Channel]
    let playingID: Int?
    let onTap: (Channel) -> Void

    static func == (a: Self, b: Self) -> Bool {
        a.playingID == b.playingID && a.channels.map(\.id) == b.channels.map(\.id)
    }

    var body: some View {
        IOSGuideTimeline(channels: channels, playingID: playingID, onTap: onTap)
    }
}
