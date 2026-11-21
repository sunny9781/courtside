import SwiftUI
import UIKit
import AVKit
import CoreMedia

/// Full-screen player.
/// - Swipe or press up/down: previous/next stream for this game (or channel in this category).
/// - Click: stream information (channel, what's on, resolution, frame rate, sound) and the streams watched before
///   (most recent on the left). Left/right picks one, click plays it; Back hides it all again.
/// - Swipe left/right: show the info bar.
/// - Play/Pause: pause. Back (Menu): close.
/// A stream that fails, stops, or buffers for 10 seconds switches to the next one (USA and Canada first).
struct TVPlayerView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @AppStorage(Prefs.autoSwitch) private var autoSwitch = false
    @AppStorage(Prefs.matchFrameRate) private var matchFrameRate = true
    @ObservedObject private var controller = PlaybackController.shared
    @FocusState private var focused: Bool
    @State private var tried: Set<Int> = []
    @State private var stalledSince: Date?
    @State private var switchingAutomatically = false
    @State private var showInfo = true
    /// The stream information panel (click the remote's centre button).
    @State private var showDetails = false
    @State private var detailsTask: Task<Void, Never>?
    /// Which of the recently watched streams is picked (left/right while the information shows).
    @State private var recentIndex = 0
    @State private var hideTask: Task<Void, Never>?
    @State private var flipLabel: String?
    @State private var flipTask: Task<Void, Never>?
    let item: NowPlaying

    private var position: Int {
        (item.lineup.firstIndex(where: { $0.id == item.channel.id }) ?? 0) + 1
    }

    var body: some View {
        // A button the size of the screen: the remote's centre button reliably reaches it (a tap gesture didn't).
        Button { toggleDetails() } label: {
        ZStack {
            Color.black.ignoresSafeArea()
            TVVideoSurface(view: controller.view)
                .ignoresSafeArea()

            statusOverlay

            VStack(spacing: 0) {
                if showDetails && !recents.isEmpty {
                    recentStrip
                        .transition(.opacity)
                }
                infoBar
                    .opacity(showInfo || showDetails ? 1 : 0)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)

            if let flipLabel {
                Text(flipLabel)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 18)
                    .background(Capsule().fill(.black.opacity(0.75)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
                    .transition(.opacity)
            }
        }
        }
        .buttonStyle(TVBareButtonStyle())
        .focused($focused)
        .onMoveCommand { direction in
            switch direction {
            case .up: model.step(-1)
            case .down: model.step(1)
            case .left where showDetails && !recents.isEmpty:
                recentIndex = max(-1, recentIndex - 1)   // -1: the bin (clear the list)
                keepDetails()
            case .right where showDetails && !recents.isEmpty:
                recentIndex = min(recents.count - 1, recentIndex + 1)
                keepDetails()
            default: poke()
            }
        }
        .onPlayPauseCommand {
            // The press that ends a hold (which opened full screen) isn't a pause.
            guard !TVRemoteHold.justHeld else { return }
            controller.togglePause()
            poke()
        }
        .onExitCommand {
            // Back hides the information first, then closes full screen.
            if showDetails {
                detailsTask?.cancel()
                withAnimation(.easeOut(duration: 0.2)) { showDetails = false }
            } else {
                model.closePlayer()
            }
        }
        .onAppear {
            focused = true
            tried = [item.channel.id]
            start()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            checkForStall()
        }
        .onChange(of: item.channel.id) {
            stalledSince = nil
            start()
            if switchingAutomatically {
                switchingAutomatically = false
            } else {
                tried = [item.channel.id]
                showFlipLabel()
            }
        }
        .onChange(of: controller.resolution) {
            if !controller.resolution.isEmpty {
                model.recordQuality(item.channel.id, controller.resolution)
            }
        }
        .onChange(of: controller.audio) { model.recordAudio(item.channel.id, controller.audio) }
        .onChange(of: controller.frameRate) {
            model.recordFrameRate(item.channel.id, controller.frameRate)
            // The HDR player (4K) says exactly what the TV should switch to, HDR included (below); until it has,
            // match the frame rate as for VLC.
            if matchFrameRate && controller.displayCriteria == nil {
                DisplayMatcher.match(frameRate: controller.frameRate, height: controller.resolution)
            }
        }
        // 4K on the HDR player: switch the TV to the stream's own frame rate and dynamic range (HDR10, Dolby Vision,
        // HLG), like other apps do, so HDR shows as HDR. The Apple TV's Match Content settings still decide.
        .onChange(of: controller.displayCriteria) {
            if let criteria = controller.displayCriteria { DisplayMatcher.apply(criteria) }
        }
        .onAppear {
            // Already playing in the corner: switch now.
            if let criteria = controller.displayCriteria { DisplayMatcher.apply(criteria) }
        }
        .onDisappear {
            hideTask?.cancel()
            flipTask?.cancel()
            DisplayMatcher.reset()
        }
    }

    // MARK: Playback

    private func start() {
        model.startStream(item.channel, on: controller, bufferMs: bufferMs)
        poke()
    }

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

    // MARK: Overlays

    private var recents: [NowPlaying] { model.recentStreams(besides: item, limit: 5) }

    /// Centre button: show the recent streams (and the info bar) for 8 seconds (no stream information panel since 2.11). While
    /// they show, it plays the picked recent stream (with none, it hides the information again).
    private func toggleDetails() {
        detailsTask?.cancel()
        if showDetails {
            withAnimation(.easeOut(duration: 0.2)) { showDetails = false }
            let list = recents
            if recentIndex < 0, !list.isEmpty {
                model.clearWatched()
            } else if !list.isEmpty {
                let pick = list[min(recentIndex, list.count - 1)]
                model.play(pick.channel, gameTitle: pick.gameTitle, lineup: pick.lineup)
            }
            return
        }
        recentIndex = 0
        withAnimation(.easeOut(duration: 0.2)) { showDetails = true }
        keepDetails()
    }

    /// Shows the information for another 8 seconds.
    private func keepDetails() {
        poke()
        detailsTask?.cancel()
        detailsTask = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.4)) { showDetails = false } }
        }
    }

    /// The streams watched before this one, most recent on the left, along the bottom above the info bar.
    private var recentStrip: some View {
        let list = recents
        return VStack(alignment: .leading, spacing: 12) {
            Text("RECENTLY WATCHED · CLICK TO SWITCH")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.muted)
            HStack(spacing: 18) {
                // The bin, on the left: clears the list.
                Image(systemName: "trash")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white.opacity(recentIndex < 0 ? 0.9 : 0.6))
                    .frame(width: 76, height: 76)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(recentIndex < 0 ? 0.35 : 0.18)))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(recentIndex < 0 ? Theme.accent : .white.opacity(0.08),
                                                                     lineWidth: recentIndex < 0 ? 4 : 1))
                    .scaleEffect(recentIndex < 0 ? 1.04 : 1)
                ForEach(Array(list.enumerated()), id: \.element.channel.id) { i, recent in
                    let picked = i == recentIndex
                    HStack(spacing: 14) {
                        TVChannelIcon(url: recent.channel.icon, size: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.playerTitle(recent))
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text(recent.channel.name)
                                .font(.system(size: 17))
                                .foregroundStyle(Theme.soft)
                        }
                        .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(width: 330, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(picked ? 0.35 : 0.18)))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(picked ? Theme.accent : .white.opacity(0.08),
                                                                     lineWidth: picked ? 4 : 1))
                    .scaleEffect(picked ? 1.04 : 1)
                    .animation(.easeOut(duration: 0.15), value: recentIndex)
                }
            }
        }
        .padding(.horizontal, 80)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func poke() {
        withAnimation(.easeOut(duration: 0.2)) { showInfo = true }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled, controller.status == .playing {
                withAnimation(.easeOut(duration: 0.4)) { showInfo = false }
            }
        }
    }

    /// Flipping by hand: the channel shows in the info bar along the bottom, not at the top as well.
    private func showFlipLabel() {}

    private func flipMessage(_ text: String, seconds: Double = 4) {
        withAnimation(.easeOut(duration: 0.15)) { flipLabel = text }
        flipTask?.cancel()
        flipTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.3)) { flipLabel = nil }
            }
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch controller.status {
        // Only before the first picture: "buffering" flickers on while streams play fine, so it isn't shown.
        case .opening where controller.resolution.isEmpty, .buffering where controller.resolution.isEmpty,
             .idle where controller.resolution.isEmpty:
            // No "Opening…" message, just the spinner until the picture comes.
            ProgressView()
        case .failed(let why):
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
                Text(why)
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.soft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
                Text(item.lineup.count > 1 ? "Swipe up or down for another stream." : "Press Back to choose another channel.")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.muted)
            }
        case .ended:
            Text("The stream stopped. Swipe up or down for another stream.")
                .font(.system(size: 28))
                .foregroundStyle(Theme.soft)
        case .paused:
            Image(systemName: "pause.fill")
                .font(.system(size: 80))
                .foregroundStyle(Theme.text.opacity(0.85))
        case .playing, .opening, .buffering, .idle:
            EmptyView()
        }
    }

    private var infoBar: some View {
        HStack(alignment: .center, spacing: 24) {
            TVChannelIcon(url: item.channel.icon, size: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.playerTitle(item))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(item.lineup.count > 1
                     ? "\(item.channel.name) · \(position) of \(item.lineup.count) · Swipe up or down to switch"
                     : item.channel.name)
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.soft)
            }
            .lineLimit(1)
            Spacer()
            if !controller.resolution.isEmpty {
                TVBadge(text: controller.resolution)
            }
            if controller.frameRate > 0 {
                TVBadge(text: PlaybackController.fpsLabel(controller.frameRate))
            }
            if !controller.audio.isEmpty {
                TVBadge(text: controller.audio)
            }
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 44)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}

