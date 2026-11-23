import SwiftUI
import AppKit

/// Multiview on the Mac (2.44, like the TVs' 2.30): two streams side by side, over the whole window. Click a tile to
/// give it the sound (and make it big, unless Settings › Playback says sound only); right-click a tile to swap its
/// stream, pick another game or remove it; Esc or Done leaves, keeping the tile with the sound in the mini player.
/// The logic (connections, picking streams, opening and closing) is shared with Apple TV in Shared/Multiview.swift.
struct MacMultiviewView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var mv = Multiview.shared
    @AppStorage(Prefs.multiviewSelect) private var selectMode = "big"

    var body: some View {
        VStack(spacing: 14) {
            header
            GeometryReader { geo in
                tileRow(size: geo.size)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            Text(selectMode == "sound"
                 ? "Click a tile to move the sound  ·  Right-click to swap or remove  ·  Esc to leave"
                 : "Click a tile to make it big and move the sound  ·  Right-click to swap or remove  ·  Esc to leave")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .disabled(mv.leaving)
        .animation(.easeOut(duration: 0.25), value: mv.big)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in mv.tick(model: model) }
        .background {
            // Keys: Esc leaves, 1 and 2 pick a tile (like clicking it).
            Group {
                Button("") { mv.leave(model: model) }.keyboardShortcut(.cancelAction)
                Button("") { mv.select(0) }.keyboardShortcut("1", modifiers: [])
                Button("") { mv.select(1) }.keyboardShortcut("2", modifiers: [])
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("Multiview")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.text)
            if let max = model.account?.maxConnections, max > 0 {
                Label("\(mv.tiles.count) of \(max) connections", systemImage: "person.2.fill")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(mv.tiles.count >= max ? Theme.onAccent : Theme.muted)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(mv.tiles.count >= max ? Theme.accent : Theme.raised))
            }
            Spacer()
            if mv.leaving { ProgressView().controlSize(.small) }
            Button {
                toggleWindowFullScreen()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.soft)
            .help("Full screen")
            Button("Done") { mv.leave(model: model) }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 14)
                .frame(height: 26)
                .background(Capsule().fill(Theme.accent))
                .help("Leave multiview: the tile with the sound carries on in the player (Esc)")
        }
    }

    private func tileRow(size: CGSize) -> some View {
        let gap: CGFloat = 16
        // Room under each tile for its caption.
        let caption: CGFloat = 30
        return HStack(alignment: .center, spacing: gap) {
            ForEach(Array(mv.tiles.indices), id: \.self) { i in
                let w = min(tileWidth(i, total: size.width, gap: gap), (size.height - caption) * 16 / 9)
                VStack(alignment: .leading, spacing: 8) {
                    MacMultiviewTile(controller: mv.controller(i), index: i, tile: mv.tiles[i], sound: mv.sound == i)
                        .frame(width: w, height: w * 9 / 16)
                        .contentShape(Rectangle())
                        .onTapGesture { mv.select(i) }
                        .contextMenu { tileMenu(i) }
                    MacMultiviewCaption(controller: mv.controller(i), channel: mv.tiles[i].channel)
                        .frame(width: w, alignment: .leading)
                }
            }
        }
    }

    /// Side by side: the same size. Big: the sound tile ~69% of the width, the other ~31%.
    private func tileWidth(_ i: Int, total: CGFloat, gap: CGFloat) -> CGFloat {
        let n = CGFloat(max(mv.tiles.count, 1))
        let room = total - gap * (n - 1)
        guard let big = mv.big, mv.tiles.count > 1 else { return room / n }
        return i == big ? room * 0.69 : room * 0.31 / (n - 1)
    }

    /// Right-click on a tile: its game's streams (4K left out), another live game, or remove the tile.
    @ViewBuilder
    private func tileMenu(_ index: Int) -> some View {
        if mv.tiles.indices.contains(index) {
            let tile = mv.tiles[index]
            let game = tile.gameID.flatMap { model.game($0) }
            if let game {
                let list = mv.streams(game, model: model)
                if !list.isEmpty {
                    Section(game.title) {
                        ForEach(list) { match in
                            Button {
                                mv.swap(index, to: match.channel, game: game, model: model)
                            } label: {
                                let quality = model.measuredQuality[match.channel.id] ?? match.quality
                                let name = "\(match.channel.name)\(quality.isEmpty ? "" : "  ·  \(quality)")"
                                if match.channel.id == tile.channel.id {
                                    Label(name, systemImage: "checkmark")
                                } else {
                                    Text(name)
                                }
                            }
                            .disabled(match.channel.id == tile.channel.id)
                        }
                    }
                }
            }
            let groups = mv.liveGames(model: model)
            Menu("Pick another game") {
                if groups.isEmpty {
                    Text("Nothing is live right now")
                }
                ForEach(groups, id: \.sport) { group in
                    Section(group.sport.rawValue) {
                        ForEach(group.games) { g in
                            Button(gameLine(g)) { mv.pick(g, for: index, model: model) }
                        }
                    }
                }
            }
            Divider()
            Button("Remove tile", role: .destructive) { mv.remove(index, model: model) }
        }
    }

    private func gameLine(_ game: Game) -> String {
        if game.isEvent && !game.hasSides { return "\(game.title)  ·  \(game.statusText)" }
        return "\(game.title)  ·  \(game.away.score)–\(game.home.score)  ·  \(game.statusText)"
    }

    private func toggleWindowFullScreen() {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil)
    }
}

