import SwiftUI

/// Home, laid out like the Mac: Live Now and the sports down the left (leagues open under the sport you're on),
/// games on the right. Moving onto a sport shows its games; clicking a game opens its streams.
struct TVHomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: TVNav
    @FocusState private var sidebarFocus: TVNav.HomeSelection?
    /// Focus is on the games (or league chips) on the right: the left column shrinks to icons and counts.
    @State private var inPane = false

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
            // The games line up with the text beside the player's video (the games pane pads itself by 24).
            // The left column stays lined up with the player above it (it no longer shrinks), so moving across is smooth.
            HStack(alignment: .top, spacing: TVLayout.playerGap - 24) {
                TVSportList(focused: $sidebarFocus, compact: false)
                    .frame(width: TVLayout.sidebar)
                    // On top of the player in the bottom-left corner.
                    .padding(.bottom, model.pinned != nil ? TVLayout.playerInset : 0)
                    .focusSection()
                    // Coming back from the games lands on the sport you left, not the row beside it.
                    .defaultFocus($sidebarFocus, sidebarTarget, priority: .userInitiated)
                    .zIndex(0)
                TVGamesPane(inPane: $inPane)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .focusSection()
                    .zIndex(1)
            }
            .padding(.horizontal, TVLayout.margin)
            // The navigation container adds wide side margins of its own; use the full width instead.
            .ignoresSafeArea(.container, edges: .horizontal)
            .onChange(of: sidebarFocus) { if sidebarFocus != nil { inPane = false } }
            // Pressing down from Home / EPG / Settings starts on the left column.
            .defaultFocus($sidebarFocus, sidebarTarget, priority: .userInitiated)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { gameID in
                TVGameView(gameID: gameID)
                    .toolbar(.hidden, for: .navigationBar)
                    .ignoresSafeArea(.container, edges: .horizontal)
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
    /// Just icons and counts (while you're on the games), to leave more room for them.
    var compact = false

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
                    live: live, total: model.games.filter { sports.contains($0.league.sport) }.count,
                    detail: "\(model.games.count) today")
                    .padding(.bottom, 14)

                // Sports with live scores | sports shown as channels (pickleball) | sports with nothing today.
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    Rectangle().fill(Theme.raised).frame(height: 2).padding(.horizontal, 16).padding(.vertical, 8)
                    ForEach(group) { sport in
                        let games = model.games(for: sport)
                        let channelOnly = isChannelSport(sport, model: model)
                        row(.sport(sport), symbol: sport.symbol, name: sport.rawValue,
                            live: channelOnly ? 0 : games.filter { $0.state == .live }.count, total: games.count,
                            detail: games.isEmpty ? "No games" : (channelOnly ? "Channels" : "\(games.count) today"),
                            favorite: favorites.contains(sport))
                            .opacity(games.isEmpty ? 0.5 : 1)
                    }
                }
            }
            .padding(.vertical, 20)
        }
        // Use the full width: no Apple TV side insets on top of our own small margin.
        .ignoresSafeArea(.container, edges: .horizontal)
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

    private var groups: [[Sport]] {
        let scored = sports.filter { s in model.games(for: s).contains { !$0.id.hasPrefix("guide-") } }
        let channels = sports.filter { !scored.contains($0) && isChannelSport($0, model: model) }
        let empty = sports.filter { !scored.contains($0) && !channels.contains($0) }
        return [scored, channels, empty].filter { !$0.isEmpty }
    }

    /// Live games as an orange number; otherwise today's count.
    private func row(_ selection: TVNav.HomeSelection, symbol: String, name: String, live: Int, total: Int, detail: String,
                     favorite: Bool = false) -> some View {
        Button {
            nav.homeSelection = selection
        } label: {
            HStack(spacing: 18) {
                Image(systemName: symbol)
                    .font(.system(size: 28))
                    .frame(width: 40)
                if compact {
                    Spacer(minLength: 0)
                    if live > 0 {
                        TVBadge(text: "\(live)", fill: Theme.accent, color: Theme.onAccent)
                    } else if total > 0 {
                        Text("\(total)").font(.system(size: 21)).opacity(0.6)
                    }
                } else {
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
                    TVBadge(text: "\(live)", fill: Theme.accent, color: Theme.onAccent)
                } else {
                    Text(detail)
                        .font(.system(size: 21))
                        .opacity(0.6)
                        .fixedSize()
                }
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
    /// Set while focus is on a game card or league chip here.
    @Binding var inPane: Bool
    @FocusState private var focusedGame: String?
    @AppStorage(Prefs.hiddenSports) private var hiddenSports = ""
    @AppStorage(Prefs.sportOrder) private var sportOrder = ""
    /// Width available for the cards, so they stretch to fill the row (like the Mac) instead of leaving a gap.
    @State private var paneWidth: CGFloat = 1300
    @FocusState private var focusedChip: TVNav.HomeSelection?

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
            // Only games that are live right now, all in one grid (each card names its league), in your sport order,
            // so games from different sports share a row.
            let games = orderedSports(model: model).flatMap { sport in
                sortedGames(model.games(for: sport).filter { $0.state == .live })
            }
            return games.isEmpty ? [] : [PaneSection(id: "live", title: "", symbol: nil, league: nil, games: games)]
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
        // A sport with channels but no live scores (pickleball): its channels as an EPG list, not score cards.
        if let sport = filterSport, isChannelSport(sport, model: model) {
            TVSportChannels(sport: sport)
        } else {
            cards
        }
    }

    private var cards: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 40) {
                // No title or live count line here: the sport is highlighted on the left, and live counts are on the
                // league chips.
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
                        if !section.title.isEmpty {
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
                        }
                        // Cards just wide enough for their team names and scores (not stretched), as many to a row as fit.
                        let width = cardWidth(for: section.league.map { model.games(for: $0.sport) } ?? section.games,
                                              charWidth: 15.5, fixed: 130, minimum: 340, maximum: 560)
                        let count = max(1, Int((paneWidth + 32) / (width + 32)))
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: 32, alignment: .top), count: count),
                                  alignment: .leading, spacing: 32) {
                            ForEach(section.games) { game in
                                Button {
                                    nav.homePath.append(game.id)
                                } label: {
                                    TVGameCard(game: game, showLeague: nav.homeSelection == .liveNow)
                                }
                                .buttonStyle(.card)
                                .focused($focusedGame, equals: game.id)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { paneWidth = $0 }
            .onChange(of: focusedGame) { if focusedGame != nil || focusedChip != nil { inPane = true } }
            .onChange(of: focusedChip) { if focusedGame != nil || focusedChip != nil { inPane = true } }
            // Room around the cards so the focus zoom never slides under the left column or off screen.
            .padding(.vertical, 24)
            .padding(.horizontal, 24)
        }
        // Use the full width: no Apple TV side insets on top of our own small margin.
        .ignoresSafeArea(.container, edges: .horizontal)
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

    /// Live games as an orange number, otherwise today's games in grey.
    @ViewBuilder
    private func chipCount(live: Int, total: Int) -> some View {
        if live > 0 {
            TVBadge(text: "\(live)", fill: Theme.accent, color: Theme.onAccent)
        } else if total > 0 {
            Text("\(total)").font(.system(size: 19)).opacity(0.6)
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
                let sportGames = model.games(for: sport)
                Button {
                    nav.homeSelection = .sport(sport)
                } label: {
                    HStack(spacing: 10) {
                        Text("All")
                            .font(.system(size: 22, weight: .semibold))
                        chipCount(live: sportGames.filter { $0.state == .live }.count, total: sportGames.count)
                    }
                }
                .buttonStyle(TVChipButtonStyle(selected: nav.homeSelection == .sport(sport)))
                .focused($focusedChip, equals: .sport(sport))

                ForEach(ordered) { league in
                    let games = model.games.filter { $0.league.id == league.id }
                    Button {
                        nav.homeSelection = .league(league.id)
                    } label: {
                        HStack(spacing: 10) {
                            TVLeagueLogo(league: league, size: 30)
                            Text(league.name)
                                .font(.system(size: 22, weight: .semibold))
                            chipCount(live: games.filter { $0.state == .live }.count, total: games.count)
                        }
                    }
                    .buttonStyle(TVChipButtonStyle(selected: nav.homeSelection == .league(league.id)))
                    .focused($focusedChip, equals: .league(league.id))
                    .opacity(games.isEmpty ? 0.5 : 1)
                }
            }
            // Moving across the chips switches straight away, like the tabs at the top.
            .onChange(of: focusedChip) {
                if let focusedChip, focusedChip != nav.homeSelection { nav.homeSelection = focusedChip }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
        }
        // Use the full width: no Apple TV side insets on top of our own small margin.
        .ignoresSafeArea(.container, edges: .horizontal)
        .scrollClipDisabled()
        .focusSection()
    }

    private var subtitle: String {
        let live = sections.flatMap(\.games).filter { $0.state == .live }.count
        return live > 0 ? "\(live) live" : ""
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
    private var has4K: Bool { model.mainStreams(game.id).contains { $0.is4K } }

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
        .frame(minHeight: 210, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .opacity(game.state == .upcoming ? 0.6 : (game.state == .finished ? 0.85 : 1))
    }

    private func teamLine(_ team: Team) -> some View {
        HStack(spacing: 16) {
            TVTeamLogo(team: team, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(team.shortName.isEmpty ? team.name : team.shortName)
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if game.state != .upcoming && team.hasLongScore {
                    Text(team.score)
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .foregroundStyle(game.scoreColor(team))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if game.state != .upcoming && !team.hasLongScore {
                Text(team.score)
                    .font(.system(size: 32, weight: .bold).monospacedDigit())
                    .foregroundStyle(game.scoreColor(team))
            }
        }
    }
}

/// A sport with no live scores today but channels or shows in the guide (pickleball): shown as channels.
@MainActor
func isChannelSport(_ sport: Sport, model: AppModel) -> Bool {
    let games = model.games(for: sport)
    return !games.isEmpty && games.allSatisfy { $0.id.hasPrefix("guide-") }
}

/// Every channel showing a channel sport (its own channels and today's shows), like the EPG. Click to play in the
/// player, again for full screen.
struct TVSportChannels: View {
    @EnvironmentObject var model: AppModel
    let sport: Sport
    @FocusState private var focused: Int?

    private var channels: [Channel] {
        var seen = Set<Int>()
        let all = model.games(for: sport).flatMap { model.matches[$0.id] ?? [] }.map(\.channel)
            .filter { seen.insert($0.id).inserted }
        let name = sport.rawValue.lowercased()
        return all.sorted { a, b in
            let ao = a.name.lowercased().contains(name), bo = b.name.lowercased().contains(name)
            return ao != bo ? ao : a.name < b.name
        }
    }

    var body: some View {
        // Under a heading per category they come from (like the game screen), names on one line.
        let all = channels
        var order: [String] = []
        let groups = Dictionary(grouping: all) { (c: Channel) -> String in
            let name = c.categoryName.isEmpty ? "Other" : c.categoryName
            if !order.contains(name) { order.append(name) }
            return name
        }
        let list = order.flatMap { groups[$0] ?? [] }
        let playing = model.pinned?.channel.id
        let nameWidth = TVLayout.nameWidth(all)
        return ScrollView(.vertical) {
            LazyVStack(spacing: 6) {
                ForEach(order, id: \.self) { category in
                    Text(category.uppercased())
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 22)
                        .padding(.top, 14)
                    ForEach(groups[category] ?? []) { channel in
                        Button {
                            if channel.id == playing { model.play(channel, lineup: list) } else { model.pin(channel, lineup: list) }
                        } label: {
                            TVChannelRow(channel: channel, playing: channel.id == playing, nameWidth: nameWidth)
                        }
                        .buttonStyle(TVRowButtonStyle())
                        .focused($focused, equals: channel.id)
                    }
                }
            }
            .padding(.vertical, 20)
        }
        .defaultFocus($focused, playing ?? list.first?.id)
    }
}
