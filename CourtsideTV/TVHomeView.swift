import SwiftUI

/// Home, laid out like the Mac: Live Now and the sports down the left (leagues open under the sport you're on),
/// games on the right. Moving onto a sport shows its games; clicking a game opens its streams.
struct TVHomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: TVNav
    @FocusState private var sidebarFocus: TVNav.HomeSelection?
    /// Focus is on the games (or league chips) on the right: the left column shrinks to icons and counts.
    @State private var inPane = false
    /// The games on the right (pressing down from the tabs lands on the first one).
    @FocusState private var gameFocus: String?
    @State private var firstGame: String?
    /// 2.24 (like Android TV): a sport with several leagues lists them beside it. Right from the sport moves into its
    /// leagues and the sports fold to icons; going back onto the sports opens them out again.
    @State private var folded = false
    @FocusState private var leagueFocus: TVNav.HomeSelection?
    /// An invisible strip at the right edge of the sports: right from a sport with leagues lands here, which opens
    /// the leagues and moves onto the selected one.
    @FocusState private var bridge: Bool

    /// The sport whose leagues can open beside it (more than one league, and not a channel sport).
    private var leagueSport: Sport? {
        let sport: Sport?
        switch nav.homeSelection {
        case .sport(let s): sport = s
        case .league(let id): sport = League.all.first { $0.id == id }?.sport
        case .liveNow: sport = nil
        }
        guard let sport, model.leagues(for: sport).count > 1, !isChannelSport(sport, model: model) else { return nil }
        return sport
    }

    /// The league row to land on: the selected league, or All.
    private var leagueTarget: TVNav.HomeSelection? {
        guard let sport = leagueSport else { return nil }
        if case .league = nav.homeSelection { return nav.homeSelection }
        return .sport(sport)
    }

    private func focusLeagues() {
        folded = true
        Task { @MainActor in
            for _ in 0..<6 {
                try? await Task.sleep(for: .milliseconds(50))
                if leagueFocus != nil { return }
                leagueFocus = leagueTarget
            }
        }
    }

    /// The row to land on when coming down from the tabs: the selected sport (or Live Now).
    private var sidebarTarget: TVNav.HomeSelection {
        // Live Now is no longer listed (the sports already show what's live): it stands for the first sport.
        let first: TVNav.HomeSelection = orderedSports(model: model).first.map { .sport($0) } ?? .liveNow
        switch nav.homeSelection {
        case .liveNow: return first
        case .sport(let s): return .sport(s)
        case .league(let id): return League.all.first { $0.id == id }.map { .sport($0.sport) } ?? first
        }
    }

    var body: some View {
        NavigationStack(path: $nav.homePath) {
            // The games line up with the text beside the player's video (the games pane pads itself by 24).
            // The left column stays lined up with the player above it (it no longer shrinks), so moving across is smooth.
            HStack(alignment: .top, spacing: TVLayout.playerGap - 24) {
                HStack(alignment: .top, spacing: 0) {
                    TVSportList(focused: $sidebarFocus, compact: folded)
                        .frame(width: folded ? 100 : TVLayout.sidebar)
                        .focusSection()
                        // Coming back from the games lands on the sport you left, not the row beside it.
                        .defaultFocus($sidebarFocus, sidebarTarget, priority: .userInitiated)
                    if folded, let sport = leagueSport {
                        Rectangle().fill(Theme.raised).frame(width: 2).padding(.vertical, 20)
                        TVLeagueList(sport: sport, focused: $leagueFocus)
                            .frame(maxWidth: .infinity)
                            .focusSection()
                            .defaultFocus($leagueFocus, leagueTarget, priority: .userInitiated)
                    }
                }
                .frame(width: TVLayout.sidebar, alignment: .leading)
                // Right from a sport with leagues: open them (the strip only takes focus from the sports).
                .overlay(alignment: .trailing) {
                    if leagueSport != nil && !folded && (sidebarFocus != nil || bridge) {
                        Color.clear.frame(width: 4).frame(maxHeight: .infinity)
                            .focusable()
                            .focused($bridge)
                    }
                }
                // On top of the player in the bottom-left corner.
                .padding(.bottom, model.pinned != nil ? TVLayout.playerInset : TVLayout.margin)
                .zIndex(0)
                TVGamesPane(inPane: $inPane, focusedGame: $gameFocus)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .focusSection()
                    .zIndex(1)
            }
            // Starts right beside the rail, in line with the now-playing bar and the player under it.
            .padding(.trailing, TVLayout.margin)
            // The navigation container adds wide side margins of its own; use the full width instead.
            .ignoresSafeArea(.container, edges: .horizontal)
            .onChange(of: sidebarFocus) {
                nav.sideFocused = sidebarFocus != nil || leagueFocus != nil
                if sidebarFocus != nil { inPane = false; folded = false }
            }
            .onChange(of: leagueFocus) {
                nav.sideFocused = sidebarFocus != nil || leagueFocus != nil
                nav.leaguesFocused = leagueFocus != nil
                if leagueFocus != nil { inPane = false }
            }
            .onChange(of: bridge) { if bridge { focusLeagues() } }
            .onChange(of: leagueSport) { if leagueSport == nil { folded = false } }
            // Back from the games (or the rail): to the league you're in when they're out, otherwise the sport.
            .onChange(of: nav.sideRequest) {
                guard nav.homePath.isEmpty else { return }
                if folded, let leagueTarget { leagueFocus = leagueTarget } else { sidebarFocus = sidebarTarget }
            }
            // Back from a league: its sport (the sports open out again).
            .onChange(of: nav.sportRequest) { if nav.homePath.isEmpty { sidebarFocus = sidebarTarget } }
            .onDisappear { nav.sideFocused = false; nav.leaguesFocused = false }
            .onPreferenceChange(TVFirstGameKey.self) { firstGame = $0 }
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
    /// A selection waiting for you to stop on that row.
    @State private var pendingSelection: Task<Void, Never>?
    /// The sport Home picked by itself (not you), and when Home opened.
    @State private var autoSport: Sport?
    @State private var openedAt = Date()
    @State private var waitingSelection: TVNav.HomeSelection?
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
                // Sports with live scores | sports shown as channels (pickleball) | sports with nothing today.
                // (No Live Now row: each sport already shows its live games.)
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    if index > 0 {
                        Rectangle().fill(Theme.raised).frame(height: 2).padding(.horizontal, 16).padding(.vertical, 8)
                    }
                    ForEach(group) { sport in
                        let games = model.games(for: sport)
                        let channelOnly = isChannelSport(sport, model: model)
                        row(.sport(sport), symbol: sport.symbol, name: sport.rawValue,
                            live: channelOnly ? 0 : games.filter { $0.state == .live }.count, total: games.count,
                            detail: games.isEmpty ? "No games" : (channelOnly ? "Channels" : "\(games.count) today"),
                            favorite: favorites.contains(sport))
                            .opacity(games.isEmpty ? 0.5 : 1)
                            // Hold the select button: favourite or hide (switch off) the sport.
                            .contextMenu {
                                let fav = favorites.contains(sport)
                                Button(fav ? "Remove from Favourites" : "Add to Favourites",
                                       systemImage: fav ? "heart.slash" : "heart") {
                                    var set = favorites
                                    if fav { set.remove(sport) } else { set.insert(sport) }
                                    favoriteSports = Sport.allCases.filter { set.contains($0) }.map(\.rawValue).joined(separator: ",")
                                }
                                Button("Hide", systemImage: "eye.slash") {
                                    var set = Sport.hidden(hiddenSports)
                                    set.insert(sport)
                                    hiddenSports = Sport.allCases.filter { set.contains($0) }.map(\.rawValue).joined(separator: ",")
                                    if openSport == sport { nav.homeSelection = .liveNow }
                                    model.sportsChanged()
                                    model.notice = "\(sport.rawValue) is hidden. Settings › Hidden brings it back."
                                }
                            }
                    }
                }
            }
            .padding(.vertical, 20)
        }
        // Use the full width: no Apple TV side insets on top of our own small margin.
        .ignoresSafeArea(.container, edges: .horizontal)
        // Live Now isn't listed any more: start on (and fall back to) the first sport instead.
        .onAppear { leaveLiveNow() }
        .onChange(of: nav.homeSelection) { leaveLiveNow() }
        .onChange(of: model.games.count) { followTopSport() }
        .onChange(of: focused.wrappedValue) {
            // Moving onto a row shows its games once you stop on it (a quarter second), so passing several sports
            // doesn't draw each one's games. Moving right into the games shows it straight away. Coming back to the
            // sport whose league you picked on the right keeps that league.
            pendingSelection?.cancel()
            guard let focused = focused.wrappedValue else {
                if let waitingSelection { nav.homeSelection = waitingSelection }
                waitingSelection = nil
                return
            }
            guard focused != nav.homeSelection else { waitingSelection = nil; return }
            if case .sport(let s) = focused, openSport == s { waitingSelection = nil; return }
            waitingSelection = focused
            pendingSelection = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                waitingSelection = nil
                nav.homeSelection = focused
            }
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
    private func leaveLiveNow() {
        if nav.homeSelection == .liveNow, let first = sports.first {
            nav.homeSelection = .sport(first)
            autoSport = first
        }
    }

    /// While today's games are still coming in (the first 30 seconds), Home keeps moving to the top sport until you
    /// pick one yourself (2.21, like Android), instead of staying on whichever sport loaded first.
    private func followTopSport() {
        guard let auto = autoSport, nav.homeSelection == .sport(auto), Date().timeIntervalSince(openedAt) < 30,
              let first = sports.first, first != auto else { return }
        nav.homeSelection = .sport(first)
        autoSport = first
    }

    private func row(_ selection: TVNav.HomeSelection, symbol: String, name: String, live: Int, total: Int, detail: String,
                     favorite: Bool = false) -> some View {
        Button {
            pendingSelection?.cancel()
            waitingSelection = nil
            nav.homeSelection = selection
        } label: {
            HStack(spacing: 18) {
                Image(systemName: symbol)
                    .font(.system(size: 28))
                    .frame(width: 40)
                if compact {
                    // Folded (the leagues are out): just the icon, with a dot when it has live games.
                    if live > 0 {
                        Circle().fill(Theme.accent).frame(width: 10, height: 10).padding(.leading, -18).offset(y: -14)
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

// MARK: Leagues beside the sports

/// A sport's leagues beside its (folded) icon: All first, then the most popular league first, so the list never
/// moves. Moving onto a league shows its games straight away; right goes into them.
struct TVLeagueList: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: TVNav
    let sport: Sport
    var focused: FocusState<TVNav.HomeSelection?>.Binding

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 6) {
                Text(sport.rawValue.uppercased())
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .padding(.leading, 22)
                    .padding(.bottom, 4)
                let all = model.games(for: sport)
                row(.sport(sport), league: nil, name: "All", games: all)
                ForEach(model.leagues(for: sport)) { league in
                    row(.league(league.id), league: league, name: league.name,
                        games: model.games.filter { $0.league.id == league.id })
                }
            }
            .padding(.vertical, 20)
            .padding(.leading, 8)
        }
        .ignoresSafeArea(.container, edges: .horizontal)
        .onChange(of: focused.wrappedValue) {
            if let f = focused.wrappedValue, f != nav.homeSelection { nav.homeSelection = f }
        }
    }

    private func row(_ selection: TVNav.HomeSelection, league: League?, name: String, games: [Game]) -> some View {
        let live = games.filter { $0.state == .live }.count
        return Button {
            nav.homeSelection = selection
        } label: {
            HStack(spacing: 14) {
                if let league { TVLeagueLogo(league: league, size: 30) }
                Text(name).font(.system(size: 26, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 6)
                if live > 0 {
                    TVBadge(text: "\(live)", fill: Theme.accent, color: Theme.onAccent)
                } else if !games.isEmpty {
                    Text("\(games.count)").font(.system(size: 21)).opacity(0.6)
                }
            }
        }
        .buttonStyle(TVRowButtonStyle(selected: nav.homeSelection == selection))
        .focused(focused, equals: selection)
        .opacity(games.isEmpty ? 0.5 : 1)
    }
}

// MARK: Right side

struct TVGamesPane: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: TVNav
    /// Set while focus is on a game card or league chip here.
    @Binding var inPane: Bool
    var focusedGame: FocusState<String?>.Binding
    @AppStorage(Prefs.hiddenSports) private var hiddenSports = ""
    @AppStorage(Prefs.sportOrder) private var sportOrder = ""
    @AppStorage(Prefs.multiview) private var multiviewOn = true
    /// Width available for the cards, so they stretch to fill the row (like the Mac) instead of leaving a gap.
    @State private var paneWidth: CGFloat = 1300
    /// Finished games start open on Apple TV (Android folds them in Lite mode only).
    @State private var showFinished = true
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
            // Only games that are live right now, under a heading per league (NBA, NCAA, NFL...), in your sport order.
            return orderedSports(model: model).flatMap { model.leagues(for: $0) }.compactMap { league in
                let live = model.games.filter { $0.league.id == league.id && $0.state == .live }
                return live.isEmpty ? nil
                    : PaneSection(id: league.id, title: league.name, symbol: nil, league: league, games: sortedGames(live))
            }
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

    /// The sections with only the games that are live or coming up; finished ones are folded (below). (No "Later
    /// today" fold since 2.2: that's an Android Lite mode option only.)
    private var open: [PaneSection] {
        sections.compactMap { s in
            let games = s.games.filter { $0.state != .finished }
            return games.isEmpty ? nil : PaneSection(id: s.id, title: s.title, symbol: s.symbol, league: s.league, games: games)
        }
    }

    private var finished: [Game] { sections.flatMap { $0.games.filter { $0.state == .finished } } }

    /// NFL RedZone (2.39): while any NFL game is live, a card at the top of Football / NFL that opens a game screen of
    /// its channels, grouped like any game's streams.
    private var redZone: Game? {
        let here: Bool
        switch nav.homeSelection {
        case .liveNow: here = true
        case .sport(let s): here = s == .football
        case .league(let id): here = id == "nfl"
        }
        guard here, model.games.contains(where: { $0.league.id == "nfl" && $0.state == .live }) else { return nil }
        return model.redZoneGame
    }

    private func fold(_ title: String, open: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 14) {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.system(size: 20, weight: .semibold))
                Text(title).font(.system(size: 23, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(Theme.muted)
        }
        .buttonStyle(TVRowButtonStyle())
        .padding(.top, 12)
    }

    var body: some View {
        // A sport with channels but no live scores (pickleball): its channels as an EPG list, not score cards.
        if let sport = filterSport, isChannelSport(sport, model: model) {
            TVSportChannels(sport: sport)
        } else {
            cards
        }
    }

    /// Score cards, as many to a row as fit (each at least `TVScoreCard.minWidth`).
    private var columns: Int { max(1, Int((paneWidth - 16 + 20) / (TVScoreCard.minWidth + 20))) }

    /// A grid of score cards.
    private func gameGrid(_ games: [Game]) -> some View {
        let count = columns
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20, alignment: .top), count: count),
                         alignment: .leading, spacing: 20) {
            ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                let button = Button {
                    nav.homePath.append(game.id)
                } label: {
                    TVScoreCard(game: game)
                }
                .buttonStyle(TVCardButtonStyle())
                .focused(focusedGame, equals: game.id)
                // Hold select (2.30): this game's best stream beside the one playing.
                .contextMenu {
                    if multiviewOn && model.pinned != nil && !model.mainStreams(game.id).isEmpty {
                        Button("Watch alongside", systemImage: "rectangle.split.2x1") {
                            TVMultiview.shared.watchAlongside(nil, game: game, model: model)
                        }
                    }
                }
                button
            }
        }
        .padding(.horizontal, 8)
    }

    /// Score cards under a heading per league (like the Mac and iPhone), running to the bottom of the screen under
    /// the now-playing bar.
    private var cards: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 6) {
                if let redZone { gameGrid([redZone]) }

                // Only when there's nothing at all (no "Nothing live or coming up": the folds below say it).
                if open.isEmpty && finished.isEmpty {
                    Text(emptyMessage)
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.muted)
                        .padding(22)
                }

                ForEach(open) { section in
                    if !section.title.isEmpty && open.count > 1 {
                        HStack(spacing: 12) {
                            if let league = section.league { TVLeagueLogo(league: league, size: 30) }
                            Text(section.title.uppercased())
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.leading, 22)
                        .padding(.top, 16)
                    }
                    gameGrid(section.games)
                }

                // Finished games fold into one row at the bottom ("Finished · 6", click to show them), so a page
                // mostly shows the games that are live or coming up.
                if !finished.isEmpty {
                    fold("Finished · \(finished.count)", open: showFinished) { showFinished.toggle() }
                    if showFinished { gameGrid(finished) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: nav.homeSelection) { showFinished = true }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { paneWidth = $0 }
            .onChange(of: focusedGame.wrappedValue) { if focusedGame.wrappedValue != nil || focusedChip != nil { inPane = true } }
            .onChange(of: focusedChip) { if focusedGame.wrappedValue != nil || focusedChip != nil { inPane = true } }
            .preference(key: TVFirstGameKey.self, value: redZone?.id ?? open.first?.games.first?.id ?? (showFinished ? finished.first?.id : nil))
            .padding(.vertical, 20)
        }
        // Runs to the bottom of the screen, under the now-playing bar (the last row can scroll clear of it).
        .contentMargins(.bottom, model.pinned != nil ? TVLayout.barHeight + TVLayout.margin : TVLayout.margin, for: .scrollContent)
        .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
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

    /// "All · NBA · WNBA · NCAA Men…": always in that order (most popular league first), so chips never move.
    private func leagueFilters(_ sport: Sport) -> some View {
        let leagues = model.leagues(for: sport)
        // Always the same order: All, then the most popular league first (NBA, WNBA, NCAA...).
        let ordered = leagues
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
            // Coming up from the games lands on the selected chip (All, or the league), not the one above.
            .defaultFocus($focusedChip, nav.homeSelection)
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
        return "No games today."
    }
}

