import Foundation

/// Groups the provider's categories into a tree, worked out from the names every time they load,
/// so it keeps up when the provider renames or adds categories.
///
/// Everything A to Z (names starting with a number first):
/// 24/7 · Country (Canada, UK, USA…, and Foreign › Brazil, Mexico…) · Sports (4K, leagues, countries, streaming services)
/// · other shared prefixes (like a provider's own brand) · Random (categories that fit nowhere else).
enum CategoryGrouping {
    struct Node: Identifiable, Hashable {
        let id: String
        let name: String
        let children: [Node]
        /// Every provider category under this node (just one for a single category).
        let categories: [ChannelCategory]

        var isGroup: Bool { !children.isEmpty }
    }

    static let sportsGroup = "Sports"
    static let countryGroup = "Country"
    static let foreignGroup = "Foreign"
    static let randomGroup = "Random"
    static let allDayGroup = "24/7"
    static let nodePrefix = "__node:"
    static let servicesGroup = "Streaming services"

    // MARK: Building

    static func build(_ categories: [ChannelCategory]) -> [Node] {
        // 1. Where each category would go. Sports and 24/7 are final; country and prefix groups
        //    only count when at least two categories land in them.
        var final: [String: [String]] = [:]
        var candidate: [String: [String]] = [:]
        var counts: [String: Int] = [:]
        for cat in categories {
            let name = cat.name
            if isAllDay(name) {
                final[cat.id] = [allDayGroup]
            } else if let country = foreignCountry(name) {
                // Always kept, even a country with one category (it then sits directly under Foreign).
                final[cat.id] = [countryGroup, foreignGroup, country]
            } else if isUHD(name) {
                final[cat.id] = [sportsGroup, "4K"]
            } else if isSports(name) {
                final[cat.id] = sportsPath(name)
            } else if let p = split(name).prefix {
                candidate[cat.id] = ownCountry(p).map { [countryGroup, $0] } ?? [p]
            } else {
                final[cat.id] = [randomGroup]
            }
            if let c = candidate[cat.id] { counts[c.joined(separator: "/"), default: 0] += 1 }
        }

        // 2. A country or prefix with a single category goes to Random instead.
        let items: [(ChannelCategory, [String])] = categories.map { cat in
            if let path = final[cat.id] { return (cat, path) }
            if let c = candidate[cat.id], (counts[c.joined(separator: "/")] ?? 0) > 1 { return (cat, c) }
            return (cat, [randomGroup])
        }

        return sorted(makeNodes(items, parentPath: [], depth: 0))
    }

    /// A to Z at every level, with names starting with a number first.
    private static func sorted(_ nodes: [Node]) -> [Node] {
        nodes.map { n in
            Node(id: n.id, name: n.name, children: Self.sorted(n.children), categories: n.categories)
        }
        .sorted { sortsBefore($0.name, $1.name) }
    }

    /// Finder-style order: numbers before letters, and "2" before "10".
    static func sortsBefore(_ a: String, _ b: String) -> Bool {
        a.localizedStandardCompare(b) == .orderedAscending
    }

    private enum Entry {
        case single(ChannelCategory)
        case bucket(String)
    }

    private static func makeNodes(_ items: [(ChannelCategory, [String])], parentPath: [String], depth: Int) -> [Node] {
        var entries: [Entry] = []
        var buckets: [String: [(ChannelCategory, [String])]] = [:]
        for (cat, path) in items {
            if let key = path.first {
                if buckets[key] == nil { entries.append(.bucket(key)) }
                buckets[key, default: []].append((cat, Array(path.dropFirst())))
            } else {
                entries.append(.single(cat))
            }
        }
        return entries.map { entry -> Node in
            switch entry {
            case .single(let cat):
                return leaf(cat, group: parentPath.last)
            case .bucket(let key):
                let members = buckets[key] ?? []
                if members.count == 1 { return leaf(members[0].0, group: parentPath.last) }
                let path = parentPath + [key]
                return Node(id: nodePrefix + path.joined(separator: "/"), name: key,
                            children: makeNodes(members, parentPath: path, depth: depth + 1),
                            categories: members.map(\.0))
            }
        }
    }

