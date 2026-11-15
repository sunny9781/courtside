import SwiftUI
import UIKit
import AVKit
import AVFoundation
import Combine

/// A view whose layer is an AVPlayerLayer.
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// Apple's player, used first on iPhone/iPad because it can do Picture in Picture (including automatically when
/// you swipe up to leave the app) and AirPlay video. Plays the provider's HLS (.m3u8) version of each channel.
@MainActor
final class AVEngine: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    static let shared = AVEngine()

    @Published private(set) var status: PlaybackController.Status = .idle
    @Published private(set) var resolution = ""
    @Published private(set) var frameRate: Double = 0
    @Published private(set) var pipActive = false
    @Published private(set) var pipStarting = false

    let view = PlayerLayerView()
    let player = AVPlayer()
    private(set) var currentURL: URL?
    private var pip: AVPictureInPictureController?
    private var timer: Timer?
    /// Called when the floating window's "back to app" button is tapped, and when it's closed.
    var onPiPRestore: (() -> Void)?
    var onPiPClosed: (() -> Void)?
    private var restoring = false

    override init() {
        super.init()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        player.allowsExternalPlayback = true                      // AirPlay video
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        if AVPictureInPictureController.isPictureInPictureSupported(),
           let pip = AVPictureInPictureController(playerLayer: view.playerLayer) {
            pip.delegate = self
            pip.canStartPictureInPictureAutomaticallyFromInline = true   // swipe up to leave the app → floats
            self.pip = pip
        }
    }

    static var pipSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    func play(_ url: URL, bufferMs: Int) {
        if url == currentURL, status != .idle, status != .ended {
            if case .failed = status {} else {
                if status == .paused { player.play() }
                return
            }
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        currentURL = url
        status = .opening
        resolution = ""
        frameRate = 0
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = Double(bufferMs) / 1000
        player.replaceCurrentItem(with: item)
        player.play()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func togglePause() {
        if player.timeControlStatus == .paused { player.play() } else { player.pause() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if pip?.isPictureInPictureActive == true { pip?.stopPictureInPicture() }
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentURL = nil
        status = .idle
        resolution = ""
        frameRate = 0
    }

    func startPictureInPicture() {
        guard let pip, pip.isPictureInPicturePossible else { return }
        pip.startPictureInPicture()
    }

    private func poll() {
        guard let item = player.currentItem else { return }
        switch item.status {
        case .failed:
            status = .failed("This stream couldn't be opened.")
        case .readyToPlay:
            switch player.timeControlStatus {
            case .playing: status = .playing
            case .paused: status = .paused
            default: status = .buffering
            }
        default:
            status = .opening
        }
        let size = item.presentationSize
        if size.height > 0 {
            resolution = size.height >= 2000 ? "4K" : (size.height >= 1000 ? "1080p" : (size.height >= 700 ? "720p" : "\(Int(size.height))p"))
        }
        if frameRate == 0, let fps = item.tracks.first(where: { $0.assetTrack?.mediaType == .video })?.currentVideoFrameRate,
           fps > 0 {
            frameRate = Double(fps > 61 ? fps / 2 : fps)
        }
    }

    // MARK: Picture in Picture

    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in self.pipStarting = true }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in
            self.pipStarting = false
            self.pipActive = true
        }
    }

    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in self.pipStarting = false }
    }

    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in
            self.restoring = true
            self.onPiPRestore?()
            completionHandler(true)
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in
            self.pipActive = false
            self.pipStarting = false
            if !self.restoring { self.onPiPClosed?() }   // closed with the X: stop
            self.restoring = false
        }
    }
}

/// Picks the player for each stream: Apple's first (Picture in Picture, AirPlay, casting), VLC when a channel
/// won't play that way. Channels that needed VLC are remembered.
@MainActor
final class IOSPlayback: ObservableObject {
    static let shared = IOSPlayback()

    let av = AVEngine.shared
    let vlc = PlaybackController.shared
    @Published private(set) var usingVLC = false
    @Published private(set) var channelID: Int?
    private var vlcOnly: Set<Int> = Set(UserDefaults.standard.array(forKey: "vlcOnlyChannels") as? [Int] ?? [])
    private var fallback: Task<Void, Never>?
    private var bag: Set<AnyCancellable> = []

    private init() {
        // Re-publish changes from whichever player is in use.
        av.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        vlc.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
    }

    var status: PlaybackController.Status { usingVLC ? vlc.status : av.status }
    var resolution: String { usingVLC ? vlc.resolution : av.resolution }
    var frameRate: Double { usingVLC ? vlc.frameRate : av.frameRate }
    var isActive: Bool { channelID != nil }
    var canPictureInPicture: Bool { !usingVLC && AVEngine.pipSupported }

    func play(_ channel: Channel, model: AppModel, bufferMs: Int) {
        if channelID == channel.id {
            switch status {
            case .failed, .ended, .idle: break
            default:
                if status == .paused { togglePause() }
                return
            }
        }
        stop()
        channelID = channel.id
        if vlcOnly.contains(channel.id) {
            startVLC(channel, model: model, bufferMs: bufferMs)
            return
        }
        guard let hls = model.streamURL(for: channel, hls: true) else { return }
        usingVLC = false
        av.play(hls, bufferMs: bufferMs)
        // If Apple's player can't get going within 8 seconds, use VLC for this channel from now on.
        fallback = Task { [weak self] in
            for _ in 0..<16 {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled, self.channelID == channel.id else { return }
                if self.av.status == .playing { return }
                if case .failed = self.av.status { break }
            }
            guard let self, !Task.isCancelled, self.channelID == channel.id, self.av.status != .playing else { return }
            self.vlcOnly.insert(channel.id)
            UserDefaults.standard.set(Array(self.vlcOnly), forKey: "vlcOnlyChannels")
            self.av.stop()
            self.startVLC(channel, model: model, bufferMs: bufferMs)
        }
    }

    private func startVLC(_ channel: Channel, model: AppModel, bufferMs: Int) {
        guard let url = model.streamURL(for: channel, hls: false) else { return }
        usingVLC = true
        vlc.play(url, bufferMs: bufferMs)
    }

    func togglePause() {
        if usingVLC { vlc.togglePause() } else { av.togglePause() }
    }

    func stop() {
        fallback?.cancel()
        av.stop()
        vlc.stop()
        channelID = nil
        usingVLC = false
    }
}

/// The video of whichever player is in use.
struct IOSVideo: View {
    @ObservedObject private var playback = IOSPlayback.shared

    var body: some View {
        if playback.usingVLC {
            IOSVideoSurface(view: playback.vlc.view)
        } else {
            IOSVideoSurface(view: playback.av.view)
        }
    }
}

/// The AirPlay button.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = UIColor(Theme.accent)
        v.prioritizesVideoDevices = true
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
