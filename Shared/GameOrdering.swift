import Foundation

/// Shared by the Apple TV and iPhone/iPad apps.
extension Game {
    /// "LIVE · Q3 4:12", "STARTS 7:30 PM" or "FINAL", like the Mac cards.
    var headerText: String {
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
func sportOrder(model: AppModel) -> [Sport] {
    let defaults = UserDefaults.standard
    let hidden = Sport.hidden(defaults.string(forKey: Prefs.hiddenSports) ?? "")
    let favs = Set((defaults.string(forKey: Prefs.favoriteSports) ?? "")
        .split(separator: ",").compactMap { Sport(rawValue: String($0)) })
    let order = Sport.ordered(defaults.string(forKey: Prefs.sportOrder) ?? "").filter { !hidden.contains($0) }
    func rank(_ s: Sport) -> Int {
        if favs.contains(s) { return 0 }
        return model.games(for: s).isEmpty ? 2 : 1
    }
    return order.enumerated()
        .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
        .map(\.element)
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
