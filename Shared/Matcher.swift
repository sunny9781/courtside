import Foundation

/// Ties games to the provider's channels using three signals:
/// the channel name has both teams, the guide shows the game on that channel, or the channel is an official broadcaster.
enum Matcher {
    struct IndexedChannel {
        let channel: Channel
        let tokens: [String]
        let tokenSet: Set<String>
    }

    struct Alias {
        let tokens: [String]
        let notFollowedBy: [String]

        init(_ tokens: [String], notFollowedBy: [String] = []) {
            self.tokens = tokens
            self.notFollowedBy = notFollowedBy
        }
    }

    /// Everything needed to recognise one game in a piece of text.
    struct GameKey {
        let game: Game
        let away: [[String]]
        let home: [[String]]
        let awayLocation: [String]
        let homeLocation: [String]
        let leagueWords: Set<String>
        /// For tournaments, races and fight cards: the event's name in a few forms.
        let eventAliases: [[String]]
        let conflicts: Set<String>
        let triggers: Set<String>
        let from: Date
        let to: Date
    }

    static func tokens(_ text: String) -> [String] {
        let cleaned = String(text.lowercased().map { ($0.isLetter || $0.isNumber) ? $0 : " " })
        return cleaned.split(separator: " ").map(String.init)
    }

    static func index(_ channels: [Channel]) -> [IndexedChannel] {
        channels.map { ch in
            let t = tokens(ch.name)
            return IndexedChannel(channel: ch, tokens: t, tokenSet: Set(t))
        }
    }

    static func has(_ hay: [String], _ needle: [String], notFollowedBy: [String] = []) -> Bool {
        guard !needle.isEmpty, hay.count >= needle.count else { return false }
        for i in 0...(hay.count - needle.count) where hay[i] == needle[0] {
            if Array(hay[i..<(i + needle.count)]) == needle {
                let next = i + needle.count
                if next < hay.count, notFollowedBy.contains(hay[next]) { continue }
                return true
            }
        }
        return false
    }

    static func has(_ hay: [String], _ alias: Alias) -> Bool {
        has(hay, alias.tokens, notFollowedBy: alias.notFollowedBy)
    }

    static func linkKey(_ epg: String, _ start: Date) -> String {
        "\(epg)|\(Int(start.timeIntervalSince1970))"
    }

    // MARK: Teams

    private static let extras: [String: [[String]]] = [
        "76ers": [["sixers"]],
        "trail blazers": [["blazers"]],
        "timberwolves": [["wolves"]],
        "cavaliers": [["cavs"]],
        "mavericks": [["mavs"]],
        "maple leafs": [["leafs"]],
        "golden knights": [["knights"], ["vegas"]],
        "blue jackets": [["jackets"]],
        "manchester united": [["man", "utd"], ["man", "united"]],
        "manchester city": [["man", "city"]],
        "tottenham hotspur": [["tottenham"], ["spurs"]],
        "wolverhampton wanderers": [["wolves"]],
        "nottingham forest": [["forest"], ["nottm", "forest"]],
        "paris saint germain": [["psg"]],
        "inter miami cf": [["inter", "miami"]],
        "bayern munich": [["bayern"]],
        "real madrid": [["madrid"]]
    ]

    private static let proLeagueWords: [Sport: Set<String>] = [
        .basketball: ["nba", "wnba", "ncaab"],
        .football: ["nfl", "ncaaf", "cfl"],
        .hockey: ["nhl"],
        .baseball: ["mlb"],
        .soccer: ["epl", "mls", "ucl"],
        .fighting: ["ufc", "mma", "boxing"],
        .tennis: ["atp", "wta"],
        .motorsport: ["f1", "nascar", "indycar", "motogp"],
        .golf: ["pga", "lpga"],
        .rugby: ["rugby"],
        .aussieRules: ["afl"],
        .lacrosse: ["nll", "pll", "lacrosse"]
    ]

    private static let filler: Set<String> = ["the", "of", "presented", "by", "at", "in", "2025", "2026", "2027", "fia"]

