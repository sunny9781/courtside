import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.hideSD) private var hideSD = true
    @State private var showLocal = false
    let game: Game
    let onBack: () -> Void

    private var allStreams: [StreamMatch] {
        let all = model.matches[game.id] ?? []
        return hideSD ? all.filter { $0.quality != "SD" } : all
    }

    private var mainStreams: [StreamMatch] {
        let main = allStreams.filter { !$0.hidden }
        return main.isEmpty ? allStreams : main
    }

    private var localCount: Int {
        allStreams.count - mainStreams.count
    }

    struct CountrySection: Identifiable {
        let name: String
        let streams: [StreamMatch]
        var id: String { name }
    }

    /// 4K first (any country), then the rest grouped by country. The country with the best stream comes
    /// next; unknown countries go last.
    private var sections: [CountrySection] {
        let all = mainStreams
        let uhd = all.filter { $0.qualityRank == 4 }
        // Fight cards: pay-per-view streams come right after 4K.
        let ppv = game.league.sport == .fighting ? all.filter { $0.qualityRank != 4 && $0.isPPV } : []
        let ppvIDs = Set(ppv.map(\.id))
        let list = all.filter { $0.qualityRank != 4 && !ppvIDs.contains($0.id) }
        var order: [String] = []
        var groups: [String: [StreamMatch]] = [:]
        for match in list {
            let name = match.country ?? "Other"
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(match)
        }
        if let i = order.firstIndex(of: "Other"), order.count > 1 {
            order.append(order.remove(at: i))
        }
        let byCountry = order.map { CountrySection(name: $0, streams: groups[$0] ?? []) }
        let main = (uhd.isEmpty ? [] : [CountrySection(name: "4K", streams: uhd)])
            + (ppv.isEmpty ? [] : [CountrySection(name: "PPV", streams: ppv)]) + byCountry
        // The extras (local stations, "usually on" guesses) get their own section at the end.
        let mainIDs = Set(mainStreams.map(\.id))
        let extras = allStreams.filter { !mainIDs.contains($0.id) }
        if showLocal && !extras.isEmpty {
            return main + [CountrySection(name: "Local stations and likely channels", streams: extras)]
        }
        return main
    }

    /// What's listed, in on-screen order, which is also what up/down flips through.
    private var streams: [StreamMatch] {
        sections.flatMap(\.streams)
    }

    private var title: String { game.title }

    /// The stream in the pinned player, if it's one of this game's.
    private var previewChannel: Channel? {
        guard let pinned = model.pinned?.channel, allStreams.contains(where: { $0.channel.id == pinned.id }) else { return nil }
        return pinned
    }

    /// Click: play in the pinned player at the top.
    private func preview(_ channel: Channel) {
        model.pin(channel, gameTitle: title, lineup: streams.map(\.channel))
    }

    /// Double-click: full screen.
    private func watch(_ channel: Channel) {
        model.pin(channel, gameTitle: title, lineup: streams.map(\.channel))
        model.play(channel, gameTitle: title, lineup: streams.map(\.channel))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fixed at the top: back link, mini player and score. Only the streams scroll.
            VStack(alignment: .leading, spacing: 16) {
                BackButton(title: game.league.sport.rawValue, action: onBack)

                hero
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Spacer()
                        Text(mainStreams.isEmpty ? "None found" : "\(mainStreams.count) found · best match first")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                        if localCount > 0 {
                            Button(showLocal ? "Hide \(localCount) extra" : "+ \(localCount) local and likely") {
                                showLocal.toggle()
                            }
                            .buttonStyle(GhostButtonStyle())
                            .help("Local stations and channels that usually carry this league, kept separate at the bottom")
                        }
                    }

                    if streams.isEmpty {
                        Banner(text: "No channels on your provider matched this game yet. If you know which channel has it, find it in the Guide.",
                               icon: "magnifyingglass")
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                if sections.count > 1 {
                                    HStack(spacing: 8) {
                                        Text(section.name.uppercased())
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(Theme.soft)
                                        Text("\(section.streams.count)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.muted)
                                    }
                                    .padding(.leading, 4)
                                }
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 400), spacing: 10)], spacing: 10) {
                                    ForEach(section.streams) { match in
                                        StreamRow(match: match, previewing: match.channel.id == previewChannel?.id,
                                                  onSelect: { preview(match.channel) },
                                                  onWatch: { watch(match.channel) })
                                    }
                                }
                            }
                        }
                    }

                    if showLocal && localCount > 0 {
                        Button("Hide local stations and likely channels") { showLocal = false }
                            .buttonStyle(GhostButtonStyle())
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            // Opening a game plays its first stream in the pinned player, unless one of its streams already is.
            if previewChannel == nil, let first = streams.first { preview(first.channel) }
        }
    }

    /// The score and game info, combined with the pinned player when it's playing one of this game's streams.
    @ViewBuilder
    private var hero: some View {
        if let item = model.pinned, model.pinnedIsFrom(gameID: game.id) {
            PinnedPlayerBar(item: item, hidden: model.nowPlaying != nil, card: true) {
                scoreAndInfo
            }
        } else {
            scoreAndInfo
                .frame(height: 245)
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 20).fill(Theme.card))
        }
    }

    private var scoreAndInfo: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                Text(statusLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(game.state == .live ? Theme.accent : Theme.muted)
                if game.isEvent {
                    EventLines(game: game, big: true)
                } else {
                    scoreLine(game.away)
                    scoreLine(game.home)
                }
            }
            .frame(minWidth: 240, maxWidth: 420, alignment: .topLeading)

            Rectangle().fill(Theme.raised).frame(width: 1)

            gameInfo
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func scoreLine(_ team: Team) -> some View {
        HStack(spacing: 12) {
            TeamBadge(abbr: team.abbr, logo: team.logo, size: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text(team.shortName)
                    .font(Theme.display(28))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if team.hasLongScore {
                    Text(team.score)
                        .font(.system(size: 20, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(game.scoreColor(team))
                }
                if !team.record.isEmpty {
                    Text(team.record)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 12)
            if !team.hasLongScore {
                Text(team.score)
                    .font(Theme.display(30))
                    .monospacedDigit()
                    .foregroundStyle(game.scoreColor(team))
            }
        }
    }

    /// Box score by period, venue and broadcasters: what fills the space beside the score.
    private var gameInfo: some View {
        VStack(alignment: .leading, spacing: 14) {
            let periods = max(game.away.linescores.count, game.home.linescores.count)
            if !game.isEvent && periods > 0 {
                Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("").gridColumnAlignment(.leading)
                        ForEach(0..<periods, id: \.self) { i in
                            Text(periodLabel(i))
                        }
                        Text("T")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    ForEach([game.away, game.home], id: \.self) { team in
                        GridRow {
                            Text(team.abbr)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.soft)
                                .gridColumnAlignment(.leading)
                            ForEach(0..<periods, id: \.self) { i in
                                Text(i < team.linescores.count ? team.linescores[i] : "–")
                            }
                            Text(team.score)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.text)
                        }
                        .font(.system(size: 14))
                        .monospacedDigit()
                        .foregroundStyle(Theme.soft)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised.opacity(0.5)))
            }

            if !game.venue.isEmpty {
                Label(game.venue, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.soft)
                    .lineLimit(2)
            }
            if let start = game.start {
                Label(start.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.soft)
            }
            if !broadcasterLine.isEmpty {
                Label(broadcasterLine.replacingOccurrences(of: "Broadcasters: ", with: ""), systemImage: "tv")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.soft)
                    .lineLimit(3)
            }
        }
    }

    /// Q1–Q4 for basketball and football, P1–P3 for hockey, H1–H2 for soccer, innings for baseball; OT after.
    private func periodLabel(_ i: Int) -> String {
        let n = i + 1
        switch game.league.sport {
        case .basketball where game.league.id.hasPrefix("ncaam"):
            return n <= 2 ? "\(n)H" : (n == 3 ? "OT" : "\(n - 2)OT")
        case .basketball, .football, .aussieRules, .lacrosse:
            return n <= 4 ? "Q\(n)" : (n == 5 ? "OT" : "\(n - 4)OT")
        case .hockey:
            return n <= 3 ? "P\(n)" : (n == 4 ? "OT" : "SO")
        case .soccer, .rugby:
            return n <= 2 ? "\(n)H" : "ET"
        default:
            return "\(n)"
        }
    }

    /// "Broadcasters: ABC · Canada: Sportsnet, TVA Sports", from ESPN and the official league schedules.
    private var broadcasterLine: String {
        var parts: [String] = []
        let confirmed = (model.extraBroadcasts[game.id] ?? []).filter(\.confirmed)
        let general = game.broadcasters + confirmed.filter { $0.country == nil }.map(\.name)
        var seen = Set<String>()
        let generalUnique = general.filter { seen.insert($0.lowercased()).inserted }
        if !generalUnique.isEmpty { parts.append(generalUnique.joined(separator: ", ")) }
        let byCountry = Dictionary(grouping: confirmed.filter { $0.country != nil }, by: { $0.country ?? "" })
        for country in byCountry.keys.sorted() {
            let names = byCountry[country]!.map(\.name).filter { seen.insert($0.lowercased()).inserted }
            if !names.isEmpty { parts.append("\(country): \(names.joined(separator: ", "))") }
        }
        return parts.isEmpty ? "" : "Broadcasters: " + parts.joined(separator: " · ")
    }

    private var statusLine: String {
        switch game.state {
        case .live: return "\(game.league.name.uppercased()) · LIVE · \(game.statusText)"
        case .upcoming: return "\(game.league.name.uppercased()) · STARTS \(game.statusText)"
        case .finished: return "\(game.league.name.uppercased()) · \(game.statusText.uppercased())"
        }
    }
}

/// A stream card for the grid: full name and why it matched (wrapping, never cut off) and badges.
/// Click plays it in the mini player (the card lights up); double-click goes full screen.
struct StreamRow: View {
    @EnvironmentObject var model: AppModel
    let match: StreamMatch
    let previewing: Bool
    let onSelect: () -> Void
    let onWatch: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            CardButton(radius: 10, action: onSelect) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(match.channel.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(previewing ? Theme.accent : Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if !match.channel.categoryName.isEmpty {
                            Label(match.channel.categoryName, systemImage: "folder")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.soft)
                                .labelStyle(.titleAndIcon)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(match.reason)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 4) {
                        if !match.quality.isEmpty {
                            Badge(text: match.quality)
                        }
                        if let fps = model.measuredFrameRate[match.channel.id] {
                            Badge(text: PlaybackController.fpsLabel(fps))
                        }
                    }
                    .fixedSize()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 54)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(previewing ? Theme.accent : Color.clear, lineWidth: 1.5))
            }
            .simultaneousGesture(TapGesture(count: 2).onEnded { onWatch() })
            .help("Click to play in the mini player, double-click for full screen")
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
