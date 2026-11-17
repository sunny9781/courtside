import Foundation

struct XtreamCredentials: Codable, Equatable {
    var server: String
    var username: String
    var password: String
}

struct AccountInfo: Equatable, Codable {
    var status: String
    var expires: Date?
    var maxConnections: Int?
    var activeConnections: Int?
}

struct ChannelCategory: Identifiable, Hashable, Codable {
    let id: String
    let name: String
}

struct Channel: Identifiable, Hashable, Codable {
    let id: Int
    let number: Int?
    let name: String
    let categoryID: String
    let categoryName: String
    /// Lowercased XMLTV channel id, empty when the provider doesn't link one.
    let epgID: String
    let icon: URL?
}

struct Programme: Hashable {
    let title: String
    let start: Date
    let end: Date
}

// MARK: Sports and leagues

enum Sport: String, CaseIterable, Identifiable {
    case basketball = "Basketball"
    case football = "Football"
    case hockey = "Hockey"
    case soccer = "Soccer"
    case baseball = "Baseball"
    case fighting = "Fighting"
    case tennis = "Tennis"
    case motorsport = "Motorsport"
    case golf = "Golf"
    case rugby = "Rugby"
    case aussieRules = "Aussie Rules"
    case lacrosse = "Lacrosse"
    case cricket = "Cricket"
    case pickleball = "Pickleball"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .basketball: return "basketball.fill"
        case .football: return "football.fill"
        case .hockey: return "hockey.puck.fill"
        case .soccer: return "soccerball"
        case .baseball: return "baseball.fill"
        case .fighting: return "figure.boxing"
        case .tennis: return "tennis.racket"
        case .motorsport: return "flag.checkered"
        case .golf: return "figure.golf"
        case .rugby: return "figure.rugby"
        case .aussieRules: return "figure.australian.football"
        case .lacrosse: return "figure.lacrosse"
        case .cricket: return "cricket.ball"
        case .pickleball: return "figure.pickleball"
        }
    }

    var leagues: [League] {
        League.all.filter { $0.sport == self }
    }

    /// The user's saved order, with any sport missing from it added at the end.
    static func ordered(_ saved: String) -> [Sport] {
        var out: [Sport] = []
        for raw in saved.split(separator: ",") {
            if let s = Sport(rawValue: String(raw)), !out.contains(s) { out.append(s) }
        }
        for s in Sport.allCases where !out.contains(s) { out.append(s) }
        return out
    }

    static func encode(_ list: [Sport]) -> String {
        list.map(\.rawValue).joined(separator: ",")
    }

    static func hidden(_ saved: String) -> Set<Sport> {
        Set(saved.split(separator: ",").compactMap { Sport(rawValue: String($0)) })
    }

    static var savedOrder: [Sport] {
        ordered(UserDefaults.standard.string(forKey: Prefs.sportOrder) ?? "")
    }
}

struct League: Identifiable, Hashable {
    let id: String
    let name: String
    let sport: Sport
    /// Path in ESPN's public scoreboard feed.
    let path: String
    /// Words that identify this league in a channel name or guide title.
    let keywords: Set<String>
    /// Tournaments, races and fight cards rather than one team against another.
    var isEvent = false

    static func hidden(_ saved: String) -> Set<String> {
        Set(saved.split(separator: ",").map(String.init))
    }

    static var hiddenSaved: Set<String> {
        hidden(UserDefaults.standard.string(forKey: Prefs.hiddenLeagues) ?? "")
    }

