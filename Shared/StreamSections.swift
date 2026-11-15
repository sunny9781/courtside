import Foundation

/// How a game screen lists its streams, the same on every app:
///   4K · PPV (fight cards) · the league's own channels ("NFL Sunday Ticket", "NBA League Pass") · the official
///   broadcasters from the league's home country (USA for the NFL and NBA, Canada then USA for the NHL, UK for
///   the Premier League…) · other English-language countries · unknown country. Foreign-language countries and
///   local stations come back separately, for groups at the bottom that fold open.
/// Within each section the matcher's order (best match first) is kept.
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
        case "atp", "wta", "cricket", "pickleball": return []
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

    static func isForeign(_ match: StreamMatch, home: [String]) -> Bool {
        guard let c = country(of: match) else { return false }
        return !englishCountries.contains(c) && !home.contains(c)
    }

    /// The league's own category: "NFL Sunday Ticket", "US | NBA League Pass", "NHL Center Ice".
    static func isLeagueChannel(_ match: StreamMatch, league: League) -> Bool {
        let cat = match.channel.categoryName.lowercased()
        let words = Set(cat.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        if words.contains(league.name.lowercased()) || cat.contains(league.name.lowercased()) { return true }
        // Short, specific keywords only ("nfl", "nba"); words like "college" or "premier" are too loose.
        return league.keywords.contains { $0.count <= 4 && $0.count >= 3 && words.contains($0) }
    }

    static func build(_ all: [StreamMatch], league: League, search: String = "") -> Result {
        let main = all.filter { !$0.hidden }
        let base = main.isEmpty ? all : main
        let extras = main.isEmpty ? [] : all.filter(\.hidden)
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
            sections.append(Section(name: name, streams: picked))
        }

        take("4K") { $0.qualityRank == 4 }
        if league.sport == .fighting { take("PPV") { $0.isPPV } }
        take("\(league.name) channels") { isLeagueChannel($0, league: league) }
        for c in home { take(c) { country(of: $0) == c } }
        for c in englishCountries where !home.contains(c) { take(c) { country(of: $0) == c } }
        take("Other") { _ in true }

        // Foreign-language countries, biggest first.
        let byCountry = Dictionary(grouping: foreignList, by: { country(of: $0) ?? "Other" })
        let foreign = byCountry.keys
            .sorted { ((byCountry[$0]?.count ?? 0), $1) > ((byCountry[$1]?.count ?? 0), $0) }
            .map { Section(name: $0, streams: byCountry[$0] ?? []) }

        return Result(sections: sections, foreign: foreign, extras: extras.filter(matchesSearch))
    }
}
