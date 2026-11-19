#if canImport(KSPlayer)
import AVFoundation
import CoreMedia
import KSPlayer
import UIKit

/// Apple TV: the 4K player. FFmpeg reads the same TS stream VLC would (one provider connection) and VideoToolbox
/// decodes it, so HDR10 / HLG / Dolby Vision reach the TV as HDR instead of VLC's dark tone-mapped picture.
/// KSPlayer (GPL build, github.com/kingslay/KSPlayer) does the work; PlaybackController drives it.
@MainActor
final class HDREngine: NSObject {
    /// What the TV should switch to (frame rate and dynamic range), once the video track is known.
    var onDisplayCriteria: ((AVDisplayCriteria) -> Void)?

    private(set) var player: KSMEPlayer?
    private(set) var failed = false
    private(set) var ended = false
    private(set) var openedAt = Date.distantPast

    /// KSPlayer's own logging is switched off: its messages can include the stream URL (and with it the login).
    static func configure() {
        KSOptions.logLevel = .panic
        KSOptions.logger = SilentLog()
        KSOptions.canBackgroundPlay = false
    }

    /// Opens `url` inside `container` (the same view VLC draws into).
    func open(_ url: URL, in container: UIView, bufferMs: Int) {
        close()
        Self.configure()
        failed = false
        ended = false
        let options = Options()
        options.isLive = true
        options.registerRemoteControll = false
        options.subtitleDisable = true
        options.preferredForwardBufferDuration = max(1, Double(bufferMs) / 1000)
        // Look like VLC to the provider, which some panels check.
        options.userAgent = "VLC/3.0.21 LibVLC/3.0.21"
        options.onVideo = { [weak self] refreshRate, format in
            guard let self, self.player != nil else { return }
            var rate = refreshRate
            if rate > 61 { rate /= 2 }
            self.onDisplayCriteria?(AVDisplayCriteria(refreshRate: rate, formatDescription: format))
        }
        let player = KSMEPlayer(url: url, options: options)
        player.delegate = self
        player.contentMode = .scaleAspectFit
        let view = player.view
        view.frame = container.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = .black
        container.addSubview(view)
        self.player = player
        openedAt = Date()
        player.prepareToPlay()
    }

    /// Stops the stream and closes its connection. True if one was open.
    @discardableResult
    func close() -> Bool {
        guard let player else { return false }
        player.delegate = nil
        player.pause()
        player.stop()
        player.view.removeFromSuperview()
        self.player = nil
        return true
    }

    func togglePause() {
        guard let player else { return }
        if player.isPlaying { player.pause() } else { player.play() }
    }

    // MARK: What it's showing

    var height: CGFloat { player?.naturalSize.height ?? 0 }
    var isPlaying: Bool { player?.isPlaying ?? false }
    var isPaused: Bool { player?.playbackState == .paused }
    var isBuffering: Bool { player?.loadState == .loading }
    var isReady: Bool { player?.isReadyToPlay ?? false }
    var time: Double { player?.currentPlaybackTime ?? 0 }

    var frameRate: Double {
        guard let player else { return 0 }
        var fps = Double(player.nominalFrameRate)
        if fps > 61 { fps /= 2 }
        return fps
    }

    /// "HDR10", "HLG", "Dolby Vision" (empty for standard range).
    var dynamicRangeLabel: String {
        switch player?.dynamicRange {
        case .hdr10: return "HDR10"
        case .hlg: return "HLG"
        case .dolbyVision: return "Dolby Vision"
        default: return ""
        }
    }

    /// The sound as "Stereo", "5.1 Dolby" and so on, like the VLC path.
    var soundLabel: String? {
        guard let player else { return nil }
        let tracks = player.tracks(mediaType: .audio)
        guard let track = tracks.first(where: { $0.isEnabled }) ?? tracks.first else { return nil }
        let channels = Int(track.audioStreamBasicDescription?.mChannelsPerFrame ?? 0)
        let layout: String
        switch channels {
        case 0: layout = ""
        case 1: layout = "Mono"
        case 2: layout = "Stereo"
        case 6: layout = "5.1"
        case 8: layout = "7.1"
        default: layout = "\(channels) ch"
        }
        let text = (track.description + " " + track.name).lowercased()
        let codec: String
        if track.codecType == kAudioFormatEnhancedAC3 || text.contains("eac3") || text.contains("e-ac-3") {
            codec = "Dolby+"
        } else if track.codecType == kAudioFormatAC3 || text.contains("ac3") || text.contains("ac-3") {
            codec = "Dolby"
        } else if text.contains("truehd") {
            codec = "TrueHD"
        } else if text.contains("dts") {
            codec = "DTS"
        } else {
            codec = ""
        }
        let label = [layout, codec].filter { !$0.isEmpty }.joined(separator: " ")
        return label.isEmpty ? nil : label
    }

    // MARK: Options

    /// Hands the video's frame rate and format to the app instead of switching the TV straight away (KSPlayer's own
    /// behaviour): the TV should only switch in full screen, not for the corner player.
    final class Options: KSOptions, @unchecked Sendable {
        var onVideo: ((Float, CMFormatDescription) -> Void)?

        @MainActor
        override func updateVideo(refreshRate: Float, isDovi: Bool, formatDescription: CMFormatDescription) {
            onVideo?(refreshRate, formatDescription)
        }
    }

    final class SilentLog: LogHandler {
        func log(level: LogLevel, message: any CustomStringConvertible, file: String, function: String, line: UInt) {}
    }
}

extension HDREngine: MediaPlayerDelegate {
    func readyToPlay(player: some MediaPlayerProtocol) {
        player.play()
    }

    func changeLoadState(player: some MediaPlayerProtocol) {}

    func changeBuffering(player: some MediaPlayerProtocol, progress: UInt8) {}

    func changePlaybackTime(player: some MediaPlayerProtocol, time: TimeInterval) {}

    func playBack(player: some MediaPlayerProtocol, loopCount: Int) {}

    func reachEndOfStream(player: some MediaPlayerProtocol) {
        ended = true
    }

    func finish(player: some MediaPlayerProtocol, error: (any Error)?) {
        if error != nil { failed = true } else { ended = true }
    }

    func playerDidClear(player: some MediaPlayerProtocol) {}
}
#endif
