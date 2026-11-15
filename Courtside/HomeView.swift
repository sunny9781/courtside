import SwiftUI

/// A sport's games grouped into league sections (logo and name as the heading),
/// or a single league when one is picked in the left column.
struct SportView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.showFinished) private var showFinished = true
    let sport: Sport
    var leagueID: String? = nil
    let onOpen: (Game) -> Void

    private var allGames: [Game] { model.games(for: sport) }

    private var league: League? {
        leagueID.flatMap { id in sport.leagues.first { $0.id == id } }
    }

    /// Leagues to show: the picked one, or every league with games today (in the usual order).
    private var sections: [League] {
        if let league { return [league] }
        return model.leagues(for: sport).filter { l in allGames.contains { $0.league == l } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                ScreenHeader(title: league?.name ?? sport.rawValue,
                             subtitle: Date().formatted(.dateTime.weekday(.wide).month(.wide).day())) { EmptyView() }

                if let error = model.errorMessage {
                    Banner(text: error)
                }

                if sections.isEmpty || sections.allSatisfy({ l in !allGames.contains { $0.league == l } }) {
                    emptyState
                }

                ForEach(sections) { item in
                    LeagueSection(league: item, games: allGames.filter { $0.league == item },
                                  showHeading: league == nil, showFinished: showFinished, onOpen: onOpen)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .padding(.bottom, 48)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.isLoading {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Loading today's games and your channels…")
                    .foregroundStyle(Theme.muted)
            }
        } else if model.errorMessage == nil {
            Text("No \(league?.name ?? sport.rawValue) games today.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
        }
    }
}

/// One league's games: live cards, then coming up, then finished.
struct LeagueSection: View {
    @EnvironmentObject var model: AppModel
    let league: League
    let games: [Game]
    let showHeading: Bool
    let showFinished: Bool
    let onOpen: (Game) -> Void

    var body: some View {
        let live = games.filter { $0.state == .live }
        let upcoming = games.filter { $0.state == .upcoming }
        let finished = games.filter { $0.state == .finished }

        VStack(alignment: .leading, spacing: 16) {
            if showHeading {
                HStack(spacing: 14) {
                    LeagueLogo(league: league, size: 40)
                    Text(league.name)
                        .font(Theme.display(22))
                        .foregroundStyle(Theme.text)
                    Text([live.isEmpty ? nil : "\(live.count) live",
                          upcoming.isEmpty ? nil : "\(upcoming.count) coming up"].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
            }

            // One grid of cards: live first, then coming up (greyed, by start time), then finished.
            let byStart: (Game, Game) -> Bool = { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
            let cards = live.sorted(by: byStart) + upcoming.sorted(by: byStart)
                + (showFinished ? finished.sorted(by: byStart) : [])
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 16)], spacing: 16) {
                ForEach(cards) { game in
                    LiveGameCard(game: game, streams: model.streamCount(game.id)) { onOpen(game) }
                }
            }
        }
    }
}

/// A league's logo from the schedule feed, or the sport icon when there isn't one.
struct LeagueLogo: View {
    @EnvironmentObject var model: AppModel
    let league: League
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let url = model.leagueLogos[league.id] {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: league.sport.symbol).foregroundStyle(Theme.accent)
                }
            } else {
                Image(systemName: league.sport.symbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Theme.accent)
                    .padding(size * 0.15)
            }
        }
        .frame(width: size, height: size)
    }
}

func streamCountText(_ n: Int) -> String {
    n == 1 ? "1 stream" : "\(n) streams"
}

/// A live game, or one starting soon (greyed out with its start time, still clickable).
struct LiveGameCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    let streams: Int
    var showLeague = false
    let action: () -> Void

    private var has4K: Bool {
        model.mainStreams(game.id).contains { $0.qualityRank == 4 }
    }

    private var header: String {
        let state: String
        switch game.state {
        case .live: state = "LIVE · \(game.statusText)"
        case .upcoming: state = "STARTS \(game.statusText)"
        case .finished: state = game.statusText.uppercased()
        }
        return showLeague ? "\(game.league.name) · \(state)" : state
    }

    var body: some View {
        CardButton(radius: 16, action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(header)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(game.state == .live ? Theme.accent : Theme.soft)
                        .lineLimit(1)
                    Spacer()
                    if has4K {
                        Text("4K")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accent))
                            .help("A 4K stream is available")
                    }
                    Text(streamCountText(streams))
                        .font(.system(size: 12))
                        .foregroundStyle(streams == 0 ? Theme.danger : Theme.muted)
                }
                if game.isEvent {
                    EventLines(game: game)
                } else {
                    VStack(spacing: 10) {
                        TeamLine(team: game.away, scoreColor: game.scoreColor(game.away))
                        TeamLine(team: game.home, scoreColor: game.scoreColor(game.home))
                    }
                }
            }
            .padding(20)
        }
        .opacity(game.state == .upcoming ? 0.55 : (game.state == .finished ? 0.8 : 1))
        .help(game.state == .upcoming ? "Starts \(game.statusText). Click to see its streams." : "")
    }
}