/// A game as an EPG row, all on one line: when (or LIVE and the clock), the teams with their scores, and how many
/// streams it has. Upcoming games are grey and finished ones a little dimmer, so live games stand out in white.
struct TVGameRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.isFocused) private var focused
    let game: Game
    var showLeague = false
    static let statusWidth: CGFloat = 230

    static let teamWidth: CGFloat = 350
    /// Room for three digits (basketball scores over 99) at the score's size.
    static let scoreWidth: CGFloat = 66

    var body: some View {
        let main = model.mainStreams(game.id)
        let text: Color = focused ? Theme.bg
            : (game.state == .upcoming ? Theme.muted : (game.state == .finished ? Theme.soft : Theme.text))
        HStack(spacing: 0) {
            // Upcoming: just the start time (the row is already grey).
            let status = game.state == .upcoming ? game.startText : game.headerText
            Text(showLeague ? "\(status) · \(game.league.name)" : status)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(focused ? Theme.bg : (game.state == .live ? Theme.accent : Theme.muted))
                .lineLimit(1)
                .frame(width: Self.statusWidth, alignment: .leading)
            HStack(spacing: 14) {
                if game.isEvent && !game.hasSides {
                    Text(game.eventTitle).font(.system(size: 24, weight: .semibold)).foregroundStyle(text).lineLimit(1)
                    if !game.eventDetail.isEmpty {
                        Text(game.eventDetail).font(.system(size: 21)).foregroundStyle(text.opacity(0.75)).lineLimit(1)
                    }
                } else {
                    // Lined up around the "@" on every row: name, score, logo | @ | logo, score, name, so each score
                    // sits between its team's name and logo.
                    HStack(spacing: 12) {
                        Text(name(game.away)).font(.system(size: 24, weight: .semibold)).foregroundStyle(text).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        score(game.away, alignment: .trailing)
                        TVTeamLogo(team: game.away, size: 30)
                    }
                    .frame(width: Self.teamWidth)
                    Text("@").font(.system(size: 21)).foregroundStyle(text.opacity(0.6))
                    HStack(spacing: 12) {
                        TVTeamLogo(team: game.home, size: 30)
                        score(game.home, alignment: .leading)
                        Text(name(game.home)).font(.system(size: 24, weight: .semibold)).foregroundStyle(text).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: Self.teamWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 4K tag and the number of streams (back in 1.87).
            HStack(spacing: 8) {
                if main.contains(where: \.is4K) { TVBadge(text: "4K", fill: Theme.accent, color: Theme.onAccent) }
                Text(main.isEmpty ? "None" : "\(main.count)")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(main.isEmpty && !focused ? Theme.danger : text)
                if !main.isEmpty { Image(systemName: "play.tv").font(.system(size: 18)).foregroundStyle(text) }
            }
        }
    }

    private func name(_ team: Team) -> String { team.shortName.isEmpty ? team.name : team.shortName }

    private func score(_ team: Team, alignment: Alignment) -> some View {
        Text(game.state != .upcoming ? team.score : "")
            .font(.system(size: 24, weight: .bold).monospacedDigit())
            .foregroundStyle(focused ? Theme.bg : game.scoreColor(team))
            .lineLimit(1)
            .frame(width: Self.scoreWidth, alignment: alignment)
    }
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
                            TVChannelRow(channel: channel, playing: channel.id == playing, nameWidth: nameWidth, showNext: false)
                        }
                        .buttonStyle(TVRowButtonStyle())
                        .focused($focused, equals: channel.id)
                    }
                }
            }
            .padding(.vertical, 20)
        }
        .defaultFocus($focused, playing ?? list.first?.id)
        // Runs to the bottom of the screen, under the now-playing bar (the last row can scroll clear of it).
        .contentMargins(.bottom, model.pinned != nil ? TVLayout.barHeight + TVLayout.margin : TVLayout.margin, for: .scrollContent)
    }
}