/// One tile's video, with the score (or channel) top left, the sound top right and an orange outline on the tile with
/// the sound.
struct MacMultiviewTile: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var controller: PlaybackController
    let index: Int
    let tile: Multiview.Tile
    let sound: Bool

    var body: some View {
        ZStack {
            Color.black
            if !DemoData.isOn { VideoSurface(view: controller.view) }
            if controller.resolution.isEmpty {
                if case .failed = controller.status {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.accent)
                } else {
                    ProgressView()
                }
            }
        }
        .overlay(alignment: .topLeading) { chip.padding(10) }
        .overlay(alignment: .topTrailing) {
            Image(systemName: sound ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(sound ? Theme.accent : Theme.muted)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.black.opacity(0.6)))
                .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(sound ? Theme.accent : Color.white.opacity(0.08), lineWidth: sound ? 2 : 1))
        // The mini player is hidden while multiview is open, so every tile records what it measured here.
        .onChange(of: controller.resolution) {
            if !controller.resolution.isEmpty { model.recordQuality(tile.channel.id, controller.resolution) }
        }
        .onChange(of: controller.frameRate) {
            if controller.frameRate > 0 { model.recordFrameRate(tile.channel.id, controller.frameRate) }
        }
        .onChange(of: controller.audio) {
            if !controller.audio.isEmpty { model.recordAudio(tile.channel.id, controller.audio) }
        }
    }

    @ViewBuilder
    private var chip: some View {
        Group {
            if let id = tile.gameID, let game = model.game(id) {
                HStack(spacing: 6) {
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
        .font(.system(size: 12, weight: .bold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
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
struct MacMultiviewCaption: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var controller: PlaybackController
    let channel: Channel

    var body: some View {
        HStack(spacing: 8) {
            ReliabilityDot(channelID: channel.id, size: 9, bare: true)
            Text(channel.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.soft)
                .lineLimit(1)
            let quality = controller.resolution.isEmpty ? (model.measuredQuality[channel.id] ?? "") : controller.resolution
            if !quality.isEmpty { Badge(text: quality).fixedSize() }
            if controller.frameRate > 0 { Badge(text: PlaybackController.fpsLabel(controller.frameRate)).fixedSize() }
            if !controller.audio.isEmpty { Badge(text: controller.audio).fixedSize() }
            Spacer(minLength: 0)
        }
    }
}

/// "Watch alongside" for right-click menus (game-screen streams, score cards, EPG channels): only while a stream plays
/// in the mini player and multiview is on in Settings › Playback.
struct MacWatchAlongsideButton: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.multiview) private var multiviewOn = true
    var channel: Channel? = nil
    var game: Game? = nil

    var body: some View {
        if multiviewOn, model.pinned != nil, model.nowPlaying == nil, channel?.id != model.pinned?.channel.id {
            Button {
                Multiview.shared.watchAlongside(channel, game: game, model: model)
            } label: {
                Label("Watch alongside", systemImage: "rectangle.split.2x1")
            }
        }
    }
}
