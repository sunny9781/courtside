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
                .pinnedPlayerSlot(.home)
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
    /// Sections whose finished games are open (they fold into one "Finished · 6" line under the cards).
    @State private var openFinished: Set<String> = []
    /// Sections whose later games are open (games starting more than 2 hours from now fold into "Later today · 6").
    @State private var openLater: Set<String> = []
    @State private var redZoneOpen = false

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
            // No Live Now page any more: until today's games are in, nothing is picked.
            return []
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
        case .liveNow: return "Courtside"
        case .sport(let s): return s.rawValue
        case .league(let id): return League.all.first { $0.id == id }?.sport.rawValue ?? ""
        }
    }

    var body: some View {
        ScrollView {
            // "Updated" lives in Settings; pull down to refresh.
            VStack(alignment: .leading, spacing: 22) {
                // iPhone: sports and leagues are at the bottom, in easy reach of the thumb. iPad: leagues stay here.
                if !showsSportChips, let sport = nav.selectedSport, model.leagues(for: sport).count > 1 { leagueChips(sport) }

                epgStatus

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal)
                }
                let redZone = HomeFolds.redZone(model: model, sport: nav.homeSelection == .league("nfl") ? .football
                                                : (nav.homeSelection == .sport(.football) ? .football : nil))
                if !redZone.isEmpty { redZoneFolder(redZone) }

                if sections.isEmpty {
                    Text(model.isLoading || model.games.isEmpty ? "Loading today's games…" : "No games today.")
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
                        let later = section.games.filter { HomeFolds.isLater($0) }
                        let finished = section.id == "finals" ? [] : section.games.filter { $0.state == .finished }
                        let shown = section.games.filter { game in
                            if game.state == .finished && section.id != "finals" { return openFinished.contains(section.id) }
                            if HomeFolds.isLater(game) { return openLater.contains(section.id) }
                            return true
                        }
                        // iPhone: two cards side by side; iPad: as many as fit.
                        LazyVGrid(columns: showsSportChips
                                      ? [GridItem(.flexible(), spacing: 10, alignment: .top), GridItem(.flexible(), spacing: 10, alignment: .top)]
                                      : [GridItem(.adaptive(minimum: width, maximum: width), spacing: 12, alignment: .top)],
                                  alignment: .leading, spacing: showsSportChips ? 10 : 12) {
                            ForEach(shown) { game in
                                NavigationLink(value: game.id) {
                                    IOSGameCard(game: game, compact: showsSportChips)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        if !later.isEmpty { foldButton("Later today · \(later.count)", id: section.id, in: $openLater) }
                        if !finished.isEmpty { foldButton("Finished · \(finished.count)", id: section.id, in: $openFinished) }
                    }
                }
            }
            .padding(.vertical, 12)
            // Always the full width, also when there's only a short message (it used to shrink to the text).
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.bg.ignoresSafeArea())
        // The sport is already picked in the chips (iPhone) or the sidebar (iPad), so no big title repeats it.
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showsSportChips ? .hidden : .automatic, for: .navigationBar)
        .refreshable { await model.refresh(force: true) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsSportChips { bottomBar }
        }
        .onAppear { pickStartingSport() }
        .onChange(of: model.games.count) { pickStartingSport() }
    }

    /// "Later today · 6" / "Finished · 6": tap to show or hide them.
    private func foldButton(_ text: String, id: String, in set: Binding<Set<String>>) -> some View {
        Button {
            if set.wrappedValue.contains(id) { set.wrappedValue.remove(id) } else { set.wrappedValue.insert(id) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: set.wrappedValue.contains(id) ? "chevron.down" : "chevron.right")
                    .font(.caption.bold())
                Text(text).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Theme.muted)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    /// "NFL RedZone · 2" while an NFL game is live: tap to show its channels; tap a channel to play it.
    private func redZoneFolder(_ channels: [Channel]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { redZoneOpen.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: redZoneOpen ? "chevron.down" : "chevron.right").font(.caption.bold())
                    Text("NFL RedZone · \(channels.count)").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            if redZoneOpen {
                ForEach(channels) { channel in
                    IOSChannelRow(channel: channel, playing: model.pinned?.channel.id == channel.id)
                        .onTapGesture {
                            if model.pinned?.channel.id == channel.id {
                                model.play(channel, gameTitle: nil, lineup: channels)
                            } else {
                                model.pin(channel, lineup: channels)
                            }
                        }
                }
            }
        }
    }

    /// Home opens on a sport (no Live Now page): a favourite with something live, else any sport with something
    /// live. Picked once today's games are in.
    private func pickStartingSport() {
        guard nav.homeSelection == .liveNow, !model.games.isEmpty, let sport = startingSport(model: model) else { return }
        nav.homeSelection = .sport(sport)
    }

    /// The EPG download, as on the TVs: "Refreshing EPG 45%" while it downloads, or waiting for the stream to stop.
    @ViewBuilder
    var epgStatus: some View {
        if model.guideDownloading || model.downloadingChannels {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.downloadingChannels ? "Refreshing channels…"
                     : "Refreshing EPG\(model.guideProgress.map { " \(Int($0 * 100))%" } ?? " · \(model.guideMegabytes) MB")")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                if let p = model.guideProgress, model.guideDownloading {
                    ProgressView(value: p).tint(Theme.accent)
                }
            }
            .padding(.horizontal)
        } else if model.refreshWaiting {
            Label("EPG refreshes after this stream", systemImage: "clock")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                .padding(.horizontal)
        }
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

    // MARK: iPhone: controls at the bottom, laid out for the right thumb

    @State private var barWidth: CGFloat = 390

    /// Leagues (when the sport has more than one) above the sports, both starting from the right edge: the most
    /// used (Live Now, "All") sit nearest the thumb, the rest further left.
    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let sport = nav.selectedSport, model.leagues(for: sport).count > 1 {
                trailingRow { leagueItems(sport) }
            }
            trailingRow { sportItems }
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
    }

    /// A row that starts at the right edge and scrolls left if it doesn't fit.
    private func trailingRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content() }
                .padding(.horizontal)
                .frame(minWidth: barWidth, alignment: .center)
        }
        .defaultScrollAnchor(.trailing)
    }

    /// Right to left: favourites and sports with live games, then the rest with games today.
    /// Sports with no games today are left out (unless they're a favourite or picked).
    @ViewBuilder
    private var sportItems: some View {
        let favs = Set(favoriteSports.split(separator: ",").map(String.init))
        let shown = sports.filter { !model.games(for: $0).isEmpty || nav.selectedSport == $0 || favs.contains($0.rawValue) }
        ForEach(shown.reversed()) { sport in
            let games = model.games(for: sport)
            let liveCount = games.filter { $0.state == .live }.count
            IOSChip(selected: nav.selectedSport == sport, action: { nav.homeSelection = .sport(sport) }) {
                HStack(spacing: 6) {
                    Image(systemName: sport.symbol)
                    if liveCount > 0 {
                        IOSBadge(text: "\(liveCount)", fill: Theme.accent, color: Theme.onAccent)
                    } else if !games.isEmpty {
                        Text("\(games.count)").font(.caption.weight(.semibold)).opacity(0.6)
                    }
                }
                .frame(minHeight: 30)
            }
            .accessibilityLabel(sport.rawValue)
        }
    }

    /// Right to left: All, then leagues with live games, then leagues with games, then the rest.
    @ViewBuilder
    private func leagueItems(_ sport: Sport) -> some View {
        let leagues = model.leagues(for: sport)
        let ranks: [String: Int] = Dictionary(uniqueKeysWithValues: leagues.map { league in
            let games = model.games.filter { $0.league.id == league.id }
            return (league.id, games.contains(where: { $0.state == .live }) ? 0 : (games.isEmpty ? 2 : 1))
        })
        let ordered = leagues.enumerated()
            .sorted { ((ranks[$0.element.id] ?? 2), $0.offset) < ((ranks[$1.element.id] ?? 2), $1.offset) }
            .map(\.element)
        ForEach(ordered.reversed()) { league in
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
        IOSChip(selected: nav.homeSelection == .sport(sport), action: { nav.homeSelection = .sport(sport) }) {
            Text("All")
        }
    }

    private var sportChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Icons and counts only (live games in orange, otherwise today's games), to fit more sports.
                ForEach(sports) { sport in
                    let games = model.games(for: sport)
                    let liveCount = games.filter { $0.state == .live }.count
                    IOSChip(selected: nav.selectedSport == sport, action: { nav.homeSelection = .sport(sport) }) {
                        HStack(spacing: 6) {
                            Image(systemName: sport.symbol)
                            if liveCount > 0 {
                                IOSBadge(text: "\(liveCount)", fill: Theme.accent, color: Theme.onAccent)
                            } else if !games.isEmpty {
                                Text("\(games.count)").font(.caption.weight(.semibold)).opacity(0.6)
                            }
                        }
                    }
                    .accessibilityLabel(sport.rawValue)
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
    /// iPhone: two cards to a row, so smaller logos, text and padding.
    var compact = false

    private var has4K: Bool { model.mainStreams(game.id).contains { $0.is4K } }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(spacing: 6) {
                Text(showLeague ? "\(game.league.name) · \(game.headerText)" : game.headerText)
                    .font(.caption.bold())
                    .foregroundStyle(game.state == .live ? Theme.accent : Theme.soft)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if has4K { IOSBadge(text: "4K", fill: Theme.accent, color: Theme.onAccent) }
            }
            if game.isEvent && !game.hasSides {
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.eventTitle).font(compact ? .subheadline.weight(.semibold) : .headline).foregroundStyle(Theme.text).lineLimit(2)
                    if !game.eventDetail.isEmpty {
                        Text(game.eventDetail).font(.subheadline).foregroundStyle(Theme.soft).lineLimit(2)
                    }
                }
            } else {
                VStack(spacing: compact ? 7 : 10) {
                    teamLine(game.away)
                    teamLine(game.home)
                }
            }
        }
        .padding(compact ? 10 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        .opacity(game.state == .upcoming ? 0.6 : (game.state == .finished ? 0.85 : 1))
        .contentShape(Rectangle())
    }

    private func teamLine(_ team: Team) -> some View {
        HStack(spacing: compact ? 6 : 10) {
            IOSTeamLogo(team: team, size: compact ? 22 : 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(compact && !team.abbr.isEmpty && (team.shortName.isEmpty ? team.name : team.shortName).count > 11
                     ? team.abbr : (team.shortName.isEmpty ? team.name : team.shortName))
                    .font(compact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
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
                    .font((compact ? Font.headline : Font.title3).bold().monospacedDigit())
                    .foregroundStyle(game.scoreColor(team))
            }
        }
    }
}
