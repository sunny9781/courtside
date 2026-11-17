import Foundation

/// Shared by the Apple TV and iPhone/iPad apps.
extension Game {
    /// "LIVE · Q3 4:12", "STARTS 7:30 PM" or "FINAL", like the Mac cards.
    var headerText: String {
        if isChannel { return "CHANNEL" }
        switch state {
        case .live: return "LIVE · \(statusText)"
        case .upcoming: return "STARTS \(startText)"
        case .finished: return statusText.uppercased()
        }
    }

    var startText: String {
        guard let start else { return statusText }
        return Calendar.current.isDateInToday(start)
            ? start.formatted(date: .omitted, time: .shortened)
            : start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

/// Favourites first, then sports with games today, then the rest, each in your saved order, without hidden ones.
@MainActor
func orderedSports(model: AppModel) -> [Sport] {
    let defaults = UserDefaults.standard
    let hidden = Sport.hidden(defaults.string(forKey: Prefs.hiddenSports) ?? "")
    let favs = Set((defaults.string(forKey: Prefs.favoriteSports) ?? "")
        .split(separator: ",").compactMap { Sport(rawValue: String($0)) })
    let order = Sport.ordered(defaults.string(forKey: Prefs.sportOrder) ?? "").filter { !hidden.contains($0) }
    // Favourites first, then sports with live games, then ones with games still to come, then finished-only,
    // then no games. Within each, your own order.
    func rank(_ s: Sport) -> Int {
        if favs.contains(s) { return 0 }
        let games = model.games(for: s)
        if games.contains(where: { $0.state == .live }) { return 1 }
        if games.contains(where: { $0.state == .upcoming }) { return 2 }
        return games.isEmpty ? 4 : 3
    }
    return order.enumerated()
        .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
        .map(\.element)
}

/// How wide score cards need to be so every team name and score in these games fits on one line. Pass all of a
/// sport's games so the sport's cards all share one width. `charWidth` is the average width of a letter in the
/// card's team-name font; `fixed` covers the logo, padding and gaps.
func cardWidth(for games: [Game], charWidth: Double, fixed: Double, minimum: Double, maximum: Double) -> Double {
    var longest = 0
    for g in games {
        if g.isEvent && !g.hasSides {
            longest = max(longest, min(g.eventTitle.count, 36))
            continue
        }
        for t in [g.away, g.home] {
            let name = (t.shortName.isEmpty ? t.name : t.shortName).count
            // A long score sits under the name; a short one sits beside it.
            longest = max(longest, t.hasLongScore ? max(name, t.score.count) : name + t.score.count + 2)
        }
        longest = max(longest, Int(Double(g.headerText.count + g.league.name.count) * 0.75))
    }
    return min(max(fixed + Double(longest) * charWidth, minimum), maximum)
}

extension Team {
    /// Scores that don't fit beside a name (cricket: "322/7 (83 ov)") go on their own line under it.
    var hasLongScore: Bool { score.count > 4 }
}

/// Live games first, then upcoming by start time, then finished.
func sortedGames(_ games: [Game]) -> [Game] {
    func rank(_ g: Game) -> Int {
        switch g.state {
        case .live: return 0
        case .upcoming: return 1
        case .finished: return 2
        }
    }
    return games.sorted {
        (rank($0), $0.start ?? .distantFuture) < (rank($1), $1.start ?? .distantFuture)
    }
}

extension Array where Element == StreamMatch {
    /// The stream a game screen starts with: the first one that isn't 4K (those are often a different picture or
    /// hard on the connection), or the first if they're all 4K. 4K here means any sign of it: the channel's name,
    /// its category, its quality label, or the resolution seen when it last played.
    func firstToPlay(_ measured: [Int: String]) -> StreamMatch? {
        first { !$0.looksUHD(measured) } ?? first
    }
}
