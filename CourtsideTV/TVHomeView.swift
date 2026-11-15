import SwiftUI

/// Home, laid out like the Mac: Live Now and the sports down the left (leagues open under the sport you're on),
/// games on the right. Moving onto a sport shows its games; clicking a game opens its streams.
struct TVHomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: TVNav
    @FocusState private var sidebarFocus: TVNav.HomeSelection?

    /// The row to land on when coming down from the tabs: the selected sport (or Live Now).
    private var sidebarTarget: TVNav.HomeSelection {
        switch nav.homeSelection {
        case .liveNow: return .liveNow
        case .sport(let s): return .sport(s)
        case .league(let id): return League.all.first { $0.id == id }.map { .sport($0.sport) } ?? .liveNow
        }
    }

    var body: some View {
        NavigationStack(path: $nav.homePath) {
            HStack(alignment: .top, spacing: 30) {
                TVSportList(focused: $sidebarFocus)
                    .frame(width: TVLayout.sidebar)
                    .focusSection()
                    .zIndex(0)
                TVGamesPane()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .focusSection()
                    .zIndex(1)
            }
            .padding(.horizontal, TVLayout.margin)
            // Pressing down from Home / EPG / Settings starts on the left column.
            .defaultFocus($sidebarFocus, sidebarTarget, priority: .userInitiated)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { gameID in
                TVGameView(gameID: gameID)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
    }
}

// MARK: Left column

struct TVSportList: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: TVNav
    @AppStorage(Prefs.sportOrder) private var sportOrder = ""
    @AppStorage(Prefs.hiddenSports) private var hiddenSports = ""
    @AppStorage(Prefs.favoriteSports) private var favoriteSports = ""
    var focused: FocusState<TVNav.HomeSelection?>.Binding

    private var sports: [Sport] {
        _ = (sportOrder, hiddenSports, favoriteSports)
        return orderedSports(model: model)
    }

    /// The sport highlighted on the left: the one selected, or the one a selected league belongs to.
    private var openSport: Sport? {
        switch nav.homeSelection {
        case .sport(let s): return s
        case .league(let id): return League.all.first { $0.id == id }?.sport
        case .liveNow: return nil
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 6) {
                let live = model.games.filter { $0.state == .live && sports.contains($0.league.sport) }.count
                row(.liveNow, symbol: "dot.radiowaves.left.and.right", name: "Live Now",
                    live: live, detail: "\(model.games.count) today")
                    .padding(.bottom, 14)

                ForEach(sports) { sport in
                    let games = model.games(for: sport)
                    row(.sport(sport), symbol: sport.symbol, name: sport.rawValue,
                        live: games.filter { $0.state == .live }.count,
                        detail: games.isEmpty ? "No games" : "\(games.count) today",
                        favorite: favorites.contains(sport))
                        .opacity(games.isEmpty ? 0.5 : 1)
                }
            }
            .padding(.vertical, 20)
        }
        .onChange(of: focused.wrappedValue) {
            // Moving onto a row shows its games, the usual Apple TV sidebar behaviour. Coming back to the sport
            // whose league you picked on the right keeps that league.
            guard let focused = focused.wrappedValue, focused != nav.homeSelection else { return }
            if case .sport(let s) = focused, openSport == s { return }
            nav.homeSelection = focused
        }
    }

    private var favorites: Set<Sport> {
        Set(favoriteSports.split(separator: ",").compactMap { Sport(rawValue: String($0)) })
    }

    private func row(_ selection: TVNav.HomeSelection, symbol: String, name: String, live: Int, detail: String,
                     favorite: Bool = false) -> some View {
        Button {
            nav.homeSelection = selection
        } label: {
            HStack(spacing: 18) {
                Image(systemName: symbol)
                    .font(.system(size: 28))
                    .frame(width: 40)
                Text(name)
                    .font(.system(size: 28, weight: .semibold))
                    .lineLimit(1)
                if favorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.accent)
                }
                Spacer(minLength: 8)
                if live > 0 {
                    TVBadge(text: "\(live) LIVE", fill: Theme.accent, color: Theme.onAccent)
                } else {
                    Text(detail)
                        .font(.system(size: 21))
                        .opacity(0.6)
                        .fixedSize()
                }
            }
        }
        .buttonStyle(TVRowButtonStyle(selected: isSelected(selection)))
        .focused(focused, equals: selection)
    }

    private func isSelected(_ selection: TVNav.HomeSelection) -> Bool {
        if case .sport(let s) = selection { return openSport == s }
        return nav.homeSelection == selection
    }
}