    static let all: [League] = [
        League(id: "nba", name: "NBA", sport: .basketball, path: "basketball/nba", keywords: ["nba"]),
        League(id: "wnba", name: "WNBA", sport: .basketball, path: "basketball/wnba", keywords: ["wnba"]),
        League(id: "ncaam", name: "NCAA Men", sport: .basketball, path: "basketball/mens-college-basketball",
               keywords: ["ncaab", "ncaa", "college", "cbb"]),
        League(id: "ncaaw", name: "NCAA Women", sport: .basketball, path: "basketball/womens-college-basketball",
               keywords: ["ncaaw", "ncaa", "college", "wbb"]),
        League(id: "nfl", name: "NFL", sport: .football, path: "football/nfl", keywords: ["nfl"]),
        League(id: "ncaaf", name: "NCAA", sport: .football, path: "football/college-football",
               keywords: ["ncaaf", "ncaa", "college", "cfb"]),
        League(id: "cfl", name: "CFL", sport: .football, path: "football/cfl", keywords: ["cfl"]),
        League(id: "nhl", name: "NHL", sport: .hockey, path: "hockey/nhl", keywords: ["nhl"]),
        League(id: "mlb", name: "MLB", sport: .baseball, path: "baseball/mlb", keywords: ["mlb"]),
        League(id: "epl", name: "Premier League", sport: .soccer, path: "soccer/eng.1", keywords: ["epl", "premier"]),
        League(id: "ucl", name: "Champions League", sport: .soccer, path: "soccer/uefa.champions", keywords: ["ucl", "champions"]),
        League(id: "mls", name: "MLS", sport: .soccer, path: "soccer/usa.1", keywords: ["mls"]),
        League(id: "laliga", name: "La Liga", sport: .soccer, path: "soccer/esp.1", keywords: ["laliga", "liga"]),
        League(id: "seriea", name: "Serie A", sport: .soccer, path: "soccer/ita.1", keywords: ["serie"]),
        League(id: "bundesliga", name: "Bundesliga", sport: .soccer, path: "soccer/ger.1", keywords: ["bundesliga"]),
        League(id: "ligue1", name: "Ligue 1", sport: .soccer, path: "soccer/fra.1", keywords: ["ligue"]),
        League(id: "ufc", name: "UFC", sport: .fighting, path: "mma/ufc", keywords: ["ufc"], isEvent: true),
        // No free boxing schedule: its events and channels come from the TV guide, like pickleball.
        League(id: "boxing", name: "Boxing", sport: .fighting, path: "", keywords: ["boxing"], isEvent: true),
        League(id: "atp", name: "ATP", sport: .tennis, path: "tennis/atp", keywords: ["atp", "tennis"], isEvent: true),
        League(id: "wta", name: "WTA", sport: .tennis, path: "tennis/wta", keywords: ["wta", "tennis"], isEvent: true),
        League(id: "f1", name: "Formula 1", sport: .motorsport, path: "racing/f1", keywords: ["f1", "formula"], isEvent: true),
        League(id: "nascar", name: "NASCAR", sport: .motorsport, path: "racing/nascar-premier", keywords: ["nascar"], isEvent: true),
        League(id: "indycar", name: "IndyCar", sport: .motorsport, path: "racing/irl", keywords: ["indycar"], isEvent: true),
        League(id: "pga", name: "PGA Tour", sport: .golf, path: "golf/pga", keywords: ["pga", "golf"], isEvent: true),
        League(id: "lpga", name: "LPGA", sport: .golf, path: "golf/lpga", keywords: ["lpga", "golf"], isEvent: true),
        League(id: "sixnations", name: "Six Nations", sport: .rugby, path: "rugby/180659", keywords: ["rugby", "nations"]),
        League(id: "premrugby", name: "Premiership", sport: .rugby, path: "rugby/267979", keywords: ["rugby", "premiership"]),
        League(id: "urc", name: "URC", sport: .rugby, path: "rugby/270557", keywords: ["rugby", "urc"]),
        League(id: "top14", name: "Top 14", sport: .rugby, path: "rugby/270559", keywords: ["rugby", "top"]),
        League(id: "afl", name: "AFL", sport: .aussieRules, path: "australian-football/afl", keywords: ["afl"]),
        League(id: "nll", name: "NLL", sport: .lacrosse, path: "lacrosse/nll", keywords: ["nll", "lacrosse"]),
        League(id: "pll", name: "PLL", sport: .lacrosse, path: "lacrosse/pll", keywords: ["pll", "lacrosse"]),
        // Cricket comes from ESPN's list of current matches (series change constantly); see ScheduleClient.
        League(id: "cricket", name: "Cricket", sport: .cricket, path: "cricket", keywords: ["cricket", "ipl", "bbl", "t20", "psl"]),
        // No free schedule exists for pickleball, so its events are built from the TV guide (empty path).
        League(id: "pickleball", name: "Pickleball", sport: .pickleball, path: "", keywords: ["pickleball", "ppa"])
    ]
}

struct Team: Hashable {
    let name: String       // "Toronto Raptors"
    let nickname: String   // "Raptors"
    let shortName: String  // "Raptors", or "Man United" in soccer
    let location: String   // "Toronto"
    let abbr: String       // "TOR"
    let score: String
    let logo: URL?
    /// Season record like "8-2", when the feed has it.
    var record = ""
    /// Score by period (quarter, half, inning…).
    var linescores: [String] = []
}

struct Game: Identifiable, Hashable {
    enum State: String {
        case upcoming, live, finished
    }

    let id: String
    let league: League
    let start: Date?
    let state: State
    let statusText: String
    let away: Team
    let home: Team
    let broadcasters: [String]
    /// Tournaments, races and fight cards: shown by name instead of "Team A at Team B".
    var isEvent = false
    var eventTitle = ""
    /// "Qualifying", "Leader: Scheffler -12", "Main event: Pantoja vs Asakura"…
    var eventDetail = ""
    /// "Hard Rock Stadium · Miami Gardens, FL"
    var venue = ""
    /// A channel for a sport with no schedule (pickleball), listed after its events.
    var isChannel = false

    var title: String { isEvent ? eventTitle : "\(away.nickname) at \(home.nickname)" }

    /// Events with two named sides (a UFC main event) also show them.
    var hasSides: Bool { !away.name.isEmpty && !home.name.isEmpty }
}

extension Team {
    static let none = Team(name: "", nickname: "", shortName: "", location: "", abbr: "", score: "", logo: nil)
}

struct StreamMatch: Identifiable, Hashable {
    let channel: Channel
    let reason: String
    let score: Int
    let quality: String
    let qualityRank: Int
    let recent: Bool
    /// A local affiliate (for example "AK | Fairbanks | ABC KATN"). Hidden by default.
    let local: Bool
    /// Only matched through the rights table ("usually on"), with nothing else pointing to this game.
    let likelyOnly: Bool
    /// The country the channel is for (from "UK |", "CA |" and so on), nil when unknown.
    let country: String?

    /// Kept behind "Show more" on the game screen.
    var hidden: Bool { local || likelyOnly }

    /// Pay-per-view channel or category ("PPV", "Pay Per View"), listed right after 4K for fight cards.
    var isPPV: Bool {
        let text = (channel.name + " " + channel.categoryName).lowercased()
        return text.range(of: #"\bppv\b"#, options: .regularExpression) != nil || text.contains("pay per view")
            || text.contains("pay-per-view")
    }

    var id: Int { channel.id }
}

/// What the player shows. The lineup is what up/down flips through:
/// a game's streams, or the channels of a guide category.
struct NowPlaying: Equatable {
    let channel: Channel
    let gameTitle: String?
    let lineup: [Channel]
}

/// Xtream providers are inconsistent about numbers vs strings in their JSON.
enum Flex {
    static func int(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let s = value as? String { return Int(s) }
        if let d = value as? Double { return Int(d) }
        return nil
    }

    static func string(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let i = value as? Int { return String(i) }
        if let d = value as? Double { return String(Int(d)) }
        return nil
    }
}
