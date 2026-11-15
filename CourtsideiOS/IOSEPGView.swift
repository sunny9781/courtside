import SwiftUI

/// EPG: groups (Sports, Country, 24/7…) you tap into, then a category's channels with what's on now and next.
/// Search finds categories; inside a category it finds channels. Tap a channel to watch full screen, where
/// swiping up and down flips through that category.
struct IOSEPGView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.guideGrouped) private var grouped = true
    @State private var search = ""

    private var allLeaves: [CategoryGrouping.Node] {
        func leaves(_ nodes: [CategoryGrouping.Node]) -> [CategoryGrouping.Node] {
            nodes.flatMap { $0.isGroup ? leaves($0.children) : [$0] }
        }
        return leaves(model.categoryTree)
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.channels.isEmpty {
                    ContentUnavailableView(model.downloadingChannels ? "Downloading channels…" : "No channels yet",
                                           systemImage: "tv",
                                           description: Text(model.errorMessage ?? ""))
                } else if !search.isEmpty {
                    List(allCategories.filter { $0.name.localizedCaseInsensitiveContains(search) }) { cat in
                        NavigationLink(cat.name) { IOSChannelList(title: cat.name, categories: [cat]) }
                    }
                } else if grouped {
                    IOSCategoryLevel(nodes: model.categoryTree, title: "EPG")
                } else {
                    List(allCategories) { cat in
                        NavigationLink {
                            IOSChannelList(title: cat.name, categories: [cat])
                        } label: {
                            categoryLabel(cat.name, count: model.channelsByCategory[cat.id]?.count ?? 0)
                        }
                    }
                    .navigationTitle("EPG")
                }
            }
            .searchable(text: $search, prompt: "Search categories")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Group similar categories", isOn: $grouped)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    private var allCategories: [ChannelCategory] {
        model.categories.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private func categoryLabel(_ name: String, count: Int, group: Bool = false) -> some View {
    HStack {
        if group {
            Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
        }
        Text(name)
        Spacer()
        Text("\(count)").foregroundStyle(Theme.muted).font(.subheadline)
    }
}

/// One level of the grouped category tree.
struct IOSCategoryLevel: View {
    @EnvironmentObject var model: AppModel
    let nodes: [CategoryGrouping.Node]
    let title: String

    var body: some View {
        List(nodes) { node in
            if node.isGroup {
                NavigationLink {
                    IOSCategoryLevel(nodes: node.children, title: node.name)
                } label: {
                    categoryLabel(node.name, count: node.categories.count, group: true)
                }
            } else {
                NavigationLink {
                    IOSChannelList(title: node.name, categories: node.categories)
                } label: {
                    categoryLabel(node.name, count: node.categories.reduce(0) { $0 + (model.channelsByCategory[$1.id]?.count ?? 0) })
                }
            }
        }
        .navigationTitle(title)
    }
}

/// A category's channels.
struct IOSChannelList: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    let title: String
    let categories: [ChannelCategory]

    private var channels: [Channel] {
        categories.flatMap { model.channelsByCategory[$0.id] ?? [] }
    }

    private var shown: [Channel] {
        search.isEmpty ? channels : channels.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List(shown) { channel in
            Button {
                model.play(channel, lineup: channels)
            } label: {
                IOSChannelRow(channel: channel)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search channels")
    }
}

struct IOSChannelRow: View {
    @EnvironmentObject var model: AppModel
    let channel: Channel

    var body: some View {
        let now = model.currentProgramme(channel)
        let next = now.flatMap { n in model.guide[channel.epgID]?.first { $0.start >= n.end } }
        HStack(spacing: 12) {
            IOSChannelIcon(url: channel.icon, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(channel.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
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
        .contentShape(Rectangle())
    }

    private func progress(_ p: Programme) -> Double {
        let total = p.end.timeIntervalSince(p.start)
        guard total > 0 else { return 0 }
        return min(max(Date().timeIntervalSince(p.start) / total, 0), 1)
    }
}
