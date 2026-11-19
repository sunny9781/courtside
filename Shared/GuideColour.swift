import SwiftUI

/// The EPG's colours (all Apple apps): a shade per sport, worked out from a programme's title, a team playing
/// today, the channel's name or its category; anything else gets its channel's own colour (the same each time).
enum GuideColour {
    /// A shade per sport (white text reads on all of them).
    static func fill(_ sport: Sport) -> Color {
        switch sport {
        case .basketball: return Color(hex: 0x8A4214)
        case .hockey: return Color(hex: 0x22508F)
        case .football: return Color(hex: 0x267040)
        case .soccer: return Color(hex: 0x177375)
        case .motorsport: return Color(hex: 0x8A2532)
        case .cricket: return Color(hex: 0x75600F)
        case .baseball: return Color(hex: 0x76305A)
        case .fighting: return Color(hex: 0x6A4A2E)
        case .tennis: return Color(hex: 0x557018)
        case .golf: return Color(hex: 0x3A6430)
        case .rugby: return Color(hex: 0x52408A)
        case .aussieRules: return Color(hex: 0x7A5016)
        case .lacrosse: return Color(hex: 0x2E5F7A)
        case .pickleball: return Color(hex: 0x687A16)
        }
    }

    /// Channels whose sport can't be told still get a colour of their own (the same one every time), like UHF.
    private static let channelFills: [UInt32] = [0x5B3A8C, 0x2C5D8A, 0x7A3B5E, 0x2F6F6A, 0x6E5320, 0x3E5C2E, 0x803A2A, 0x46508A]

    @MainActor static func fill(title: String, channel: Channel, games: [Game]) -> Color {
        if let s = sport(title: title, channel: channel, games: games) { return fill(s) }
        var h: UInt32 = 5381
        for b in channel.name.utf8 { h = (h &* 33) &+ UInt32(b) }
        return Color(hex: channelFills[Int(h % UInt32(channelFills.count))])
    }

    private static let words: [(Sport, [String])] = [
        (.basketball, ["nba", "wnba", "basketball", "ncaab", "euroleague", "march madness"]),
        (.hockey, ["nhl", "hockey", "hockey night", "ahl", "ohl", "whl", "khl", "stanley cup"]),
        (.football, ["nfl", "cfl", "ncaaf", "college football", "super bowl", "redzone", "red zone", "grey cup"]),
        (.baseball, ["mlb", "baseball", "world series"]),
        (.soccer, ["soccer", "epl", "premier league", "champions league", "europa league", "conference league", "la liga",
                   "laliga", "serie a", "bundesliga", "ligue 1", "mls", "uefa", "fifa", "fa cup", "world cup", "eredivisie"]),
        (.fighting, ["ufc", "boxing", "mma", "wwe", "aew", "pfl", "fight night"]),
        (.tennis, ["tennis", "atp", "wta", "wimbledon"]),
        (.motorsport, ["f1", "formula 1", "formula one", "nascar", "indycar", "motogp", "grand prix", "motorsport"]),
        (.golf, ["golf", "pga", "lpga"]),
        (.rugby, ["rugby", "six nations", "urc"]),
        (.aussieRules, ["afl"]),
        (.lacrosse, ["lacrosse", "nll", "pll"]),
        (.cricket, ["cricket", "ipl", "bbl", "t20", "odi", "test match", "psl"]),
        (.pickleball, ["pickleball", "ppa"])
    ]

    @MainActor private static var cache: [String: Sport?] = [:]

    /// The sport a programme is about: from its title (league or sport words, or a team playing today), else the
    /// channel's name ("NBA TV"), else the channel's category ("USA | NHL").
    @MainActor static func sport(title: String, channel: Channel, games: [Game]) -> Sport? {
        if let hit = guess(title) { return hit }
        if let hit = team(title, games: games) { return hit }
        if let hit = guess(channel.name) { return hit }
        return guess(channel.categoryName)
    }

    @MainActor private static var teams: [String: Sport] = [:]
    @MainActor private static var teamsFrom = -1
    @MainActor private static var teamCache: [String: Sport?] = [:]

    /// Team names from the scoreboard ("raptors", "toronto raptors") and their sport; a nickname two sports share
    /// ("kings", "panthers") is left out.
    @MainActor private static func team(_ title: String, games: [Game]) -> Sport? {
        if teamsFrom != games.count {
            var map: [String: Sport] = [:]
            var clash: Set<String> = []
            for g in games where !g.isEvent {
                for t in [g.away, g.home] {
                    for n in [t.name, t.nickname, t.shortName] {
                        let key = normalized(n).trimmingCharacters(in: .whitespaces)
                        guard key.count >= 4 else { continue }
                        if let had = map[key], had != g.league.sport { clash.insert(key) }
                        map[key] = g.league.sport
                    }
                }
            }
            for k in clash { map[k] = nil }
            teams = map
            teamsFrom = games.count
            teamCache = [:]
        }
        if let hit = teamCache[title] { return hit }
        let clean = normalized(title)
        let found = teams.first { clean.contains(" \($0.key) ") }?.value
        if teamCache.count > 4000 { teamCache.removeAll() }
        teamCache[title] = found
        return found
    }

    /// Lower case, letters and digits only, single spaces, with a space at each end (so whole words match).
    private static func normalized(_ text: String) -> String {
        let letters = String(text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " })
        return " " + letters.split(separator: " ").joined(separator: " ") + " "
    }

    @MainActor private static func guess(_ text: String) -> Sport? {
        if let hit = cache[text] { return hit }
        let clean = normalized(text)
        let found = words.first { entry in entry.1.contains { clean.contains(" \($0) ") } }?.0
        if cache.count > 4000 { cache.removeAll() }
        cache[text] = found
        return found
    }

}
