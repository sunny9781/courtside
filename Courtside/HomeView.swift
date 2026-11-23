import SwiftUI

/// A sport's games grouped into league sections (logo and name as the heading),
/// or a single league when one is picked in the left column.
struct SportView: View {
    @EnvironmentObject var model: AppModel
    let sport: Sport
    var leagueID: String? = nil
    let onOpen: (Game) -> Void

    /// Finished games only under the Finished chip (2.45); everywhere else, what's live or coming up.
    private var finishedPage: Bool { leagueID == finishedLeagueID }
    private var allGames: [Game] { model.games(for: sport).filter { ($0.state == .finished) == finishedPage } }
    @State private var width: CGFloat = 0

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
                if let error = model.errorMessage {
                    Banner(text: error)
                }

                let redZone = HomeFolds.redZone(model: model, sport: leagueID == nil || leagueID == "nfl" ? sport : nil)
                if let redZone {
                    // A card (2.41): opens a game screen of RedZone's channels, grouped like any game's streams.
                    // A slim bar across the whole row (2.42).
                    Button { onOpen(redZone) } label: {
                        HStack(spacing: 12) {
                            Text("LIVE").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent)
                            Text(redZone.title).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                            Spacer(minLength: 8)
                            let n = model.streamCount(redZone.id)
                            Text(n == 1 ? "1 channel" : "\(n) channels").font(.system(size: 12)).foregroundStyle(Theme.muted)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                        .contentShape(Rectangle())
                    }
                }

                if sections.isEmpty || sections.allSatisfy({ l in !allGames.contains { $0.league == l } }) {
                    emptyState
                }

                // Leagues with only a few games (and none finished) share a row when they fit (2.43).
                let cardMin = cardWidth(for: allGames, charWidth: 9.5, fixed: 112, minimum: 260, maximum: 560) * 0.86
                let cols = max(1, Int((width + 16) / (cardMin + 16)))
                let packs = sections.count > 1 && width > 0
                    ? packRows(sections, columns: cols) { l in
                        let g = allGames.filter { $0.league == l }
                        return g.count
                    }
                    : sections.map { [$0] }
                ForEach(packs, id: \.first!.id) { pack in
                    if pack.count > 1 {
                        let card = (width - 16 * CGFloat(cols - 1)) / CGFloat(cols)
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(pack) { item in
                                let games = allGames.filter { $0.league == item }
                                VStack(alignment: .leading, spacing: 16) {
                                    LeagueSummary(league: item, games: games)
                                    HStack(alignment: .top, spacing: 16) {
                                        ForEach(games.sorted { ($0.state == .live ? 0 : 1, $0.start ?? .distantFuture) < ($1.state == .live ? 0 : 1, $1.start ?? .distantFuture) }) { game in
                                            LiveGameCard(game: game, streams: model.streamCount(game.id)) { onOpen(game) }
                                                .frame(width: card)
                                        }
                                    }
                                }
                            }
                        }
                    } else if let item = pack.first {
                        // One league on screen with the chip row above: its name sits at the end of that row instead.
                        LeagueSection(league: item, games: allGames.filter { $0.league == item },
                                      showHeading: sections.count > 1 || model.leagues(for: sport).count <= 1 || finishedPage,
                                      onOpen: onOpen, finishedPage: finishedPage)
                    }
                }
            }
            // Always full width on the left: with every game folded away it used to shrink and sit in the middle.
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .padding(.horizontal, 40)
            .padding(.top, 20)
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
    let onOpen: (Game) -> Void
    /// The Finished chip's page (2.45): the finished games as ordinary cards, no fold.
    var finishedPage = false
    /// Finished games show under the cards (as on the TVs); "Finished · 6" folds them away.
    @State private var showFinished = true

    var body: some View {
        let live = games.filter { $0.state == .live }
        let upcoming = games.filter { $0.state == .upcoming }
        let finished = games.filter { $0.state == .finished }

        VStack(alignment: .leading, spacing: 16) {
            if showHeading {
                // Compact: a small logo and the name on one short line (it used to take a tall row).
                LeagueSummary(league: league, games: games)
            }

            // Live first, then coming up (greyed, by start time). "Finished" folds below, each
            // heading above its own cards (as on the TVs).
            let byStart: (Game, Game) -> Bool = { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
            // The smallest width that fits the longest names; the grid fits as many as it can per row and stretches
            // them to fill it (no empty band on the right).
            let width = cardWidth(for: model.games(for: league.sport), charWidth: 9.5, fixed: 112, minimum: 260, maximum: 560) * 0.86
            grid(finishedPage ? finished.sorted(by: byStart) : live.sorted(by: byStart) + upcoming.sorted(by: byStart), width: width)
            if !finished.isEmpty && !finishedPage {
                FoldButton(text: "Finished · \(finished.count)", open: $showFinished)
                if showFinished { grid(finished.sorted(by: byStart), width: width) }
            }
        }
    }

    @ViewBuilder
    private func grid(_ cards: [Game], width: CGFloat) -> some View {
        if !cards.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: width), spacing: 16, alignment: .top)],
                      alignment: .leading, spacing: 16) {
                ForEach(cards) { game in
                    LiveGameCard(game: game, streams: model.streamCount(game.id)) { onOpen(game) }
                }
            }
        }
    }
}

