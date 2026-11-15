import SwiftUI

/// Home. iPhone: sport chips across the top, games below. iPad: sports down the left like the Mac, games on the
/// right. Tap a game for its streams.
struct IOSHomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: IOSNav
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                IOSSportSidebar()
            } detail: {
                NavigationStack(path: $nav.homePath) {
                    IOSGamesList(showsSportChips: false)
                        .navigationDestination(for: String.self) { IOSGameView(gameID: $0) }
                }
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            NavigationStack(path: $nav.homePath) {
                IOSGamesList(showsSportChips: true)
                    .navigationDestination(for: String.self) { IOSGameView(gameID: $0) }
            }
        }
    }
}

// MARK: iPad sidebar

struct IOSSportSidebar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: IOSNav
    @AppStorage(Prefs.sportOrder) private var sportOrderPref = ""
    @AppStorage(Prefs.hiddenSports) private var hiddenSports = ""
    @AppStorage(Prefs.favoriteSports) private var favoriteSports = ""

    private var sports: [Sport] {
        _ = (sportOrderPref, hiddenSports, favoriteSports)
        return orderedSports(model: model)
    }

    var body: some View {
        List {
            row(.liveNow, symbol: "dot.radiowaves.left.and.right", name: "Live Now",
                live: model.games.filter { $0.state == .live && sports.contains($0.league.sport) }.count,
                total: model.games.filter { sports.contains($0.league.sport) }.count,
                detail: "\(model.games.count) today")
            Section("Sports") {
                ForEach(sports) { sport in
                    let games = model.games(for: sport)
                    row(.sport(sport), symbol: sport.symbol, name: sport.rawValue,
                        live: games.filter { $0.state == .live }.count, total: games.count,
                        detail: games.isEmpty ? "No games" : "\(games.count) today")
                        .opacity(games.isEmpty ? 0.5 : 1)
                }
            }
        }
        .navigationTitle("Courtside")
        .refreshable { await model.refresh(force: true) }
    }

    /// "2/5 LIVE": live games out of today's games for that sport.
    private func row(_ selection: IOSNav.HomeSelection, symbol: String, name: String, live: Int, total: Int, detail: String) -> some View {
        let selected: Bool = {
            if case .sport(let s) = selection { return nav.selectedSport == s }
            return nav.homeSelection == selection
        }()
        return Button {
            nav.homeSelection = selection
            nav.homePath = []
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 26)
                Text(name)
                    .foregroundStyle(Theme.text)
                Spacer()
                if live > 0 {
                    IOSBadge(text: "\(live)/\(total) LIVE", fill: Theme.accent, color: Theme.onAccent)
                } else {
                    Text(detail).font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
        .listRowBackground(selected ? Theme.raised : Color.clear)
    }
}

// MARK: Games

