import SwiftUI
import UIKit

/// Multiview (2.30): two streams side by side, full screen. Tile 1 is the stream already playing, on the app's own
/// player (no reopen); tile 2 has a second player of its own, VLC only. Only offered while a stream plays and the
/// provider has a free connection; never more streams open than tiles, and a tile's old stream is closed (and given a
/// second to be gone) before its new one opens. Each player keeps its own freeze watch and reconnects.
@MainActor
final class TVMultiview: ObservableObject {
    static let shared = TVMultiview()

    struct Tile: Equatable {
        var channel: Channel
        var gameID: String?
        var gameTitle: String?
        var lineup: [Channel]
        /// Picked by the app: if it shows no picture within 7 s (or fails first), the first of these plays instead,
        /// once. Empty for streams picked by hand and once a picture has shown.
        var backups: [Channel] = []
        var openedAt = Date()
    }

    enum Panel: Hashable { case tile(Int), games(Int) }

    @Published private(set) var active = false
    @Published private(set) var tiles: [Tile] = []
    /// The tile whose sound plays (the others are muted).
    @Published private(set) var sound = 0
    /// The big tile (layout "big"), nil = side by side, the same size.
    @Published private(set) var big: Int?
    /// The left panel (hold select on a tile).
    @Published var panel: Panel?
    /// Leaving: tile 2's stream moving to the app's player.
    @Published private(set) var leaving = false
    private var starting = false

    /// Tile 2's player (made the first time multiview opens).
    private(set) lazy var second = PlaybackController(measuresStats: false)
    /// Bumped whenever a tile's stream is closed or opened, so a delayed open for an older pick does nothing.
    private var generation: [Int: Int] = [:]
    /// A stream picked by hand for a game comes first for that game for the rest of the session.
    private var preferred: [String: Int] = [:]

    func controller(_ index: Int) -> PlaybackController { index == 0 ? PlaybackController.shared : second }

    private var bufferMs: Int { max(UserDefaults.standard.integer(forKey: Prefs.bufferMs), 500) }

    // MARK: Starting and leaving

    /// Starts multiview with `channel` (picked by hand) or the best stream for `game` in tile 2, after checking with
    /// the provider that a connection is free (ours is already counted as in use).
    func watchAlongside(_ channel: Channel?, game: Game?, model: AppModel) {
        guard !active, !starting, let current = model.pinned, model.nowPlaying == nil else { return }
        starting = true
        Task { @MainActor in
            defer { self.starting = false }
            await model.refreshAccount()
            let max = model.account?.maxConnections ?? 0
            let used = model.account?.activeConnections ?? max
            guard max >= 2, max - used >= 1 else {
                model.notice = "No free connection for multiview (\(used) of \(max) in use)"
                return
            }
            guard model.pinned == current, model.nowPlaying == nil, !self.active else { return }
            let pick: Channel
            var backups: [Channel] = []
            if let channel {
                guard channel.id != current.channel.id else {
                    model.notice = "\(channel.name) is already playing"
                    return
                }
                pick = channel
            } else if let game {
                let list = self.candidates(game, besides: [current.channel.id], model: model)
                guard let first = list.first else {
                    model.notice = "No other stream for \(game.title)"
                    return
                }
                pick = first
                backups = Array(list.dropFirst().prefix(1))
            } else {
                return
            }
            let lineup = game.map { g in self.streams(g, model: model).map(\.channel) } ?? []
            self.tiles = [
                Tile(channel: current.channel, gameID: model.pinnedGame?.id, gameTitle: current.gameTitle,
                     lineup: current.lineup),
                Tile(channel: pick, gameID: game?.id, gameTitle: game?.title,
                     lineup: lineup.isEmpty ? [pick] : lineup, backups: backups)
            ]
            self.sound = 0
            self.big = nil
            self.panel = nil
            self.leaving = false
            self.second.onChange = { [weak model] in model?.checkConnectionsSoon() }
            PlaybackController.shared.setMuted(false)
            self.active = true
            ConnLog.add("Multiview: started")
            self.open(1, model: model, wait: false)
        }
    }