    /// "Nitto ATP Finals" → also "ATP Finals"; "UFC 310: Pantoja vs Asakura" → also "UFC 310".
    /// Only names of two or more words, so a single common word never matches.
    static func eventAliases(_ game: Game) -> [[String]] {
        let t = tokens(game.eventTitle).filter { !filler.contains($0) }
        var out: [[String]] = []
        func add(_ a: [String]) { if a.count >= 2 && !out.contains(a) { out.append(a) } }
        add(t)
        if t.count > 2 { add(Array(t.dropFirst())) }
        if let i = t.firstIndex(of: "ufc"), i + 1 < t.count {
            if t[i + 1].allSatisfy(\.isNumber) { add(["ufc", t[i + 1]]) }
            if t[i + 1] == "fight" { add(["ufc", "fight", "night"]) }
        }
        if let i = t.firstIndex(of: "grand"), i + 1 < t.count, t[i + 1] == "prix", i > 0 {
            add(Array(t[..<i]) + ["gp"])
            add(Array(t[(i - 1)...(i + 1)]))
        }
        return out
    }

    static func aliases(_ team: Team) -> [[String]] {
        var out: [[String]] = []
        for name in [team.nickname, team.shortName, team.name] {
            let t = tokens(name)
            if !t.isEmpty && !out.contains(t) { out.append(t) }
            out += extras[t.joined(separator: " ")] ?? []
        }
        // A full name like "Toronto Raptors" is covered by the nickname; keep it only when it's the sole alias.
        return out
    }

    static func key(for game: Game, now: Date) -> GameKey {
        let away = aliases(game.away)
        let home = aliases(game.home)
        let awayLoc = tokens(game.away.location)
        let homeLoc = tokens(game.home.location)
        var conflicts = Set<String>()
        for (sport, words) in proLeagueWords where sport != game.league.sport {
            conflicts.formUnion(words)
        }
        let events = game.isEvent ? eventAliases(game) : []
        var triggers = Set<String>()
        for a in away + home + events { if let first = a.first { triggers.insert(first) } }
        if let first = awayLoc.first { triggers.insert(first) }
        if let first = homeLoc.first { triggers.insert(first) }
        var from: Date
        var to: Date
        switch game.league.sport {
        case .tennis, .golf:
            // Multi-day tournaments: whatever is on around now.
            from = now.addingTimeInterval(-3 * 3600)
            to = now.addingTimeInterval(12 * 3600)
        default:
            let start = game.start ?? now
            let length: TimeInterval
            switch game.league.sport {
            case .baseball, .football: length = 4 * 3600
            case .fighting: length = 6 * 3600
            case .motorsport: length = 3 * 3600
            default: length = 3.5 * 3600
            }
            from = start.addingTimeInterval(-20 * 60)
            to = start.addingTimeInterval(length)
        }
        return GameKey(game: game, away: away, home: home, awayLocation: awayLoc, homeLocation: homeLoc,
                       leagueWords: game.league.keywords, eventAliases: events, conflicts: conflicts,
                       triggers: triggers, from: from, to: to)
    }

    static func matches(_ hay: [String], _ set: Set<String>, _ key: GameKey) -> Bool {
        if !set.isDisjoint(with: key.conflicts) { return false }
        if key.eventAliases.contains(where: { has(hay, $0) }) { return true }
        if key.away.contains(where: { has(hay, $0) }) && key.home.contains(where: { has(hay, $0) }) { return true }
        if !set.isDisjoint(with: key.leagueWords), !key.awayLocation.isEmpty, !key.homeLocation.isEmpty,
           has(hay, key.awayLocation), has(hay, key.homeLocation) {
            return true
        }
        return false
    }

    // MARK: Broadcasters

