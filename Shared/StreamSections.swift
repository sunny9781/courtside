import Foundation

/// How a game screen lists its streams, the same on every app:
///   4K · PPV (fight cards) · the league's own channels ("NFL Sunday Ticket", "NBA League Pass") · the official
///   broadcasters from the league's home country (USA for the NFL and NBA, Canada then USA for the NHL, UK for
///   the Premier League…) · other English-language countries · unknown country. Foreign-language countries and
///   local stations come back separately, for groups at the bottom that fold open.
/// Within each section the highest quality comes first (2.14: resolution, measured when it's been played, else from
/// the name; then frame rate), and the matcher's order (best match first) among equals.
enum StreamSections {
    struct Section: Identifiable, Hashable {
        let name: String
        let streams: [StreamMatch]
        var id: String { name }
    }

    struct Result {
        let sections: [Section]
        /// Foreign-language countries (Spain, Latino, Mexico…), shown together in one group that folds open.
        let foreign: [Section]
        /// Local stations and "usually on" guesses (shown at the bottom when asked for).
        let extras: [StreamMatch]
        var foreignCount: Int { foreign.reduce(0) { $0 + $1.streams.count } }
        static let empty = Result(sections: [], foreign: [], extras: [])
    }

    /// The league's home country (or countries, in order) for broadcasters.
    static func homeCountries(_ league: League) -> [String] {
        switch league.id {
        case "nhl", "nll": return ["Canada", "USA"]
        case "cfl": return ["Canada"]
        case "epl", "ucl", "sixnations", "premrugby", "f1": return ["UK"]
        case "urc": return ["UK", "Ireland"]
        case "laliga": return ["Spain"]
        case "seriea": return ["Italy"]
        case "bundesliga": return ["Germany"]
        case "ligue1", "top14": return ["France"]
        case "afl": return ["Australia"]
        case "atp", "wta", "cricket", "pickleball", "boxing": return []
        default: return ["USA"]
        }
    }

    static let englishCountries: [String] = ["USA", "Canada", "UK", "Ireland", "Australia", "New Zealand", "Caribbean"]

    /// The country to file a stream under: the matcher's, else a foreign language/country from the name
    /// ("LATINO | ESPN" → Latino).
    static func country(of match: StreamMatch) -> String? {
        if let c = match.country { return c }
        return CategoryGrouping.foreignCountry(match.channel.categoryName)
            ?? CategoryGrouping.foreignCountry(match.channel.name)
    }

    /// Words that mark a foreign-language channel even in an English-speaking country's category:
    /// "CA | French", "US | Latino", "RDS", "TVA Sports".
    private static let languageWords: [String: String] = [
        "french": "French", "francais": "French", "français": "French", "quebec": "French", "québec": "French",
        "rds": "French", "tva": "French",
        "latino": "Latino", "latin": "Latino", "spanish": "Spanish", "espanol": "Spanish", "español": "Spanish",
        "deportes": "Spanish", "portuguese": "Portuguese", "arabic": "Arabic", "hindi": "Hindi", "punjabi": "Punjabi",
        "italian": "Italian", "german": "German"
    ]

    /// The language of a foreign-language channel, from its category or name.
    static func language(of match: StreamMatch) -> String? {
        for text in [match.channel.categoryName, match.channel.name] {
            let words = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            if let hit = words.lazy.compactMap({ languageWords[$0] }).first { return hit }
        }
        return nil
    }

    static func isForeign(_ match: StreamMatch, home: [String]) -> Bool {
        if language(of: match) != nil { return true }
        guard let c = country(of: match) else { return false }
        return !englishCountries.contains(c) && !home.contains(c)
    }

    /// The section a foreign stream goes in: its language ("French" for "CA | French") or its country.
    private static func foreignGroup(_ match: StreamMatch) -> String {
        if let lang = language(of: match), match.country == nil || englishCountries.contains(match.country ?? "") {
            return lang
        }
        return country(of: match) ?? language(of: match) ?? "Other"
    }