    /// Back: the tile with the sound (or `index`) carries on as the normal single stream, full screen; the others
    /// are closed.
    func leave(keeping index: Int? = nil, model: AppModel) {
        guard active, !leaving else { return }
        let keep = index ?? sound
        guard tiles.indices.contains(keep) else { end(model: model); return }
        let kept = tiles[keep]
        for i in tiles.indices where i != keep { close(i) }
        panel = nil
        PlaybackController.shared.setMuted(false)
        second.setMuted(false)
        let item = NowPlaying(channel: kept.channel, gameTitle: kept.gameTitle,
                              lineup: kept.lineup.isEmpty ? [kept.channel] : kept.lineup)
        if keep == 0 {
            // Already on the app's player: full screen carries on with it, no reconnect.
            model.pinned = item
            model.play(item.channel, gameTitle: item.gameTitle, lineup: item.lineup)
            finish()
        } else {
            // Tile 2's player only lives in multiview: its stream moves to the app's player, closed and reopened a
            // second apart, so the provider never counts more than one.
            close(keep)
            leaving = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                model.pinned = item
                model.play(item.channel, gameTitle: item.gameTitle, lineup: item.lineup)
                self.finish()
            }
        }
    }

    /// "Remove tile": the other tile carries on as the normal single stream.
    func remove(_ index: Int, model: AppModel) {
        guard tiles.count > 1, tiles.indices.contains(index) else { return }
        leave(keeping: index == 0 ? 1 : 0, model: model)
    }

    /// Leaving the app: tile 2 is closed and tile 1 stays in the corner, as normal playback does.
    func end(model: AppModel) {
        guard active else { return }
        for i in tiles.indices where i != 0 { close(i) }
        PlaybackController.shared.setMuted(false)
        finish()
    }

    private func finish() {
        active = false
        leaving = false
        tiles = []
        panel = nil
        big = nil
        sound = 0
        ConnLog.add("Multiview: ended")
    }

    // MARK: Tiles

    /// Select on a tile: the sound moves there; with "Make big" it also becomes the big one (again on the big tile
    /// with the sound: back to side by side).
    func select(_ index: Int) {
        guard active, !leaving, panel == nil, tiles.indices.contains(index) else { return }
        if UserDefaults.standard.string(forKey: Prefs.multiviewSelect) == "sound" {
            big = nil
        } else if sound == index && big == index {
            big = nil
        } else {
            big = index
        }
        sound = index
        for i in tiles.indices { controller(i).setMuted(i != index) }
    }

    /// Puts another stream in a tile: the old one is fully closed first. `backups` only for streams the app picked.
    func swap(_ index: Int, to channel: Channel, game: Game?, backups: [Channel] = [], model: AppModel) {
        guard active, !leaving, tiles.indices.contains(index), tiles[index].channel.id != channel.id else { return }
        if tiles.indices.contains(where: { $0 != index && tiles[$0].channel.id == channel.id }) {
            model.notice = "\(channel.name) is already playing in the other tile"
            return
        }
        close(index)
        let list = game.map { streams($0, model: model).map(\.channel) } ?? []
        tiles[index] = Tile(channel: channel, gameID: game?.id, gameTitle: game?.title,
                            lineup: list.isEmpty ? [channel] : list, backups: backups)
        if backups.isEmpty, let id = game?.id { preferred[id] = channel.id }
        syncPinned(index, model: model)
        open(index, model: model, wait: true)
    }

    /// "Pick another game…": the best stream for that game (not one the other tile plays).
    func pick(_ game: Game, for index: Int, model: AppModel) {
        let others = Set(tiles.indices.filter { $0 != index }.map { tiles[$0].channel.id })
        let list = candidates(game, besides: others, model: model)
        guard let first = list.first else {
            model.notice = "No other stream for \(game.title)"
            return
        }
        swap(index, to: first, game: game, backups: Array(list.dropFirst().prefix(1)), model: model)
    }

    /// Every second: a stream the app picked that shows no picture within 7 s (or fails first) is closed and the
    /// next candidate tried, once. One that has shown a picture is never skipped.
    func tick(model: AppModel) {
        guard active, !leaving else { return }
        for index in tiles.indices {
            guard let next = tiles[index].backups.first else { continue }
            let player = controller(index)
            guard player.currentURL != nil else { continue }   // still waiting to open
            if !player.resolution.isEmpty {
                tiles[index].backups = []
                continue
            }
            var failed = false
            if case .failed = player.status { failed = true }
            guard failed || Date().timeIntervalSince(tiles[index].openedAt) > 7 else { continue }
            ConnLog.add("Multiview: tile \(index + 1) showed no picture; trying \(next.name)")
            close(index)
            tiles[index].channel = next
            tiles[index].backups = []
            syncPinned(index, model: model)
            open(index, model: model, wait: true)
        }
    }

    /// Tile 1 is the app's own stream: the corner player and the now-playing bar follow it.
    private func syncPinned(_ index: Int, model: AppModel) {
        guard index == 0 else { return }
        let t = tiles[0]
        model.pinned = NowPlaying(channel: t.channel, gameTitle: t.gameTitle, lineup: t.lineup)
    }

    /// Opens a tile's stream on its player (VLC only), muted unless it's the sound tile. `wait`: a second first, for
    /// the provider to see the old stream gone.
    private func open(_ index: Int, model: AppModel, wait: Bool) {
        guard tiles.indices.contains(index) else { return }
        let player = controller(index)
        generation[index, default: 0] += 1
        let gen = generation[index] ?? 0
        let channel = tiles[index].channel
        Task { @MainActor in
            if wait { try? await Task.sleep(for: .seconds(1)) }
            guard self.active, !self.leaving, self.generation[index] == gen, self.tiles.indices.contains(index),
                  let url = model.streamURL(for: channel, hls: !PlaybackController.usesVLC) else { return }
            self.tiles[index].openedAt = Date()
            player.setMuted(index != self.sound)
            player.play(url, bufferMs: self.bufferMs, hdrPlayer: false)
            ConnLog.add("Multiview: opened tile \(index + 1) (\(channel.name))")
        }
    }

    private func close(_ index: Int) {
        generation[index, default: 0] += 1
        let player = controller(index)
        guard player.currentURL != nil else { return }
        player.stop()
        ConnLog.add("Multiview: closed tile \(index + 1)")
    }

    // MARK: Streams

    /// A game's streams as its game screen lists them, without 4K.
    func streams(_ game: Game, model: AppModel) -> [StreamMatch] {
        let hideSD = UserDefaults.standard.bool(forKey: Prefs.hideSD)
        let all = (model.matches[game.id] ?? []).filter { !hideSD || $0.quality != "SD" }
        let listing = StreamSections.build(all, league: game.league, measured: model.measuredQuality,
                                           fps: model.measuredFrameRate, hdr: model.measuredHDR, audio: model.measuredAudio)
        let ordered = listing.sections.flatMap(\.streams) + listing.foreign.flatMap(\.streams) + listing.extras
        return ordered.filter { !$0.looksUHD(model.measuredQuality) }
    }

    /// The streams the app would pick for a game, best first: no 4K, no local or "likely" matches, none another tile
    /// plays; then reliability (green, amber, none, red), quality (1080p, 720p, SD), favourites, English before
    /// foreign, and the game screen's order. A stream picked by hand for this game earlier comes first.
    func candidates(_ game: Game, besides: Set<Int>, model: AppModel) -> [Channel] {
        let home = StreamSections.homeCountries(game.league)
        let ratings = StreamStats.shared.ratings
        let measured = model.measuredQuality
        func reliability(_ m: StreamMatch) -> Int {
            switch ratings[m.channel.id] {
            case .good?: return 0
            case .ok?: return 1
            case nil: return 2
            case .poor?: return 3
            }
        }
        let kept = streams(game, model: model).enumerated().filter { !$0.element.hidden && !besides.contains($0.element.channel.id) }
        var list = kept.sorted { a, b in
            let x = a.element, y = b.element
            let rx = reliability(x), ry = reliability(y)
            if rx != ry { return rx < ry }
            let qx = StreamSections.qualityRank(x, measured: measured), qy = StreamSections.qualityRank(y, measured: measured)
            if qx != qy { return qx > qy }
            let fx = model.isFavorite(channel: x.channel.id), fy = model.isFavorite(channel: y.channel.id)
            if fx != fy { return fx }
            let ex = StreamSections.isForeign(x, home: home), ey = StreamSections.isForeign(y, home: home)
            if ex != ey { return ey }
            return a.offset < b.offset
        }.map(\.element.channel)
        if let id = preferred[game.id], let i = list.firstIndex(where: { $0.id == id }) {
            let chosen = list.remove(at: i)
            list.insert(chosen, at: 0)
        }
        return list
    }

    /// Live games by sport, in Home's sport order (for "Pick another game…").
    func liveGames(model: AppModel) -> [(sport: Sport, games: [Game])] {
        orderedSports(model: model).compactMap { sport in
            let live = sortedGames(model.games(for: sport).filter { $0.state == .live })
            return live.isEmpty ? nil : (sport: sport, games: live)
        }
    }
}