// MARK: Right side

struct TVGamesPane: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: TVNav
    @AppStorage(Prefs.hiddenSports) private var hiddenSports = ""
    @AppStorage(Prefs.sportOrder) private var sportOrder = ""

    struct PaneSection: Identifiable {
        let id: String
        let title: String
        let symbol: String?
        let league: League?
        let games: [Game]
    }

    private var sections: [PaneSection] {
        _ = (hiddenSports, sportOrder)
        switch nav.homeSelection {
        case .liveNow:
            // Live and starting-soon games by sport (upcoming dimmed), then today's final scores.
            var out: [PaneSection] = []
            for sport in orderedSports(model: model) {
                let games = model.games(for: sport).filter { $0.state != .finished }
                if !games.isEmpty {
                    out.append(PaneSection(id: sport.id, title: sport.rawValue, symbol: sport.symbol, league: nil,
                                       games: sortedGames(games)))
                }
            }
            let shown = Set(orderedSports(model: model))
            let finals = model.games.filter { $0.state == .finished && shown.contains($0.league.sport) }
            if !finals.isEmpty {
                out.append(PaneSection(id: "finals", title: "Final scores", symbol: "checkmark.circle", league: nil,
                                   games: finals.sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }))
            }
            return out
        case .sport(let sport):
            return model.leagues(for: sport).compactMap { league in
                let games = model.games.filter { $0.league.id == league.id }
                return games.isEmpty ? nil
                    : PaneSection(id: league.id, title: league.name, symbol: nil, league: league, games: sortedGames(games))
            }
        case .league(let id):
            guard let league = League.all.first(where: { $0.id == id }) else { return [] }
            let games = model.games.filter { $0.league.id == id }
            return [PaneSection(id: id, title: league.name, symbol: nil, league: league, games: sortedGames(games))]
        }
    }

    private var title: String {
        switch nav.homeSelection {
        case .liveNow: return "Live Now"
        case .sport(let s): return s.rawValue
        case .league(let id): return League.all.first { $0.id == id }?.sport.rawValue ?? ""
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 40) {
                VStack(alignment: .leading, spacing: 6) {
                    // "Live Now" is already highlighted on the left, so it isn't repeated here.
                    if nav.homeSelection != .liveNow {
                        Text(title)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(Theme.text)
                    }
                    Text(subtitle)
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.muted)
                }

                if let sport = filterSport, model.leagues(for: sport).count > 1 {
                    leagueFilters(sport)
                }

                if sections.isEmpty {
                    Text(emptyMessage)
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.muted)
                }

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(spacing: 14) {
                            if let league = section.league {
                                TVLeagueLogo(league: league, size: 44)
                            } else if let symbol = section.symbol {
                                Image(systemName: symbol)
                                    .font(.system(size: 24))
                                    .foregroundStyle(Theme.accent)
                            }
                            Text(section.title)
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(Theme.text)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 32, alignment: .top), count: 3),
                                  alignment: .leading, spacing: 32) {
                            ForEach(section.games) { game in
                                Button {
                                    nav.homePath.append(game.id)
                                } label: {
                                    TVGameCard(game: game, showLeague: nav.homeSelection == .liveNow)
                                }
                                .buttonStyle(.card)
                            }
                        }
                    }
                }
            }
            // Room around the cards so the focus zoom never slides under the left column or off screen.
            .padding(.vertical, 24)
            .padding(.horizontal, 24)
        }
        .scrollClipDisabled()
    }

    /// The sport whose league filters show above the games.
    private var filterSport: Sport? {
        switch nav.homeSelection {
        case .sport(let s): return s
        case .league(let id): return League.all.first { $0.id == id }?.sport
        case .liveNow: return nil
        }
    }

    /// "All · NBA · WNBA · NCAA Men…" — leagues with games first.
    private func leagueFilters(_ sport: Sport) -> some View {
        let leagues = model.leagues(for: sport)
        let ranks: [String: Int] = Dictionary(uniqueKeysWithValues: leagues.map { league in
            let games = model.games.filter { $0.league.id == league.id }
            return (league.id, games.contains(where: { $0.state == .live }) ? 0 : (games.isEmpty ? 2 : 1))
        })
        let ordered = leagues.enumerated()
            .sorted { ((ranks[$0.element.id] ?? 2), $0.offset) < ((ranks[$1.element.id] ?? 2), $1.offset) }
            .map(\.element)
        return ScrollView(.horizontal) {
            HStack(spacing: 16) {
                Button {
                    nav.homeSelection = .sport(sport)
                } label: {
                    Text("All")
                        .font(.system(size: 22, weight: .semibold))
                }
                .buttonStyle(TVChipButtonStyle(selected: nav.homeSelection == .sport(sport)))

                ForEach(ordered) { league in
                    let count = model.games.filter { $0.league.id == league.id }.count
                    Button {
                        nav.homeSelection = .league(league.id)
                    } label: {
                        HStack(spacing: 10) {
                            TVLeagueLogo(league: league, size: 30)
                            Text(league.name)
                                .font(.system(size: 22, weight: .semibold))
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 19))
                                    .opacity(0.6)
                            }
                        }
                    }
                    .buttonStyle(TVChipButtonStyle(selected: nav.homeSelection == .league(league.id)))
                    .opacity(count == 0 ? 0.5 : 1)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
        }
        .scrollClipDisabled()
        .focusSection()
    }

    private var subtitle: String {
        let date = Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
        let live = sections.flatMap(\.games).filter { $0.state == .live }.count
        return live > 0 ? "\(date) · \(live) live" : date
    }

    private var emptyMessage: String {
        if let error = model.errorMessage { return error }
        if model.isLoading && model.games.isEmpty { return "Loading today's games…" }
        return nav.homeSelection == .liveNow ? "Nothing live right now." : "No games today."
    }
}

