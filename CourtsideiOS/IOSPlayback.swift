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
    /// "HDR10", "HLG" or "Dolby Vision" from the video track's format (2.21); empty for SDR or not known yet.
    @Published private(set) var dynamicRange = ""
    private var rangeLookup: Task<Void, Never>?
    /// The sound ("Stereo", "5.1 Dolby"...), from the audio track's format.
    @Published private(set) var audio = ""
    /// When the picture started playing (for "No sound").
    private var playingSince: Date?
    private var audioLookup: Task<Void, Never>?
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
        view.isUserInteractionEnabled = false
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
        StreamStats.shared.begin(url)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        currentURL = url
        status = .opening
        resolution = ""
        frameRate = 0
        audio = ""
        dynamicRange = ""
        rangeLookup?.cancel()
        rangeLookup = nil
        playingSince = nil
        audioLookup?.cancel()
        lastBufferMs = bufferMs
        freezeWatch.reset()
        droppedSince = nil
        if player.currentItem != nil { ConnLog.add("Closed \(ConnLog.stream((player.currentItem?.asset as? AVURLAsset)?.url))") }
        ConnLog.add("Opened \(ConnLog.stream(url))")
        // With a proxy the stream comes from the app's own relay (127.0.0.1), which an Apple TV can't reach: AirPlay
        // then sends the picture from the phone instead of handing the TV the address.
        player.allowsExternalPlayback = !ProxySettings.current.enabled
        let item = AVPlayerItem(url: ProxyRelay.shared.wrap(url))
        item.preferredForwardBufferDuration = Double(bufferMs) / 1000
        player.replaceCurrentItem(with: item)
        player.play()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.poll()
                let picture = !self.resolution.isEmpty
                StreamStats.shared.tick(picture: picture, playing: picture && self.status == .playing,
                                        buffering: picture && self.status == .buffering)
            }
        }
    }

    /// Called when a stream keeps freezing even after restarting it, so the app can move to the next stream.
    var onRepeatedFreezing: (() -> Void)?
    private let freezeWatch = FreezeWatch()
    private var droppedSince: Date?
    private var lastReconnect = Date.distantPast
    private var lastBufferMs = 2000

    /// Starts the stream again without showing it (the resolution and frame rate stay as they were).
    private func restartQuietly() {
        guard let url = currentURL else { return }
        ConnLog.add("Opened \(ConnLog.stream(url)) again")
        let item = AVPlayerItem(url: ProxyRelay.shared.wrap(url))
        item.preferredForwardBufferDuration = Double(lastBufferMs) / 1000
        player.replaceCurrentItem(with: item)
        player.play()
    }

    func togglePause() {
        if player.timeControlStatus == .paused { player.play() } else { player.pause() }
    }

    func stop() {
        StreamStats.shared.end()
        timer?.invalidate()
        timer = nil
        if pip?.isPictureInPictureActive == true { pip?.stopPictureInPicture() }
        if let url = currentURL { ConnLog.add("Closed \(ConnLog.stream(url))") }
        audioLookup?.cancel()
        audio = ""
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
            // It had been playing: the connection dropped, so open it again (every 3 s, up to 2 minutes) instead
            // of stopping.
            if !resolution.isEmpty, currentURL != nil {
                let now = Date()
                if droppedSince == nil { StreamStats.shared.dropped() }
                let since = droppedSince ?? now
                droppedSince = since
                if now.timeIntervalSince(since) < 120 {
                    status = .buffering
                    if now.timeIntervalSince(lastReconnect) >= 3 {
                        lastReconnect = now
                        ConnLog.add("Stream dropped: opening it again")
                        restartQuietly()
                    }
                    return
                }
            }
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
        if status == .playing { droppedSince = nil }
        let size = item.presentationSize
        if size.height > 0 {
            resolution = size.height >= 2000 ? "4K" : (size.height >= 1000 ? "1080p" : (size.height >= 700 ? "720p" : "\(Int(size.height))p"))
        }
        if frameRate == 0, let fps = item.tracks.first(where: { $0.assetTrack?.mediaType == .video })?.currentVideoFrameRate,
           fps > 0 {
            frameRate = Double(fps > 61 ? fps / 2 : fps)
        }
        if dynamicRange.isEmpty, rangeLookup == nil, status == .playing,
           let track = item.tracks.first(where: { $0.assetTrack?.mediaType == .video })?.assetTrack {
            rangeLookup = Task { @MainActor [weak self] in
                guard let formats = try? await track.load(.formatDescriptions), !Task.isCancelled,
                      let label = Self.rangeLabel(formats) else { return }
                self?.dynamicRange = label
            }
        }
        // No sound 8 seconds into the picture: "No sound" (2.17, a dead audio feed), replaced if it turns up later.
        if status == .playing, !resolution.isEmpty {
            let since = playingSince ?? Date()
            playingSince = since
            if audio.isEmpty, Date().timeIntervalSince(since) > 8 { audio = StreamSections.noSound }
        }
        if audio.isEmpty || audio == StreamSections.noSound, audioLookup == nil || audioLookup?.isCancelled == true, status == .playing,
           let track = item.tracks.first(where: { $0.assetTrack?.mediaType == .audio })?.assetTrack {
            audioLookup = Task { @MainActor [weak self] in
                guard let formats = try? await track.load(.formatDescriptions), !Task.isCancelled,
                      let label = Self.soundLabel(formats) else { return }
                self?.audio = label
            }
        }
        // Hiccups are waited out with the connection open; only 10 seconds without progress reopens the stream.
        let watching = !resolution.isEmpty && (status == .playing || status == .buffering || status == .opening)
        switch freezeWatch.check(progress: player.currentTime().seconds, watching: watching) {
        case .restart: StreamStats.shared.froze(); restartQuietly()
        case .skip: onRepeatedFreezing?()
        case .none: break
        }
    }

    /// HDR10 (PQ), HLG or Dolby Vision from the video format; nil for SDR.
    private static func rangeLabel(_ formats: [CMFormatDescription]) -> String? {
        guard let f = formats.first else { return nil }
        switch CMFormatDescriptionGetMediaSubType(f) {
        case kCMVideoCodecType_DolbyVisionHEVC, 0x64766131 /* dva1 */, 0x64766176 /* dvav */: return "Dolby Vision"
        default: break
        }
        let transfer = CMFormatDescriptionGetExtension(f, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
        if transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) { return "HDR10" }
        if transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String) { return "HLG" }
        return nil
    }

    /// "Stereo", "5.1 Dolby", "Dolby+" and so on, from the audio track's format (like the VLC label on the Mac).
    private static func soundLabel(_ formats: [CMFormatDescription]) -> String? {
        guard let f = formats.first else { return nil }
        let channels = Int(CMAudioFormatDescriptionGetStreamBasicDescription(f)?.pointee.mChannelsPerFrame ?? 0)
        let layout: String
        switch channels {
        case 0: layout = ""
        case 1: layout = "Mono"
        case 2: layout = "Stereo"
        case 6: layout = "5.1"
        case 8: layout = "7.1"
        default: layout = "\(channels) ch"
        }
        let codec: String
        switch CMFormatDescriptionGetMediaSubType(f) {
        case kAudioFormatAC3: codec = "Dolby"
        case kAudioFormatEnhancedAC3: codec = "Dolby+"
        default: codec = ""
        }
        let label = [layout, codec].filter { !$0.isEmpty }.joined(separator: " ")
        return label.isEmpty ? nil : label
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
    var dynamicRange: String { usingVLC ? "" : av.dynamicRange }
    var audio: String { usingVLC ? vlc.audio : av.audio }
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
        // If Apple's player can't show a picture within 8 seconds (fails, never starts, or plays sound over a black
        // screen because it can't decode the video, as with some 4K channels), use VLC for this channel from now on.
        fallback = Task { [weak self] in
            for _ in 0..<16 {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled, self.channelID == channel.id else { return }
                if self.av.status == .playing && !self.av.resolution.isEmpty { return }
                if case .failed = self.av.status { break }
            }
            guard let self, !Task.isCancelled, self.channelID == channel.id,
                  !(self.av.status == .playing && !self.av.resolution.isEmpty) else { return }
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
