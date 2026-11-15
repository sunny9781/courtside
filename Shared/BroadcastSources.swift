import Foundation

/// A network carrying a game, with the country it airs in when known.
/// Confirmed = from an official league schedule; otherwise it's a "usually on" guess from the rights table.
struct Broadcast: Hashable {
    let name: String
    let country: String?
    let confirmed: Bool
}

/// Second source of broadcasters beyond ESPN's (mostly US) list:
/// official NHL, NBA and MLB schedules, plus a table of who holds the rights in Canada, the UK and Europe.
enum BroadcastSources {
    static func fetch(for games: [Game], now: Date = Date()) async -> [String: [Broadcast]] {
        var out: [String: [Broadcast]] = [:]
        for game in games {
            let likely = RightsTable.likely(for: game)
            if !likely.isEmpty { out[game.id] = likely }
        }

        async let nhl = nhlBroadcasts(games.filter { $0.league.id == "nhl" }, now: now)
        async let nba = nbaBroadcasts(games.filter { $0.league.id == "nba" })
        async let mlb = mlbBroadcasts(games.filter { $0.league.id == "mlb" }, now: now)
        let confirmed = (await nhl).merging(await nba, uniquingKeysWith: +).merging(await mlb, uniquingKeysWith: +)

        // Confirmed entries replace a "usually on" guess for the same network.
        for (id, list) in confirmed {
            let names = Set(list.map { $0.name.lowercased() })
            out[id] = list + (out[id] ?? []).filter { !names.contains($0.name.lowercased()) }
        }
        return out
    }

    // MARK: NHL (api-web.nhle.com)

    private static let nhlNames: [String: String] = [
        "SN": "Sportsnet", "SN1": "Sportsnet One", "SNE": "Sportsnet East", "SNO": "Sportsnet Ontario",
        "SNP": "Sportsnet Pacific", "SNW": "Sportsnet West", "SN+": "Sportsnet+", "SN360": "Sportsnet 360",
        "TVAS": "TVA Sports", "TVAS2": "TVA Sports 2", "Prime": "Prime Video", "NHLN": "NHL Network"
    ]

    private static func nhlBroadcasts(_ games: [Game], now: Date) async -> [String: [Broadcast]] {
        guard !games.isEmpty,
              let url = URL(string: "https://api-web.nhle.com/v1/schedule/\(sportsDay(now, format: "yyyy-MM-dd"))"),
              let json = await getJSON(url) else { return [:] }

        var out: [String: [Broadcast]] = [:]
        for item in collect(json, where: { $0["tvBroadcasts"] != nil }) {
            let home = ((item["homeTeam"] as? [String: Any])?["commonName"] as? [String: Any])?["default"] as? String ?? ""
            let away = ((item["awayTeam"] as? [String: Any])?["commonName"] as? [String: Any])?["default"] as? String ?? ""
            guard let game = find(games, home: home, away: away, start: date(item["startTimeUTC"])) else { continue }
            for tv in (item["tvBroadcasts"] as? [[String: Any]]) ?? [] {
                guard let code = (tv["network"] as? String)?.trimmingCharacters(in: .whitespaces), !code.isEmpty else { continue }
                let country = (tv["countryCode"] as? String).map { $0 == "CA" ? "Canada" : ($0 == "US" ? "USA" : $0) }
                out[game.id, default: []].append(Broadcast(name: nhlNames[code] ?? code, country: country, confirmed: true))
            }
        }
        return out
    }

    // MARK: NBA (cdn.nba.com season schedule, cached for 12 hours because it's large)

    private static func nbaBroadcasts(_ games: [Game]) async -> [String: [Broadcast]] {
        guard !games.isEmpty, let json = await nbaSchedule() else { return [:] }
        let keys = ["nationalTvBroadcasters", "nationalBroadcasters", "homeTvBroadcasters", "awayTvBroadcasters",
                    "intlTvBroadcasters", "nationalOttBroadcasters", "homeOttBroadcasters", "awayOttBroadcasters",
                    "intlOttBroadcasters"]
        var out: [String: [Broadcast]] = [:]
        for item in collect(json, where: { $0["gameId"] != nil && $0["broadcasters"] != nil }) {
            let home = (item["homeTeam"] as? [String: Any])?["teamName"] as? String ?? ""
            let away = (item["awayTeam"] as? [String: Any])?["teamName"] as? String ?? ""
            guard let game = find(games, home: home, away: away, start: date(item["gameDateTimeUTC"])),
                  let b = item["broadcasters"] as? [String: Any] else { continue }
            var seen = Set<String>()
            for key in keys {
                for entry in (b[key] as? [[String: Any]]) ?? [] {
                    let name = (entry["broadcasterDisplay"] as? String) ?? (entry["broadcasterAbbreviation"] as? String) ?? ""
                    if !name.isEmpty, seen.insert(name.lowercased()).inserted {
                        out[game.id, default: []].append(Broadcast(name: name, country: nil, confirmed: true))
                    }
                }
            }
        }
        return out
    }

