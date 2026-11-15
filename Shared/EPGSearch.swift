import Foundation

/// One search box for the whole EPG: it finds categories by name and channels by name or by what's on now,
/// and returns them grouped by category.
///   "NFL"   → every NFL category (with all its channels), plus NFL channels sitting in other categories.
///   "lions" → just the channels (or games on now) mentioning the Lions, under the categories they're in.
enum EPGSearch {
    struct Hit: Identifiable, Hashable {
        let category: ChannelCategory
        /// Where it sits when grouping is on ("Sports › NFL"), empty otherwise.
        let path: String
        let channels: [Channel]
        /// The category's own name matched (so all its channels are listed).
        let categoryMatched: Bool
        /// Channels matched by their own name or programme (not just by being in a matching category).
        let directHits: Int
        var id: String { category.id }

        /// Opened by default: groups with channel hits, and every group when there are only a few.
        func startsOpen(totalHits: Int) -> Bool { directHits > 0 || totalHits <= 4 }
    }

    @MainActor
    static func run(_ raw: String, model: AppModel, grouped: Bool, now: Date = Date()) -> [Hit] {
        let query = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard query.count >= 2 else { return [] }
        let paths = grouped ? pathMap(model.categoryTree) : [:]

        var hits: [Hit] = []
        for cat in model.categories {
            let channels = model.channelsByCategory[cat.id] ?? []
            let catMatch = cat.name.lowercased().contains(query)
            let direct = channels.filter { ch in
                ch.name.lowercased().contains(query)
                    || (model.currentProgramme(ch, at: now)?.title.lowercased().contains(query) ?? false)
            }
            guard catMatch || !direct.isEmpty else { continue }
            hits.append(Hit(category: cat, path: paths[cat.id] ?? "", channels: catMatch ? channels : direct,
                            categoryMatched: catMatch, directHits: direct.count))
        }
        // Channel hits first (most first), then categories that matched by name, A to Z.
        return hits.sorted { a, b in
            if (a.directHits > 0) != (b.directHits > 0) { return a.directHits > 0 }
            if a.directHits != b.directHits { return a.directHits > b.directHits }
            return CategoryGrouping.sortsBefore(a.category.name, b.category.name)
        }
    }

    /// Every channel found, each once, in the order of the hits.
    static func channels(_ hits: [Hit]) -> [Channel] {
        var seen = Set<Int>()
        return hits.flatMap(\.channels).filter { seen.insert($0.id).inserted }
    }

    /// Category id → "Sports › NFL", from the first place it appears in the tree.
    private static func pathMap(_ nodes: [CategoryGrouping.Node], parent: [String] = []) -> [String: String] {
        var out: [String: String] = [:]
        for node in nodes {
            if node.isGroup {
                for (k, v) in pathMap(node.children, parent: parent + [node.name]) where out[k] == nil { out[k] = v }
            } else if let cat = node.categories.first, out[cat.id] == nil {
                out[cat.id] = parent.joined(separator: " › ")
            }
        }
        return out
    }
}
