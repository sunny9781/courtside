import SwiftUI

/// EPG: a search field with a "Group" filter, then groups → categories → channels, opened in place.
/// Tap a channel to play it in the pinned player at the top; tap it again for full screen (swipe up/down flips
/// through the category).
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

    // MARK: Data

    private var allCategories: [ChannelCategory] {
        model.categories.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var openNodes: [CategoryGrouping.Node] {
        var out: [CategoryGrouping.Node] = []
        var level = model.categoryTree
        for id in path where !id.hasPrefix("cat:") {
            guard let node = level.first(where: { $0.id == id }) else { break }
            out.append(node)
            level = node.children
        }
        return out
    }

    /// The category whose channels are showing, if one is open.
    private var openCategory: (name: String, categories: [ChannelCategory])? {
        guard let last = path.last, last.hasPrefix("cat:") else { return nil }
        let id = String(last.dropFirst(4))
        if grouped {
            if let group = openNodes.last, group.id == id { return (group.name, group.categories) }
            let level = openNodes.last?.children ?? model.categoryTree
            if let node = level.first(where: { $0.id == id }) { return (node.name, node.categories) }
        }
        if let cat = model.categories.first(where: { $0.id == id }) { return (cat.name, [cat]) }
        return nil
    }

    private var channels: [Channel] {
        guard let open = openCategory else { return [] }
        return open.categories.flatMap { model.channelsByCategory[$0.id] ?? [] }
    }

    /// What's in the pinned player.
    private var playing: Channel? { model.pinned?.channel }

    // MARK: Layout

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Search categories and channels", text: $search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))

                IOSChip(selected: grouped, action: { grouped.toggle(); path = [] }) {
                    Label("Group", systemImage: "square.stack.3d.up")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            if !path.isEmpty {
                Button {
                    path.removeLast()
                    search = ""
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.subheadline.weight(.semibold))
                        Text(breadcrumb).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                }
            }

            if model.channels.isEmpty {
                Spacer()
                Text(model.downloadingChannels ? "Downloading channels…" : (model.errorMessage ?? "No channels yet."))
                    .foregroundStyle(Theme.muted)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if search.trimmingCharacters(in: .whitespaces).count >= 2 {
                            searchResults
                        } else if openCategory != nil {
                            ForEach(channels) { channel in
                                Button { tap(channel) } label: {
                                    IOSChannelRow(channel: channel, playing: channel.id == playing?.id)
                                }
                                .buttonStyle(.plain)
                                Divider().overlay(Theme.raised).padding(.leading, 62)
                            }
                        } else if grouped {
                            if let group = openNodes.last {
                                categoryRow("All \(group.name) channels", count: count(group.categories), group: false) {
                                    open("cat:" + group.id)
                                }
                            }
                            ForEach(openNodes.last?.children ?? model.categoryTree) { node in
                                if node.isGroup {
                                    categoryRow(node.name, count: node.categories.count, group: true) { open(node.id) }
                                } else {
                                    categoryRow(node.name, count: count(node.categories), group: false) { open("cat:" + node.id) }
                                }
                            }
                        } else {
                            ForEach(allCategories) { cat in
                                categoryRow(cat.name, count: model.channelsByCategory[cat.id]?.count ?? 0, group: false) {
                                    open("cat:" + cat.id)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
        }
        .background(Theme.bg)
        .task(id: "\(search)|\(grouped)") {
            // A moment after typing stops, search every category and channel.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            hits = EPGSearch.run(search, model: model, grouped: grouped)
            flipped = []
        }
    }

    private var breadcrumb: String {
        var names = openNodes.map(\.name)
        if let open = openCategory, open.name != names.last { names.append(open.name) }
        return names.joined(separator: " › ")
    }

    private func count(_ categories: [ChannelCategory]) -> Int {
        categories.reduce(0) { $0 + (model.channelsByCategory[$1.id]?.count ?? 0) }
    }

    private func open(_ id: String) {
        path.append(id)
        search = ""
    }

    private func isOpen(_ hit: EPGSearch.Hit) -> Bool {
        hit.startsOpen(totalHits: hits.count) != flipped.contains(hit.id)
    }

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
                ForEach(hit.channels) { channel in
                    Button {
                        if channel.id == playing?.id { fullScreen(channel) } else { model.pin(channel, lineup: hit.channels) }
                    } label: {
                        IOSChannelRow(channel: channel, playing: channel.id == playing?.id)
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Theme.raised).padding(.leading, 62)
                }
            }
        }
    }

    /// Tap once to play it in the pinned player at the top, tap again for full screen.
    private func tap(_ channel: Channel) {
        if channel.id == playing?.id {
            fullScreen(channel)
        } else {
            model.pin(channel, lineup: currentLineup(channel))
        }
    }

    private func currentLineup(_ channel: Channel) -> [Channel] {
        let list = openCategory.map { $0.categories.flatMap { model.channelsByCategory[$0.id] ?? [] } } ?? []
        return list.isEmpty ? [channel] : list
    }

    private func fullScreen(_ channel: Channel) {
        model.play(channel, gameTitle: model.pinned?.gameTitle, lineup: model.pinned?.lineup ?? currentLineup(channel))
    }

    private func categoryRow(_ name: String, count: Int, group: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: group ? "folder.fill" : "list.bullet")
                    .foregroundStyle(group ? Theme.accent : Theme.muted)
                    .frame(width: 24)
                Text(name).foregroundStyle(Theme.text).lineLimit(1)
                Spacer()
                Text("\(count)").font(.subheadline).foregroundStyle(Theme.muted)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider().overlay(Theme.raised).padding(.leading, 52) }
    }
}

struct IOSChannelRow: View {
    @EnvironmentObject var model: AppModel
    let channel: Channel
    var playing = false

    var body: some View {
        let now = model.currentProgramme(channel)
        let next = now.flatMap { n in model.guide[channel.epgID]?.first { $0.start >= n.end } }
        HStack(spacing: 12) {
            IOSChannelIcon(url: channel.icon, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(channel.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(playing ? Theme.accent : Theme.text)
                        .lineLimit(1)
                    if playing {
                        Image(systemName: "speaker.wave.2.fill").font(.caption).foregroundStyle(Theme.accent)
                    }
                    Spacer()
                    if let q = model.measuredQuality[channel.id] { IOSBadge(text: q) }
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
        .contentShape(Rectangle())
    }

    private func progress(_ p: Programme) -> Double {
        let total = p.end.timeIntervalSince(p.start)
        guard total > 0 else { return 0 }
        return min(max(Date().timeIntervalSince(p.start) / total, 0), 1)
    }
}