// MARK: Screen

/// Full screen over everything: "Multiview" and the connections along the top, the tiles, and the keys along the
/// bottom. Left/right moves between tiles (focus doesn't move the sound), Select moves the sound (and makes the tile
/// big), hold Select opens the tile's left panel, Back leaves.
struct TVMultiviewView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var mv = TVMultiview.shared
    @AppStorage(Prefs.multiviewSelect) private var selectMode = "big"
    @FocusState private var focusedTile: Int?
    @State private var lastTile = 0

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                header
                GeometryReader { geo in
                    tileRow(width: geo.size.width)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                Text(selectMode == "sound"
                     ? "Select  move sound  ·  Hold select  swap or remove  ·  Back  leave"
                     : "Select  make big / move sound  ·  Hold select  swap or remove  ·  Back  leave")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 40)
            .disabled(mv.panel != nil || mv.leaving)

            if let panel = mv.panel {
                TVMultiviewPanel(panel: panel)
                    .id(panel)
                    .transition(.move(edge: .leading))
            }
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.25), value: mv.big)
        .animation(.easeOut(duration: 0.2), value: mv.panel)
        // Hold select on a tile: its left panel. (The release that ends the hold is ignored: the panel is open.)
        .background(TVPlayPauseHold(action: {
            guard mv.panel == nil, !mv.leaving, let i = focusedTile else { return }
            lastTile = i
            mv.panel = .tile(i)
        }, pressType: .select))
        .onExitCommand {
            if mv.panel != nil { mv.panel = nil } else { mv.leave(model: model) }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in mv.tick(model: model) }
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                focusedTile = mv.sound
            }
        }
        .onChange(of: mv.panel == nil) {
            guard mv.panel == nil else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                focusedTile = mv.tiles.indices.contains(lastTile) ? lastTile : mv.sound
            }
        }
        .onChange(of: focusedTile) { if let focusedTile { lastTile = focusedTile } }
    }

    private var header: some View {
        HStack(spacing: 24) {
            Text("Multiview")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(Theme.text)
            if let max = model.account?.maxConnections, max > 0 {
                Label("\(mv.tiles.count) of \(max) connections", systemImage: "person.2.fill")
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle(mv.tiles.count >= max ? Theme.onAccent : Theme.muted)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Capsule().fill(mv.tiles.count >= max ? Theme.accent : Theme.raised))
            }
            Spacer()
            if mv.leaving { ProgressView() }
        }
    }

    private func tileRow(width: CGFloat) -> some View {
        let gap: CGFloat = 32
        return HStack(alignment: .center, spacing: gap) {
            ForEach(Array(mv.tiles.indices), id: \.self) { i in
                let w = tileWidth(i, total: width, gap: gap)
                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        mv.select(i)
                    } label: {
                        TVMultiviewTile(controller: mv.controller(i), index: i, tile: mv.tiles[i],
                                        sound: mv.sound == i, focused: focusedTile == i)
                            .frame(width: w, height: w * 9 / 16)
                    }
                    .buttonStyle(TVBareButtonStyle())
                    .focused($focusedTile, equals: i)
                    TVMultiviewCaption(controller: mv.controller(i), channel: mv.tiles[i].channel)
                        .frame(width: w, alignment: .leading)
                }
            }
        }
    }

    /// Side by side: the same size. Big: the sound tile ~68% of the width (on its own side), the other ~30%.
    private func tileWidth(_ i: Int, total: CGFloat, gap: CGFloat) -> CGFloat {
        let n = CGFloat(max(mv.tiles.count, 1))
        let room = total - gap * (n - 1)
        guard let big = mv.big, mv.tiles.count > 1 else { return room / n }
        return i == big ? room * 0.69 : room * 0.31 / (n - 1)
    }
}

