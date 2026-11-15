import Foundation

/// How a game screen lists its streams, the same on every app:
///   4K · PPV (fight cards) · the league's own channels ("NFL Sunday Ticket", "NBA League Pass") · the official
///   broadcasters from the league's home country (USA for the NFL and NBA, Canada then USA for the NHL, UK for
///   the Premier League…) · other English-language countries · foreign-language countries (hidden unless switched
///   on) · unknown country · local stations and likely channels (when shown).
/// Within each section the matcher's order (best match first) is kept.
enum StreamSections {
    struct Section: Identifiable, Hashable {
        let name: String
        let streams: [StreamMatch]
        var id: String { name }
    }

    struct Result {
        let sections: [Section]
        /// Foreign-language streams left out because the toggle is off.
        let hiddenForeign: Int
        /// Local stations and "usually on" guesses not shown.
        let hiddenExtras: Int
        var streams: [StreamMatch] { sections.flatMap(\.streams) }
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

    static func build(_ all: [StreamMatch], league: League, showExtras: Bool, showForeign: Bool,
                      search: String = "") -> Result {
        let main = all.filter { !$0.hidden }
        let base = main.isEmpty ? all : main
        let extras = main.isEmpty ? [] : all.filter(\.hidden)
        let home = homeCountries(league)

        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        func matchesSearch(_ m: StreamMatch) -> Bool {
            query.isEmpty || m.channel.name.lowercased().contains(query) || m.channel.categoryName.lowercased().contains(query)
        }

        var hiddenForeign = 0
        var list: [StreamMatch] = []
        for m in base where matchesSearch(m) {
            if !showForeign && isForeign(m, home: home) { hiddenForeign += 1; continue }
            list.append(m)
        }

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
        // Foreign countries, biggest first.
        let foreign = Dictionary(grouping: list.filter { !used.contains($0.id) && country(of: $0) != nil },
                                 by: { country(of: $0) ?? "" })
        for c in foreign.keys.sorted(by: { (foreign[$0]?.count ?? 0, $1) > (foreign[$1]?.count ?? 0, $0) }) {
            take(c) { country(of: $0) == c }
        }
        take("Other") { _ in true }

        let shownExtras = extras.filter { matchesSearch($0) && (showForeign || !isForeign($0, home: home)) }
        if showExtras && !shownExtras.isEmpty {
            sections.append(Section(name: "Local stations and likely channels", streams: shownExtras))
        }
        return Result(sections: sections, hiddenForeign: hiddenForeign,
                      hiddenExtras: showExtras ? 0 : shownExtras.count)
    }
}
