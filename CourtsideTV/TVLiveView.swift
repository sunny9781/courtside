import SwiftUI

/// EPG, laid out like the Mac guide: categories down the left (grouped), the mini player and what's on at the
/// top, and the channels with what's on now and next below. Moving onto a channel previews it; clicking it
/// goes full screen, where up/down flips through the category.
struct TVLiveView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.guideCategory) private var selectedID = ""
    @State private var focusedChannelID: Int?
    @FocusState private var focusedCategory: String?
    @FocusState private var focusedChannel: Int?

    struct Entry: Identifiable, Hashable {
        let id: String
        let name: String
        let categories: [ChannelCategory]
    }

    struct CategorySection: Identifiable {
        let id: String
        let name: String
        let entries: [Entry]
    }

    /// The category tree flattened into headed lists: "Sports" › "NBA", "Country" › "Foreign › Spain"…
    private var groups: [CategorySection] {
        model.categoryTree.map { node in
            if node.isGroup {
                return CategorySection(id: node.id, name: node.name, entries: leaves(node.children, prefix: ""))
            }
            return CategorySection(id: node.id, name: "", entries: [Entry(id: node.id, name: node.name, categories: node.categories)])
        }
        .reduce(into: [CategorySection]()) { out, group in
            // Single categories at the top level go together under one untitled heading.
            if group.name.isEmpty, let last = out.last, last.name.isEmpty {
                out[out.count - 1] = CategorySection(id: last.id, name: "", entries: last.entries + group.entries)
            } else {
                out.append(group)
            }
        }
    }

    private func leaves(_ nodes: [CategoryGrouping.Node], prefix: String) -> [Entry] {
        nodes.flatMap { node -> [Entry] in
            if node.isGroup {
                return leaves(node.children, prefix: prefix + node.name + " › ")
            }
            return [Entry(id: node.id, name: prefix + node.name, categories: node.categories)]
        }
    }

    private var allEntries: [Entry] { groups.flatMap(\.entries) }

    private var selected: Entry? {
        allEntries.first { $0.id == selectedID } ?? allEntries.first
    }

    private var channels: [Channel] {
        guard let selected else { return [] }
        return selected.categories.flatMap { model.channelsByCategory[$0.id] ?? [] }
    }

    /// The channel in the info panel: the one you're on, or what's playing in the background from Home.
    private var infoChannel: Channel? {
        if let id = focusedChannelID, let channel = model.channelByID[id] { return channel }
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
            .onChange(of: focusedCategory) {
                if let focusedCategory, focusedCategory != selectedID { selectedID = focusedCategory }
            }
            .onChange(of: focusedChannel) {
                if let focusedChannel {
                    focusedChannelID = focusedChannel
                    model.backgroundChannel = nil
                }
            }
        }
    }

    // MARK: Categories

    private var categoryList: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(groups) { group in
                    if !group.name.isEmpty {
                        Text(group.name.uppercased())
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.muted)
                            .kerning(1)
                            .padding(.top, 22)
                            .padding(.bottom, 4)
                            .padding(.horizontal, 22)
                    }
                    ForEach(group.entries) { entry in
                        Button {
                            selectedID = entry.id
                        } label: {
                            HStack {
                                Text(entry.name)
                                    .font(.system(size: 24, weight: .medium))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(entry.categories.reduce(0) { $0 + (model.channelsByCategory[$1.id]?.count ?? 0) })")
                                    .font(.system(size: 19))
                                    .opacity(0.55)
                            }
                        }
                        .buttonStyle(TVRowButtonStyle(selected: entry.id == selected?.id))
                        .focused($focusedCategory, equals: entry.id)
                    }
                }
            }
            .padding(.vertical, 20)
        }
    }

    // MARK: Mini player and programme

    private var infoPanel: some View {
        HStack(alignment: .top, spacing: 36) {
            TVPreview(channel: infoChannel)
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
                    Text(model.backgroundChannel != nil && focusedChannelID == nil
                         ? "Still playing from Home. Pick a channel to change it."
                         : "Click to watch full screen.")
                        .font(.system(size: 19))
                        .foregroundStyle(Theme.muted.opacity(0.8))
                } else {
                    Text("Pick a channel")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("Move onto a channel to preview it here. Click to watch full screen.")
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
                        model.play(channel, lineup: channels)
                    } label: {
                        TVChannelRow(channel: channel, playing: channel.id == model.previewChannel?.id)
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
