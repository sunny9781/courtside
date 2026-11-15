import SwiftUI

/// The player pinned above the tabs. Appears only while something is playing, in the same spot on every screen,
/// and keeps playing as you move between tabs, sports and games.
/// Under the video: resolution and frame rate, then hide video (keeps the sound), full screen and stop (ends the
/// stream, so it stops using a connection).
struct IOSPinnedPlayer: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    /// Width as a share of the screen; 0 means the default (full width on iPhone, under half on iPad).
    @AppStorage(Prefs.pinnedCollapsed) private var collapsed = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject private var playback = IOSPlayback.shared
    @ObservedObject private var cast = CastManager.shared
    @State private var available: CGFloat = 360
    @State private var showControls = false
    @State private var hideTask: Task<Void, Never>?
    let item: NowPlaying
    /// The game the stream belongs to: its score replaces the title, so the game screen doesn't need its own.
    var game: Game? = nil

    /// Smallest size where the quality badges and buttons still fit on one line under the video.
    private var minWidth: CGFloat { min(available, 270) }
    private var videoWidth: CGFloat {
        let share: CGFloat = sizeClass == .regular ? 0.45 : 1   // full width on iPhone, under half on iPad
        return min(available, max(minWidth, available * share))
    }
    /// Title beside the video when there's room, under it otherwise.
    private var titleBeside: Bool { available - videoWidth >= 190 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if collapsed {
                collapsedBar
            } else {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        video
                        if !titleBeside { titles }
                    }
                    .frame(width: videoWidth)
                    if titleBeside {
                        titles.padding(.top, 2)
                        Spacer(minLength: 0)
                    }
                }
                Color.clear.frame(height: 8)
            }
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .background(Theme.bg)
        .onGeometryChange(for: CGFloat.self) { $0.size.width - 32 } action: { available = max(200, $0) }
        .task(id: item.channel.id) { start() }
        .onChange(of: cast.deviceName) { start() }
        .onChange(of: playback.resolution) {
            if !playback.resolution.isEmpty { model.recordQuality(item.channel.id, playback.resolution) }
        }
        .onChange(of: playback.frameRate) { model.recordFrameRate(item.channel.id, playback.frameRate) }
    }

    /// One line: the score (or title), then the channel.
    private var titles: some View {
        HStack(spacing: 6) {
            if let game {
                scoreLine(game)
            } else {
                Text(model.playerTitle(item)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
            }
            Text("· \(item.channel.name)").font(.caption).foregroundStyle(Theme.muted)
                .layoutPriority(-1)
        }
        .lineLimit(1)
    }

    /// "🏀 TOR 78  81 BOS 🏀 · Q3 4:12", or the event's name.
    @ViewBuilder
    private func scoreLine(_ game: Game) -> some View {
        if game.isEvent && !game.hasSides {
            Text(game.eventTitle).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
        } else {
            HStack(spacing: 6) {
                IOSTeamLogo(team: game.away, size: 20)
                Text(game.away.abbr).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                if game.state != .upcoming {
                    Text(game.away.score).font(.subheadline.bold().monospacedDigit()).foregroundStyle(game.scoreColor(game.away))
                    Text("–").foregroundStyle(Theme.muted)
                    Text(game.home.score).font(.subheadline.bold().monospacedDigit()).foregroundStyle(game.scoreColor(game.home))
                } else {
                    Text("at").font(.caption).foregroundStyle(Theme.muted)
                }
                Text(game.home.abbr).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                IOSTeamLogo(team: game.home, size: 20)
                Text("· \(game.statusText)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(game.state == .live ? Theme.accent : Theme.muted)
                    .lineLimit(1)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    /// Over the bottom of the video after a tap: quality on the left, buttons on the right. Hides after a few
    /// seconds.
    private var overlayControls: some View {
        HStack(spacing: 8) {
            if !playback.resolution.isEmpty { IOSBadge(text: playback.resolution).fixedSize() }
            if playback.frameRate > 0 { IOSBadge(text: PlaybackController.fpsLabel(playback.frameRate)).fixedSize() }
            Spacer(minLength: 4)
            smallButton("rectangle.compress.vertical") { withAnimation(.easeOut(duration: 0.2)) { collapsed = true } }
            smallButton("arrow.up.left.and.arrow.down.right") { fullScreen() }
            smallButton("stop.fill") { stop() }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .padding(.top, 26)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
    }

    private func toggleControls() {
        withAnimation(.easeOut(duration: 0.15)) { showControls.toggle() }
        hideTask?.cancel()
        guard showControls else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { showControls = false }
        }
    }

    private func start() {
        guard !DemoData.isOn else { return }
        if cast.isCasting {
            playback.stop()
            if let url = model.streamURL(for: item.channel, hls: true) {
                cast.cast(url, title: model.playerTitle(item), subtitle: item.channel.name)
            }
        } else {
            playback.play(item.channel, model: model, bufferMs: bufferMs)
        }
    }

    private func fullScreen() {
        model.play(item.channel, gameTitle: item.gameTitle, lineup: item.lineup)
    }

    /// Ends the stream (frees the connection) and hides the player.
    private func stop() {
        playback.stop()
        model.pinned = nil
        model.checkConnectionsSoon()
    }

    private var video: some View {
        ZStack {
            Color.black
            if cast.isCasting {
                Label("Playing on \(cast.deviceName ?? "Chromecast")", systemImage: "tv.and.mediabox")
                    .font(.footnote).foregroundStyle(Theme.muted)
            } else {
                IOSVideo()
                if playback.av.pipActive {
                    Label("Playing in picture in picture", systemImage: "pip").font(.footnote).foregroundStyle(Theme.muted)
                } else {
                    switch playback.status {
                    // Only before the first picture ("buffering" flickers on while streams play fine).
                    case .opening where playback.resolution.isEmpty, .buffering where playback.resolution.isEmpty:
                        ProgressView()
                    case .failed: Text("This stream couldn't be opened").font(.footnote).foregroundStyle(Theme.muted)
                    default: EmptyView()
                    }
                }
            }
        }
        .frame(width: videoWidth, height: videoWidth * 9 / 16)
        .contentShape(Rectangle())
        .onTapGesture { toggleControls() }
        .overlay(alignment: .bottom) {
            if showControls { overlayControls.transition(.opacity) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var collapsedBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.2.fill").foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(game.map { GameScoreText.slim($0) } ?? model.playerTitle(item))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(item.channel.name).font(.caption2).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            smallButton("rectangle.expand.vertical") { withAnimation(.easeOut(duration: 0.2)) { collapsed = false } }
            smallButton("arrow.up.left.and.arrow.down.right") { fullScreen() }
            smallButton("stop.fill") { stop() }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { collapsed = false } }

    }

    private func smallButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white.opacity(0.2)))
        }
        .buttonStyle(.plain)
    }
}

/// One-line score text: "TOR 78 – 81 BOS · Q3 4:12".
enum GameScoreText {
    static func slim(_ game: Game) -> String {
        if game.isEvent && !game.hasSides { return game.eventTitle }
        if game.state == .upcoming { return "\(game.away.abbr) at \(game.home.abbr) · \(game.statusText)" }
        return "\(game.away.abbr) \(game.away.score) – \(game.home.score) \(game.home.abbr) · \(game.statusText)"
    }
}