    /// Full category name, except the prefix is dropped when the group is already that prefix
    /// ("CA | Entertainment" shows as "Entertainment" under CA, but "IE | Sports" stays whole under Sports).
    private static func leaf(_ cat: ChannelCategory, group: String?) -> Node {
        let parts = split(cat.name)
        let prefix = parts.prefix?.lowercased()
        let sameCountry = parts.prefix.flatMap { countryName($0) } == group
        let short = group != nil && (prefix == group?.lowercased() || sameCountry || (prefix?.contains("sport") ?? false))
        return Node(id: cat.id, name: short ? parts.rest : cat.name, children: [], categories: [cat])
    }

    static func find(_ id: String, in nodes: [Node]) -> Node? {
        for node in nodes {
            if node.id == id { return node }
            if let hit = find(id, in: node.children) { return hit }
        }
        return nil
    }

    // MARK: Reading names

    /// "UK | Sky Sports" → ("UK", "Sky Sports"). Also splits on ":".
    static func split(_ name: String) -> (prefix: String?, rest: String) {
        for separator in ["|", ":"] {
            if let range = name.range(of: separator) {
                let head = name[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let tail = name[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !head.isEmpty && head.count <= 24 {
                    return (head, tail.isEmpty ? name : tail)
                }
            }
        }
        return (nil, name)
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// Sports by league, else by country prefix (US, UK, CA…), else under Streaming services.
    private static func sportsPath(_ name: String) -> [String] {
        if let league = league(name) { return [sportsGroup, league] }
        if let prefix = split(name).prefix, !prefix.lowercased().contains("sport") { return [sportsGroup, prefix.uppercased()] }
        return [sportsGroup, servicesGroup, serviceKey(name)]
    }

    private static let ownCountries: [String: String] = [
        "us": "USA", "usa": "USA", "uk": "UK", "gb": "UK", "england": "UK", "ca": "Canada", "can": "Canada",
        "canada": "Canada", "au": "Australia", "aus": "Australia", "australia": "Australia", "nz": "New Zealand",
        "ie": "Ireland", "ireland": "Ireland", "car": "Caribbean", "carib": "Caribbean", "caribbean": "Caribbean"
    ]

    /// English-speaking countries from a prefix like "US" or "CA". Foreign ones come from foreignCountry.
    static func ownCountry(_ prefix: String) -> String? {
        ownCountries[prefix.lowercased()]
    }

    /// The country a prefix stands for, English-speaking or not.
    static func countryName(_ prefix: String) -> String? {
        ownCountry(prefix) ?? foreignCountry(prefix + " | x")
    }

    static func isAllDay(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("24/7") || lower.contains("24-7") || lower.contains("24x7") || words(name).contains("247")
    }

    static func isUHD(_ name: String) -> Bool {
        let w = Set(words(name))
        return !w.isDisjoint(with: ["4k", "uhd", "2160p", "2160"]) || name.contains("ᵁᴴᴰ") || name.contains("⁴ᴷ")
    }

    // MARK: Foreign

    /// Prefixes treated as your own, English-language groups.
    private static let english: Set<String> = ["us", "usa", "uk", "gb", "ca", "can", "canada", "au", "aus", "nz", "ie", "en", "eng", "english"]

    private static let codes: [String: String] = [
        "br": "Brazil", "mx": "Mexico", "es": "Spain", "pt": "Portugal", "fr": "France", "de": "Germany", "it": "Italy",
        "nl": "Netherlands", "be": "Belgium", "pl": "Poland", "tr": "Turkey", "ar": "Arabic", "arb": "Arabic",
        "in": "India", "pk": "Pakistan", "ph": "Philippines", "al": "Albania", "gr": "Greece", "ro": "Romania",
        "ru": "Russia", "ua": "Ukraine", "se": "Sweden", "no": "Norway", "dk": "Denmark", "fi": "Finland",
        "lat": "Latino", "latam": "Latino", "cr": "Costa Rica", "co": "Colombia", "cl": "Chile", "pe": "Peru",
        "ve": "Venezuela", "ec": "Ecuador", "do": "Dominican Republic", "hu": "Hungary", "cz": "Czechia",
        "sk": "Slovakia", "bg": "Bulgaria", "rs": "Serbia", "hr": "Croatia", "ba": "Bosnia", "mk": "Macedonia",
        "si": "Slovenia", "ch": "Switzerland", "at": "Austria", "il": "Israel", "ir": "Iran", "af": "Afghanistan",
        "jp": "Japan", "kr": "Korea", "cn": "China", "vn": "Vietnam", "th": "Thailand", "my": "Malaysia",
        "id": "Indonesia", "so": "Somalia", "et": "Ethiopia", "ht": "Haiti", "ku": "Kurdish", "exyu": "Ex-Yu",
        "ex-yu": "Ex-Yu", "afr": "Africa", "pr": "Puerto Rico", "cu": "Cuba", "ni": "Nicaragua", "hn": "Honduras",
        "gt": "Guatemala", "sv": "El Salvador", "pa": "Panama", "uy": "Uruguay", "py": "Paraguay", "bo": "Bolivia"
    ]

    private static let countries: [String] = [
        "brazil", "brasil", "costa rica", "mexico", "spain", "espana", "portugal", "france", "germany", "deutschland",
        "italy", "italia", "netherlands", "holland", "belgium", "poland", "turkey", "turkiye", "arabic", "arab",
        "india", "indian", "hindi", "punjabi", "tamil", "telugu", "urdu", "pakistan", "bangla", "bangladesh",
        "philippines", "filipino", "albania", "greece", "greek", "romania", "russia", "russian", "ukraine",
        "sweden", "norway", "denmark", "finland", "nordic", "scandinavia", "latino", "latin", "latam", "spanish",
        "portuguese", "french", "german", "italian", "argentina", "colombia", "chile", "peru", "venezuela",
        "ecuador", "dominican", "honduras", "guatemala", "el salvador", "panama", "uruguay", "paraguay", "bolivia",
        "hungary", "czech", "slovakia", "bulgaria", "serbia", "croatia", "bosnia", "macedonia", "slovenia",
        "balkan", "ex-yu", "exyu", "switzerland", "austria", "israel", "iran", "persian", "farsi", "afghan",
        "kurdish", "japan", "korea", "china", "chinese", "vietnam", "thai", "thailand", "malaysia", "indonesia",
        "somali", "ethiopia", "haiti", "africa", "nigeria", "ghana", "kenya", "armenia", "georgia", "azerbaijan",
        "lithuania", "latvia", "estonia", "malta", "cyprus", "quebec", "francais", "puerto rico", "cuba",
        "nicaragua", "venezuela", "mexican", "brazilian", "caribe"
    ]

    /// The country or language for foreign categories: from a prefix like "BR |" or "Brazil |",
    /// or a name that starts with a country.
    static func foreignCountry(_ name: String) -> String? {
        let (prefix, _) = split(name)
        let probe = (prefix ?? name).lowercased().trimmingCharacters(in: .whitespaces)
        if let prefix {
            let p = prefix.lowercased()
            // "CA | French" or "US | Latino" belong to that country, not to Foreign.
            if english.contains(p) { return nil }
            if let n = codes[p] { return n }
            if let c = countries.first(where: { p == $0 || p.hasPrefix($0 + " ") }) { return display(c) }
            return nil
        }
        if let c = countries.first(where: { probe.hasPrefix($0 + " ") || probe == $0 }) { return display(c) }
        return nil
    }

    private static func display(_ country: String) -> String {
        let aliases = ["brasil": "Brazil", "espana": "Spain", "deutschland": "Germany", "italia": "Italy",
                       "holland": "Netherlands", "turkiye": "Turkey", "arab": "Arabic", "latin": "Latino",
                       "latam": "Latino", "exyu": "Ex-Yu", "ex-yu": "Ex-Yu", "francais": "French"]
        return aliases[country] ?? country.capitalized
    }

    // MARK: Sports

    private static let sportWords: Set<String> = [
        "sport", "sports", "nba", "wnba", "nfl", "nhl", "mlb", "ncaa", "ncaaf", "ncaab", "mls", "epl", "soccer",
        "ppv", "ufc", "boxing", "wwe", "wrestling", "mma", "f1", "nascar", "indycar", "motogp", "golf", "tennis",
        "cricket", "rugby", "dazn", "espn", "tsn", "sportsnet", "bein", "redzone", "fanduel", "flosports", "uefa",
        "laliga", "bundesliga", "ligue", "olympics", "efl", "fifa", "ahl", "chl", "hockey", "basketball", "baseball"
    ]

    private static let sportPhrases = ["league pass", "sunday ticket", "center ice", "premier league", "sky sports",
                                       "tnt sports", "champions league", "serie a", "red zone", "mlb tv"]

    static func isSports(_ name: String) -> Bool {
        let lower = name.lowercased()
        return !Set(words(name)).isDisjoint(with: sportWords) || sportPhrases.contains { lower.contains($0) }
    }

    private static let leagues: [(name: String, words: [String], phrases: [String])] = [
        ("WNBA", ["wnba"], []),
        ("NBA", ["nba"], []),
        ("NFL", ["nfl", "redzone"], ["sunday ticket", "red zone"]),
        ("Hockey", ["nhl", "ahl", "chl", "ohl", "whl", "qmjhl", "khl", "hockey"], ["center ice"]),
        ("MLB", ["mlb"], ["mlb tv"]),
        ("NCAA", ["ncaa", "ncaaf", "ncaab", "college"], ["big ten", "sec network", "acc network", "pac-12", "pac 12"]),
        ("Soccer", ["soccer", "epl", "efl", "mls", "laliga", "bundesliga", "ligue", "uefa", "futbol", "fifa", "concacaf"],
         ["premier league", "champions league", "serie a"]),
        ("Fighting", ["ufc", "boxing", "ppv", "wwe", "wrestling", "mma"], []),
        ("Motorsport", ["f1", "nascar", "indycar", "motogp", "formula"], []),
        ("Golf", ["golf"], []),
        ("Tennis", ["tennis"], []),
        ("Cricket", ["cricket"], []),
        ("Rugby", ["rugby"], [])
    ]

    /// The league or sport a category name mentions, if any.
    static func league(_ name: String) -> String? {
        let w = Set(words(name))
        let lower = name.lowercased()
        return leagues.first(where: { l in !w.isDisjoint(with: l.words) || l.phrases.contains { lower.contains($0) } })?.name
    }

    private static let regionSuffixes: Set<String> = ["uk", "us", "usa", "ca", "de", "fr", "es", "it", "au", "nz", "ie",
                                                       "mx", "br", "latam", "intl", "international"]

    /// The service a category belongs to, so its variants sit together:
    /// "DAZN UK (2)", "DAZN CA" and "DAZN" all give "DAZN"; "HBO Max US" gives "HBO Max".
    static func serviceKey(_ name: String) -> String {
        let parts = split(name)
        var rest = (parts.prefix?.lowercased().contains("sport") ?? false) ? parts.rest : name
        if let range = rest.range(of: #"\s*\(\d+\)\s*$"#, options: .regularExpression) {
            rest.removeSubrange(range)
        }
        var pieces = rest.split(separator: " ").map(String.init)
        if pieces.count > 1, let last = pieces.last, regionSuffixes.contains(last.lowercased()) {
            pieces.removeLast()
        }
        let key = pieces.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? name : key
    }
}
