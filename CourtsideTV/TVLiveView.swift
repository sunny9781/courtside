import SwiftUI

/// Live TV: categories down the left (grouped like the Mac guide), channels with what's on now on the right.
struct TVLiveView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.guideCategory) private var selectedID = ""

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
            HStack(alignment: .top, spacing: 40) {
                categoryList
                    .frame(width: 560)
                channelList
            }
            .padding(.horizontal, 60)
        }
    }

    private var categoryList: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(groups) { group in
                    if !group.name.isEmpty {
                        Text(group.name.uppercased())
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 24)
                            .padding(.horizontal, 24)
                    }
                    ForEach(group.entries) { entry in
                        Button {
                            selectedID = entry.id
                        } label: {
                            HStack {
                                Text(entry.name)
                                    .font(.system(size: 24, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                        .buttonStyle(TVRowButtonStyle(selected: entry.id == selected?.id))
                    }
                }
            }
            .padding(.vertical, 20)
        }
    }

    private var channelList: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 8) {
                if let selected {
                    Text(selected.name)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                }
                ForEach(channels) { channel in
                    Button {
                        model.play(channel, lineup: channels)
                    } label: {
                        TVChannelRow(channel: channel)
                    }
                    .buttonStyle(TVRowButtonStyle())
                }
            }
            .padding(.vertical, 20)
        }
    }
}

/// A channel in Live TV: logo, name, and what's on now with a progress bar.
struct TVChannelRow: View {
    @EnvironmentObject var model: AppModel
    let channel: Channel

    var body: some View {
        HStack(spacing: 22) {
            TVChannelIcon(url: channel.icon, size: 60)
            VStack(alignment: .leading, spacing: 6) {
                Text(channel.name)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(1)
                if let now = model.currentProgramme(channel) {
                    Text("\(now.title)  ·  until \(now.end.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 20))
                        .opacity(0.7)
                        .lineLimit(1)
                    ProgressView(value: progress(now))
                        .frame(maxWidth: 420)
                }
            }
            Spacer()
            if let quality = model.measuredQuality[channel.id] {
                Text(quality)
                    .font(.system(size: 20, weight: .bold))
                    .opacity(0.7)
            }
        }
    }

    private func progress(_ p: Programme) -> Double {
        let total = p.end.timeIntervalSince(p.start)
        guard total > 0 else { return 0 }
        return min(max(Date().timeIntervalSince(p.start) / total, 0), 1)
    }
}