    private static func nbaSchedule() async -> Any? {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let file = caches.appendingPathComponent("Courtside", isDirectory: true).appendingPathComponent("nba-schedule.json")
        let fresh = ((try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate)
            .map { Date().timeIntervalSince($0) < 12 * 3600 } ?? false
        if !fresh, let url = URL(string: "https://cdn.nba.com/static/json/staticData/scheduleLeagueV2.json"),
           let result = try? await URLSession.shared.data(from: url),
           (result.1 as? HTTPURLResponse)?.statusCode == 200 {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? result.0.write(to: file, options: .atomic)
        }
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    // MARK: MLB (statsapi.mlb.com)

    private static func mlbBroadcasts(_ games: [Game], now: Date) async -> [String: [Broadcast]] {
        let day = sportsDay(now, format: "yyyy-MM-dd")
        guard !games.isEmpty,
              let url = URL(string: "https://statsapi.mlb.com/api/v1/schedule?sportId=1&date=\(day)&hydrate=broadcasts(all)"),
              let json = await getJSON(url) else { return [:] }

        var out: [String: [Broadcast]] = [:]
        for item in collect(json, where: { $0["gamePk"] != nil && $0["teams"] != nil }) {
            let teams = item["teams"] as? [String: Any]
            let home = ((teams?["home"] as? [String: Any])?["team"] as? [String: Any])?["name"] as? String ?? ""
            let away = ((teams?["away"] as? [String: Any])?["team"] as? [String: Any])?["name"] as? String ?? ""
            guard let game = find(games, home: home, away: away, start: date(item["gameDate"])) else { continue }
            var seen = Set<String>()
            for b in (item["broadcasts"] as? [[String: Any]]) ?? [] where (b["type"] as? String)?.uppercased() == "TV" {
                if let name = b["name"] as? String, seen.insert(name.lowercased()).inserted {
                    out[game.id, default: []].append(Broadcast(name: name, country: nil, confirmed: true))
                }
            }
        }
        return out
    }

    // MARK: Helpers

    private static func getJSON(_ url: URL) async -> Any? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: result.0)
    }

    /// Every dictionary in the JSON that passes the test, wherever it sits, so small format changes don't break it.
    private static func collect(_ json: Any, where test: ([String: Any]) -> Bool) -> [[String: Any]] {
        var out: [[String: Any]] = []
        func walk(_ node: Any) {
            if let d = node as? [String: Any] {
                if test(d) { out.append(d); return }
                d.values.forEach(walk)
            } else if let a = node as? [Any] {
                a.forEach(walk)
            }
        }
        walk(json)
        return out
    }

    /// The ESPN game with these two teams, starting within six hours of the other source's time.
    private static func find(_ games: [Game], home: String, away: String, start: Date?) -> Game? {
        let h = home.lowercased(), a = away.lowercased()
        guard !h.isEmpty, !a.isEmpty else { return nil }
        func same(_ team: Team, _ other: String) -> Bool {
            [team.nickname, team.name, team.shortName].map { $0.lowercased() }.filter { !$0.isEmpty }
                .contains { $0.contains(other) || other.contains($0) }
        }
        return games.first { g in
            guard same(g.home, h), same(g.away, a) else { return false }
            if let start, let gs = g.start { return abs(start.timeIntervalSince(gs)) < 6 * 3600 }
            return true
        }
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: text) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: text)
    }

    /// The sports day in Eastern time, ending at 5 AM, same as the ESPN schedule.
    private static func sportsDay(_ now: Date, format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = format
        return f.string(from: now.addingTimeInterval(-5 * 3600))
    }
}

/// Who usually carries each league outside the US, for the 2026–27 season.
/// These are guesses ("usually on"), ranked below confirmed broadcasters, and rights change between seasons.
enum RightsTable {
    static let byLeague: [String: [(country: String, names: [String])]] = [
        "nfl": [("Canada", ["TSN", "CTV", "RDS", "DAZN"])],
        "epl": [("Canada", ["Fubo"]), ("UK", ["Sky Sports", "TNT Sports"])],
        "ucl": [("Canada", ["DAZN"]), ("UK", ["TNT Sports", "Amazon Prime"])],
        "laliga": [("UK", ["Premier Sports", "LaLiga TV", "Disney+"]), ("Spain", ["Movistar", "DAZN"])],
        "seriea": [("UK", ["TNT Sports", "DAZN"]), ("Italy", ["DAZN", "Sky Sport"])],
        "bundesliga": [("Canada", ["DAZN"]), ("UK", ["Sky Sports"]), ("Germany", ["Sky Sport", "DAZN"])],
        "ligue1": [("France", ["Ligue 1+", "beIN Sports"])],
        "mls": [("Canada", ["TSN"]), ("All", ["Apple TV", "MLS Season Pass"])],
        "f1": [("Canada", ["TSN", "RDS"]), ("UK", ["Sky Sports F1"]), ("All", ["F1 TV"])],
        "ufc": [("UK", ["TNT Sports"]), ("All", ["UFC Fight Pass"])],
        "atp": [("Canada", ["TSN"]), ("UK", ["Sky Sports Tennis"])],
        "wta": [("Canada", ["TSN"]), ("UK", ["Sky Sports Tennis"])],
        "pga": [("Canada", ["TSN"]), ("UK", ["Sky Sports Golf"])],
        "sixnations": [("UK", ["BBC", "ITV"])],
        "premrugby": [("UK", ["TNT Sports"])]
    ]

    /// Canadian teams whose games are on Canadian networks.
    private static let teamRights: [(league: String, team: String, country: String, names: [String])] = [
        ("nba", "raptors", "Canada", ["TSN", "Sportsnet"]),
        ("mlb", "blue jays", "Canada", ["Sportsnet"])
    ]

    static func likely(for game: Game) -> [Broadcast] {
        var out: [Broadcast] = []
        for entry in byLeague[game.league.id] ?? [] {
            out += entry.names.map { Broadcast(name: $0, country: entry.country == "All" ? nil : entry.country, confirmed: false) }
        }
        for rule in teamRights where rule.league == game.league.id {
            if [game.home, game.away].contains(where: { $0.name.lowercased().contains(rule.team) }) {
                out += rule.names.map { Broadcast(name: $0, country: rule.country, confirmed: false) }
            }
        }
        return out
    }
}
