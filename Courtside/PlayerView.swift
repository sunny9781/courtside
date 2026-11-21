import SwiftUI
import AppKit
import AVFoundation
#if canImport(VLCKitSPM)
import VLCKitSPM
#endif

/// Shows the one video view. It sits inside a container of its own, so when the video moves somewhere else
/// (full screen, the pinned player, the pop-out window) the place it left can't pull it back out.
struct VideoSurface: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        view.removeFromSuperview()
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        return container
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct PlayerView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @AppStorage(Prefs.autoSwitch) private var autoSwitch = false
    /// Streams already tried in this viewing, so automatic switching never loops.
    @State private var tried: Set<Int> = []
    /// When the current stream started buffering (or opening) without playing.
    @State private var stalledSince: Date?
    @State private var switchingAutomatically = false
    @ObservedObject private var controller = PlaybackController.shared
    @State private var showControls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var flipLabel: String?
    @State private var isFullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false
    /// True when opening the player put the window into full screen, so leaving it can undo that.
    @State private var enteredFullScreen = false
    @State private var flipTask: Task<Void, Never>?
    /// The stream information panel (click the video or press I), like the TVs' centre button.
    @State private var showDetails = false
    @State private var detailsTask: Task<Void, Never>?
    /// The recently watched stream picked with the left/right keys (Return plays it).
    @State private var recentIndex = 0
    let item: NowPlaying

    private var position: Int {
        (item.lineup.firstIndex(where: { $0.id == item.channel.id }) ?? 0) + 1
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            VideoSurface(view: controller.view)
                .ignoresSafeArea()

            // The video view swallows mouse events, so this clear layer sits on top to catch them.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onContinuousHover { _ in poke() }
                .onTapGesture(count: 2) { exitPlayer() }
                .onTapGesture { toggleDetails() }

            statusOverlay

            if showDetails {
                detailsPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(40)
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                if showDetails {
                    recentStrip
                        .transition(.opacity)
                }
                bottomBar
                    .opacity(showControls || showDetails ? 1 : 0)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)

            keyboardShortcuts

            if let flipLabel {
                Text(flipLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(.black.opacity(0.75)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 48)
                    .transition(.opacity)
            }
        }
        .onAppear {
            tried = [item.channel.id]
            start()
            enterFullScreen()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            checkForStall()
        }
        .onChange(of: item.channel.id) {
            stalledSince = nil
            start()
            if switchingAutomatically {
                switchingAutomatically = false   // keep the "Switched to…" message showing
            } else {
                tried = [item.channel.id]        // you switched yourself: start fresh
                showFlipLabel()
            }
        }
        .onChange(of: controller.resolution) {
            if !controller.resolution.isEmpty {
                model.recordQuality(item.channel.id, controller.resolution)
            }
        }
        .onChange(of: controller.frameRate) {
            model.recordFrameRate(item.channel.id, controller.frameRate)
        }
        .onChange(of: controller.audio) { model.recordAudio(item.channel.id, controller.audio) }
        .onDisappear {
            hideTask?.cancel()
            flipTask?.cancel()
            detailsTask?.cancel()
            // Playback carries on in the mini player if there is one; the model stops it otherwise.
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
    }

    /// Failed, dropped, or stuck buffering/opening for 10 seconds: move to the next stream automatically.
    private func checkForStall() {
        guard autoSwitch, item.lineup.count > 1 else { return }
        switch controller.status {
        case .failed, .ended:
            switchToNext(reason: "The stream stopped")
        case .buffering, .opening:
            if let since = stalledSince {
                if Date().timeIntervalSince(since) >= 10 { switchToNext(reason: "The stream stalled") }
            } else {
                stalledSince = Date()
            }
        default:
            stalledSince = nil
        }
    }

    /// The next stream not tried yet, USA and Canada first, otherwise in the game screen's order.
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
        controller.stop()
        model.switchStream(to: next)
        flipMessage("\(reason). Switched to \(next.name)")
    }

    private func flipMessage(_ text: String) {
        withAnimation(.easeOut(duration: 0.15)) { flipLabel = text }
        flipTask?.cancel()
        flipTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.3)) { flipLabel = nil }
            }
        }
    }

    private func start() {
        guard let url = model.streamURL(for: item.channel, hls: !PlaybackController.usesVLC) else { return }
        controller.play(url, bufferMs: bufferMs)
        poke()
    }

    private func showFlipLabel() {
        guard item.lineup.count > 1 else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            flipLabel = "\(position) of \(item.lineup.count) · \(item.channel.name)"
        }
        flipTask?.cancel()
        flipTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.3)) { flipLabel = nil }
            }
        }
    }

    private var window: NSWindow? { NSApp.keyWindow ?? NSApp.mainWindow }

    /// Watching full screen means the whole screen: go full screen if the window isn't already.
    private func enterFullScreen() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        window.toggleFullScreen(nil)
        enteredFullScreen = true
    }

    /// Back to where you were: leave full screen (if opening the player entered it) and close the player.
    private func exitPlayer() {
        if enteredFullScreen, let window, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        model.closePlayer()
    }

    /// Click or I: show the stream information (and the bar) for 8 seconds, or hide it again.
    private func toggleDetails() {
        detailsTask?.cancel()
        if showDetails {
            withAnimation(.easeOut(duration: 0.2)) { showDetails = false }
            return
        }
        recentIndex = 0
        withAnimation(.easeOut(duration: 0.2)) { showDetails = true }
        keepDetails()
    }

    /// Shows the information (and the recent streams) for another 8 seconds.
    private func keepDetails() {
        poke()
        detailsTask?.cancel()
        detailsTask = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.4)) { showDetails = false } }
        }
    }

    private var recents: [NowPlaying] { model.recentStreams(besides: item, limit: 5) }

    private func reconnect() {
        ConnLog.add("Reconnect pressed")
        detailsTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { showDetails = false }
        controller.stop()
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            start()
        }
    }

    private func playRecent(_ recent: NowPlaying) {
        detailsTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { showDetails = false }
        model.play(recent.channel, gameTitle: recent.gameTitle, lineup: recent.lineup)
    }

    /// The streams watched before this one, most recent on the left: click one (or Left/Right and Return) to go back.
    private var recentStrip: some View {
        let list = recents
        return VStack(alignment: .leading, spacing: 8) {
            Text("RECENTLY WATCHED")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.muted)
            HStack(spacing: 10) {
                // Reconnect (2.16): close the stream and open it again, for a feed that's stuck or looping.
                Button { reconnect() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 48, height: 48)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.18)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.08), lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .help("Reconnect to this stream")
                // The bin: clears the list.
                if !list.isEmpty { Button {
                    model.clearWatched()
                    withAnimation(.easeOut(duration: 0.2)) { showDetails = false }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 48, height: 48)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.18)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.08), lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .help("Clear recent streams") }
                ForEach(Array(list.enumerated()), id: \.element.channel.id) { i, recent in
                    let picked = i == min(recentIndex, list.count - 1)
                    Button { playRecent(recent) } label: {
                        HStack(spacing: 10) {
                            SmallLogoImage(url: recent.channel.icon, size: 32) {
                                Image(systemName: "tv").foregroundStyle(Theme.muted)
                            }
                            .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.playerTitle(recent))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                Text(recent.channel.name)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.muted)
                            }
                            .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(width: 230, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(picked ? 0.35 : 0.18)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(picked ? Theme.accent : .white.opacity(0.08),
                                                                         lineWidth: picked ? 2 : 1))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .onHover { if $0 { recentIndex = i; keepDetails() } }
                }
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Channel (and its place in the lineup), what's on now and next, video, sound and number: as on the TVs.
    private var detailsPanel: some View {
        let now = model.currentProgramme(item.channel)
        let next = now.flatMap { n in model.guide[item.channel.epgID]?.first { $0.start >= n.end } }
        func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
        func row(_ label: String, _ value: String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 80, alignment: .leading)
                Text(value)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
            }
        }
        var video: [String] = []
        if !controller.resolution.isEmpty { video.append(controller.resolution) }
        if controller.frameRate > 0 { video.append(PlaybackController.fpsLabel(controller.frameRate)) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Stream information")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.accent)
            row("Channel", item.lineup.count > 1 ? "\(item.channel.name) · \(position) of \(item.lineup.count)" : item.channel.name)
            row("Now", now.map { "\($0.title)  (\(time($0.start)) – \(time($0.end)))" } ?? model.playerTitle(item))
            if let next { row("Next", "\(time(next.start))  \(next.title)") }
            row("Video", video.isEmpty ? "Waiting for the picture…" : video.joined(separator: " · "))
            row("Sound", controller.audio.isEmpty ? "–" : controller.audio)
            if let n = item.channel.number { row("Number", "\(n)") }
        }
        .padding(22)
        .frame(width: 480, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.82)))
        .allowsHitTesting(false)
    }

    private func poke() {
        showControls = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled, controller.status == .playing {
                withAnimation(.easeOut(duration: 0.3)) { showControls = false }
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch controller.status {
        case .opening, .buffering, .idle:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(controller.status == .buffering ? "Buffering…" : "Opening \(item.channel.name)…")
                    .foregroundStyle(Theme.soft)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let why):
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accent)
                Text(why)
                    .foregroundStyle(Theme.soft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                HStack(spacing: 10) {
                    Button("Try again") {
                        controller.stop()
                        start()
                    }
                        .buttonStyle(GhostButtonStyle())

                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ended:
            VStack(spacing: 12) {
                Text("The stream stopped.")
                    .foregroundStyle(Theme.soft)
                Button("Reconnect") {
                    controller.stop()
                    start()
                }
                    .buttonStyle(GhostButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .playing, .paused:
            EmptyView()
        }
    }

    /// Title, channel, resolution and the way back, along the bottom; fades out with the mouse pointer.
    private var bottomBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.playerTitle(item))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(item.lineup.count > 1
                     ? "\(item.channel.name) · \(position) of \(item.lineup.count) · Up/Down to switch · click for info and recent"
                     : item.channel.name)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            .lineLimit(1)

            Spacer()

            if !controller.resolution.isEmpty {
                Badge(text: controller.resolution)
            }
            if controller.frameRate > 0 {
                Badge(text: PlaybackController.fpsLabel(controller.frameRate))
            }
            if !controller.audio.isEmpty {
                Badge(text: controller.audio)
            }

            Button {
                exitPlayer()
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.white.opacity(0.12)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Back to the mini player (Esc or double-click)")
        }
        .padding(.horizontal, 28)
        .padding(.top, 60)
        .padding(.bottom, 28)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
        )
    }

    /// Up/Down switch streams from the keyboard (and a TV remote later) without buttons on screen.
    private var keyboardShortcuts: some View {
        ZStack {
            Button("Previous stream") { model.step(-1) }
                .keyboardShortcut(.upArrow, modifiers: [])
            Button("Next stream") { model.step(1) }
                .keyboardShortcut(.downArrow, modifiers: [])
            Button("Stream information") { toggleDetails() }
                .keyboardShortcut("i", modifiers: [])
            // While the information shows: Left/Right pick a recent stream, Return plays it.
            Button("Previous recent stream") {
                if showDetails { recentIndex = max(0, recentIndex - 1); keepDetails() }
            }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Next recent stream") {
                if showDetails { recentIndex = min(max(recents.count - 1, 0), recentIndex + 1); keepDetails() }
            }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("Play recent stream") {
                let list = recents
                if showDetails, !list.isEmpty { playRecent(list[min(recentIndex, list.count - 1)]) } else { toggleDetails() }
            }
                .keyboardShortcut(.return, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