/// One tile's video, with the score (or channel) top left, the sound top right and the orange outline when focused.
struct TVMultiviewTile: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var controller: PlaybackController
    let index: Int
    let tile: TVMultiview.Tile
    let sound: Bool
    let focused: Bool

    var body: some View {
        ZStack {
            Color.black
            if !DemoData.isOn { TVVideoSurface(view: controller.view) }
            if controller.resolution.isEmpty {
                if case .failed = controller.status {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.accent)
                } else {
                    ProgressView()
                }
            }
        }
        .overlay(alignment: .topLeading) { chip.padding(16) }
        .overlay(alignment: .topTrailing) {
            Image(systemName: sound ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(sound ? Theme.accent : Theme.muted)
                .frame(width: 48, height: 48)
                .background(Circle().fill(.black.opacity(0.6)))
                .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: TVLayout.corner))
        .overlay(RoundedRectangle(cornerRadius: TVLayout.corner)
            .stroke(focused ? Theme.accent : Color.white.opacity(0.08), lineWidth: focused ? 3 : 1))
        // Tile 1's quality is recorded by the corner player, as always; tile 2's here.
        .onChange(of: controller.resolution) {
            if index > 0, !controller.resolution.isEmpty { model.recordQuality(tile.channel.id, controller.resolution) }
        }
    }

    @ViewBuilder
    private var chip: some View {
        Group {
            if let id = tile.gameID, let game = model.game(id) {
                HStack(spacing: 10) {
                    if game.isEvent && !game.hasSides {
                        Text(game.eventTitle).foregroundStyle(Theme.text).lineLimit(1)
                    } else {
                        Text(abbr(game.away)).foregroundStyle(Theme.text)
                        if game.state != .upcoming {
                            Text("\(game.away.score) – \(game.home.score)").foregroundStyle(Theme.text).monospacedDigit()
                        }
                        Text(abbr(game.home)).foregroundStyle(Theme.text)
                    }
                    Text(status(game)).foregroundStyle(Theme.accent).lineLimit(1)
                }
            } else {
                Text(tile.channel.name).foregroundStyle(Theme.text).lineLimit(1)
            }
        }
        .font(.system(size: 21, weight: .bold))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(.black.opacity(0.65)))
    }

    private func abbr(_ team: Team) -> String {
        team.abbr.isEmpty ? String(team.name.prefix(3)).uppercased() : team.abbr
    }

    private func status(_ game: Game) -> String {
        switch game.state {
        case .live: return game.statusText
        case .upcoming: return game.startText
        case .finished: return game.statusText.uppercased()
        }
    }
}