struct IOSGamesList: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: IOSNav
    @AppStorage(Prefs.hiddenSports) private var hiddenSports = ""
    @AppStorage(Prefs.sportOrder) private var sportOrderPref = ""
    @AppStorage(Prefs.favoriteSports) private var favoriteSports = ""
    let showsSportChips: Bool

    struct GameSection: Identifiable {
        let id: String
        let title: String
        let symbol: String?
        let league: League?
        let games: [Game]
    }

    private var sports: [Sport] {
        _ = (sportOrderPref, hiddenSports, favoriteSports)
        return orderedSports(model: model)
    }

    private var sections: [GameSection] {
        switch nav.homeSelection {
        case .liveNow:
            var out: [GameSection] = []
            for sport in sports {
                let games = model.games(for: sport).filter { $0.state == .live }
                if !games.isEmpty {
                    out.append(GameSection(id: sport.id, title: sport.rawValue, symbol: sport.symbol, league: nil,
                                           games: sortedGames(games)))
                }
            }
            return out
        case .sport(let sport):
            return model.leagues(for: sport).compactMap { league in
                let games = model.games.filter { $0.league.id == league.id }
                return games.isEmpty ? nil
                    : GameSection(id: league.id, title: league.name, symbol: nil, league: league, games: sortedGames(games))
            }
        case .league(let id):
            guard let league = League.all.first(where: { $0.id == id }) else { return [] }
            return [GameSection(id: id, title: league.name, symbol: nil, league: league,
                                games: sortedGames(model.games.filter { $0.league.id == id }))]
        }
    }

    private var title: String {
        switch nav.homeSelection {
        // On iPad "Live Now" is already highlighted in the sidebar, so the title is today's date instead.
        case .liveNow: return "Live Now"
        case .sport(let s): return s.rawValue
        case .league(let id): return League.all.first { $0.id == id }?.sport.rawValue ?? ""
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                statusRow
                if showsSportChips { sportChips }
                if let sport = nav.selectedSport, model.leagues(for: sport).count > 1 { leagueChips(sport) }

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal)
                }
                if sections.isEmpty {
                    Text(model.isLoading && model.games.isEmpty ? "Loading today's games…"
                         : (nav.homeSelection == .liveNow ? "Nothing live right now." : "No games today."))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal)
                }

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            if let league = section.league {
                                IOSLeagueLogo(league: league, size: 24)
                            } else if let symbol = section.symbol {
                                Image(systemName: symbol).foregroundStyle(Theme.accent)
                            }
                            Text(section.title).font(.title3.bold()).foregroundStyle(Theme.text)
                        }
                        .padding(.horizontal)

                        let width = cardWidth(for: section.league.map { model.games(for: $0.sport) }
                                                ?? (section.id == "finals" ? section.games
                                                    : model.games(for: Sport(rawValue: section.title) ?? .basketball)),
                                              charWidth: 9.5, fixed: 90, minimum: 280, maximum: 560)
                        LazyVGrid(columns: showsSportChips
                                      ? [GridItem(.flexible(), spacing: 12)]
                                      : [GridItem(.adaptive(minimum: width, maximum: width), spacing: 12, alignment: .top)],
                                  alignment: .leading, spacing: 12) {
                            ForEach(section.games) { game in
                                NavigationLink(value: game.id) {
                                    IOSGameCard(game: game, showLeague: nav.homeSelection == .liveNow)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .background(Theme.bg)
        // The sport is already picked in the chips (iPhone) or the sidebar (iPad), so no big title repeats it.
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showsSportChips ? .hidden : .automatic, for: .navigationBar)
        .refreshable { await model.refresh(force: true) }
    }

    /// When channels were last downloaded (tap to refresh), on the right.
    private var statusRow: some View {
        HStack {
            Spacer()
            if model.downloadingChannels {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Downloading channels…")
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
            } else if let saved = model.savedAt {
                Button {
                    Task { await model.refresh(force: true) }
                } label: {
                    Label("Updated \(saved.formatted(date: .omitted, time: .shortened))", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.horizontal)
    }

    private var sportChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let live = model.games.filter { $0.state == .live && sports.contains($0.league.sport) }.count
                IOSChip(selected: nav.homeSelection == .liveNow, action: { nav.homeSelection = .liveNow }) {
                    HStack(spacing: 6) {
                        Text("Live Now")
                        if live > 0 { IOSBadge(text: "\(live)", fill: Theme.accent, color: Theme.onAccent) }
                    }
                }
                ForEach(sports) { sport in
                    let games = model.games(for: sport)
                    let liveCount = games.filter { $0.state == .live }.count
                    IOSChip(selected: nav.selectedSport == sport, action: { nav.homeSelection = .sport(sport) }) {
                        HStack(spacing: 6) {
                            Image(systemName: sport.symbol)
                            Text(sport.rawValue)
                            if liveCount > 0 { IOSBadge(text: "\(liveCount)", fill: Theme.accent, color: Theme.onAccent) }
                        }
                    }
                    .opacity(games.isEmpty ? 0.5 : 1)
                }
            }
            .padding(.horizontal)
        }
    }

    private func leagueChips(_ sport: Sport) -> some View {
        let leagues = model.leagues(for: sport)
        let ranks: [String: Int] = Dictionary(uniqueKeysWithValues: leagues.map { league in
            let games = model.games.filter { $0.league.id == league.id }
            return (league.id, games.contains(where: { $0.state == .live }) ? 0 : (games.isEmpty ? 2 : 1))
        })
        let ordered = leagues.enumerated()
            .sorted { ((ranks[$0.element.id] ?? 2), $0.offset) < ((ranks[$1.element.id] ?? 2), $1.offset) }
            .map(\.element)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                IOSChip(selected: nav.homeSelection == .sport(sport), action: { nav.homeSelection = .sport(sport) }) {
                    Text("All")
                }
                ForEach(ordered) { league in
                    let count = model.games.filter { $0.league.id == league.id }.count
                    IOSChip(selected: nav.homeSelection == .league(league.id), action: { nav.homeSelection = .league(league.id) }) {
                        HStack(spacing: 6) {
                            IOSLeagueLogo(league: league, size: 18)
                            Text(league.name)
                            if count > 0 { Text("\(count)").opacity(0.6) }
                        }
                    }
                    .opacity(count == 0 ? 0.5 : 1)
                }
            }
            .padding(.horizontal)
        }
    }
}

/// A game card: status and stream count on top, then both teams with logos and scores.
struct IOSGameCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    var showLeague = false

    private var streams: Int { model.streamCount(game.id) }
    private var has4K: Bool { model.mainStreams(game.id).contains { $0.qualityRank == 4 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(showLeague ? "\(game.league.name) · \(game.headerText)" : game.headerText)
                    .font(.caption.bold())
                    .foregroundStyle(game.state == .live ? Theme.accent : Theme.soft)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if has4K { IOSBadge(text: "4K", fill: Theme.accent, color: Theme.onAccent) }
                Text(streams == 0 ? "No streams" : "\(streams)")
                    .font(.caption)
                    .foregroundStyle(streams == 0 ? Theme.danger : Theme.muted)
                if streams > 0 {
                    Image(systemName: "play.tv").font(.caption2).foregroundStyle(Theme.muted)
                }
            }
            if game.isEvent && !game.hasSides {
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.eventTitle).font(.headline).foregroundStyle(Theme.text).lineLimit(2)
                    if !game.eventDetail.isEmpty {
                        Text(game.eventDetail).font(.subheadline).foregroundStyle(Theme.soft).lineLimit(2)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    teamLine(game.away)
                    teamLine(game.home)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        .opacity(game.state == .upcoming ? 0.6 : (game.state == .finished ? 0.85 : 1))
        .contentShape(Rectangle())
    }

    private func teamLine(_ team: Team) -> some View {
        HStack(spacing: 10) {
            IOSTeamLogo(team: team, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(team.shortName.isEmpty ? team.name : team.shortName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if game.state != .upcoming && team.hasLongScore {
                    Text(team.score)
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(game.scoreColor(team))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            if game.state != .upcoming && !team.hasLongScore {
                Text(team.score)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(game.scoreColor(team))
            }
        }
    }
}
