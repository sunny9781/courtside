import SwiftUI
import AppKit

/// TiviMate-style guide: categories on the left, a preview and details of the selected channel on top,
/// and the channel grid below. Click selects and previews, double-click (or Return) watches full screen.
struct GuideView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.guideHours) private var guideHours = 6
    @AppStorage(Prefs.guideCategory) private var categoryID = ""
    @AppStorage(Prefs.guideGrouped) private var grouped = true
    /// The filter box in the top bar.
    @Binding var categorySearch: String
    @State private var channelSearch = ""
    /// Results of the one search box (categories and channels), worked out a moment after typing stops.
    @State private var hits: [EPGSearch.Hit] = []
    /// The text the results are for. The EPG switches to results only once they're ready, so typing never shows an
    /// empty "Nothing matches" in between.
    @State private var hitsQuery = ""
    /// Result groups opened or closed by hand (otherwise they follow Hit.startsOpen).
    @State private var flipped: Set<String> = []
    @State private var expanded: Set<String> = []
    @State private var selectedID: Int?
    @State private var offset = 0          // in half hours from the default start
    @FocusState private var gridFocused: Bool
    let onOpenGame: (String) -> Void

    static let allID = "__all"
    static let recentID = "__recent"
    /// Your favourite channels from every category, at the top of the list.
    static let favoritesID = "__fav"

    private let slotWidth: CGFloat = 200   // width of 30 minutes
    private let rowHeight: CGFloat = 56

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let list = rows
            let selected = list.first { $0.id == selectedID }

            HStack(spacing: 0) {
                categoryList

                // What's playing (and what's next) is in the player strip at the top, so the guide starts right
                // away; the category's name and channel count sit at the left of the time row.
                VStack(alignment: .leading, spacing: 16) {
                    // While it downloads, the top bar already says so ("Refreshing EPG 45%").
                    if let status = model.guideStatus, !model.guideDownloading {
                        Banner(text: status, icon: "tablecells")
                    }

                    if list.isEmpty {
                        Text(model.isLoading ? "Loading channels…" : (channelSearch.isEmpty ? "No channels here." : "No channels match."))
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 20)
                        Spacer()
                    } else {
                        grid(list, selected: selected, now: now)
                    }
                }
                .padding(.leading, 28)
                .padding(.trailing, 32)
                .padding(.top, 18)
                .padding(.bottom, 16)
            }
        }
        .onChange(of: selectedID) {
            // The channel you pick plays in the pinned player at the top.
            if let id = selectedID, let channel = model.channelByID[id] { model.pin(channel, lineup: rows) }
        }
        .onAppear {
            pickDefaultCategory()
            gridFocused = true
        }
        .onChange(of: model.categories) { pickDefaultCategory() }
        .onChange(of: model.lastPlayedChannelID) {
            if let id = model.lastPlayedChannelID, rows.contains(where: { $0.id == id }) { selectedID = id }
        }
        .task(id: "\(categorySearch)|\(grouped)") {
            let query = categorySearch.trimmingCharacters(in: .whitespaces)
            guard query.count >= 2 else {
                if !hitsQuery.isEmpty { hits = []; hitsQuery = ""; flipped = [] }
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            // Worked out away from the main thread, so typing never stutters on a big channel list.
            let input = EPGSearch.Input(model: model)
            let group = grouped
            let found = await Task.detached(priority: .userInitiated) { EPGSearch.run(query, input: input, grouped: group) }.value
            guard !Task.isCancelled else { return }
            hits = found
            hitsQuery = query
            flipped = []
        }
        .onChange(of: categoryID) {
            selectedID = nil
            offset = 0
            channelSearch = ""
        }
    }

    // MARK: Categories

    /// The tree rows currently visible, with their depth, following which groups are open.
    struct VisibleNode: Identifiable {
        let node: CategoryGrouping.Node
        let depth: Int
        let parent: String
        var id: String { parent + ">" + node.id }
    }

    private func visibleNodes(_ nodes: [CategoryGrouping.Node], depth: Int = 0, parent: String = "") -> [VisibleNode] {
        var out: [VisibleNode] = []
        // At the top, favourites are listed above the tree; inside a group they come first.
        let ordered = depth == 0 ? nodes.filter { !model.isFavorite(category: $0.id) } : model.favoritesFirst(nodes)
        for node in ordered {
            out.append(VisibleNode(node: node, depth: depth, parent: parent))
            if node.isGroup && expanded.contains(node.id) {
                out += visibleNodes(node.children, depth: depth + 1, parent: node.id)
            }
        }
        return out
    }

    private func channelCount(_ cats: [ChannelCategory]) -> Int {
        cats.reduce(0) { $0 + (model.channelsByCategory[$1.id]?.count ?? 0) }
    }

    private var searching: Bool { hitsQuery.count >= 2 }

    private var currentTitle: String {
        if searching { return "Results for \u{201C}\(hitsQuery)\u{201D}" }
        switch categoryID {
        case Self.allID: return "All channels"
        case Self.recentID: return "Recently watched"
        case Self.favoritesID: return "Favourites"
        default:
            if let node = CategoryGrouping.find(categoryID, in: model.categoryTree), node.isGroup {
                return node.id.dropFirst(CategoryGrouping.nodePrefix.count).replacingOccurrences(of: "/", with: " › ")
            }
            return model.categories.first { $0.id == categoryID }?.name ?? ""
        }
    }

    private func pickDefaultCategory() {
        guard !model.categories.isEmpty else { return }
        let known = categoryID == Self.favoritesID || model.categories.contains { $0.id == categoryID }
            || CategoryGrouping.find(categoryID, in: model.categoryTree) != nil
        if !known {
            if grouped, let sports = model.categoryTree.first(where: { $0.name == CategoryGrouping.sportsGroup }) {
                categoryID = sports.id
                expanded.insert(sports.id)
            } else {
                categoryID = (model.categories.first { $0.name.lowercased().contains("sport") } ?? model.categories[0]).id
            }
        }
    }

    /// Right-click › Hide, as on the TVs (hold select): out of favourites, into Settings › Hidden.
    private func hideCategory(_ id: String, name: String) {
        if model.isFavorite(category: id) { model.toggleFavorite(category: id) }
        model.setCategoryHidden(id, true)
        if categoryID == id { categoryID = ""; pickDefaultCategory() }
        model.notice = "\(name) is hidden. Settings › Hidden brings it back."
    }

    private func hideChannel(_ channel: Channel) {
        if model.isFavorite(channel: channel.id) { model.toggleFavorite(channel: channel.id) }
        model.setChannelHidden(channel.id, true)
        model.notice = "\(channel.name) is hidden. Settings › Hidden brings it back."
    }

    private func choose(_ id: String) {
        categoryID = id
        gridFocused = true
    }

    /// Just wide enough for the longest category name, within limits.
    private var categoryWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let names = model.categories.map(\.name)
        let longest = names.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 120
        return min(max(longest, 150), 260) + 80
    }

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $grouped) {
                Text("Auto-Group")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.soft)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Theme.accent)
            .padding(.horizontal, 4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if searching {
                        searchResults
                    } else {
                        favoriteRows
                    }
                    if !searching && grouped {
                        ForEach(visibleNodes(model.categoryTree)) { item in
                            let node = item.node
                            if node.isGroup {
                                CategoryRow(name: node.name, count: channelCount(node.categories),
                                            selected: categoryID == node.id, depth: item.depth,
                                            favorite: model.isFavorite(category: node.id),
                                            onFavorite: { model.toggleFavorite(category: node.id) },
                                            onHide: { hideCategory(node.id, name: node.name) },
                                            expanded: expanded.contains(node.id),
                                            onToggle: {
                                                if expanded.contains(node.id) { expanded.remove(node.id) } else { expanded.insert(node.id) }
                                            }) { choose(node.id) }
                            } else {
                                CategoryRow(name: node.name, count: channelCount(node.categories),
                                            selected: categoryID == node.id, depth: item.depth,
                                            favorite: model.isFavorite(category: node.id),
                                            onFavorite: { model.toggleFavorite(category: node.id) },
                                            onHide: { hideCategory(node.id, name: node.name) },
                                            alignWithArrows: true) { choose(node.id) }
                            }
                        }
                    } else if !searching {
                        ForEach(model.categories.filter { !model.isFavorite(category: $0.id) }
                            .sorted { CategoryGrouping.sortsBefore($0.name, $1.name) }) { cat in
                            CategoryRow(name: cat.name, count: model.channelsByCategory[cat.id]?.count ?? 0,
                                        selected: categoryID == cat.id,
                                        favorite: model.isFavorite(category: cat.id), onFavorite: { model.toggleFavorite(category: cat.id) },
                                        onHide: { hideCategory(cat.id, name: cat.name) }) { choose(cat.id) }
                        }
                    }
                }
            }
        }
        .padding(.top, 18)
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
        .frame(width: categoryWidth)
        .frame(maxHeight: .infinity)
        .background(Color(hex: 0x0B0E12))
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.raised).frame(width: 1) }
    }

    /// Favourites at the top of the list: your favourite channels, then favourite categories and groups, then a line.
    @ViewBuilder
    private var favoriteRows: some View {
        let nodes = model.favoriteCategoryNodes
        if !model.favoriteChannels.isEmpty {
            CategoryRow(name: "Favourites", count: model.favoriteChannelList.count,
                        selected: categoryID == Self.favoritesID, symbol: "heart.fill") { choose(Self.favoritesID) }
        }
        ForEach(nodes) { node in
            CategoryRow(name: node.name, count: channelCount(node.categories), selected: categoryID == node.id,
                        favorite: true, onFavorite: { model.toggleFavorite(category: node.id) },
                        onHide: { hideCategory(node.id, name: node.name) }) { choose(node.id) }
        }
        if !nodes.isEmpty || !model.favoriteChannels.isEmpty {
            Divider().overlay(Theme.raised).padding(.vertical, 6)
        }
    }

    private func isOpen(_ hit: EPGSearch.Hit) -> Bool {
        hit.startsOpen(totalHits: hits.count) != flipped.contains(hit.id)
    }

    /// Search results in the left column: a foldable row per category, with its matching channels under it.
    /// The grid on the right shows every channel found.
    @ViewBuilder
    private var searchResults: some View {
        if hits.isEmpty {
            Text("Nothing matches.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .padding(12)
        }
        ForEach(hits) { hit in
            CategoryRow(name: hit.category.name, count: hit.channels.count, selected: false,
                        expanded: isOpen(hit),
                        onToggle: { if flipped.contains(hit.id) { flipped.remove(hit.id) } else { flipped.insert(hit.id) } }) {
                // Clicking the name opens that category's guide.
                categorySearch = ""
                choose(hit.category.id)
            }
            .help(hit.path.isEmpty ? hit.category.name : "\(hit.path) › \(hit.category.name)")
            if isOpen(hit) {
                ForEach(hit.channels.prefix(60)) { channel in
                    Button {
                        select(channel)
                    } label: {
                        Text(channel.name)
                            .font(.system(size: 12, weight: channel.id == selectedID ? .semibold : .regular))
                            .foregroundStyle(channel.id == selectedID ? Theme.accent : Theme.soft)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 34)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if hit.channels.count > 60 {
                    Text("+ \(hit.channels.count - 60) more in the grid")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .padding(.leading, 34)
                }
            }
        }
    }

    /// The chosen category (or group) in the provider's order, narrowed by the channel search.
    private var rows: [Channel] {
        if searching { return EPGSearch.channels(hits) }
        let base: [Channel]
        switch categoryID {
        case Self.allID:
            base = model.channels
        case Self.recentID:
            base = model.recentChannels
        case Self.favoritesID:
            base = model.favoriteChannelList
        default:
            if let node = CategoryGrouping.find(categoryID, in: model.categoryTree), node.isGroup {
                base = model.favoritesFirst(node.categories.flatMap { model.channelsByCategory[$0.id] ?? [] })
            } else {
                base = model.favoritesFirst(model.channelsByCategory[categoryID] ?? [])
            }
        }
        let query = channelSearch.trimmingCharacters(in: .whitespaces).lowercased()
        return query.isEmpty ? base : base.filter { $0.name.lowercased().contains(query) }
    }

    private func listHeader(count: Int) -> some View {
        HStack(spacing: 12) {
            Text(currentTitle)
                .font(Theme.display(20))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Text("\(count.formatted()) channels")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Spacer()
        }
    }

    // MARK: Selected channel

    private func select(_ channel: Channel) {
        selectedID = channel.id
        gridFocused = true
    }

    private func watch(_ channel: Channel, _ lineup: [Channel]) {
        selectedID = channel.id
        model.play(channel, lineup: lineup)
    }

    @ViewBuilder
    private func infoPanel(_ channel: Channel?, now: Date) -> some View {
        HStack(alignment: .top, spacing: 24) {
            if channel == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pick a channel")
                        .font(Theme.display(26))
                        .foregroundStyle(Theme.text)
                    Text("Click a channel to play it in the player at the top. Double-click or press Return to watch full screen.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 420, alignment: .leading)
            }

            if let channel {
                let current = model.currentProgramme(channel, at: now)
                let next = model.guide[channel.epgID]?.first { $0.start >= (current?.end ?? now) }
                let gameID = current.flatMap { model.guideLinks[Matcher.linkKey(channel.epgID, $0.start)] }

                VStack(alignment: .leading, spacing: 10) {
                    Text(current.map { $0.title.isEmpty ? channel.name : $0.title } ?? channel.name)
                        .font(Theme.display(26))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)

                    if let current {
                        let total = max(current.end.timeIntervalSince(current.start), 1)
                        let elapsed = min(max(now.timeIntervalSince(current.start), 0), total)
                        HStack(spacing: 10) {
                            Text("\(current.start.formatted(date: .omitted, time: .shortened)) – \(current.end.formatted(date: .omitted, time: .shortened))")
                            ProgressView(value: elapsed, total: total)
                                .tint(Theme.accent)
                                .frame(width: 110)
                            Text("\(Int((total - elapsed) / 60)) min left")
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.soft)
                    }

                    Text([channel.number.map(String.init), channel.name].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)

                    if let next {
                        Text("Next  \(next.start.formatted(date: .omitted, time: .shortened))  \(next.title)")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 10) {
                        Button {
                            watch(channel, rows)
                        } label: {
                            Label("Watch", systemImage: "play.fill")
                        }
                        .buttonStyle(AccentButtonStyle())

                        if let gameID {
                            Button("All streams for this game") { onOpenGame(gameID) }
                                .buttonStyle(GhostButtonStyle())
                        }
                    }
                }
                .frame(height: 191, alignment: .topLeading)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: Grid

    /// Just wide enough for the longest channel name shown, within limits.
    private func channelColumnWidth(_ list: [Channel]) -> CGFloat {
        let font = ChannelCell.nameFont
        let longest = list.prefix(400).map { ($0.name as NSString).size(withAttributes: [.font: font]).width }.max() ?? 100
        // Names wrap onto two lines (longer ones scroll), so the column stays narrow: enough for the longest name
        // over two lines, between 110 and 180 pt, plus the number, logo and heart. At least room for the time buttons.
        let name = min(max(ceil(longest / 2) + 12, 110), 180)
        return max(name + ChannelCell.fixedWidth, 290)
    }

    private func grid(_ list: [Channel], selected: Channel?, now: Date) -> some View {
        GeometryReader { geo in
            let column = channelColumnWidth(list)
            let area = max(geo.size.width - column - 8, 200)
            let windowStart = Self.floorToHalfHour(now).addingTimeInterval(Double(offset) * 1800)
            let windowEnd = windowStart.addingTimeInterval(Double(area / slotWidth) * 1800)

            VStack(spacing: 6) {
                timeHeader(column: column, area: area, windowStart: windowStart, now: now, count: list.count)

                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 4) {
                            ForEach(list) { ch in
                                row(ch, list: list, selected: ch.id == selected?.id, column: column, area: area,
                                    windowStart: windowStart, windowEnd: windowEnd, now: now)
                                    .id(ch.id)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if now >= windowStart && now <= windowEnd {
                                Rectangle()
                                    .fill(Theme.accent)
                                    .frame(width: 2)
                                    .offset(x: column + 8 + x(now, windowStart))
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    .onChange(of: selectedID) {
                        if let id = selectedID {
                            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                        }
                    }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($gridFocused)
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return]) { press in
            handleKey(press.key, list: list, selected: selected)
        }
    }

    private func handleKey(_ key: KeyEquivalent, list: [Channel], selected: Channel?) -> KeyPress.Result {
        guard model.nowPlaying == nil, !list.isEmpty else { return .ignored }
        let index = selected.flatMap { s in list.firstIndex { $0.id == s.id } } ?? -1
        switch key {
        case .upArrow:
            selectedID = list[max(index - 1, 0)].id
        case .downArrow:
            selectedID = list[min(index + 1, list.count - 1)].id
        case .leftArrow:
            offset = max(offset - 1, -2)
        case .rightArrow:
            offset = min(offset + 1, guideHours * 2)
        case .return:
            if let selected { watch(selected, list) }
        default:
            return .ignored
        }
        return .handled
    }

    private func timeHeader(column: CGFloat, area: CGFloat, windowStart: Date, now: Date, count: Int) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(currentTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text("\(count.formatted()) channels")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 4)
                RoundIconButton(symbol: "chevron.left", help: "Earlier (Left arrow)") { offset = max(offset - 1, -2) }
                Button("Now") { offset = 0 }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(offset == 0)
                RoundIconButton(symbol: "chevron.right", help: "Later (Right arrow)") { offset = min(offset + 1, guideHours * 2) }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.soft)
            .padding(.trailing, 8)
            .frame(width: column)

            ZStack(alignment: .leading) {
                ForEach(0...Int(area / slotWidth), id: \.self) { i in
                    Text(windowStart.addingTimeInterval(Double(i) * 1800).formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .offset(x: CGFloat(i) * slotWidth)
                }
            }
            .frame(width: area, height: 40, alignment: .leading)
            .clipped()
        }
    }

    private func x(_ date: Date, _ windowStart: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(windowStart) / 1800) * slotWidth
    }

    private func row(_ channel: Channel, list: [Channel], selected: Bool, column: CGFloat, area: CGFloat,
                     windowStart: Date, windowEnd: Date, now: Date) -> some View {
        let progs = Array((model.guide[channel.epgID] ?? []).overlapping(windowStart, windowEnd))

        return HStack(spacing: 8) {
            ChannelCell(channel: channel, selected: selected, width: column, height: rowHeight,
                        favorite: model.isFavorite(channel: channel.id),
                        onFavorite: { model.toggleFavorite(channel: channel.id) },
                        onHide: { hideChannel(channel) })
                .onTapGesture(count: 2) { watch(channel, list) }
                .onTapGesture { select(channel) }

            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: area, height: rowHeight)

                if progs.isEmpty {
                    Text(channel.epgID.isEmpty ? "No guide for this channel" : "No guide information")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 12)
                        .frame(width: area - 4, height: rowHeight, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.raised : Theme.card))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { watch(channel, list) }
                        .onTapGesture { select(channel) }
                }

                ForEach(progs, id: \.self) { p in
                    let start = max(p.start, windowStart)
                    let end = min(p.end, windowEnd)
                    let width = max(x(end, windowStart) - x(start, windowStart) - 4, 0)
                    let gameID = model.guideLinks[Matcher.linkKey(channel.epgID, p.start)]

                    // Every show in its sport's colour (or its channel's own), what's already been on darker.
                    let past = p.start < now ? min(max(x(now, windowStart) - x(start, windowStart), 0), width) : 0
                    ProgrammeBlock(programme: p, width: width, height: rowHeight,
                                   isNow: p.start <= now && p.end > now, selectedRow: selected,
                                   gameID: gameID, streams: gameID.map { model.streamCount($0) },
                                   colour: GuideColour.fill(title: p.title, channel: channel, games: model.games),
                                   past: past)
                        .offset(x: x(start, windowStart))
                        .onTapGesture(count: 2) {
                            if let gameID { onOpenGame(gameID) } else { watch(channel, list) }
                        }
                        .onTapGesture { select(channel) }
                }
            }
            .frame(width: area, height: rowHeight, alignment: .topLeading)
            .clipped()
        }
    }

    static func floorToHalfHour(_ date: Date) -> Date {
        let t = date.timeIntervalSince1970
        return Date(timeIntervalSince1970: (t / 1800).rounded(.down) * 1800)
    }
}