/// A game card, like the Mac's: status and stream count on top, then both teams with logos and scores.
struct TVGameCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    var showLeague = false

    private var streams: Int { model.streamCount(game.id) }
    private var has4K: Bool { model.mainStreams(game.id).contains { $0.qualityRank == 4 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Text(showLeague ? "\(game.league.name) · \(game.headerText)" : game.headerText)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(game.state == .live ? Theme.accent : Theme.soft)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if has4K {
                    TVBadge(text: "4K", fill: Theme.accent, color: Theme.onAccent)
                }
                Text(streams == 0 ? "No streams" : "\(streams)")
                    .font(.system(size: 19))
                    .foregroundStyle(streams == 0 ? Theme.danger : Theme.muted)
                    .fixedSize()
                if streams > 0 {
                    Image(systemName: "play.tv")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.muted)
                }
            }

            if game.isEvent && !game.hasSides {
                VStack(alignment: .leading, spacing: 8) {
                    Text(game.eventTitle)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    if !game.eventDetail.isEmpty {
                        Text(game.eventDetail)
                            .font(.system(size: 21))
                            .foregroundStyle(Theme.soft)
                            .lineLimit(2)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                VStack(spacing: 14) {
                    teamLine(game.away)
                    teamLine(game.home)
                }
            }
        }
        .padding(24)
        .frame(height: 210, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .opacity(game.state == .upcoming ? 0.6 : (game.state == .finished ? 0.85 : 1))
    }

    private func teamLine(_ team: Team) -> some View {
        HStack(spacing: 16) {
            TVTeamLogo(team: team, size: 48)
            Text(team.shortName.isEmpty ? team.name : team.shortName)
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            if game.state != .upcoming {
                Text(team.score)
                    .font(.system(size: 32, weight: .bold).monospacedDigit())
                    .foregroundStyle(game.scoreColor(team))
            }
        }
    }
}