/// The first game on Home's right-hand side, where pressing down from the tabs lands.
struct TVFirstGameKey: PreferenceKey {
    static let defaultValue: String? = nil
    static func reduce(value: inout String?, nextValue: () -> String?) { value = value ?? nextValue() }
}

/// A game as a score card: when (or the live clock), its 4K tag and number of streams, then each team with its logo
/// and score. Upcoming games are dimmer, so live games stand out.
struct TVScoreCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.isFocused) private var focused
    let game: Game
    static let minWidth: CGFloat = 400

    var body: some View {
        let main = model.mainStreams(game.id)
        let text: Color = focused ? Theme.bg : Theme.text
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(game.state == .upcoming ? game.startText : game.headerText)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(focused ? Theme.bg : (game.state == .live ? Theme.accent : Theme.muted))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if main.contains(where: \.is4K) { TVBadge(text: "4K", fill: Theme.accent, color: Theme.onAccent) }
                Text(main.isEmpty ? "None" : "\(main.count)")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(main.isEmpty && !focused ? Theme.danger : (focused ? Theme.bg : Theme.muted))
                if !main.isEmpty {
                    Image(systemName: "play.tv").font(.system(size: 17)).foregroundStyle(focused ? Theme.bg : Theme.muted)
                }
            }
            if game.isEvent && !game.hasSides {
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.eventTitle).font(.system(size: 24, weight: .semibold)).foregroundStyle(text).lineLimit(2)
                    if !game.eventDetail.isEmpty {
                        Text(game.eventDetail).font(.system(size: 20)).foregroundStyle(text.opacity(0.75)).lineLimit(1)
                    }
                }
                .frame(minHeight: 96, alignment: .topLeading)
            } else {
                teamLine(game.away, text: text)
                teamLine(game.home, text: text)
            }
        }
        .opacity(game.state == .upcoming && !focused ? 0.7 : 1)
    }

    private func teamLine(_ team: Team, text: Color) -> some View {
        HStack(spacing: 14) {
            TVTeamLogo(team: team, size: 40)
            Text(team.shortName.isEmpty ? team.name : team.shortName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            if game.state != .upcoming {
                Text(team.score)
                    .font(.system(size: 30, weight: .bold).monospacedDigit())
                    .foregroundStyle(focused ? Theme.bg : game.scoreColor(team))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(height: 42)
    }
}

/// A score card: a dark card that turns white when it's focused (no zoom, like the rows).
struct TVCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Card(configuration: configuration)
    }

    private struct Card: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18).fill(focused ? Theme.text : Theme.card))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}