    static func broadcasterAliases(_ name: String) -> [Alias] {
        var t = tokens(name)
        if name.hasSuffix("+") { t.append("plus") }
        switch t.joined(separator: " ") {
        case "espn":
            return [Alias(["espn"], notFollowedBy: ["2", "3", "u", "news", "deportes", "plus"])]
        case "espn2":
            return [Alias(["espn2"]), Alias(["espn", "2"])]
        case "espn plus":
            return [Alias(["espn", "plus"]), Alias(["espn+"])]
        case "abc":
            return [Alias(["abc"], notFollowedBy: ["news"])]
        case "nbc":
            return [Alias(["nbc"], notFollowedBy: ["sports", "news", "golf"])]
        case "cbs":
            return [Alias(["cbs"], notFollowedBy: ["news", "sports", "sn"])]
        case "cbssn", "cbs sports network":
            return [Alias(["cbs", "sports", "network"]), Alias(["cbssn"]), Alias(["cbs", "sn"])]
        case "fox":
            return [Alias(["fox"], notFollowedBy: ["news", "business", "sports", "life", "soccer", "deportes"])]
        case "fs1":
            return [Alias(["fs1"]), Alias(["fox", "sports", "1"])]
        case "fs2":
            return [Alias(["fs2"]), Alias(["fox", "sports", "2"])]
        case "nba tv":
            return [Alias(["nba", "tv"]), Alias(["nbatv"])]
        case "nfl net", "nfl network":
            return [Alias(["nfl", "network"]), Alias(["nfln"])]
        case "nhl net", "nhl network":
            return [Alias(["nhl", "network"])]
        case "mlb net", "mlb network":
            return [Alias(["mlb", "network"])]
        case "usa net", "usa network":
            return [Alias(["usa", "network"])]
        case "prime video", "amazon prime video":
            return [Alias(["prime", "video"]), Alias(["amazon", "prime"])]
        case "sn", "sportsnet":
            return [Alias(["sportsnet"]), Alias(["sn"]), Alias(["sn1"]), Alias(["sn360"])]
        case "tsn":
            return [Alias(["tsn"]), Alias(["tsn1"]), Alias(["tsn2"]), Alias(["tsn3"]), Alias(["tsn4"]), Alias(["tsn5"])]
        case "tnt":
            return [Alias(["tnt"])]
        case "sportsnet one":
            return [Alias(["sportsnet", "one"]), Alias(["sportsnet", "1"]), Alias(["sn1"]), Alias(["sn", "one"])]
        case "sportsnet 360":
            return [Alias(["sportsnet", "360"]), Alias(["sn360"]), Alias(["sn", "360"])]
        case "sportsnet east", "sportsnet ontario", "sportsnet pacific", "sportsnet west":
            return [Alias(t), Alias(["sn", t[1]])]
        case "sportsnet plus":
            return [Alias(["sportsnet", "plus"])]
        case "tva sports":
            return [Alias(["tva", "sports"], notFollowedBy: ["2"]), Alias(["tvas"])]
        case "tva sports 2":
            return [Alias(["tva", "sports", "2"]), Alias(["tvas2"])]
        case "rds":
            return [Alias(["rds"], notFollowedBy: ["2", "info"])]
        case "cbc":
            return [Alias(["cbc"], notFollowedBy: ["news"])]
        case "ctv":
            return [Alias(["ctv"], notFollowedBy: ["news", "2", "drama", "comedy", "sci", "life", "nature", "speed", "wild"])]
        case "amazon prime":
            return [Alias(["prime", "video"]), Alias(["amazon", "prime"])]
        case "sky sports":
            return [Alias(["sky", "sports"], notFollowedBy: ["news", "golf", "f1", "cricket", "racing", "tennis", "arena", "mix"])]
        default:
            break
        }
        // "TSN2" also matches "TSN 2", "RDS2" matches "RDS 2" and so on.
        if t.count == 1, let last = t[0].last, last.isNumber, t[0].count > 1, t[0].dropLast().allSatisfy(\.isLetter) {
            return [Alias(t), Alias([String(t[0].dropLast()), String(last)])]
        }
        if t.first == "nbcs", t.count >= 2 {
            let cities: [String: [String]] = [
                "bos": ["boston"], "phi": ["philadelphia"], "ca": ["california"], "ba": ["bay", "area"]
            ]
            let rest = Array(t[1...])
            let city = cities[rest.joined(separator: " ")] ?? rest
            return [Alias(["nbc", "sports"] + city), Alias(["nbcs"] + city), Alias(t)]
        }
        if t.count >= 3, t[0] == "fanduel", t[1] == "sn" {
            let rest = Array(t[2...])
            return [Alias(["fanduel", "sports"] + rest), Alias(["fanduel", "sn"] + rest),
                    Alias(["fdsn"] + rest), Alias(["bally", "sports"] + rest)]
        }
        return t.isEmpty ? [] : [Alias(t)]
    }

