import SwiftUI

/// Home: sports down the left (All sports, favourites, sports with games, then the rest),
/// and on the right either the live overview or the chosen sport's page.
struct DashboardView: View {
    /// The sport Home picked by itself (not you), and when Home opened.
    @State private var autoSport: Sport?
    @State private var openedAt = Date()
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.sportOrder) private var sportOrder = ""
    @AppStorage(Prefs.favoriteSports) private var favoriteSports = ""
    @AppStorage(Prefs.hiddenSports) private var hiddenSports = ""
    @Binding var selectedSport: Sport?
    @Binding var selectedLeague: String?
    let onOpenGame: (Game) -> Void

    var body: some View {
        HStack(spacing: 0) {
            sportList
            Rectangle().fill(Theme.raised).frame(width: 1)
            Group {
                if let sport = selectedSport, isChannelSport(sport, model: model) {
                    MacSportChannels(sport: sport)
                        .id(sport.rawValue)
                } else if let sport = selectedSport {
                    // Like the Apple TV: sports down the left, the sport's leagues across the top.
                    VStack(spacing: 0) {
                        if model.leagues(for: sport).count > 1 || model.games(for: sport).contains(where: { $0.state == .finished }) {
                            leagueChips(sport)
                        }
                        SportView(sport: sport, leagueID: selectedLeague, onOpen: onOpenGame)
                            .id("\(sport.rawValue)|\(selectedLeague ?? "")")
                    }
                } else {
                    // No Live Now page: until today's games are in, nothing is picked.
                    overview
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { pickStartingSport() }
        .onChange(of: model.games.count) { pickStartingSport() }
    }

    /// Home opens on a sport (no Live Now page): a favourite with something live, else any sport with something
    /// live, else the first with games. Picked once today's games are in.
    /// While today's games are still coming in (the first 30 seconds), Home keeps moving to the top sport until you
    /// pick one yourself (2.21, like Android), instead of staying on whichever sport loaded first.
    private func pickStartingSport() {
        guard !model.games.isEmpty else { return }
        let following = selectedSport == nil || (selectedSport == autoSport && Date().timeIntervalSince(openedAt) < 30)
        guard following, let sport = startingSport(model: model), sport != selectedSport else { return }
        selectedSport = sport
        autoSport = sport
    }

    // MARK: Left column

    private var sportList: some View {
        ScrollView {
            VStack(spacing: 4) {
                // Like the TVs: sports with live scores | sports shown as channels (pickleball) | nothing today,
                // with a line between the groups.
                ForEach(Array(sportGroups.enumerated()), id: \.offset) { index, group in
                    if index > 0 {
                        Rectangle().fill(Theme.raised).frame(height: 1).padding(.horizontal, 12).padding(.vertical, 6)
                    }
                    ForEach(group) { sport in
                        let games = model.games(for: sport)
                        let channelOnly = isChannelSport(sport, model: model)
                        SportRow(symbol: sport.symbol, name: sport.rawValue,
                                 detail: games.isEmpty ? "No games" : (channelOnly ? "Channels" : "\(games.count) today"),
                                 live: channelOnly ? 0 : games.filter { $0.state == .live }.count,
                                 selected: selectedSport == sport,
                                 dimmed: games.isEmpty && !favorites.contains(sport),
                                 favorite: favorites.contains(sport),
                                 onToggleFavorite: { toggleFavorite(sport) }) {
                            selectedSport = sport
                            selectedLeague = nil
                        }
                        .contextMenu {
                            let fav = favorites.contains(sport)
                            Button(fav ? "Remove from Favourites" : "Add to Favourites") { toggleFavorite(sport) }
                            Button("Hide") { hide(sport) }
                        }
                        .draggable(sport.rawValue)
                        .dropDestination(for: String.self) { items, _ in
                            guard let raw = items.first, let dragged = Sport(rawValue: raw) else { return false }
                            moveSport(dragged, to: sport)
                            return true
                        }
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 290)
        .background(Theme.sidebar)
    }

    /// The TVs' groups: sports with scores today, channel-only sports, then sports with nothing today.
    private var sportGroups: [[Sport]] {
        let sports = orderedSports(model: model)
        let scored = sports.filter { s in model.games(for: s).contains { !$0.id.hasPrefix("guide-") } }
        let channels = sports.filter { !scored.contains($0) && isChannelSport($0, model: model) }
        let empty = sports.filter { !scored.contains($0) && !channels.contains($0) }
        return [scored, channels, empty].filter { !$0.isEmpty }
    }

    /// Right-click › Hide: switches the sport off (as on the TVs); Settings › Hidden brings it back.
    private func hide(_ sport: Sport) {
        var set = Sport.hidden(hiddenSports)
        set.insert(sport)
        hiddenSports = Sport.allCases.filter { set.contains($0) }.map(\.rawValue).joined(separator: ",")
        if selectedSport == sport {
            selectedSport = orderedSports(model: model).first { $0 != sport }
            selectedLeague = nil
        }
        model.sportsChanged()
        model.notice = "\(sport.rawValue) is hidden. Settings › Hidden brings it back."
    }

    /// The chosen sport's leagues as chips along the top ("All" first, then leagues with games).
    private func leagueChips(_ sport: Sport) -> some View {
        // Counts leave out finished games (2.45): they're under Finished, at the end.
        let games = model.games(for: sport).filter { $0.state != .finished }
        let done = model.games(for: sport).filter { $0.state == .finished }.count
        // Only one league on screen (picked, or the only one with games): its logo, name and "9 coming up" sit at
        // the right end of this row instead of taking a row of their own above the cards.
        let shown = selectedLeague == finishedLeagueID ? []
            : selectedLeague.flatMap { id in sport.leagues.first { $0.id == id } }.map { [$0] }
                ?? model.leagues(for: sport).filter { l in games.contains { $0.league == l } }
        return HStack(spacing: 16) {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { selectedLeague = nil } label: {
                    HStack(spacing: 6) {
                        Text("All")
                        chipCount(live: games.filter { $0.state == .live }.count, total: games.count,
                                  selected: selectedLeague == nil)
                    }
                }
                .buttonStyle(ChipStyle(selected: selectedLeague == nil))
                ForEach(orderedLeagues(sport)) { league in
                    let leagueGames = games.filter { $0.league == league }
                    Button { selectedLeague = league.id } label: {
                        HStack(spacing: 6) {
                            LeagueLogo(league: league, size: 16)
                            Text(league.name)
                            chipCount(live: leagueGames.filter { $0.state == .live }.count, total: leagueGames.count,
                                      selected: selectedLeague == league.id)
                        }
                        .opacity(leagueGames.isEmpty && selectedLeague != league.id ? 0.55 : 1)
                    }
                    .buttonStyle(ChipStyle(selected: selectedLeague == league.id))
                    // Right-click › Hide (2.43).
                    .contextMenu {
                        Button("Hide \(league.name)") {
                            if selectedLeague == league.id { selectedLeague = nil }
                            hideLeague(league, model: model)
                        }
                    }
                }
                if done > 0 {
                    Button { selectedLeague = finishedLeagueID } label: {
                        HStack(spacing: 6) {
                            Text("Finished")
                            chipCount(live: 0, total: done, selected: selectedLeague == finishedLeagueID)
                        }
                    }
                    .buttonStyle(ChipStyle(selected: selectedLeague == finishedLeagueID))
                }
            }
            .padding(.leading, 32)
            .padding(.vertical, 12)
        }
            if shown.count == 1, let league = shown.first {
                LeagueSummary(league: league, games: games.filter { $0.league == league })
                    .fixedSize()
            }
        }
        .padding(.trailing, 32)
    }

    // MARK: All sports overview

    private var overview: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let shown = model.games.filter { !Sport.hidden(hiddenSports).contains($0.league.sport) }
            let live = shown.filter { $0.state == .live }
            // Live Now shows only games that are live right now: nothing upcoming, nothing final.
            let soon: [Game] = []
            let finals: [Game] = []

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
                            // All live games in one grid, rows that wrap like the TV apps (no sideways scrolling).
                            // In your sport order; each card names its league.
                            let cards = tileOrder.flatMap { sport in (live + soon).filter { $0.league.sport == sport } }
                            let width = cardWidth(for: cards, charWidth: 9.5, fixed: 112, minimum: 290, maximum: 520)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: width, maximum: width), spacing: 16, alignment: .top)],
                                      alignment: .leading, spacing: 16) {
                                ForEach(cards) { game in
                                    LiveGameCard(game: game, streams: model.streamCount(game.id), showLeague: true) {
                                        onOpenGame(game)
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

    /// Like the TVs: live games as an orange number, otherwise today's games in grey.
    @ViewBuilder
    private func chipCount(live: Int, total: Int, selected: Bool) -> some View {
        if live > 0 {
            Text("\(live)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Theme.accent))
        } else if total > 0 {
            Text("\(total)").foregroundStyle(selected ? Theme.bg.opacity(0.65) : Theme.muted)
        }
    }

    private func orderedLeagues(_ sport: Sport) -> [League] {
        // Always the same order, like the TVs: the most popular league first (NBA, WNBA, NCAA...), so chips never move.
        model.leagues(for: sport)
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
        let today = model.games.filter { $0.state != .finished }.count
        if model.games.isEmpty { return model.isLoading ? "Loading today's games…" : "" }
        return "\(live) live · \(today) still to play today"
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
    /// Unused since the badge shows only the live count (as on the TVs).
    var total = 0
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
                        Text("\(live)")
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
    var total = 0
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
                    Text("\(live)")
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