    /// The league's own category: "NFL Sunday Ticket", "US | NBA League Pass", "NHL Center Ice".
    static func isLeagueChannel(_ match: StreamMatch, league: League) -> Bool {
        let cat = match.channel.categoryName.lowercased()
        let words = Set(cat.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        if words.contains(league.name.lowercased()) || cat.contains(league.name.lowercased()) { return true }
        // Short, specific keywords only ("nfl", "nba"); words like "college" or "premier" are too loose.
        return league.keywords.contains { $0.count <= 4 && $0.count >= 3 && words.contains($0) }
    }

    /// 4 = 4K, 3 = 1080p, 2 = 720p / HD (and unknown), 1 = SD.
    static func qualityRank(_ m: StreamMatch, measured: [Int: String]) -> Int {
        switch measured[m.channel.id] {
        case "4K"?: return 4
        case "1080p"?: return 3
        case "720p"?, "HD"?: return 2
        case "SD"?, "576p"?, "480p"?: return 1
        default: return m.qualityRank
        }
    }

    /// Highest quality first, keeping the given order among streams of the same quality.
    static func byQuality(_ list: [StreamMatch], measured: [Int: String], fps: [Int: Double]) -> [StreamMatch] {
        list.enumerated().sorted { a, b in
            let ra = qualityRank(a.element, measured: measured), rb = qualityRank(b.element, measured: measured)
            if ra != rb { return ra > rb }
            let fa = fps[a.element.channel.id] ?? 0, fb = fps[b.element.channel.id] ?? 0
            if Int(fa.rounded()) != Int(fb.rounded()) { return fa > fb }
            return a.offset < b.offset
        }.map(\.element)
    }

    static func build(_ all: [StreamMatch], league: League, search: String = "",
                      measured: [Int: String] = [:], fps: [Int: Double] = [:]) -> Result {
        // Event sports (motorsport, golf, tennis, fights): a 4K channel the guide doesn't confirm is still listed up top
        // under 4K (4K channels carry these events, and the guide often names the race only as "F2 Feature Race").
        func shown(_ m: StreamMatch) -> Bool { !m.hidden || (league.isEvent && m.is4K) }
        let main = all.filter(shown)
        let base = main.isEmpty ? all : main
        let extras = main.isEmpty ? [] : all.filter { !shown($0) }
        let home = homeCountries(league)

        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        func matchesSearch(_ m: StreamMatch) -> Bool {
            query.isEmpty || m.channel.name.lowercased().contains(query) || m.channel.categoryName.lowercased().contains(query)
        }

        let found = base.filter(matchesSearch)
        let list = found.filter { !isForeign($0, home: home) }
        let foreignList = found.filter { isForeign($0, home: home) }

        var used = Set<Int>()
        var sections: [Section] = []
        func take(_ name: String, _ pick: (StreamMatch) -> Bool) {
            let picked = list.filter { !used.contains($0.id) && pick($0) }
            guard !picked.isEmpty else { return }
            picked.forEach { used.insert($0.id) }
            sections.append(Section(name: name, streams: byQuality(picked, measured: measured, fps: fps)))
        }

        take("4K") { $0.is4K }
        if league.sport == .fighting { take("PPV") { $0.isPPV } }
        take("\(league.name) channels") { isLeagueChannel($0, league: league) }
        for c in home { take(c) { country(of: $0) == c } }
        for c in englishCountries where !home.contains(c) { take(c) { country(of: $0) == c } }
        take("Other") { _ in true }

        // Foreign-language countries, biggest first.
        let byCountry = Dictionary(grouping: foreignList, by: { foreignGroup($0) })
        let foreign = byCountry.keys
            .sorted { ((byCountry[$0]?.count ?? 0), $1) > ((byCountry[$1]?.count ?? 0), $0) }
            .map { Section(name: $0, streams: byQuality(byCountry[$0] ?? [], measured: measured, fps: fps)) }

        return Result(sections: sections, foreign: foreign,
                      extras: byQuality(extras.filter(matchesSearch), measured: measured, fps: fps))
    }
}

extension StreamMatch {
    /// Any sign this stream is 4K, for picking the one to start with.
    func looksUHD(_ measured: [Int: String]) -> Bool {
        is4K || quality == "4K" || measured[channel.id] == "4K"
            || CategoryGrouping.isUHD(channel.name) || CategoryGrouping.isUHD(channel.categoryName)
    }

    /// 4K only when the channel's own name says so ("4K", "UHD"): the category or a guessed quality isn't enough.
    var is4K: Bool {
        let words = Set(channel.name.uppercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return words.contains("4K") || words.contains("UHD") || channel.name.uppercased().contains("4K")
    }
}
