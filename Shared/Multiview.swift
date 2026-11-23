import SwiftUI

/// Multiview (2.30 Apple TV, 2.44 Mac): two streams side by side, full screen (the whole window on the Mac). Tile 1 is the stream already playing, on the app's own
/// player (no reopen); tile 2 has a second player of its own, VLC only. Only offered while a stream plays and the
/// provider has a free connection; never more streams open than tiles, and a tile's old stream is closed (and given a
/// second to be gone) before its new one opens. Each player keeps its own freeze watch and reconnects.
@MainActor
final class Multiview: ObservableObject {
    static let shared = Multiview()

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
        if model.poppedOut {
            model.notice = "Bring the player back into the window first, then watch alongside"
            return
        }
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
            // Already on the app's player: it carries on with it, no reconnect.
            resume(item, model: model)
            finish()
        } else {
            // Tile 2's player only lives in multiview: its stream moves to the app's player, closed and reopened a
            // second apart, so the provider never counts more than one.
            close(keep)
            leaving = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                self.resume(item, model: model)
                self.finish()
            }
        }
    }

    /// The kept stream carries on: full screen on Apple TV; in the Mac's mini player at the top (it reopens the stream
    /// there once multiview has gone, or carries on with no reconnect when it's already on the app's player).
    private func resume(_ item: NowPlaying, model: AppModel) {
        model.pinned = item
        #if !os(macOS)
        model.play(item.channel, gameTitle: item.gameTitle, lineup: item.lineup)
        #endif
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
