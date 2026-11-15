import SwiftUI

/// Home: sports down the left (All sports, favourites, sports with games, then the rest),
/// and on the right either the live overview or the chosen sport's page.
struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.sportOrder) private var sportOrder = ""
    @AppStorage(Prefs.favoriteSports) private var favoriteSports = ""
    @AppStorage(Prefs.hiddenSports) private var hiddenSports = ""
    @Binding var selectedSport: Sport?
    @Binding var selectedLeague: String?
    let onOpenGame: (Game) -> Void
    /// The sport whose leagues are showing in the left column. Clicking it again folds them away.
    @State private var expandedSport: Sport?

    var body: some View {
        HStack(spacing: 0) {
            sportList
                .onAppear { if expandedSport == nil { expandedSport = selectedSport } }
            Rectangle().fill(Theme.raised).frame(width: 1)
            Group {
                if let sport = selectedSport {
                    SportView(sport: sport, leagueID: selectedLeague, onOpen: onOpenGame)
                        .id("\(sport.rawValue)|\(selectedLeague ?? "")")
                } else {
                    overview
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Left column

    private var sportList: some View {
        ScrollView {
            VStack(spacing: 4) {
                let liveTotal = model.games.filter { $0.state == .live && !Sport.hidden(hiddenSports).contains($0.league.sport) }.count
                SportRow(symbol: "dot.radiowaves.left.and.right", name: "Live Now",
                         detail: liveTotal > 0 ? nil : "\(model.games.count) today", live: liveTotal,
                         selected: selectedSport == nil, dimmed: false, favorite: nil, alignWithHearts: true) {
                    selectedSport = nil
                    selectedLeague = nil
                    expandedSport = nil
                }
                .padding(.bottom, 8)

                ForEach(tileOrder) { sport in
                    let games = model.games(for: sport)
                    SportRow(symbol: sport.symbol, name: sport.rawValue,
                             detail: games.isEmpty ? "No games" : "\(games.count) today",
                             live: games.filter { $0.state == .live }.count,
                             selected: selectedSport == sport && selectedLeague == nil,
                             dimmed: games.isEmpty && !favorites.contains(sport),
                             favorite: favorites.contains(sport),
                             onToggleFavorite: { toggleFavorite(sport) }) {
                        if selectedSport == sport && expandedSport == sport {
                            expandedSport = nil          // second click folds the leagues away
                        } else {
                            expandedSport = sport
                        }
                        selectedSport = sport
                        selectedLeague = nil
                    }
                    .draggable(sport.rawValue)
                    .dropDestination(for: String.self) { items, _ in
                        guard let raw = items.first, let dragged = Sport(rawValue: raw) else { return false }
                        moveSport(dragged, to: sport)
                        return true
                    }

                    // The open sport shows its leagues underneath: ones with games first.
                    if expandedSport == sport && model.leagues(for: sport).count > 1 {
                        ForEach(orderedLeagues(sport)) { league in
                            let leagueGames = games.filter { $0.league == league }
                            LeagueRow(league: league,
                                      detail: leagueGames.isEmpty ? "No games" : "\(leagueGames.count) today",
                                      live: leagueGames.filter { $0.state == .live }.count,
                                      selected: selectedLeague == league.id,
                                      dimmed: leagueGames.isEmpty) {
                                selectedLeague = league.id
                            }
                        }
                        .padding(.bottom, 6)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 290)
        .background(Theme.sidebar)
    }

    // MARK: All sports overview

    private var overview: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let shown = model.games.filter { !Sport.hidden(hiddenSports).contains($0.league.sport) }
            let live = shown.filter { $0.state == .live }
            let soon = shown.filter {
                $0.state == .upcoming && ($0.start ?? .distantFuture) < now.addingTimeInterval(4 * 3600)
            }
            let finals = shown.filter {
                $0.state == .finished && ($0.start ?? .distantPast) > now.addingTimeInterval(-6 * 3600)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    HStack {
                        Text(subtitle(now, live: live.count))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                        Spacer()
                    }

                    if let error = model.errorMessage {
                        Banner(text: error)
                    }

                    // Live now (no heading: "Live Now" is already selected on the left)
                    VStack(alignment: .leading, spacing: 14) {
                        if live.isEmpty && soon.isEmpty {
                            Banner(text: nextUpText(shown.first { $0.state == .upcoming }), icon: "clock")
                        } else {
                            // One row per sport: live games, then games starting soon (greyed out), scrolling sideways.
                            VStack(alignment: .leading, spacing: 18) {
                                ForEach(tileOrder.filter { sport in (live + soon).contains { $0.league.sport == sport } }) { sport in
                                    let liveGames = live.filter { $0.league.sport == sport }
                                    let soonGames = soon.filter { $0.league.sport == sport }
                                    VStack(alignment: .leading, spacing: 10) {
                                        Button {
                                            selectedSport = sport
                                        } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: sport.symbol)
                                                .foregroundStyle(Theme.accent)
                                            Text(sport.rawValue)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(Theme.text)
                                            Text([liveGames.isEmpty ? nil : "\(liveGames.count) live",
                                                  soonGames.isEmpty ? nil : "\(soonGames.count) starting soon"]
                                                .compactMap { $0 }.joined(separator: " · "))
                                                .font(.system(size: 12))
                                                .foregroundStyle(Theme.muted)
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(Theme.muted)
                                        }
                                        }
                                        .buttonStyle(.plain)
                                        .help("Open \(sport.rawValue)")
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 14) {
                                                ForEach(liveGames + soonGames) { game in
                                                    LiveGameCard(game: game, streams: model.streamCount(game.id), showLeague: true) {
                                                        onOpenGame(game)
                                                    }
                                                    .frame(width: cardWidth(for: model.games(for: sport), charWidth: 9.5,
                                                                            fixed: 112, minimum: 290, maximum: 560))
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !finals.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionTitle(text: "Final scores")
                            let finalWidth = cardWidth(for: Array(finals.prefix(9)), charWidth: 8.5, fixed: 90, minimum: 240, maximum: 520)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: finalWidth, maximum: finalWidth), spacing: 12, alignment: .top)],
                                      alignment: .leading, spacing: 12) {
                                ForEach(finals.prefix(9)) { game in
                                    FinalScoreCard(game: game) { onOpenGame(game) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
        }
    }

    private func orderedLeagues(_ sport: Sport) -> [League] {
        let games = model.games(for: sport)
        let leagues = model.leagues(for: sport)
        let withGames = leagues.filter { l in games.contains { $0.league == l } }
        return withGames + leagues.filter { !withGames.contains($0) }
    }

    private var favorites: Set<Sport> {
        Set(favoriteSports.split(separator: ",").compactMap { Sport(rawValue: String($0)) })
    }

    /// Favourites first, then sports with games today, then the rest, each keeping your saved order.
    private var tileOrder: [Sport] {
        let hidden = Sport.hidden(hiddenSports)
        let order = Sport.ordered(sportOrder).filter { !hidden.contains($0) }
        let favs = favorites
        func rank(_ s: Sport) -> Int {
            if favs.contains(s) { return 0 }
            return model.games(for: s).isEmpty ? 2 : 1
        }
        return order.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    private func toggleFavorite(_ sport: Sport) {
        var set = favorites
        if set.contains(sport) { set.remove(sport) } else { set.insert(sport) }
        favoriteSports = Sport.ordered(sportOrder).filter { set.contains($0) }.map(\.rawValue).joined(separator: ",")
    }

    /// Drag a sport tile onto another to put it in that spot (same order as Settings › Sports order).
    private func moveSport(_ dragged: Sport, to target: Sport) {
        var list = Sport.ordered(sportOrder)
        guard dragged != target, let from = list.firstIndex(of: dragged), let to = list.firstIndex(of: target) else { return }
        list.remove(at: from)
        list.insert(dragged, at: to)
        sportOrder = Sport.encode(list)
    }

    private func subtitle(_ now: Date, live: Int) -> String {
        let date = now.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let today = model.games.filter { $0.state != .finished }.count
        if model.games.isEmpty { return model.isLoading ? "\(date) · loading today's games…" : date }
        return "\(date) · \(live) live · \(today) still to play today"
    }

    private func nextUpText(_ game: Game?) -> String {
        guard let game else { return "Nothing live right now, and nothing else scheduled today." }
        let name = game.isEvent ? game.eventTitle : "\(game.away.shortName) at \(game.home.shortName)"
        return "Nothing live right now. Next up: \(name), \(game.league.name), \(game.statusText)."
    }
}

/// A row in Home's left column: icon, name, live badge or today's count, and a heart (shown on hover
/// or when it's a favourite).
struct SportRow: View {
    let symbol: String
    let name: String
    let detail: String?
    let live: Int
    let selected: Bool
    let dimmed: Bool
    let favorite: Bool?
    var onToggleFavorite: (() -> Void)? = nil
    /// Leaves an empty heart-sized space on the right so this row's badge lines up with the sport rows below.
    var alignWithHearts = false
    let action: () -> Void
    @State private var hovering = false

    private var hasHeart: Bool { favorite != nil && onToggleFavorite != nil }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24)
                    Text(name)
                        .font(.system(size: 14, weight: selected ? .semibold : .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    if live > 0 {
                        Text("\(live) LIVE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                            .fixedSize()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Theme.accent))
                    } else if let detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                            .fixedSize()
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, hasHeart || alignWithHearts ? 4 : 12)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let favorite, let onToggleFavorite {
                Button(action: onToggleFavorite) {
                    Image(systemName: favorite ? "heart.fill" : "heart")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(favorite ? Theme.accent : Theme.muted)
                        .frame(width: 28, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(favorite || hovering ? 1 : 0)
                .help(favorite ? "Remove from favourites" : "Favourite: keep this sport first")
            } else if alignWithHearts {
                Color.clear.frame(width: 28, height: 44)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(selected ? Theme.raised : (hovering ? Theme.card : Color.clear)))
        .opacity(dimmed && !selected ? 0.5 : 1)
        .onHover { hovering = $0 }
    }
}

/// A league under its sport in the left column: logo, name, and live badge or today's count.
struct LeagueRow: View {
    let league: League
    let detail: String
    let live: Int
    let selected: Bool
    let dimmed: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                LeagueLogo(league: league, size: 24)
                Text(league.name)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.text : Theme.soft)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                if live > 0 {
                    Text("\(live) LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.accent))
                } else {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .fixedSize()
                }
            }
            .padding(.leading, 40)
            .padding(.trailing, 12)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Theme.raised : (hovering ? Theme.card : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .opacity(dimmed && !selected ? 0.5 : 1)
    }
}

struct FinalScoreCard: View {
    let game: Game
    let action: () -> Void

    private func line(_ team: Team, winner: Bool) -> some View {
        HStack(spacing: 10) {
            TeamBadge(abbr: team.abbr, logo: team.logo, size: 28)
            Text(team.shortName)
                .font(.system(size: 14, weight: winner ? .bold : .regular))
                .foregroundStyle(winner ? Theme.text : Theme.soft)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text(team.score)
                .font(.system(size: 16, weight: winner ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(game.scoreColor(team))
        }
    }

    var body: some View {
        let away = Int(game.away.score) ?? 0
        let home = Int(game.home.score) ?? 0
        CardButton(radius: 14, action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(game.league.name) · \(game.statusText)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                if game.isEvent {
                    Text(game.eventTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(game.eventDetail.isEmpty ? " " : game.eventDetail)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.soft)
                        .lineLimit(1)
                } else {
                    line(game.away, winner: away > home)
                    line(game.home, winner: home > away)
                }
            }
            .padding(16)
        }
    }
}
