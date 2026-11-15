import SwiftUI
import AppKit

/// TiviMate-style guide: categories on the left, a preview and details of the selected channel on top,
/// and the channel grid below. Click selects and previews, double-click (or Return) watches full screen.
struct GuideView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.guideHours) private var guideHours = 6
    @AppStorage(Prefs.guideCategory) private var categoryID = ""
    @AppStorage(Prefs.guideGrouped) private var grouped = true
    @State private var categorySearch = ""
    @State private var channelSearch = ""
    @State private var expanded: Set<String> = []
    @State private var selectedID: Int?
    @State private var offset = 0          // in half hours from the default start
    @FocusState private var gridFocused: Bool
    let onOpenGame: (String) -> Void

    static let allID = "__all"
    static let recentID = "__recent"

    private let slotWidth: CGFloat = 200   // width of 30 minutes
    private let rowHeight: CGFloat = 56

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let list = rows
            let selected = list.first { $0.id == selectedID }

            HStack(spacing: 0) {
                categoryList

                VStack(alignment: .leading, spacing: 16) {
                    infoPanel(selected ?? model.backgroundChannel, now: now)

                    if let status = model.guideStatus {
                        Banner(text: status, icon: "tablecells")
                    }

                    listHeader(count: list.count)

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
            if selectedID != nil { model.backgroundChannel = nil }
        }
        .onAppear {
            pickDefaultCategory()
            gridFocused = true
        }
        .onChange(of: model.categories) { pickDefaultCategory() }
        .onChange(of: model.lastPlayedChannelID) {
            if let id = model.lastPlayedChannelID, rows.contains(where: { $0.id == id }) { selectedID = id }
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
        var id: String { node.id }
    }

    private func visibleNodes(_ nodes: [CategoryGrouping.Node], depth: Int = 0) -> [VisibleNode] {
        var out: [VisibleNode] = []
        for node in nodes {
            out.append(VisibleNode(node: node, depth: depth))
            if node.isGroup && expanded.contains(node.id) {
                out += visibleNodes(node.children, depth: depth + 1)
            }
        }
        return out
    }

    private func channelCount(_ cats: [ChannelCategory]) -> Int {
        cats.reduce(0) { $0 + (model.channelsByCategory[$1.id]?.count ?? 0) }
    }

    private var currentTitle: String {
        switch categoryID {
        case Self.allID: return "All channels"
        case Self.recentID: return "Recently watched"
        default:
            if let node = CategoryGrouping.find(categoryID, in: model.categoryTree), node.isGroup {
                return node.id.dropFirst(CategoryGrouping.nodePrefix.count).replacingOccurrences(of: "/", with: " › ")
            }
            return model.categories.first { $0.id == categoryID }?.name ?? ""
        }
    }

    private func pickDefaultCategory() {
        guard !model.categories.isEmpty else { return }
        let known = model.categories.contains { $0.id == categoryID }
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
        let query = categorySearch.trimmingCharacters(in: .whitespaces).lowercased()

        return VStack(alignment: .leading, spacing: 12) {
            Field(placeholder: "Search categories", text: $categorySearch)

            Toggle(isOn: $grouped) {
                Text("Group similar categories")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.soft)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Theme.accent)
            .padding(.horizontal, 4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !query.isEmpty {
                        let found = model.categories.filter { $0.name.lowercased().contains(query) }
                        if found.isEmpty {
                            Text("No categories match.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                                .padding(12)
                        }
                        ForEach(found) { cat in
                            CategoryRow(name: cat.name, count: model.channelsByCategory[cat.id]?.count ?? 0,
                                        selected: categoryID == cat.id) { choose(cat.id) }
                        }
                    } else if grouped {
                        ForEach(visibleNodes(model.categoryTree)) { item in
                            let node = item.node
                            if node.isGroup {
                                CategoryRow(name: node.name, count: channelCount(node.categories),
                                            selected: categoryID == node.id, depth: item.depth,
                                            expanded: expanded.contains(node.id),
                                            onToggle: {
                                                if expanded.contains(node.id) { expanded.remove(node.id) } else { expanded.insert(node.id) }
                                            }) { choose(node.id) }
                            } else {
                                CategoryRow(name: node.name, count: channelCount(node.categories),
                                            selected: categoryID == node.id, depth: item.depth,
                                            alignWithArrows: true) { choose(node.id) }
                            }
                        }
                    } else {
                        ForEach(model.categories.sorted { CategoryGrouping.sortsBefore($0.name, $1.name) }) { cat in
                            CategoryRow(name: cat.name, count: model.channelsByCategory[cat.id]?.count ?? 0,
                                        selected: categoryID == cat.id) { choose(cat.id) }
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
        .background(Color(hex: 0x11151B))
    }

    /// The chosen category (or group) in the provider's order, narrowed by the channel search.
    private var rows: [Channel] {
        let base: [Channel]
        switch categoryID {
        case Self.allID:
            base = model.channels
        case Self.recentID:
            base = model.recentChannels
        default:
            if let node = CategoryGrouping.find(categoryID, in: model.categoryTree), node.isGroup {
                base = node.categories.flatMap { model.channelsByCategory[$0.id] ?? [] }
            } else {
                base = model.channelsByCategory[categoryID] ?? []
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
            Field(placeholder: "Search channels in \(currentTitle)", text: $channelSearch)
                .frame(width: 280)
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
            GuidePreview(channel: channel, onExpand: channel.map { ch -> () -> Void in { watch(ch, rows) } })
                .frame(width: 340, height: 191)

            if channel == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pick a channel")
                        .font(Theme.display(26))
                        .foregroundStyle(Theme.text)
                    Text("Click a channel to preview it here. Double-click or press Return to watch full screen.")
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
        let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let longest = list.prefix(400).map { ($0.name as NSString).size(withAttributes: [.font: font]).width }.max() ?? 100
        return min(max(longest, 80), 280) + 36 + 64 + 20 + 16
    }

    private func grid(_ list: [Channel], selected: Channel?, now: Date) -> some View {
        GeometryReader { geo in
            let column = channelColumnWidth(list)
            let area = max(geo.size.width - column - 8, 200)
            let windowStart = Self.floorToHalfHour(now).addingTimeInterval(Double(offset) * 1800)
            let windowEnd = windowStart.addingTimeInterval(Double(area / slotWidth) * 1800)

            VStack(spacing: 6) {
                timeHeader(column: column, area: area, windowStart: windowStart, now: now)

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

    private func timeHeader(column: CGFloat, area: CGFloat, windowStart: Date, now: Date) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
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
        let progs = (model.guide[channel.epgID] ?? []).filter { $0.end > windowStart && $0.start < windowEnd }

        return HStack(spacing: 8) {
            ChannelCell(channel: channel, selected: selected, width: column, height: rowHeight)
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

                    ProgrammeBlock(programme: p, width: width, height: rowHeight,
                                   isNow: p.start <= now && p.end > now, selectedRow: selected,
                                   gameID: gameID, streams: gameID.map { model.streamCount($0) })
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
                    Text(name)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(count.formatted())
                        .font(.system(size: 11))
                        .opacity(0.7)
                }
                .padding(.leading, onToggle == nil && !alignWithArrows ? 12 : 2)
                .padding(.trailing, 12)
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

    var body: some View {
        HStack(spacing: 10) {
            Text(channel.number.map(String.init) ?? "")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(selected ? Theme.accent : Theme.muted)
                .frame(width: 36, alignment: .trailing)

            AsyncImage(url: channel.icon) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Text(String(channel.name.prefix(3)).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(5)
            .frame(width: 64, height: height - 14)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.raised))

            Text(channel.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? Theme.accent : Theme.text)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(width: width, height: height, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.card : Color.clear))
        .contentShape(Rectangle())
        .help(channel.name)
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
        .foregroundStyle(gameID != nil ? Theme.matchText : (isNow ? Theme.text : Theme.soft))
        .padding(.horizontal, 10)
        .frame(width: width, height: height, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(background))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(programme.title)
    }

    private var background: Color {
        if gameID != nil { return hovering ? Theme.matchBG.opacity(0.8) : Theme.matchBG }
        if hovering { return Theme.cardHover }
        if selectedRow && isNow { return Color(hex: 0x323B49) }
        if selectedRow || isNow { return Theme.raised }
        return Theme.card
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
                AsyncImage(url: channel?.icon) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
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
        .onChange(of: channel?.id) { stopped = false }
        .onAppear { model.miniPlayers += 1 }
        .onDisappear {
            model.miniPlayers -= 1
            // Switching tabs keeps it playing in the background; anything else stops it.
            if model.nowPlaying == nil && model.backgroundChannel == nil { controller.stop() }
        }
    }
}
