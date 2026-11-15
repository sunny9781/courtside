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
    @State private var playingID: Int?
    @FocusState private var focusedCategory: String?
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

    private var selected: Entry? {
        if selectedID.hasPrefix("g:"), let node = CategoryGrouping.find(String(selectedID.dropFirst(2)), in: model.categoryTree) {
            return Entry(id: selectedID, name: node.name, categories: node.categories)
        }
        return allEntries.first { $0.id == selectedID } ?? allEntries.first
    }

    /// The row to land on when coming down from the tabs: the selected category if it's showing, otherwise the
    /// first row of the list.
    private var categoryTarget: String? {
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
        return selected.categories.flatMap { model.channelsByCategory[$0.id] ?? [] }
    }

    /// The channel in the info panel: the one you're on, or what's playing.
    private var infoChannel: Channel? {
        if let id = focusedChannelID, let channel = model.channelByID[id] { return channel }
        return playingChannel
    }

    /// What the mini player plays: the channel you clicked, or what's still playing from Home.
    private var playingChannel: Channel? {
        if let id = playingID { return model.channelByID[id] }
        return model.backgroundChannel
    }

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
                categoryList
                    .frame(width: TVLayout.sidebar)
                    .focusSection()
                VStack(alignment: .leading, spacing: 28) {
                    infoPanel
                    channelList
                        .focusSection()
                }
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
            .onChange(of: focusedChannel) {
                if let focusedChannel { focusedChannelID = focusedChannel }
            }
        }
    }

    // MARK: Categories

    private var categoryList: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 4) {
                Button {
                    grouped.toggle()
                    path = []
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 22))
                        Text("Group similar categories")
                            .font(.system(size: 22, weight: .medium))
                        Spacer()
                        Text(grouped ? "On" : "Off")
                            .font(.system(size: 21, weight: .semibold))
                            .opacity(0.75)
                    }
                }
                .buttonStyle(TVRowButtonStyle())
                .padding(.bottom, 6)

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
                    ForEach(levelNodes) { node in
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
                        } else {
                            categoryRow(Entry(id: node.id, name: node.name, categories: node.categories))
                        }
                    }
                } else {
                    ForEach(allEntries) { entry in
                        categoryRow(entry)
                    }
                }
            }
            .padding(.vertical, 20)
        }
        .onExitCommand(perform: path.isEmpty ? nil : { path.removeLast() })
    }

    private func categoryRow(_ entry: Entry) -> some View {
        Button {
            selectedID = entry.id
        } label: {
            HStack {
                Text(entry.name)
                    .font(.system(size: 24, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(channelCount(entry.categories))")
                    .font(.system(size: 19))
                    .opacity(0.55)
            }
        }
        .buttonStyle(TVRowButtonStyle(selected: entry.id == selected?.id))
        .focused($focusedCategory, equals: entry.id)
    }

    // MARK: Mini player and programme

    private var infoPanel: some View {
        HStack(alignment: .top, spacing: 36) {
            TVPreview(channel: playingChannel, placeholder: "Click a channel to play it here.\nClick it again for full screen.",
                      showing: infoChannel)
                .frame(width: 480, height: 270)

            VStack(alignment: .leading, spacing: 12) {
                if let channel = infoChannel {
                    Text(channel.name)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.soft)
                        .lineLimit(1)
                    if let now = model.currentProgramme(channel) {
                        Text(now.title)
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                        Text("\(now.start.formatted(date: .omitted, time: .shortened)) – \(now.end.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.muted)
                        ProgressView(value: progress(now))
                            .frame(maxWidth: 520)
                        if let next = nextProgramme(channel, after: now) {
                            Text("Next: \(next.title) at \(next.start.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 22))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                    } else {
                        Text("No guide information")
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.muted)
                    }
                    Text(model.backgroundChannel != nil && playingID == nil
                         ? "Still playing from Home. Click a channel to change it."
                         : (channel.id == playingChannel?.id ? "Click again for full screen." : "Click to play it in the mini player."))
                        .font(.system(size: 19))
                        .foregroundStyle(Theme.muted.opacity(0.8))
                } else {
                    Text("Pick a channel")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("Click a channel to play it here. Click it again for full screen.")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 270)
    }

    // MARK: Channels

    private var channelList: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text(selected?.name ?? "")
                        .frame(width: 430, alignment: .leading)
                    Text("NOW").frame(maxWidth: .infinity, alignment: .leading)
                    Text("NEXT").frame(width: 360, alignment: .leading)
                }
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 22)
                .padding(.bottom, 6)

                ForEach(channels) { channel in
                    Button {
                        if channel.id == playingChannel?.id {
                            model.play(channel, lineup: channels)
                        } else {
                            playingID = channel.id
                            model.backgroundChannel = nil
                        }
                    } label: {
                        TVChannelRow(channel: channel, playing: channel.id == playingChannel?.id)
                    }
                    .buttonStyle(TVRowButtonStyle())
                    .focused($focusedChannel, equals: channel.id)
                }
            }
            .padding(.vertical, 10)
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

    var body: some View {
        let now = model.currentProgramme(channel)
        let next = now.flatMap { n in model.guide[channel.epgID]?.first { $0.start >= n.end } }
        HStack(spacing: 0) {
            HStack(spacing: 16) {
                TVChannelIcon(url: channel.icon, size: 48)
                Text(channel.name)
                    .font(.system(size: 23, weight: .semibold))
                    .lineLimit(1)
                if playing {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 18))
                }
            }
            .frame(width: 408, alignment: .leading)

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
        }
    }

    private func progress(_ p: Programme) -> Double {
        let total = p.end.timeIntervalSince(p.start)
        guard total > 0 else { return 0 }
        return min(max(Date().timeIntervalSince(p.start) / total, 0), 1)
    }
}
