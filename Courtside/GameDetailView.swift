import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.hideSD) private var hideSD = true
    @State private var showLocal = false
    @AppStorage(Prefs.showForeignStreams) private var showForeign = false
    @State private var search = ""
    @State private var listWidth: CGFloat = 800
    /// Sections folded shut (4K, USA, Other…), by name.
    @State private var folded: Set<String> = []
    let game: Game
    let onBack: () -> Void

    private var allStreams: [StreamMatch] {
        let all = model.matches[game.id] ?? []
        return hideSD ? all.filter { $0.quality != "SD" } : all
    }

    /// 4K, PPV for fights, the league's own channels, home-country broadcasters, other countries (see
    /// StreamSections), filtered by the search field and the foreign-language toggle.
    private var listing: StreamSections.Result {
        StreamSections.build(allStreams, league: game.league, showExtras: showLocal, showForeign: showForeign, search: search)
    }

    private var sections: [StreamSections.Section] { listing.sections }

    private var localCount: Int {
        let main = allStreams.filter { !$0.hidden }
        return main.isEmpty ? 0 : allStreams.count - main.count
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
            // Fixed at the top: the player and score (Back is in the top bar). Only the streams scroll.
            VStack(alignment: .leading, spacing: 16) {
                hero
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Color.clear.frame(height: 0)
                        .frame(maxWidth: .infinity)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { listWidth = $0 }
                    HStack(spacing: 12) {
                        Field(placeholder: "Search streams", text: $search)
                            .frame(width: 260)
                        Toggle("Foreign languages", isOn: $showForeign)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .foregroundStyle(Theme.soft)
                            .help("Show Spanish, Latino, French and other foreign-language streams")
                        Spacer()
                        Text(listing.streams.isEmpty ? "None found" : "\(listing.streams.count) streams")
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
                    if listing.hiddenForeign > 0 {
                        Button("\(listing.hiddenForeign) foreign-language streams hidden · Show them") { showForeign = true }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.accent)
                    }

                    if streams.isEmpty {
                        Banner(text: search.isEmpty ? "No channels on your provider matched this game yet. If you know which channel has it, find it in the EPG."
                                                    : "No streams match \"\(search)\".",
                               icon: "magnifyingglass")
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        if folded.contains(section.name) { folded.remove(section.name) } else { folded.insert(section.name) }
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 9, weight: .bold))
                                            .rotationEffect(.degrees(folded.contains(section.name) ? 0 : 90))
                                        Text(section.name.uppercased())
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(Theme.soft)
                                        Text("\(section.streams.count)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.muted)
                                    }
                                    .foregroundStyle(Theme.muted)
                                    .padding(.leading, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if !folded.contains(section.name) {
                                // Not lazy: a lazy grid guesses row heights as cards wrap, which made the page scroll
                                // on past the last stream. A game only has a few dozen streams.
                                let columns = max(1, Int((listWidth + 10) / 410))
                                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                                    ForEach(Array(stride(from: 0, to: section.streams.count, by: columns)), id: \.self) { start in
                                        GridRow(alignment: .top) {
                                            ForEach(start..<min(start + columns, section.streams.count), id: \.self) { i in
                                                let match = section.streams[i]
                                                StreamRow(match: match, previewing: match.channel.id == previewChannel?.id,
                                                          onSelect: { preview(match.channel) },
                                                          onWatch: { watch(match.channel) })
                                                    .frame(maxWidth: .infinity)
                                            }
                                            ForEach(0..<(columns - min(columns, section.streams.count - start)), id: \.self) { _ in
                                                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                                            }
                                        }
                                    }
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
            PinnedPlayerBar(item: item, hidden: model.nowPlaying != nil, card: true, slimTitle: slimScore) {
                scoreAndInfo
            }
        } else {
            scoreAndInfo
                .frame(height: 245)
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 20).fill(Theme.card))
        }
    }

    /// The slim player bar's one line: "TOR 78 – 81 BOS · Q3 4:12".
    private var slimScore: String {
        if game.isEvent && !game.hasSides { return game.eventTitle }
        if game.state == .upcoming { return "\(game.away.abbr) at \(game.home.abbr) · \(game.statusText)" }
        return "\(game.away.abbr) \(game.away.score) – \(game.home.score) \(game.home.abbr) · \(game.statusText)"
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
