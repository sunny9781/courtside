import SwiftUI

/// Home: a row of live games across every sport, then a row per sport. Pick a game to see its streams.
struct TVHomeView: View {
    @EnvironmentObject var model: AppModel
    // Re-read the order when these change in Settings.
    @AppStorage(Prefs.sportOrder) private var sportOrder = ""
    @AppStorage(Prefs.hiddenSports) private var hiddenSports = ""
    @AppStorage(Prefs.favoriteSports) private var favoriteSports = ""

    private var sports: [Sport] {
        _ = (sportOrder, hiddenSports, favoriteSports)
        return tvSportOrder(model: model).filter { !model.games(for: $0).isEmpty }
    }

    private var liveNow: [Game] {
        let shown = Set(sports)
        let order = Dictionary(uniqueKeysWithValues: sports.enumerated().map { ($1, $0) })
        return model.games
            .filter { $0.state == .live && shown.contains($0.league.sport) }
            .sorted { (order[$0.league.sport] ?? 0) < (order[$1.league.sport] ?? 0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 56) {
                    if let message = statusMessage {
                        Text(message)
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 80)
                    }
                    if !liveNow.isEmpty {
                        TVShelf(title: "Live now", symbol: "dot.radiowaves.left.and.right", games: liveNow)
                    }
                    ForEach(sports) { sport in
                        TVShelf(title: sport.rawValue, symbol: sport.symbol, games: tvSorted(model.games(for: sport)))
                    }
                }
                .padding(.vertical, 40)
            }
            .navigationDestination(for: String.self) { gameID in
                TVGameView(gameID: gameID)
            }
        }
    }

    private var statusMessage: String? {
        if let error = model.errorMessage { return error }
        if model.games.isEmpty {
            return model.isLoading ? "Loading today's games…" : "No games today."
        }
        return nil
    }
}

/// One sideways-scrolling row of game cards.
struct TVShelf: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let symbol: String
    let games: [Game]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(title, systemImage: symbol)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 80)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 40) {
                    ForEach(games) { game in
                        NavigationLink(value: game.id) {
                            TVGameCard(game: game, streams: model.streamCount(game.id))
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 24)
            }
            .scrollClipDisabled()
        }
    }
}

/// A game on a shelf: status, both teams with logos and scores, and how many streams were found.
struct TVGameCard: View {
    let game: Game
    let streams: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if game.state == .live {
                    TVBadge(text: "LIVE", fill: Theme.accent, color: Theme.onAccent)
                }
                Text(game.tvStatus)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(game.state == .live ? Theme.text : Theme.muted)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(game.league.name)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }

            if game.isEvent && !game.hasSides {
                VStack(alignment: .leading, spacing: 8) {
                    Text(game.eventTitle)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    if !game.eventDetail.isEmpty {
                        Text(game.eventDetail)
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.soft)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            } else {
                teamLine(game.away)
                teamLine(game.home)
            }

            Text(streams == 0 ? "No streams found yet" : streams == 1 ? "1 stream" : "\(streams) streams")
                .font(.system(size: 20))
                .foregroundStyle(Theme.muted)
        }
        .padding(24)
        .frame(width: 470, height: 270, alignment: .topLeading)
        .background(Theme.card)
        .opacity(game.state == .upcoming ? 0.75 : 1)
    }

    private func teamLine(_ team: Team) -> some View {
        HStack(spacing: 16) {
            TVTeamLogo(team: team, size: 52)
            Text(team.shortName.isEmpty ? team.name : team.shortName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            if game.state != .upcoming {
                Text(team.score)
                    .font(.system(size: 34, weight: .bold).monospacedDigit())
                    .foregroundStyle(game.scoreColor(team))
            }
        }
    }
}
