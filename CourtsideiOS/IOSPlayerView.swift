import SwiftUI
import UIKit

/// Full-screen player.
/// - Swipe up/down (or the arrows): next/previous stream for this game, or channel in this category.
/// - Tap: show or hide the controls (and the streams watched before this one; tap one to go back to it).
/// - Swipe up to leave the app and it keeps playing in Picture in Picture (or use the PiP button).
/// - AirPlay and Chromecast buttons send it to a TV.
/// A stream that fails, stops, or buffers for 10 seconds switches to the next one (USA and Canada first).
struct IOSPlayerView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @AppStorage(Prefs.autoSwitch) private var autoSwitch = false
    @ObservedObject private var playback = IOSPlayback.shared
    @ObservedObject private var cast = CastManager.shared
    @State private var tried: Set<Int> = []
    @State private var stalledSince: Date?
    @State private var switchingAutomatically = false
    @State private var showControls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var flipLabel: String?
    @State private var flipTask: Task<Void, Never>?
    let item: NowPlaying

    private var position: Int {
        (item.lineup.firstIndex(where: { $0.id == item.channel.id }) ?? 0) + 1
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !cast.isCasting {
                IOSVideo().ignoresSafeArea()
            }

            statusOverlay

            if showControls { controls }

            if let flipLabel {
                Text(flipLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.black.opacity(0.75)))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { toggleControls() }
        .gesture(
            // Swiping leaves full screen (back to the player at the top); the arrows switch streams.
            DragGesture(minimumDistance: 40)
                .onEnded { _ in close() }
        )
        .statusBarHidden(!showControls)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            tried = [item.channel.id]
            start()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in checkForStall() }
        .onChange(of: item.channel.id) {
            stalledSince = nil
            start()
            if switchingAutomatically {
                switchingAutomatically = false
            } else {
                tried = [item.channel.id]
                if item.lineup.count > 1 {
                    flipMessage("\(position) of \(item.lineup.count) · \(item.channel.name)", seconds: 2)
                }
            }
        }
        .onChange(of: cast.deviceName) {
            // A Chromecast connected or disconnected while watching: move the stream there, or back here.
            start()
        }
        .onChange(of: playback.resolution) {
            if !playback.resolution.isEmpty { model.recordQuality(item.channel.id, playback.resolution) }
        }
        .onChange(of: playback.frameRate) {
            model.recordFrameRate(item.channel.id, playback.frameRate)
        }
        .onChange(of: playback.audio) { model.recordAudio(item.channel.id, playback.audio) }
        .onChange(of: playback.dynamicRange) { model.recordHDR(item.channel.id, playback.dynamicRange) }
        .onDisappear {
            hideTask?.cancel()
            flipTask?.cancel()
        }
    }

    // MARK: Playback

    private func start() {
        if cast.isCasting {
            playback.stop()
            if let url = model.streamURL(for: item.channel, hls: true) {
                cast.cast(url, title: model.playerTitle(item), subtitle: item.channel.name)
            }
        } else {
            playback.play(item.channel, model: model, bufferMs: bufferMs)
        }
        poke()
    }

    private func checkForStall() {
        guard autoSwitch, item.lineup.count > 1, !cast.isCasting, !playback.av.pipStarting else { return }
        switch playback.status {
        case .failed, .ended:
            switchToNext(reason: "The stream stopped")
        case .buffering, .opening:
            if let since = stalledSince {
                // 18 seconds: allows for the 8-second try with Apple's player before VLC takes over.
                if Date().timeIntervalSince(since) >= 18 { switchToNext(reason: "The stream stalled") }
            } else {
                stalledSince = Date()
            }
        default:
            stalledSince = nil
        }
    }

    private func switchToNext(reason: String) {
        stalledSince = nil
        let untried = item.lineup.filter { !tried.contains($0.id) }
        let preferred = untried.filter { ["USA", "Canada"].contains(Matcher.country(of: $0) ?? "") }
        guard let next = preferred.first ?? untried.first else {
            flipMessage("\(reason). No other streams left to try.")
            return
        }
        tried.insert(next.id)
        switchingAutomatically = true
        playback.stop()
        model.switchStream(to: next)
        flipMessage("\(reason). Switched to \(next.name)")
    }

    /// Closing full screen leaves the stream playing in the pinned player at the top.
    private func close() {
        if model.pinned == nil, let current = model.nowPlaying { model.pinned = current }
        model.closePlayer()
    }

    // MARK: Overlays

    private func toggleControls() {
        if showControls {
            withAnimation(.easeOut(duration: 0.2)) { showControls = false }
        } else {
            poke()
        }
    }

    private func poke() {
        withAnimation(.easeOut(duration: 0.2)) { showControls = true }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled, playback.status == .playing {
                withAnimation(.easeOut(duration: 0.3)) { showControls = false }
            }
        }
    }

    private func flipMessage(_ text: String, seconds: Double = 4) {
        withAnimation(.easeOut(duration: 0.15)) { flipLabel = text }
        flipTask?.cancel()
        flipTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.3)) { flipLabel = nil } }
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if let device = cast.deviceName {
            VStack(spacing: 12) {
                Image(systemName: "tv.and.mediabox").font(.system(size: 44)).foregroundStyle(Theme.accent)
                Text("Playing on \(device)").font(.headline).foregroundStyle(.white)
                Text(item.channel.name).font(.subheadline).foregroundStyle(.white.opacity(0.7))
            }
        } else if playback.av.pipActive {
            VStack(spacing: 10) {
                Image(systemName: "pip").font(.system(size: 40)).foregroundStyle(.white.opacity(0.7))
                Text("Playing in picture in picture").foregroundStyle(.white.opacity(0.8))
            }
        } else {
            switch playback.status {
            case .opening, .buffering, .idle:
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text(playback.status == .buffering ? "Buffering…" : "Opening \(item.channel.name)…")
                        .foregroundStyle(.white.opacity(0.8))
                }
            case .failed(let why):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(Theme.accent)
                    Text(why).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center).padding(.horizontal, 40)
                    Button("Try again") { playback.stop(); start() }.buttonStyle(.borderedProminent)
                }
            case .ended:
                VStack(spacing: 12) {
                    Text("The stream stopped.").foregroundStyle(.white.opacity(0.8))
                    Button("Reconnect") { playback.stop(); start() }.buttonStyle(.borderedProminent)
                }
            case .paused:
                Image(systemName: "pause.fill").font(.system(size: 50)).foregroundStyle(.white.opacity(0.85))
            case .playing:
                EmptyView()
            }
        }
    }

    private var controls: some View {
        VStack {
            HStack(spacing: 14) {
                circleButton("xmark") { close() }
                Spacer()
                CastButton()
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(.black.opacity(0.5)))
                AirPlayButton()
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(.black.opacity(0.5)))
                if playback.canPictureInPicture && !cast.isCasting {
                    circleButton("pip.enter") { playback.av.startPictureInPicture() }
                }
                if !cast.isCasting {
                    circleButton(playback.status == .paused ? "play.fill" : "pause.fill") {
                        playback.togglePause()
                        poke()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            recentStrip

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.playerTitle(item))
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(item.lineup.count > 1
                         ? "\(item.channel.name) · \(position) of \(item.lineup.count)"
                         : item.channel.name)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .lineLimit(1)
                Spacer()
                if !playback.resolution.isEmpty { IOSBadge(text: playback.resolution) }
                if !playback.dynamicRange.isEmpty { IOSBadge(text: playback.dynamicRange) }
                if playback.frameRate > 0 { IOSBadge(text: PlaybackController.fpsLabel(playback.frameRate)) }
                if !playback.audio.isEmpty { IOSBadge(text: playback.audio) }
                if item.lineup.count > 1 {
                    circleButton("chevron.up") { model.step(-1) }
                    circleButton("chevron.down") { model.step(1) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .padding(.top, -40)
            )
        }
        .transition(.opacity)
    }

    /// The streams watched before this one, most recent on the left (as many as fit): tap one to go back to it.
    @ViewBuilder
    private var recentStrip: some View {
        let list = model.recentStreams(besides: item, limit: 4)
        Group {
            ViewThatFits(in: .horizontal) {
                ForEach((0...list.count).reversed(), id: \.self) { n in
                    HStack(spacing: 8) {
                        // Reconnect (2.16): close the stream and open it again, for a feed that's stuck or looping.
                        Button { reconnect() } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.18)))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        // The bin: clears the list.
                        if !list.isEmpty { Button { model.clearWatched(); poke() } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.18)))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(.plain) }
                        ForEach(list.prefix(n), id: \.channel.id) { recent in recentCard(recent) }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
        }
    }

    private func reconnect() {
        ConnLog.add("Reconnect pressed")
        playback.stop()
        poke()
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            start()
        }
    }

    private func recentCard(_ recent: NowPlaying) -> some View {
        Button {
            model.play(recent.channel, gameTitle: recent.gameTitle, lineup: recent.lineup)
            poke()
        } label: {
            HStack(spacing: 8) {
                IOSChannelIcon(url: recent.channel.icon, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.playerTitle(recent))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(recent.channel.name)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(width: 165, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(.black.opacity(0.5)))
        }
    }
}