struct TeamLine: View {
    let team: Team
    var big = false
    var scoreColor: Color = Theme.text

    var body: some View {
        HStack(spacing: 12) {
            TeamBadge(abbr: team.abbr, logo: team.logo, size: big ? 50 : 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(team.shortName)
                    .font(big ? Theme.display(30) : .system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if team.hasLongScore {
                    Text(team.score)
                        .font(.system(size: big ? 20 : 15, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(scoreColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            if !team.hasLongScore {
                Text(team.score)
                    .font(Theme.display(big ? 30 : 22))
                    .monospacedDigit()
                    .foregroundStyle(scoreColor)
            }
        }
    }
}

/// One game per row, in fixed-width columns so every row lines up:
/// time · league (right-aligned) · network · away team · at · home team · score · streams.
struct GameRowCard: View {
    let game: Game
    let streams: Int
    var showLeague = false
    let action: () -> Void

    /// Away team: name then logo, pushed toward "at". Home team: logo then name, right after "at".
    private func team(_ t: Team, away: Bool) -> some View {
        HStack(spacing: 8) {
            if away {
                Text(t.shortName).lineLimit(1)
                TeamBadge(abbr: t.abbr, logo: t.logo, size: 28)
            } else {
                TeamBadge(abbr: t.abbr, logo: t.logo, size: 28)
                Text(t.shortName).lineLimit(1)
            }
        }
        .frame(width: 180, alignment: away ? .trailing : .leading)
    }

    var body: some View {
        CardButton(radius: 12, action: action) {
            HStack(spacing: 20) {
                Text(game.statusText)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .frame(width: 80, alignment: .leading)

                if showLeague {
                    Badge(text: game.league.name)
                        .frame(width: 130, alignment: .trailing)
                }

                Text(game.broadcasters.joined(separator: " · "))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 150, alignment: .leading)
                    .help(game.broadcasters.joined(separator: ", "))

                if game.isEvent {
                    HStack(spacing: 10) {
                        Image(systemName: game.league.sport.symbol)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(game.eventTitle)
                                .lineLimit(1)
                            if !game.eventDetail.isEmpty {
                                Text(game.eventDetail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(width: 420, alignment: .leading)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                } else {
                    HStack(spacing: 12) {
                        team(game.away, away: true)
                        Text("at")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 18)
                        team(game.home, away: false)
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                }

                if game.state == .finished && !game.isEvent {
                    Text("\(game.away.score) – \(game.home.score)")
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.soft)
                        .frame(width: 70, alignment: .leading)
                }

                Spacer(minLength: 0)

                Text(streamCountText(streams))
                    .font(.system(size: 12))
                    .foregroundStyle(streams == 0 ? Theme.danger : Theme.muted)
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(minHeight: 56)
        }
    }
}

/// An event's name with its session, leader or main event, in place of two team lines.
struct EventLines: View {
    let game: Game
    var big = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: game.league.sport.symbol)
                .font(.system(size: big ? 30 : 22))
                .foregroundStyle(Theme.accent)
                .frame(width: big ? 50 : 40, height: big ? 50 : 40)
                .background(Circle().fill(Theme.raised))
            VStack(alignment: .leading, spacing: 4) {
                Text(game.eventTitle)
                    .font(big ? Theme.display(28) : .system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                if !game.eventDetail.isEmpty {
                    Text(game.eventDetail)
                        .font(.system(size: big ? 15 : 13))
                        .foregroundStyle(Theme.soft)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: big ? 110 : 90, alignment: .top)
    }
}