/// A league's logo, name and "2 live · 9 coming up": above its cards, or at the end of the chip row when it's the
/// only league on screen.
struct LeagueSummary: View {
    let league: League
    let games: [Game]

    var body: some View {
        let live = games.filter { $0.state == .live }.count
        let upcoming = games.filter { $0.state == .upcoming }.count
        let finished = games.filter { $0.state == .finished }.count
        HStack(spacing: 10) {
            LeagueLogo(league: league, size: 24)
            Text(league.name)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.text)
            Text([live == 0 ? nil : "\(live) live", upcoming == 0 ? nil : "\(upcoming) coming up",
                  finished == 0 ? nil : "\(finished) finished"].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
        }
    }
}

/// "Finished · 6": click to show or hide them.
struct FoldButton: View {
    let text: String
    @Binding var open: Bool
    var colour: Color = Theme.muted

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(colour)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A channel sport (pickleball): its channels under the category each comes from, like the TVs. Click to play in
/// the player, double-click for full screen.
struct MacSportChannels: View {
    @EnvironmentObject var model: AppModel
    let sport: Sport

    var body: some View {
        let groups = channelSportGroups(sport, model: model)
        let lineup = groups.flatMap(\.channels)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if let error = model.errorMessage { Banner(text: error) }
                ForEach(groups, id: \.category) { group in
                    Text(group.category.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 14)
                    ForEach(group.channels) { MacChannelLine(channel: $0, lineup: lineup) }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 10)
            .padding(.bottom, 48)
        }
    }
}

/// One channel as a line: logo, name, what's on now, and its resolution, frame rate and sound once played.
struct MacChannelLine: View {
    @EnvironmentObject var model: AppModel
    let channel: Channel
    let lineup: [Channel]

    var body: some View {
        let playing = model.pinned?.channel.id == channel.id
        let now = model.currentProgramme(channel)
        CardButton(radius: 10, action: {
            if playing { model.play(channel, lineup: lineup) } else { model.pin(channel, lineup: lineup) }
        }) {
            HStack(spacing: 12) {
                SmallLogoImage(url: channel.icon, size: 64) {
                    Text(String(channel.name.prefix(3)).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.muted)
                }
                .padding(4)
                .frame(width: 52, height: 34)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.raised))
                Text(channel.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(playing ? Theme.accent : Theme.text)
                    .lineLimit(1)
                    .frame(width: 260, alignment: .leading)
                Text(now?.title ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.soft)
                    .lineLimit(1)
                Spacer(minLength: 8)
                ForEach(MacChannelLine.tags(channel, model: model), id: \.self) { Badge(text: $0) }
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.play(channel, lineup: lineup) })
        .help("Click to play in the mini player, double-click for full screen")
    }

    /// Resolution, frame rate and sound measured when the channel last played.
    @MainActor static func tags(_ channel: Channel, model: AppModel) -> [String] {
        [model.measuredQuality[channel.id],
         model.measuredFrameRate[channel.id].map(PlaybackController.fpsLabel),
         model.measuredAudio[channel.id]].compactMap { $0 }.filter { !$0.isEmpty }
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
                SmallLogoImage(url: url, size: size) {
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
        model.mainStreams(game.id).contains { $0.is4K }
    }

    private var header: String {
        let state: String
        switch game.state {
        case _ where game.isChannel: state = "CHANNEL"
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
                    // Like the TV cards: how many streams it has, or "None" in red.
                    if !game.isChannel {
                        let count = model.mainStreams(game.id).count
                        HStack(spacing: 4) {
                            Text(count == 0 ? "None" : "\(count)")
                                .font(.system(size: 12, weight: .semibold))
                            if count > 0 { Image(systemName: "play.tv").font(.system(size: 11)) }
                        }
                        .foregroundStyle(count == 0 ? Theme.danger : Theme.muted)
                        .help(count == 0 ? "No streams found yet" : "\(count) streams")
                    }
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
        // Right-click › Watch alongside (2.44, like the TVs): the best stream of this game beside the one playing.
        .contextMenu {
            if !game.isChannel, game.state != .finished { MacWatchAlongsideButton(game: game) }
        }
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
