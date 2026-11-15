import SwiftUI
import UIKit
import AVKit
import AVFoundation

/// Full-screen player.
/// - Swipe up/down (or the arrows): next/previous stream for this game, or channel in this category.
/// - Tap: show or hide the controls. Picture in Picture button: keep watching over other apps.
/// A stream that fails, stops, or buffers for 10 seconds switches to the next one (USA and Canada first).
struct IOSPlayerView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @AppStorage(Prefs.autoSwitch) private var autoSwitch = true
    @ObservedObject private var controller = PlaybackController.shared
    @ObservedObject private var pip = PiPManager.shared
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
            IOSVideoSurface(view: controller.view)
                .ignoresSafeArea()

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
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    let dy = value.translation.height
                    guard abs(dy) > abs(value.translation.width) else { return }
                    model.step(dy < 0 ? 1 : -1)
                }
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
        .onChange(of: controller.resolution) {
            if !controller.resolution.isEmpty { model.recordQuality(item.channel.id, controller.resolution) }
        }
        .onChange(of: controller.frameRate) {
            model.recordFrameRate(item.channel.id, controller.frameRate)
        }
        .onChange(of: pip.active) {
            // Picture in Picture took over: close full screen so you're back in the app.
            if pip.active { model.closePlayer() }
        }
        .onDisappear {
            hideTask?.cancel()
            flipTask?.cancel()
        }
    }

    // MARK: Playback

    private func start() {
        guard !pip.active, !pip.starting,
              let url = model.streamURL(for: item.channel, hls: !PlaybackController.usesVLC) else { return }
        controller.play(url, bufferMs: bufferMs)
        poke()
    }

    private func checkForStall() {
        guard autoSwitch, item.lineup.count > 1, !pip.starting else { return }
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

    /// Hands the stream to Apple's player (using the provider's HLS version of the channel) and floats it.
    private func startPictureInPicture() {
        guard let url = model.streamURL(for: item.channel, hls: true) else { return }
        controller.stop()
        let current = item
        pip.start(url: url, channel: current.channel) { [model] in
            // Tapping the "back to app" button on the floating window: full screen again, with the usual player.
            model.play(current.channel, gameTitle: current.gameTitle, lineup: current.lineup)
        } onFail: {
            start()   // HLS didn't work for this channel: carry on in full screen
        }
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
            if !Task.isCancelled, controller.status == .playing {
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
        if pip.starting {
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text("Starting picture in picture…").foregroundStyle(.white.opacity(0.8))
            }
        } else {
            switch controller.status {
            case .opening, .buffering, .idle:
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text(controller.status == .buffering ? "Buffering…" : "Opening \(item.channel.name)…")
                        .foregroundStyle(.white.opacity(0.8))
                }
            case .failed(let why):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(Theme.accent)
                    Text(why).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center).padding(.horizontal, 40)
                    Button("Try again") { controller.stop(); start() }.buttonStyle(.borderedProminent)
                }
            case .ended:
                VStack(spacing: 12) {
                    Text("The stream stopped.").foregroundStyle(.white.opacity(0.8))
                    Button("Reconnect") { controller.stop(); start() }.buttonStyle(.borderedProminent)
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
                circleButton("xmark") { model.closePlayer() }
                Spacer()
                if PiPManager.isSupported {
                    circleButton("pip.enter") { startPictureInPicture() }
                }
                circleButton(controller.status == .paused ? "play.fill" : "pause.fill") {
                    controller.togglePause()
                    poke()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.playerTitle(item))
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(item.lineup.count > 1
                         ? "\(item.channel.name) · \(position) of \(item.lineup.count) · swipe up or down to switch"
                         : item.channel.name)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .lineLimit(1)
                Spacer()
                if !controller.resolution.isEmpty { IOSBadge(text: controller.resolution) }
                if controller.frameRate > 0 { IOSBadge(text: PlaybackController.fpsLabel(controller.frameRate)) }
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

// MARK: Picture in Picture

/// A view whose layer is an AVPlayerLayer, for Picture in Picture.
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// Keeps Apple's player view in the window at all times (behind the app), which Picture in Picture needs.
struct PiPLayerHost: UIViewRepresentable {
    func makeUIView(context: Context) -> PlayerLayerView { PiPManager.shared.layerView }
    func updateUIView(_ uiView: PlayerLayerView, context: Context) {}
}

/// VLC can't do Picture in Picture, so for PiP the stream is handed to Apple's player using the provider's HLS
/// (.m3u8) version of the same channel. Some providers don't offer HLS for every channel; then it says so and
/// full screen carries on.
@MainActor
final class PiPManager: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    static let shared = PiPManager()

    @Published private(set) var active = false
    @Published private(set) var starting = false
    @Published var message: String?

    let layerView = PlayerLayerView()
    private var player: AVPlayer?
    private var controller: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private var onRestore: (() -> Void)?
    private var onFail: (() -> Void)?
    private var timeout: Task<Void, Never>?

    static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    func start(url: URL, channel: Channel, onRestore: @escaping () -> Void, onFail: @escaping () -> Void) {
        stop()
        self.onRestore = onRestore
        self.onFail = onFail
        starting = true

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let player = AVPlayer(url: url)
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player
        layerView.playerLayer.player = player
        layerView.playerLayer.videoGravity = .resizeAspect

        guard let pip = AVPictureInPictureController(playerLayer: layerView.playerLayer) else {
            fail("Picture in picture isn't available on this device.")
            return
        }
        pip.delegate = self
        controller = pip
        player.play()

        // Start as soon as iOS says the video is ready for it.
        possibleObservation = pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { pip, _ in
            Task { @MainActor in
                guard PiPManager.shared.starting, pip.isPictureInPicturePossible, !pip.isPictureInPictureActive else { return }
                pip.startPictureInPicture()
            }
        }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled, self.starting else { return }
            self.fail("This channel can't play in picture in picture.")
        }
    }

    func stop() {
        timeout?.cancel()
        possibleObservation = nil
        if controller?.isPictureInPictureActive == true { controller?.stopPictureInPicture() }
        player?.pause()
        layerView.playerLayer.player = nil
        player = nil
        controller = nil
        active = false
        starting = false
    }

    private func fail(_ text: String) {
        let retry = onFail
        stop()
        message = text
        retry?()
    }

    // MARK: AVPictureInPictureControllerDelegate

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in
            self.timeout?.cancel()
            self.starting = false
            self.active = true
        }
    }

    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in self.fail("Picture in picture couldn't start for this channel.") }
    }

    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in
            let restore = self.onRestore
            self.onRestore = nil
            restore?()
            completionHandler(true)
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in self.stop() }
    }
}