    // MARK: Country of a channel

    private static let countryPrefixes: [String: String] = [
        "uk": "UK", "gb": "UK", "england": "UK", "ca": "Canada", "can": "Canada", "canada": "Canada",
        "us": "USA", "usa": "USA", "es": "Spain", "spain": "Spain", "it": "Italy", "italy": "Italy",
        "de": "Germany", "germany": "Germany", "fr": "France", "france": "France",
        "car": "Caribbean", "au": "Australia", "aus": "Australia", "australia": "Australia", "nz": "New Zealand",
        "ie": "Ireland", "ireland": "Ireland", "mx": "Mexico", "mexico": "Mexico"
    ]

    /// Codes recognised when they stand alone in capitals anywhere in a name: "DAZN UK 42", "DE Sports", "CAR: ESPN 2".
    private static let standaloneCodes: [String: String] = [
        "uk": "UK", "gb": "UK", "us": "USA", "usa": "USA", "ca": "Canada", "can": "Canada", "au": "Australia",
        "nz": "New Zealand", "ie": "Ireland", "de": "Germany", "fr": "France", "es": "Spain", "it": "Italy",
        "mx": "Mexico", "br": "Brazil", "car": "Caribbean", "pt": "Portugal", "nl": "Netherlands"
    ]

    /// Streaming services that belong to one country.
    private static let serviceCountries: [String: String] = [
        "kayo": "Australia", "foxtel": "Australia", "stan": "Australia", "optus": "Australia",
        "fubo": "Canada", "crave": "Canada"
    ]

    /// Where a network is from, when nothing in the name says otherwise.
    private static let networkHomes: [(words: [String], country: String)] = [
        (["espn"], "USA"), (["espn2"], "USA"), (["espnu"], "USA"), (["abc"], "USA"), (["nbc"], "USA"),
        (["cbs"], "USA"), (["fox"], "USA"), (["fs1"], "USA"), (["fs2"], "USA"), (["tnt"], "USA"),
        (["trutv"], "USA"), (["tbs"], "USA"), (["nhl", "network"], "USA"), (["nba", "tv"], "USA"),
        (["nfl", "network"], "USA"), (["mlb", "network"], "USA"), (["peacock"], "USA"), (["paramount"], "USA"),
        (["usa", "network"], "USA"), (["cbssn"], "USA"), (["acc", "network"], "USA"), (["sec", "network"], "USA"),
        (["big", "ten"], "USA"), (["msg"], "USA"), (["nesn"], "USA"),
        (["tsn"], "Canada"), (["tsn1"], "Canada"), (["tsn2"], "Canada"), (["tsn3"], "Canada"), (["tsn4"], "Canada"),
        (["tsn5"], "Canada"), (["sportsnet"], "Canada"), (["rds"], "Canada"), (["tva", "sports"], "Canada"),
        (["cbc"], "Canada"), (["ctv"], "Canada"),
        (["sky", "sports"], "UK"), (["tnt", "sports"], "UK"), (["bbc"], "UK"), (["itv"], "UK"), (["premier", "sports"], "UK")
    ]

    /// The country a channel is for. Checks, in order: a prefix ("UK |", "CA:"), a code in brackets ("(UK) Dazn"),
    /// a code in capitals anywhere ("DAZN UK 42"), a country's streaming service (Kayo), then the network's home.
    static func country(of channel: Channel) -> String? {
        let texts = [channel.name, channel.categoryName]
        for text in texts {
            if let prefix = CategoryGrouping.split(text).prefix?.lowercased(), let c = countryPrefixes[prefix] { return c }
            if let foreign = CategoryGrouping.foreignCountry(text) { return foreign }
            if text.hasPrefix("("), let close = text.firstIndex(of: ")") {
                let code = text[text.index(after: text.startIndex)..<close].trimmingCharacters(in: .whitespaces).lowercased()
                if let c = countryPrefixes[code] ?? standaloneCodes[code] { return c }
            }
        }
        for text in texts {
            let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            for w in words where (2...3).contains(w.count) && w == w.uppercased() && w.allSatisfy(\.isLetter) {
                if let c = standaloneCodes[w.lowercased()] { return c }
            }
        }
        for text in texts {
            let t = Set(tokens(text))
            if let hit = serviceCountries.first(where: { t.contains($0.key) }) { return hit.value }
        }
        let nameTokens = tokens(channel.name)
        if let home = networkHomes.first(where: { has(nameTokens, $0.words) }) { return home.country }
        return nil
    }