// MARK: Pieces

struct CategoryRow: View {
    let name: String
    let count: Int
    let selected: Bool
    var depth = 0
    /// A heart to add it to favourites (or take it off): shown on hover, and always when it's a favourite.
    var favorite: Bool? = nil
    var onFavorite: (() -> Void)? = nil
    /// Right-click › Hide (as on the TVs); Settings › Hidden shows it again.
    var onHide: (() -> Void)? = nil
    /// An icon before the name (the Favourites row).
    var symbol: String? = nil
    /// In the grouped list, rows without an arrow keep its space so names at the same level line up.
    var alignWithArrows = false
    var expanded: Bool? = nil
    var onToggle: (() -> Void)? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            if depth > 0 {
                Color.clear.frame(width: 16 * CGFloat(depth))
            }
            if onToggle == nil && alignWithArrows {
                Color.clear.frame(width: 30, height: 40)
            }
            if let onToggle {
                Button(action: onToggle) {
                    Image(systemName: expanded == true ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 30, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded == true ? "Hide its categories" : "Show its categories")
            }

            Button(action: action) {
                HStack(spacing: 8) {
                    if let symbol {
                        Image(systemName: symbol).foregroundStyle(selected ? Theme.bg : Theme.accent)
                    }
                    Text(name)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(count.formatted())
                        .font(.system(size: 11))
                        .opacity(0.7)
                }
                .padding(.leading, onToggle == nil && !alignWithArrows ? 12 : 2)
                .padding(.trailing, onFavorite == nil ? 12 : 4)
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let onFavorite {
                let on = favorite == true
                Button(action: onFavorite) {
                    Image(systemName: on ? "heart.fill" : "heart")
                        .font(.system(size: 11))
                        .foregroundStyle(on ? (selected ? Theme.bg : Theme.accent) : Theme.muted)
                        .frame(width: 24, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(on || hovering ? 1 : 0)
                .padding(.trailing, 4)
                .help(on ? "Remove from favourites" : "Add to favourites")
            }
        }
        .contextMenu {
            if let onFavorite {
                Button(favorite == true ? "Remove from Favourites" : "Add to Favourites", action: onFavorite)
            }
            if let onHide { Button("Hide", action: onHide) }
        }
        .font(.system(size: 13, weight: selected ? .semibold : .medium))
        .foregroundStyle(selected ? Theme.bg : (depth > 0 ? Theme.muted : Theme.soft))
        .background(RoundedRectangle(cornerRadius: 9)
            .fill(selected ? Theme.text : (hovering ? Theme.card : Color.clear)))
        .onHover { hovering = $0 }
        .help(name)
    }
}

struct ChannelCell: View {
    let channel: Channel
    let selected: Bool
    let width: CGFloat
    let height: CGFloat
    /// Resolution, frame rate and sound from the last time it played.
    var tags: [String] = []
    var favorite = false
    var onFavorite: (() -> Void)? = nil
    /// Right-click › Hide (as on the TVs).
    var onHide: (() -> Void)? = nil
    @State private var hovering = false

    static let numberWidth: CGFloat = 44
    static let logoWidth: CGFloat = 52
    static let heartWidth: CGFloat = 22
    static let spacing: CGFloat = 8
    static let padding: CGFloat = 6
    static let nameFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let twoLines = ceil(NSLayoutManager().defaultLineHeight(for: nameFont) * 2) + 1
    /// Everything in the cell but the name.
    static let fixedWidth = numberWidth + logoWidth + heartWidth + spacing * 3 + padding * 2

    private var nameWidth: CGFloat { max(width - Self.fixedWidth, 40) }

    /// Fits on two lines? Otherwise it scrolls on one line while hovered or selected (like the TVs).
    private var nameFits: Bool {
        let box = (channel.name as NSString).boundingRect(
            with: NSSize(width: nameWidth, height: 1000), options: [.usesLineFragmentOrigin],
            attributes: [.font: Self.nameFont])
        return box.height <= Self.twoLines
    }

    var body: some View {
        HStack(spacing: Self.spacing) {
            Text(channel.number.map(String.init) ?? "")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(selected ? Theme.accent : Theme.muted)
                .frame(width: Self.numberWidth, alignment: .trailing)

            SmallLogoImage(url: channel.icon, size: 64) {
                Text(String(channel.name.prefix(3)).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(4)
            .frame(width: Self.logoWidth, height: height - 18)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.raised))

            Group {
                if !nameFits && (hovering || selected) {
                    MacScrollingText(text: channel.name, font: .system(size: 13, weight: .semibold))
                } else {
                    Text(channel.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(selected ? Theme.accent : Theme.text)
            .frame(width: nameWidth, alignment: .leading)

            if let onFavorite {
                Button(action: onFavorite) {
                    Image(systemName: favorite ? "heart.fill" : "heart")
                        .font(.system(size: 12))
                        .foregroundStyle(favorite ? Theme.accent : Theme.muted)
                        .frame(width: Self.heartWidth, height: height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(favorite || hovering ? 1 : 0)
                .help(favorite ? "Remove from favourites" : "Add to favourites")
            } else {
                Color.clear.frame(width: Self.heartWidth)
            }
        }
        .padding(.horizontal, Self.padding)
        .frame(width: width, height: height, alignment: .leading)
        // A panel of its own, so the channel names stand apart from the categories and the programmes.
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.cardHover : (hovering ? Theme.card : Theme.sidebar)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            if let onFavorite {
                Button(favorite ? "Remove from Favourites" : "Add to Favourites", action: onFavorite)
            }
            if let onHide { Button("Hide", action: onHide) }
        }
        .help(channel.name)
    }
}

/// One line that scrolls sideways when it's longer than its box (the Mac version of the TVs' scrolling names).
struct MacScrollingText: View {
    let text: String
    let font: Font
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        Text(text).font(font).lineLimit(1).fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            .offset(x: offset)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
            .clipped()
            .task(id: "\(text)|\(Int(textWidth))|\(Int(boxWidth))") {
                offset = 0
                let distance = textWidth - boxWidth
                guard distance > 1 else { return }
                let seconds = Double(distance) / 50
                // Once (2.21), like the TVs.
                try? await Task.sleep(for: .seconds(0.8))
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: seconds)) { offset = -distance }
                try? await Task.sleep(for: .seconds(seconds + 1.5))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) { offset = 0 }
            }
    }
}

struct ProgrammeBlock: View {
    let programme: Programme
    let width: CGFloat
    let height: CGFloat
    let isNow: Bool
    let selectedRow: Bool
    let gameID: String?
    let streams: Int?
    /// The sport's colour (or the channel's own), and how much of the block has already been on (drawn darker).
    var colour: Color = Theme.card
    var past: CGFloat = 0
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if width > 50 {
                Text(programme.title.isEmpty ? "Untitled" : programme.title)
                    .font(.system(size: 13, weight: gameID != nil || (selectedRow && isNow) ? .semibold : .medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .opacity(0.8)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(width: width, height: height, alignment: .leading)
        .background(
            ZStack(alignment: .leading) {
                colour.brightness(hovering ? 0.08 : 0)
                Rectangle().fill(Color.black.opacity(0.3)).frame(width: past)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        )
        // What's playing (the selected channel plays in the preview): an orange outline on the show on now (2.21).
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selectedRow && isNow ? Theme.accent : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(programme.title)
    }

    private var detail: String {
        if let streams, gameID != nil {
            return "\(isNow ? "Live · " : "")\(streamCountText(streams))"
        }
        return "\(programme.start.formatted(date: .omitted, time: .shortened)) – \(programme.end.formatted(date: .omitted, time: .shortened))"
    }
}

/// Small live preview of the selected channel, like TiviMate. It shares one player with full screen,
/// so going full screen (and back) carries on without reconnecting.
struct GuidePreview: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @AppStorage(Prefs.guidePreview) private var enabled = true
    @ObservedObject private var controller = PlaybackController.shared
    @State private var stopped = false
    let channel: Channel?
    var onExpand: (() -> Void)? = nil

    private var key: String {
        "\(channel?.id ?? 0)|\(model.nowPlaying == nil)|\(enabled)|\(stopped)"
    }

    private var url: URL? {
        channel.flatMap { model.streamURL(for: $0, hls: !PlaybackController.usesVLC) }
    }

    /// The picture can only be in one place, so it leaves the mini player while full screen is open.
    private var showsVideo: Bool {
        enabled && channel != nil && model.nowPlaying == nil
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.black)

            if showsVideo && !stopped {
                VideoSurface(view: controller.view)

                switch controller.status {
                case .opening, .buffering:
                    ProgressView().controlSize(.small)
                case .failed:
                    Text("Preview unavailable")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                default:
                    EmptyView()
                }
            }

            if !enabled || channel == nil || stopped {
                SmallLogoImage(url: channel?.icon, size: 64) {
                    Image(systemName: "tv")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.muted)
                }
                .frame(width: 120, height: 70)
            }

            if enabled, channel != nil, model.nowPlaying == nil {
                Button {
                    if stopped {
                        stopped = false
                        if let url { controller.play(url, bufferMs: bufferMs) }
                    } else {
                        stopped = true
                        controller.stop()
                    }
                } label: {
                    Image(systemName: stopped ? "play.fill" : "stop.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(.black.opacity(0.6)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(stopped ? "Play" : "Stop")
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .zIndex(2)
            }

            if let onExpand, channel != nil {
                // The video view swallows clicks, so this clear layer catches the double-click.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onExpand() }
                    .overlay(alignment: .bottomTrailing) {
                        Button(action: onExpand) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.text)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(.black.opacity(0.6)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Watch full screen (or double-click)")
                        .padding(10)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: key) {
            // While full screen is open it owns the player; leave it alone.
            guard model.nowPlaying == nil else { return }
            guard enabled, !stopped, channel != nil, let url else {
                controller.stop()
                return
            }
            if url == controller.currentURL {
                controller.play(url, bufferMs: bufferMs)   // already loaded: carries on, no reconnect
                model.previewChannel = channel
                return
            }
            // Wait a moment so scrolling through channels doesn't open every stream on the way.
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            controller.play(url, bufferMs: bufferMs)
            model.previewChannel = channel
        }
        .onChange(of: controller.resolution) {
            if showsVideo, let channel, !controller.resolution.isEmpty {
                model.recordQuality(channel.id, controller.resolution)
            }
        }
        .onChange(of: controller.frameRate) {
            if showsVideo, let channel { model.recordFrameRate(channel.id, controller.frameRate) }
        }
        .onChange(of: channel?.id) { stopped = false }
        .onAppear { model.miniPlayers += 1 }
        .onDisappear {
            model.miniPlayers -= 1
            // Switching tabs keeps it playing in the background; anything else stops it.
            if model.nowPlaying == nil && model.backgroundChannel == nil { controller.stop() }
        }
    }
}
