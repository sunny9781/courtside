import Foundation

/// Sample games, channels and streams for screenshots. Used only when the app is launched with `-demo`
/// (the screenshot workflow does this in the Apple TV simulator); real logins are never involved.
enum DemoData {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    /// `-screen game` etc.
    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private static func league(_ id: String) -> League { League.all.first { $0.id == id }! }

    private static func team(_ name: String, _ nick: String, _ abbr: String, _ path: String, _ score: String, _ record: String = "") -> Team {
        var t = Team(name: name, nickname: nick, shortName: nick, location: name.replacingOccurrences(of: " " + nick, with: ""),
                     abbr: abbr, score: score,
                     logo: URL(string: "https://a.espncdn.com/i/teamlogos/\(path)/500/\(abbr.lowercased()).png"))
        t.record = record
        return t
    }

    static func build() -> (games: [Game], logos: [String: URL], categories: [ChannelCategory], channels: [Channel],
                            matches: [String: [StreamMatch]], guide: [String: [Programme]]) {
        let now = Date()
        let h: TimeInterval = 3600
        let games: [Game] = [
            Game(id: "g1", league: league("nba"), start: now.addingTimeInterval(-1.2 * h), state: .live, statusText: "Q3 4:12",
                 away: team("Toronto Raptors", "Raptors", "TOR", "nba", "78", "9-4"),
                 home: team("Boston Celtics", "Celtics", "BOS", "nba", "81", "10-3"), broadcasters: ["TSN", "NBC Sports Boston"]),
            Game(id: "g2", league: league("nba"), start: now.addingTimeInterval(-0.5 * h), state: .live, statusText: "Q1 2:40",
                 away: team("Los Angeles Lakers", "Lakers", "LAL", "nba", "24", "8-5"),
                 home: team("Denver Nuggets", "Nuggets", "DEN", "nba", "24", "9-4"), broadcasters: ["ESPN"]),
            Game(id: "g3", league: league("nba"), start: now.addingTimeInterval(2 * h), state: .upcoming, statusText: "10:00 PM",
                 away: team("Golden State Warriors", "Warriors", "GS", "nba", "0", "7-6"),
                 home: team("Phoenix Suns", "Suns", "PHX", "nba", "0", "6-7"), broadcasters: ["TNT"]),
            Game(id: "g4", league: league("nba"), start: now.addingTimeInterval(-3 * h), state: .finished, statusText: "Final",
                 away: team("New York Knicks", "Knicks", "NY", "nba", "112", "8-5"),
                 home: team("Miami Heat", "Heat", "MIA", "nba", "104", "6-7"), broadcasters: ["MSG"]),
            Game(id: "g5", league: league("nhl"), start: now.addingTimeInterval(-1 * h), state: .live, statusText: "2nd 8:51",
                 away: team("Ottawa Senators", "Senators", "OTT", "nhl", "2", "10-6-1"),
                 home: team("Montreal Canadiens", "Canadiens", "MTL", "nhl", "1", "8-7-2"), broadcasters: ["Sportsnet", "RDS"]),
            Game(id: "g6", league: league("nhl"), start: now.addingTimeInterval(1 * h), state: .upcoming, statusText: "8:00 PM",
                 away: team("Edmonton Oilers", "Oilers", "EDM", "nhl", "0", "9-7-1"),
                 home: team("Calgary Flames", "Flames", "CGY", "nhl", "0", "7-9-2"), broadcasters: ["Sportsnet"]),
            Game(id: "g7", league: league("epl"), start: now.addingTimeInterval(-4 * h), state: .finished, statusText: "FT",
                 away: team("Arsenal", "Arsenal", "ARS", "soccer", "2"),
                 home: team("Liverpool", "Liverpool", "LIV", "soccer", "2"), broadcasters: ["Peacock"]),
            Game(id: "g8", league: league("nfl"), start: now.addingTimeInterval(20 * h), state: .upcoming, statusText: "Sun 1:00 PM",
                 away: team("Buffalo Bills", "Bills", "BUF", "nfl", "0", "8-2"),
                 home: team("Kansas City Chiefs", "Chiefs", "KC", "nfl", "0", "9-1"), broadcasters: ["CBS"]),
        ]
        var logos: [String: URL] = [:]
        for id in ["nba", "nhl", "epl", "nfl", "wnba", "ncaam", "ncaaw"] {
            logos[id] = URL(string: "https://a.espncdn.com/i/teamlogos/leagues/500/\(id == "epl" ? "eng.1" : id).png")
        }

        let categories = [
            ChannelCategory(id: "1", name: "CA | Sports"), ChannelCategory(id: "2", name: "US | Sports"),
            ChannelCategory(id: "3", name: "US | NBA League Pass"), ChannelCategory(id: "4", name: "UK | Sports"),
            ChannelCategory(id: "5", name: "4K | Sports"), ChannelCategory(id: "6", name: "US | Entertainment"),
            ChannelCategory(id: "7", name: "CA | News"),
        ]
        func ch(_ id: Int, _ name: String, _ cat: String) -> Channel {
            let c = categories.first { $0.id == cat }!
            return Channel(id: id, number: id, name: name, categoryID: c.id, categoryName: c.name, epgID: "e\(id)", icon: nil)
        }
        let channels = [
            ch(1, "CA | TSN 1 HD", "1"), ch(2, "CA | TSN 4 FHD", "1"), ch(3, "CA | Sportsnet One", "1"), ch(4, "CA | Sportsnet Ontario", "1"),
            ch(5, "CA | RDS", "1"), ch(6, "US | ESPN FHD", "2"), ch(7, "US | ESPN 2", "2"), ch(8, "US | TNT HD", "2"),
            ch(9, "US | NBC Sports Boston", "2"), ch(10, "NBA 01 | Raptors @ Celtics", "3"), ch(11, "NBA 02 | Lakers @ Nuggets", "3"),
            ch(12, "UK | Sky Sports Main Event", "4"), ch(13, "4K | TSN 1 UHD", "5"), ch(14, "4K | ESPN UHD", "5"),
            ch(15, "US | ABC", "6"), ch(16, "CA | CBC News", "7"),
        ]
        func m(_ id: Int, _ reason: String, _ quality: String, _ country: String?, rank: Int) -> StreamMatch {
            StreamMatch(channel: channels.first { $0.id == id }!, reason: reason, score: 3, quality: quality, qualityRank: rank,
                        recent: false, local: false, likelyOnly: false, country: country)
        }
        let matches: [String: [StreamMatch]] = [
            "g1": [m(13, "On TSN tonight", "4K", "Canada", rank: 4), m(1, "On TSN tonight", "1080p", "Canada", rank: 3),
                   m(2, "On TSN tonight", "1080p", "Canada", rank: 3), m(10, "Game channel", "720p", "USA", rank: 2),
                   m(9, "Home broadcast", "720p", "USA", rank: 2)],
            "g2": [m(14, "On ESPN tonight", "4K", "USA", rank: 4), m(6, "On ESPN tonight", "1080p", "USA", rank: 3),
                   m(11, "Game channel", "720p", "USA", rank: 2)],
            "g3": [m(8, "On TNT tonight", "720p", "USA", rank: 2)],
            "g5": [m(3, "On Sportsnet tonight", "1080p", "Canada", rank: 3), m(4, "On Sportsnet tonight", "720p", "Canada", rank: 2),
                   m(5, "On RDS tonight", "720p", "Canada", rank: 2)],
            "g6": [m(3, "On Sportsnet tonight", "1080p", "Canada", rank: 3)],
            "g7": [m(12, "Guide listing", "1080p", "UK", rank: 3)],
        ]
        var guide: [String: [Programme]] = [:]
        let start = now.addingTimeInterval(-0.4 * h)
        for c in channels {
            guide[c.epgID] = [
                Programme(title: c.id == 16 ? "The National" : (c.id == 15 ? "Grey's Anatomy" : "NBA: Raptors at Celtics"),
                          start: start, end: start.addingTimeInterval(2 * h)),
                Programme(title: "SportsCentre", start: start.addingTimeInterval(2 * h), end: start.addingTimeInterval(3 * h)),
            ]
        }
        return (games, logos, categories, channels, matches, guide)
    }
}