    /// The channel's name or category names another sport's league (NBA on a hockey game).
    static func aboutOtherSport(_ c: IndexedChannel, _ key: GameKey) -> Bool {
        if !c.tokenSet.isDisjoint(with: key.conflicts) { return true }
        return !Set(tokens(c.channel.categoryName)).isDisjoint(with: key.conflicts)
    }

    /// An event channel for one specific matchup ("NBA LP 08 | Knicks @ Pacers"). If it didn't match this game's
    /// teams, it's showing a different game.
    static func isOtherEvent(_ c: IndexedChannel) -> Bool {
        let name = c.channel.name
        return name.contains("@") || c.tokenSet.contains("vs") || c.tokenSet.contains("v")
    }

    /// Radio and 24/7 channels never carry a live game.
    static func neverLive(_ channel: Channel) -> Bool {
        let cat = channel.categoryName.lowercased()
        return cat.contains("radio") || CategoryGrouping.isAllDay(channel.categoryName)
            || channel.name.lowercased().hasPrefix("radio")
    }

    /// Local station call signs like KING or WABC only match the exact call sign in capitals,
    /// so they don't pick up "Tiger King" or "Donkey Kong".
    static func isCallSign(_ name: String) -> Bool {
        name.count == 4 && (name.hasPrefix("K") || name.hasPrefix("W")) && name.allSatisfy { $0.isUppercase && $0.isLetter }
    }

    /// For "usually on" guesses: skip a channel whose guide shows something unrelated during the game.
    private static func guideAllows(_ channel: Channel, _ key: GameKey, guide: [String: [Programme]]) -> Bool {
        let progs = (guide[channel.epgID] ?? []).filter { $0.start < key.to && $0.end > key.from }
        guard !progs.isEmpty else { return true }
        let sporty: Set<String> = ["live", "football", "soccer", "hockey", "basketball", "baseball", "match", "game",
                                   "nfl", "nhl", "nba", "mlb", "mls", "premier", "liga", "serie", "bundesliga", "ligue"]
        let words = sporty.union(key.leagueWords).union(key.triggers)
        return progs.contains { !Set(tokens($0.title)).isDisjoint(with: words) }
    }

    // MARK: Local affiliates

