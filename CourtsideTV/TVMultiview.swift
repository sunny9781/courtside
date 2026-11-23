import SwiftUI
import UIKit

/// The multiview logic lives in Shared/Multiview.swift (2.44: the Mac has multiview too).
typealias TVMultiview = Multiview

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

/// Hold select on an EPG channel (2.39): watch this channel beside the stream that's playing.
struct WatchAlongsideButton: View {
    let channel: Channel
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.multiview) private var multiviewOn = true

    var body: some View {
        if multiviewOn && channel.id != model.pinned?.channel.id {
            Button("Watch alongside", systemImage: "rectangle.split.2x1") {
                if model.pinned == nil || model.nowPlaying != nil {
                    model.notice = "Start a stream first, then hold a channel to watch it alongside"
                } else {
                    TVMultiview.shared.watchAlongside(channel, game: nil, model: model)
                }
            }
        }
    }
}
