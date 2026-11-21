#if canImport(KSPlayer)
import AVFoundation
import AudioToolbox
import KSPlayer
import UIKit

/// Apple TV, 4K channels: KSPlayer's own engine (FFmpeg reads the stream, VideoToolbox decodes it), so HDR10, HLG
/// and Dolby Vision reach the TV as HDR. VLCKit 3 turns HDR into a dark standard-range picture.
/// It reads the same TS stream VLC would (never HLS), and only ever tries this one engine, so the provider sees one
/// connection. PlaybackController owns it and falls back to VLC (after closing this) if it shows nothing.
@MainActor
final class HDRPlayer: NSObject, KSPlayerLayerDelegate {
    enum State { case opening, buffering, playing, paused, ended, failed }

    private(set) var state: State = .opening
    /// Seconds played (for the freeze check).
    private(set) var time: Double = 0
    private(set) var openedAt = Date.distantPast
    /// A picture has shown since this stream opened.
    private(set) var hasShownPicture = false
    /// What the TV should switch to (frame rate and dynamic range), from the stream itself; applied in full screen.
    var onDisplayCriteria: ((AVDisplayCriteria) -> Void)?

    private var layer: KSPlayerLayer?
    private var playerView: UIView?

    var isOpen: Bool { layer != nil }

    private static var configured = false
    private static func configure() {
        guard !configured else { return }
        configured = true
        // FFmpeg only: never a second try with Apple's player (that would be a second connection, as in 1.80).
        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = nil
        KSOptions.isAutoPlay = true
        // Quiet: FFmpeg's messages can carry the stream address, which holds the Xtream login.
        KSOptions.logLevel = .panic
        KSOptions.hudLog = false
    }

    func open(_ url: URL, bufferMs: Int, in host: UIView) {
        Self.configure()
        close()
        let options = HDROptions()
        options.playerTypes = [KSMEPlayer.self]
        options.isLive = true
        options.isAutoPlay = true
        options.registerRemoteControll = false
        options.subtitleDisable = true
        options.preferredForwardBufferDuration = max(1, Double(bufferMs) / 1000)
        options.onDisplayCriteria = { [weak self] criteria in self?.onDisplayCriteria?(criteria) }
        state = .opening
        time = 0
        hasShownPicture = false
        openedAt = Date()
        let layer = KSPlayerLayer(url: url, options: options, delegate: self)
        let view = layer.player.view
        view.frame = host.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = .black
        host.addSubview(view)
        self.layer = layer
        playerView = view
    }

    /// Stops the stream and closes its connection.
    func close() {
        guard let layer else { return }
        layer.delegate = nil
        layer.stop()
        playerView?.removeFromSuperview()
        playerView = nil
        self.layer = nil
        state = .ended
    }

    func togglePause() {
        guard let layer else { return }
        if layer.state.isPlaying { layer.pause() } else { layer.play() }
    }

    // MARK: What's playing

    private func track(_ type: AVMediaType) -> (any MediaPlayerTrack)? {
        guard let tracks = layer?.player.tracks(mediaType: type) else { return nil }
        return tracks.first(where: { $0.isEnabled }) ?? tracks.first
    }

    /// Height of the picture (0 until known).
    var videoHeight: CGFloat { track(.video)?.naturalSize.height ?? 0 }

    /// Frames per second (0 until known). Interlaced streams can report double, so anything over 60 is halved.
    var frameRate: Double {
        var fps = Double(track(.video)?.nominalFrameRate ?? 0)
        if fps > 61 { fps /= 2 }
        return fps
    }

    /// "HDR10", "HLG" or "Dolby Vision" when the stream is HDR (nil for standard range or while unknown).
    var dynamicRangeLabel: String? {
        switch track(.video)?.dynamicRange {
        case .hdr10: return "HDR10"
        case .hlg: return "HLG"
        case .dolbyVision: return "Dolby Vision"
        default: return nil
        }
    }

    /// "Stereo", "5.1 Dolby", "5.1 Dolby+", like the VLC path.
    var sound: String? {
        guard let audio = track(.audio) else { return nil }
        let channels = Int(audio.audioStreamBasicDescription?.mChannelsPerFrame ?? 0)
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
        switch audio.codecType {
        case kAudioFormatAC3: codec = "Dolby"
        case kAudioFormatEnhancedAC3: codec = "Dolby+"
        default:
            let name = audio.description.lowercased()
            if name.contains("eac3") || name.contains("e-ac-3") { codec = "Dolby+" }
            else if name.contains("ac3") || name.contains("ac-3") { codec = "Dolby" }
            else if name.contains("dts") { codec = "DTS" }
            else if name.contains("truehd") { codec = "TrueHD" }
            else { codec = "" }
        }
        let label = [layout, codec].filter { !$0.isEmpty }.joined(separator: " ")
        return label.isEmpty ? nil : label
    }

    // MARK: KSPlayerLayerDelegate

    func player(layer: KSPlayerLayer, state: KSPlayerState) {
        guard layer === self.layer else { return }
        switch state {
        case .initialized, .preparing: self.state = .opening
        case .readyToPlay, .buffering: self.state = .buffering
        case .bufferFinished:
            self.state = .playing
            if videoHeight > 0 { hasShownPicture = true }
        case .paused: self.state = .paused
        case .playedToTheEnd: self.state = .ended
        case .error: self.state = .failed
        @unknown default: break
        }
    }

    func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        guard layer === self.layer else { return }
        time = currentTime
        if !hasShownPicture, self.state == .playing, videoHeight > 0 { hasShownPicture = true }
    }

    func player(layer: KSPlayerLayer, finish error: (any Error)?) {
        guard layer === self.layer else { return }
        if error != nil { state = .failed }
    }

    func player(layer: KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {}
}

/// Hands the TV switch (frame rate, HDR) to the app instead of KSPlayer doing it right away, so it only happens in
/// full screen, like the rest of the app's frame-rate matching.
final class HDROptions: KSOptions {
    var onDisplayCriteria: (@MainActor (AVDisplayCriteria) -> Void)?

    @MainActor
    override func updateVideo(refreshRate: Float, isDovi: Bool, formatDescription: CMFormatDescription) {
        guard refreshRate > 0 else { return }
        onDisplayCriteria?(AVDisplayCriteria(refreshRate: refreshRate, formatDescription: formatDescription))
    }
}
#endif
