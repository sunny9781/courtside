import Foundation

enum ScheduleError: LocalizedError {
    case badResponse

    var errorDescription: String? {
        "Couldn't read today's schedule."
    }
}

/// Today's games from ESPN's public scoreboard feed.
/// Everything is parsed defensively because the feed is unofficial and can change.
struct ScheduleClient {
    /// All leagues at once. A league that fails is skipped; it throws only if every league fails.
    func games(for leagues: [League], now: Date = Date()) async throws -> [Game] {
        try await schedule(for: leagues, now: now).games
    }

    /// Games plus each league's logo (the version made for dark backgrounds when ESPN has one).
    func schedule(for leagues: [League], now: Date = Date()) async throws -> (games: [Game], logos: [String: URL]) {
        var results: [Game] = []
        var logos: [String: URL] = [:]
        var failures = 0
        await withTaskGroup(of: (String, [Game], URL?)?.self) { group in
            for league in leagues {
                group.addTask {
                    guard let r = try? await leagueSchedule(league, now: now) else { return nil }
                    return (league.id, r.games, r.logo)
                }
            }
            for await item in group {
                if let item {
                    results += item.1
                    if let logo = item.2 { logos[item.0] = logo }
                } else {
                    failures += 1
                }
            }
        }
        if failures == leagues.count && !leagues.isEmpty { throw ScheduleError.badResponse }
        return (results.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }, logos)
    }

    func games(for league: League, now: Date = Date()) async throws -> [Game] {
        try await leagueSchedule(league, now: now).games
    }

    private func leagueSchedule(_ league: League, now: Date) async throws -> (games: [Game], logo: URL?) {
        // Treat the "sports day" as ending at 5 AM Eastern, so late West Coast games still show after midnight.
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "America/New_York")
        day.dateFormat = "yyyyMMdd"
        let dayString = day.string(from: now.addingTimeInterval(-5 * 3600))

        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(league.path)/scoreboard?dates=\(dayString)") else {
            throw ScheduleError.badResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else {
            throw ScheduleError.badResponse
        }
        let logos = ((root["leagues"] as? [[String: Any]])?.first?["logos"] as? [[String: Any]]) ?? []
        let dark = logos.first { (($0["rel"] as? [String]) ?? []).contains("dark") }
        let logo = ((dark ?? logos.first)?["href"] as? String).flatMap(URL.init(string:))
        return (events.compactMap { parse($0, league: league) }, logo)
    }

    private func parse(_ event: [String: Any], league: League) -> Game? {
        if league.isEvent { return parseEvent(event, league: league) }
        guard let id = Flex.string(event["id"]),
              let comp = (event["competitions"] as? [[String: Any]])?.first,
              let competitors = comp["competitors"] as? [[String: Any]], competitors.count >= 2 else { return nil }
        let homeRaw = competitors.first(where: { ($0["homeAway"] as? String) == "home" }) ?? competitors[0]
        let awayRaw = competitors.first(where: { ($0["homeAway"] as? String) == "away" }) ?? competitors[1]
        guard let home = team(homeRaw), let away = team(awayRaw) else { return nil }

        let start = parseDate(event["date"] as? String)
        let type = (event["status"] as? [String: Any])?["type"] as? [String: Any]
        let stateRaw = (type?["state"] as? String) ?? "pre"
        let detail = (type?["shortDetail"] as? String) ?? ""

        let state: Game.State
        let statusText: String
        switch stateRaw {
        case "in":
            state = .live
            statusText = detail.isEmpty ? "Live" : detail
        case "post":
            state = .finished
            statusText = detail.isEmpty ? "Final" : detail
        default:
            state = .upcoming
            if let start {
                statusText = start.formatted(date: .omitted, time: .shortened)
            } else {
                statusText = detail
            }
        }

        var names: [String] = []
        for b in (comp["broadcasts"] as? [[String: Any]]) ?? [] {
            names += (b["names"] as? [String]) ?? []
        }
        for g in (comp["geoBroadcasts"] as? [[String: Any]]) ?? [] {
            if let media = g["media"] as? [String: Any], let name = media["shortName"] as? String {
                names.append(name)
            }
        }
        var seen = Set<String>()
        let broadcasters = names.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }

        var venue = ""
        if let v = comp["venue"] as? [String: Any] {
            let name = (v["fullName"] as? String) ?? ""
            let address = v["address"] as? [String: Any]
            let place = [address?["city"] as? String, address?["state"] as? String].compactMap { $0 }.joined(separator: ", ")
            venue = [name, place].filter { !$0.isEmpty }.joined(separator: " · ")
        }

        return Game(id: "\(league.id)-\(id)", league: league, start: start, state: state, statusText: statusText,
                    away: away, home: home, broadcasters: broadcasters, venue: venue)
    }

    // MARK: Events (UFC cards, tennis and golf tournaments, races)

    private func status(_ node: [String: Any]?) -> (state: Game.State, text: String) {
        let type = (node?["status"] as? [String: Any])?["type"] as? [String: Any]
        let raw = (type?["state"] as? String) ?? "pre"
        let detail = (type?["shortDetail"] as? String) ?? ""
        switch raw {
        case "in": return (.live, detail.isEmpty ? "Live" : detail)
        case "post": return (.finished, detail.isEmpty ? "Final" : detail)
        default: return (.upcoming, detail)
        }
    }

    private func athleteName(_ competitor: [String: Any]) -> String {
        let athlete = competitor["athlete"] as? [String: Any]
        return (athlete?["displayName"] as? String) ?? (athlete?["shortName"] as? String)
            ?? ((competitor["team"] as? [String: Any])?["displayName"] as? String) ?? ""
    }

    private func athlete(_ competitor: [String: Any]) -> Team? {
        let name = athleteName(competitor)
        guard !name.isEmpty else { return nil }
        let athlete = competitor["athlete"] as? [String: Any]
        let last = name.split(separator: " ").last.map(String.init) ?? name
        let initials = name.split(separator: " ").compactMap(\.first).map(String.init).joined()
        let flag = ((athlete?["flag"] as? [String: Any])?["href"] as? String).flatMap(URL.init(string:))
        return Team(name: name, nickname: last, shortName: name, location: "", abbr: String(initials.prefix(3)),
                    score: Flex.string(competitor["score"]) ?? "", logo: flag)
    }

    /// Every competition in the event, including ones nested in groupings (tennis draws).
    private func competitions(_ event: [String: Any]) -> [[String: Any]] {
        var out = (event["competitions"] as? [[String: Any]]) ?? []
        for g in (event["groupings"] as? [[String: Any]]) ?? [] {
            out += (g["competitions"] as? [[String: Any]]) ?? []
        }
        return out
    }

    private func parseEvent(_ event: [String: Any], league: League) -> Game? {
        guard let id = Flex.string(event["id"]) else { return nil }
        let name = (event["name"] as? String) ?? (event["shortName"] as? String) ?? league.name
        let comps = competitions(event)
        var start = parseDate(event["date"] as? String)
        var (state, statusText) = status(event)
        var detail = ""
        var away = Team.none, home = Team.none

        switch league.sport {
        case .motorsport:
            // The session that's on now, else the next one, else the last one.
            let live = comps.first { status($0).state == .live }
            let next = comps.filter { status($0).state == .upcoming }
                .min { (parseDate($0["date"] as? String) ?? .distantFuture) < (parseDate($1["date"] as? String) ?? .distantFuture) }
            if let session = live ?? next ?? comps.last {
                let type = session["type"] as? [String: Any]
                detail = (type?["text"] as? String) ?? (type?["abbreviation"] as? String) ?? ""
                start = parseDate(session["date"] as? String) ?? start
                (state, statusText) = status(session)
            }
        case .fighting:
            // The main event is the last fight on the card.
            if let main = comps.last, let sides = main["competitors"] as? [[String: Any]], sides.count >= 2,
               let a = athlete(sides[0]), let b = athlete(sides[1]) {
                away = a
                home = b
                detail = "Main event: \(a.name) vs \(b.name)"
            }
        case .tennis:
            let live = comps.filter { status($0).state == .live }
            if let match = live.first, let sides = match["competitors"] as? [[String: Any]], sides.count >= 2 {
                detail = "\(athleteName(sides[0])) vs \(athleteName(sides[1]))"
                if live.count > 1 { detail += " + \(live.count - 1) more live" }
            }
        case .golf:
            if let field = comps.first?["competitors"] as? [[String: Any]] {
                let ordered = field.sorted { (Flex.int($0["order"]) ?? 999) < (Flex.int($1["order"]) ?? 999) }
                if let leader = ordered.first {
                    let score = Flex.string(leader["score"]) ?? ""
                    detail = "Leader: \(athleteName(leader))" + (score.isEmpty ? "" : " \(score)")
                }
            }
        default:
            break
        }

        if state == .upcoming, let start {
            statusText = start.formatted(date: .omitted, time: .shortened)
        }

        var names: [String] = []
        for comp in comps.prefix(3) {
            for b in (comp["broadcasts"] as? [[String: Any]]) ?? [] { names += (b["names"] as? [String]) ?? [] }
            for g in (comp["geoBroadcasts"] as? [[String: Any]]) ?? [] {
                if let n = (g["media"] as? [String: Any])?["shortName"] as? String { names.append(n) }
            }
        }
        var seen = Set<String>()
        let broadcasters = names.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }

        return Game(id: "\(league.id)-\(id)", league: league, start: start, state: state, statusText: statusText,
                    away: away, home: home, broadcasters: broadcasters,
                    isEvent: true, eventTitle: name, eventDetail: detail)
    }

    private func team(_ competitor: [String: Any]) -> Team? {
        guard let t = competitor["team"] as? [String: Any] else { return nil }
        let display = (t["displayName"] as? String) ?? (t["name"] as? String) ?? ""
        guard !display.isEmpty else { return nil }
        let nickname = (t["name"] as? String) ?? (t["shortDisplayName"] as? String) ?? display
        return Team(name: display,
                    nickname: nickname,
                    shortName: (t["shortDisplayName"] as? String) ?? nickname,
                    location: (t["location"] as? String) ?? "",
                    abbr: (t["abbreviation"] as? String) ?? "",
                    score: Flex.string(competitor["score"]) ?? "",
                    logo: (t["logo"] as? String).flatMap(URL.init(string:)),
                    record: ((competitor["records"] as? [[String: Any]])?.first?["summary"] as? String) ?? "",
                    linescores: ((competitor["linescores"] as? [[String: Any]]) ?? []).compactMap { line in
                        (line["displayValue"] as? String) ?? Flex.string(line["value"])
                    })
    }

    private func parseDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mm'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'"] {
            f.dateFormat = format
            if let d = f.date(from: text) { return d }
        }
        return nil
    }
}