/// Switches the TV to the stream's frame rate (e.g. 50 Hz for UK/European channels, 59.94 for North American
/// ones) for smoother motion, the way Apple's own apps do. Only works when "Match Content › Match Frame Rate" is
/// on in the Apple TV's Settings › Video and Audio.
@MainActor
enum DisplayMatcher {
    /// The display manager, found carefully: where it lives has changed between tvOS versions, and asking an
    /// object that doesn't have it crashes the app. Nil when this Apple TV doesn't offer it.
    private static var manager: AVDisplayManager? {
        let key = "avDisplayManager"
        let selector = NSSelectorFromString(key)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if scene.responds(to: selector), let m = scene.value(forKey: key) as? AVDisplayManager { return m }
            for window in scene.windows where window.responds(to: selector) {
                if let m = window.value(forKey: key) as? AVDisplayManager { return m }
            }
        }
        return nil
    }

    /// Whether frame-rate switching can work here: the Apple TV offers it and its Match Content setting is on.
    static var systemAllows: Bool {
        manager?.isDisplayCriteriaMatchingEnabled ?? false
    }

    static var available: Bool { manager != nil }

    static func match(frameRate fps: Double, height label: String) {
        guard fps > 0, let manager, manager.isDisplayCriteriaMatchingEnabled else { return }
        let size: (Int32, Int32) = label == "4K" ? (3840, 2160) : (label == "720p" ? (1280, 720) : (1920, 1080))
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: kCMVideoCodecType_H264,
                                             width: size.0, height: size.1, extensions: nil,
                                             formatDescriptionOut: &format) == noErr, let format else { return }
        manager.preferredDisplayCriteria = AVDisplayCriteria(refreshRate: Float(fps), formatDescription: format)
    }

    static func apply(_ criteria: AVDisplayCriteria) {
        guard let manager, manager.isDisplayCriteriaMatchingEnabled else { return }
        manager.preferredDisplayCriteria = criteria
    }

    static func reset() {
        guard let manager, manager.preferredDisplayCriteria != nil else { return }
        manager.preferredDisplayCriteria = nil
    }
}

/// A button with no look of its own (the full-screen player).
struct TVBareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}