/// Under a tile: reliability dot, channel name, quality.
struct TVMultiviewCaption: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var controller: PlaybackController
    let channel: Channel

    var body: some View {
        HStack(spacing: 12) {
            ReliabilityDot(channelID: channel.id, size: 12, bare: true)
            Text(channel.name)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Theme.soft)
                .lineLimit(1)
            let quality = controller.resolution.isEmpty ? (model.measuredQuality[channel.id] ?? "") : controller.resolution
            if !quality.isEmpty { TVBadge(text: quality) }
            Spacer(minLength: 0)
        }
    }
}

/// Hold select on a tile: its game and score, the game's streams (4K left out; the current one says "playing"),
/// "Pick another game…" and "Remove tile". Back closes it.
struct TVMultiviewPanel: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var mv = TVMultiview.shared
    @FocusState private var focused: String?
    let panel: TVMultiview.Panel

    private var index: Int {
        switch panel {
        case .tile(let i), .games(let i): return i
        }
    }

    private var tile: TVMultiview.Tile? { mv.tiles.indices.contains(index) ? mv.tiles[index] : nil }
    private var game: Game? { tile?.gameID.flatMap { id in model.game(id) } }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 6) {
                switch panel {
                case .tile: tileContent
                case .games: gamesContent
                }
            }
            .padding(.vertical, 30)
            .padding(.horizontal, 20)
        }
        .frame(width: 640)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar.ignoresSafeArea())
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.raised).frame(width: 2) }
        .focusSection()
        .defaultFocus($focused, firstFocus)
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                focused = firstFocus
            }
        }
    }

    private var firstFocus: String {
        switch panel {
        case .tile:
            if let tile, let game, mv.streams(game, model: model).contains(where: { $0.channel.id == tile.channel.id }) {
                return "s\(tile.channel.id)"
            }
            return "pick"
        case .games: return mv.liveGames(model: model).first?.games.first.map { "g\($0.id)" } ?? "none"
        }
    }

    @ViewBuilder
    private var tileContent: some View {
        if let tile {
            VStack(alignment: .leading, spacing: 6) {
                Text(game?.title ?? tile.channel.name)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                if let game, game.state != .upcoming, !(game.isEvent && !game.hasSides) {
                    Text("\(game.away.score) – \(game.home.score)  ·  \(game.state == .live ? game.statusText : game.headerText)")
                        .font(.system(size: 22, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                } else if let game {
                    Text(game.headerText).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 16)

            if let game {
                let list = mv.streams(game, model: model)
                if !list.isEmpty {
                    TVSectionTitle(text: "Streams", count: list.count)
                        .padding(.leading, 22)
                        .padding(.top, 6)
                }
                ForEach(list) { match in
                    let playing = match.channel.id == tile.channel.id
                    Button {
                        mv.panel = nil
                        mv.swap(index, to: match.channel, game: game, model: model)
                    } label: {
                        HStack(spacing: 14) {
                            ReliabilityDot(channelID: match.channel.id, size: 12, bare: true)
                            Text(match.channel.name)
                                .font(.system(size: 23, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if playing {
                                Text("playing").font(.system(size: 19, weight: .bold)).foregroundStyle(Theme.accent)
                            }
                            TVBadge(text: model.measuredQuality[match.channel.id] ?? match.quality)
                        }
                    }
                    .buttonStyle(TVRowButtonStyle(selected: playing))
                    .focused($focused, equals: "s\(match.channel.id)")
                }
            }

            Button {
                mv.panel = .games(index)
            } label: {
                Label("Pick another game…", systemImage: "sportscourt")
                    .font(.system(size: 24, weight: .semibold))
            }
            .buttonStyle(TVRowButtonStyle())
            .focused($focused, equals: "pick")
            .padding(.top, 14)

            Button {
                mv.remove(index, model: model)
            } label: {
                Label("Remove tile", systemImage: "xmark.rectangle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.danger)
            }
            .buttonStyle(TVRowButtonStyle())
            .focused($focused, equals: "remove")
        }
    }

    @ViewBuilder
    private var gamesContent: some View {
        Text("Pick another game")
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        let groups = mv.liveGames(model: model)
        if groups.isEmpty {
            Text("Nothing is live right now.")
                .font(.system(size: 22))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 22)
            // Something to stand on, so Back still works.
            Button("Back") { mv.panel = .tile(index) }
                .buttonStyle(TVRowButtonStyle())
                .focused($focused, equals: "none")
        }
        ForEach(groups, id: \.sport) { group in
            TVSectionTitle(text: group.sport.rawValue, count: group.games.count)
                .padding(.leading, 22)
                .padding(.top, 14)
            ForEach(group.games) { game in
                Button {
                    mv.panel = nil
                    mv.pick(game, for: index, model: model)
                } label: {
                    HStack(spacing: 14) {
                        Text(game.title)
                            .font(.system(size: 23, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if !(game.isEvent && !game.hasSides) {
                            Text("\(game.away.score) – \(game.home.score)")
                                .font(.system(size: 21, weight: .bold).monospacedDigit())
                        }
                        Text(game.statusText)
                            .font(.system(size: 19, weight: .semibold))
                            .opacity(0.7)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(TVRowButtonStyle())
                .focused($focused, equals: "g\(game.id)")
            }
        }
    }
}