    private static let states: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY",
        "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY", "NC", "ND", "OH",
        "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"
    ]

    private static let networks: Set<String> = ["abc", "nbc", "cbs", "fox", "cw", "pbs", "mynetwork", "telemundo", "univision", "ctv", "global", "citytv"]

    /// Local stations: a "local" category, a US call sign like KATN or WABC,
    /// or a state code in front of a network name ("AK | Fairbanks | ABC").
    static func isLocal(_ channel: Channel) -> Bool {
        if channel.categoryName.lowercased().contains("local") { return true }

        let words = channel.name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let hasCallSign = words.contains { w in
            w.count == 4 && (w.hasPrefix("K") || w.hasPrefix("W")) && w.allSatisfy { $0.isUppercase && $0.isLetter }
        }
        if hasCallSign { return true }

        if let first = words.first, first.count == 2, states.contains(first) {
            return words.dropFirst().contains { networks.contains($0.lowercased()) }
        }
        return false
    }

    // MARK: Quality guess from the channel name

    static func quality(_ set: Set<String>) -> (label: String, rank: Int) {
        // Includes the superscript labels some providers use, like "ᵁᴴᴰ" and "ᶠᴴᴰ".
        if !set.isDisjoint(with: ["4k", "uhd", "2160p", "2160", "ᵁᴴᴰ", "ᵘʰᵈ", "⁴ᴷ", "⁴ᵏ"]) { return ("4K", 4) }
        if !set.isDisjoint(with: ["fhd", "1080p", "1080", "ᶠᴴᴰ", "ᶠʰᵈ"]) { return ("1080p", 3) }
        if !set.isDisjoint(with: ["hd", "720p", "720"]) { return ("HD", 2) }
        if !set.isDisjoint(with: ["sd", "480p"]) { return ("SD", 1) }
        return ("", 2)
    }

    // MARK: Matching everything at once

    struct Result {
        var matches: [String: [StreamMatch]] = [:]
        /// Guide programmes that are one of today's games, keyed by linkKey.
        var links: [String: String] = [:]
    }

    /// Sports with no schedule feed (pickleball): events built from what the guide says is on now or in the next
    /// six hours, with the channels showing them as the streams.
    static func guideEvents(league: League, words: [String], channels: [IndexedChannel], guide: [String: [Programme]],
                            measured: [Int: String], now: Date) -> (games: [Game], matches: [String: [StreamMatch]]) {
        struct Found { var title: String; var start: Date; var end: Date; var channels: [IndexedChannel] }
        var found: [String: Found] = [:]
        for c in channels where !c.channel.epgID.isEmpty {
            for p in guide[c.channel.epgID] ?? [] where p.end > now && p.start < now.addingTimeInterval(6 * 3600) {
                let lower = p.title.lowercased()
                guard words.contains(where: { lower.contains($0) }) else { continue }
                let slot = Int(p.start.timeIntervalSince1970 / 900)
                let key = lower.filter { $0.isLetter || $0.isNumber } + "-\(slot)"
                found[key, default: Found(title: p.title, start: p.start, end: p.end, channels: [])].channels.append(c)
            }
        }
        var games: [Game] = []
        var matches: [String: [StreamMatch]] = [:]
        for (key, f) in found {
            let live = f.start <= now
            let id = "guide-\(league.id)-\(key)"
            var game = Game(id: id, league: league, start: f.start, state: live ? .live : .upcoming,
                            statusText: live ? "Live" : f.start.formatted(date: .omitted, time: .shortened),
                            away: .none, home: .none, broadcasters: [])
            game.isEvent = true
            game.eventTitle = f.title
            game.eventDetail = f.channels.count == 1 ? "On \(f.channels[0].channel.name)" : "On \(f.channels.count) channels"
            games.append(game)
            matches[id] = f.channels.map { c in
                var q = quality(c.tokenSet)
                if let real = measured[c.channel.id] {
                    q = (real, real == "4K" ? 4 : (real == "1080p" ? 3 : (real == "720p" ? 2 : 1)))
                }
                return StreamMatch(channel: c.channel, reason: "In the guide", score: 3, quality: q.label, qualityRank: q.rank,
                                   recent: false, local: false, likelyOnly: false, country: country(of: c.channel))
            }.sorted { $0.qualityRank > $1.qualityRank }
        }
        return (games.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }, matches)
    }

    static func matchAll(games: [Game], channels: [IndexedChannel], guide: [String: [Programme]],
                         extras: [String: [Broadcast]] = [:], measured: [Int: String] = [:],
                         recent: Set<Int>, now: Date) -> Result {
        let keys = games.map { key(for: $0, now: now) }
        let triggers = keys.reduce(into: Set<String>()) { $0.formUnion($1.triggers) }
        var result = Result()
        let channels = channels.filter { !neverLive($0.channel) }

        // 1. Guide titles
        var guideHits: [String: Set<String>] = [:]   // game id -> epg ids
        for (epg, progs) in guide {
            for p in progs {
                let hay = tokens(p.title)
                let set = Set(hay)
                guard !set.isDisjoint(with: triggers) else { continue }
                if let k = keys.first(where: { p.start < $0.to && p.end > $0.from && matches(hay, set, $0) }) {
                    result.links[linkKey(epg, p.start)] = k.game.id
                    guideHits[k.game.id, default: []].insert(epg)
                }
            }
        }

        // 2. Channel names
        var nameHits: [String: Set<Int>] = [:]
        for c in channels where !c.tokenSet.isDisjoint(with: triggers) {
            for k in keys where matches(c.tokens, c.tokenSet, k) {
                nameHits[k.game.id, default: []].insert(c.channel.id)
            }
        }

        // 3. Broadcasters (ESPN's list plus the second source), worked out once per network name
        var broadcasterHits: [String: Set<Int>] = [:]
        let allNames = Set(games.flatMap(\.broadcasters) + extras.values.flatMap { $0.map(\.name) })
        for name in allNames {
            if isCallSign(name) {
                broadcasterHits[name] = Set(channels.filter { c in
                    c.channel.name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0 == Substring(name) }
                }.map(\.channel.id))
                continue
            }
            let aliases = broadcasterAliases(name)
            broadcasterHits[name] = Set(channels.filter { c in aliases.contains { has(c.tokens, $0) } }.map(\.channel.id))
        }
        var countryCache: [Int: String?] = [:]
        func countryOf(_ c: Channel) -> String? {
            if let cached = countryCache[c.id] { return cached }
            let found = country(of: c)
            countryCache[c.id] = found
            return found
        }

        let byID = Dictionary(channels.map { ($0.channel.id, $0) }, uniquingKeysWith: { a, _ in a })
        var byEPG: [String: [Int]] = [:]
        for c in channels where !c.channel.epgID.isEmpty {
            byEPG[c.channel.epgID, default: []].append(c.channel.id)
        }

        for k in keys {
            let id = k.game.id
            let named = nameHits[id] ?? []
            let inGuide = Set((guideHits[id] ?? []).flatMap { byEPG[$0] ?? [] })
            var broadcast: [Int: String] = [:]
            var likely: [Int: String] = [:]
            let sources = k.game.broadcasters.map { Broadcast(name: $0, country: nil, confirmed: true) } + (extras[id] ?? [])
            for b in sources {
                let label = b.country.map { "\(b.name) (\($0))" } ?? b.name
                for cid in broadcasterHits[b.name] ?? [] where broadcast[cid] == nil {
                    guard let indexedChannel = byID[cid] else { continue }
                    let c = indexedChannel.channel
                    // A network match doesn't count for a channel clearly about another sport or another game.
                    if !named.contains(cid) && !inGuide.contains(cid)
                        && (aboutOtherSport(indexedChannel, k) || isOtherEvent(indexedChannel)) { continue }
                    // A network named for a country only matches channels for that country (or with no country).
                    if let wanted = b.country, let actual = countryOf(c), actual != wanted { continue }
                    if b.confirmed {
                        broadcast[cid] = label
                        likely[cid] = nil
                    } else if likely[cid] == nil, guideAllows(c, k, guide: guide) {
                        likely[cid] = label
                    }
                }
            }

            var list: [StreamMatch] = []
            for cid in named.union(inGuide).union(broadcast.keys).union(likely.keys) {
                guard let c = byID[cid] else { continue }
                var reasons: [String] = []
                var score = 0
                if named.contains(cid) { reasons.append("Channel name has the teams"); score += 3 }
                if inGuide.contains(cid) { reasons.append("In the guide"); score += 3 }
                if let b = broadcast[cid] { reasons.append("Broadcaster: \(b)"); score += 2 }
                else if let b = likely[cid] { reasons.append("Usually on: \(b)"); score += 1 }
                var q = quality(c.tokenSet)
                if q.rank < 4, CategoryGrouping.isUHD(c.channel.categoryName) { q = ("4K", 4) }
                if let real = measured[cid] {
                    // What the player actually saw beats the guess from the name.
                    let rank = real == "4K" ? 4 : (real == "1080p" ? 3 : (real == "720p" ? 2 : 1))
                    q = (real, rank)
                }
                list.append(StreamMatch(channel: c.channel, reason: reasons.joined(separator: " · "), score: score,
                                        quality: q.label, qualityRank: q.rank, recent: recent.contains(cid),
                                        local: isLocal(c.channel), likelyOnly: score == 1,
                                        country: countryOf(c.channel)))
            }
            result.matches[id] = list.sorted {
                if $0.hidden != $1.hidden { return !$0.hidden }
                let a4K = $0.is4K, b4K = $1.is4K
                if a4K != b4K { return a4K }
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.recent != $1.recent { return $0.recent }
                if $0.qualityRank != $1.qualityRank { return $0.qualityRank > $1.qualityRank }
                return $0.channel.name < $1.channel.name
            }
        }
        return result
    }
}
