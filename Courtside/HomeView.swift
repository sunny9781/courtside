import SwiftUI

/// A sport's games grouped into league sections (logo and name as the heading),
/// or a single league when one is picked in the left column.
struct SportView: View {
    @EnvironmentObject var model: AppModel
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
                if let error = model.errorMessage {
                    Banner(text: error)
                }

                let redZone = HomeFolds.redZone(model: model, sport: leagueID == nil || leagueID == "nfl" ? sport : nil)
                if !redZone.isEmpty { RedZoneFolder(channels: redZone) }

                if sections.isEmpty || sections.allSatisfy({ l in !allGames.contains { $0.league == l } }) {
                    emptyState
                }

                ForEach(sections) { item in
                    LeagueSection(league: item, games: allGames.filter { $0.league == item },
                                  showHeading: league == nil, onOpen: onOpen)
                }
            }
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
    /// Finished games show under the cards (as on the TVs); "Finished · 6" folds them away.
    @State private var showFinished = true
    /// Games starting more than 2 hours from now fold into "Later today · 6"; click it to show them.
    @State private var showLater = false

    var body: some View {
        let live = games.filter { $0.state == .live }
        let upcoming = games.filter { $0.state == .upcoming }
        let later = upcoming.filter { HomeFolds.isLater($0) }
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
            let cards = live.sorted(by: byStart)
                + upcoming.filter { showLater || !HomeFolds.isLater($0) }.sorted(by: byStart)
                + (showFinished ? finished.sorted(by: byStart) : [])
            let width = cardWidth(for: model.games(for: league.sport), charWidth: 9.5, fixed: 112, minimum: 260, maximum: 560)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: width, maximum: width), spacing: 16, alignment: .top)],
                      alignment: .leading, spacing: 16) {
                ForEach(cards) { game in
                    LiveGameCard(game: game, streams: model.streamCount(game.id)) { onOpen(game) }
                }
            }
            if !later.isEmpty { FoldButton(text: "Later today · \(later.count)", open: $showLater) }
            if !finished.isEmpty { FoldButton(text: "Finished · \(finished.count)", open: $showFinished) }
        }
    }
}

/// "Later today · 6" / "Finished · 6": click to show or hide them.
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

/// "NFL RedZone · 2" at the top of Football while an NFL game is live: click to show its channels.
struct RedZoneFolder: View {
    let channels: [Channel]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FoldButton(text: "NFL RedZone · \(channels.count)", open: $open, colour: Theme.accent)
            if open {
                VStack(spacing: 6) {
                    ForEach(channels) { MacChannelLine(channel: $0, lineup: channels) }
                }
            }
        }
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
