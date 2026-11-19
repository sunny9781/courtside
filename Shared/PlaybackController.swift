import Foundation
import Combine
import AVFoundation
#if os(macOS)
import AppKit
typealias PlatformView = NSView
#else
import UIKit
typealias PlatformView = UIView
#endif
#if canImport(VLCKitSPM)
import VLCKitSPM
#endif

/// Wraps VLC when the VLCKit package is added to the project, and falls back to Apple's player otherwise.
@MainActor
final class PlaybackController: ObservableObject {
    enum Status: Equatable {
        case idle, opening, buffering, playing, paused, ended
        case failed(String)
    }

    @Published var status: Status = .idle
    @Published var resolution = ""
    /// Frames per second of the current stream (0 until known), e.g. 59.94.
    @Published var frameRate: Double = 0
    /// The sound: "Stereo", "5.1 Dolby", "5.1 Dolby+" (VLC engine only).
    @Published var audio = ""
    /// Half-second ticks the current stream has been playing (to time the frame-rate check).
    private var playingPolls = 0
    /// Called when a stream starts or stops (the app uses it to re-check connections in use).
    var onChange: (() -> Void)?

    let view: PlatformView
    private var timer: Timer?
    /// The stream currently loaded, so asking for it again doesn't reconnect.
    private(set) var currentURL: URL?

    /// One player shared by the mini player and full screen, so switching between them never reconnects.
    static let shared = PlaybackController()

    static var usesVLC: Bool {
        #if canImport(VLCKitSPM)
        return true
        #else
        return false
        #endif
    }

    #if canImport(VLCKitSPM)
    private let player = VLCMediaPlayer()
    #if os(tvOS)
    /// Apple TV: 4K channels play with Apple's own player, in the same view, so HDR reaches the TV as HDR (VLC turns
    /// it into a dark standard-range picture). Everything else stays on VLC.
    private let apple = AVPlayer()
    private let appleLayer = AVPlayerLayer()
    /// The current stream plays with Apple's player.
    @Published private(set) var usesApplePlayer = false
    /// What the TV should switch to for it (frame rate, HDR), from the stream itself; applied in full screen.
    @Published private(set) var displayCriteria: AVDisplayCriteria?
    /// The same channel for VLC, if Apple's player can't show it.
    private var fallbackURL: URL?
    private var appleOpenedAt = Date.distantPast
    #endif
    #else
    private let player = AVPlayer()
    private let playerLayer = AVPlayerLayer()
    #endif

    init() {
        view = PlatformView()
        #if os(macOS)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        #else
        view.backgroundColor = .black
        #endif
        #if canImport(VLCKitSPM)
        player.drawable = view
        #if os(tvOS)
        appleLayer.player = apple
        appleLayer.videoGravity = .resizeAspect
        appleLayer.isHidden = true
        view.layer.addSublayer(appleLayer)
        #endif
        #else
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        #if os(macOS)
        playerLayer.frame = view.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(playerLayer)
        #else
        view.layer.addSublayer(playerLayer)
        #endif
        #endif
    }

    /// Called when a stream keeps freezing even after restarting it, so the app can move to the next stream.
    var onRepeatedFreezing: (() -> Void)?
    private let freezeWatch = FreezeWatch()
    private var lastBufferMs = 2000
    /// The next stream, waiting for the old one's connection to close (see open).
    private var pendingOpen: DispatchWorkItem?

    /// `applePlayer`: play with Apple's player (Apple TV, 4K channels), falling back to `fallback` on VLC.
    func play(_ url: URL, bufferMs: Int, applePlayer: Bool = false, fallback: URL? = nil) {
        if url == currentURL, status != .idle, status != .ended {
            if case .failed = status {} else {
                if status == .paused { togglePause() }
                return
            }
        }
        freezeWatch.reset()
        #if canImport(VLCKitSPM) && os(tvOS)
        wantApple = applePlayer
        fallbackURL = applePlayer ? fallback : nil
        #endif
        open(url, bufferMs: bufferMs, quiet: false)
    }

    #if canImport(VLCKitSPM) && os(tvOS)
    private var wantApple = false
    #endif

    /// Starts the stream again without showing it: keeps the resolution and frame rate shown as they were.
    private func restartQuietly() {
        guard let url = currentURL else { return }
        open(url, bufferMs: lastBufferMs, quiet: true)
    }

    private func open(_ url: URL, bufferMs: Int, quiet: Bool) {
        lastBufferMs = bufferMs
        currentURL = url
        if !quiet {
            status = .opening
            onChange?()
            resolution = ""
            frameRate = 0
            audio = ""
            playingPolls = 0
        }
        // One connection at a time: close the old stream first and give the provider a moment to see it gone
        // before opening the next, so switching (or flipping quickly through channels) never counts as two.
        // Flipping fast only opens the channel you stop on.
        pendingOpen?.cancel()
        let hadStream = closeCurrent()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.currentURL == url else { return }
            self.pendingOpen = nil
            #if canImport(VLCKitSPM)
            #if os(tvOS)
            self.usesApplePlayer = self.wantApple
            self.appleLayer.isHidden = !self.wantApple
            self.displayCriteria = nil
            if self.wantApple {
                self.appleLayer.frame = self.view.bounds
                let item = AVPlayerItem(url: url)
                item.preferredForwardBufferDuration = Double(bufferMs) / 1000
                self.apple.replaceCurrentItem(with: item)
                self.apple.play()
                self.appleOpenedAt = Date()
                Task { @MainActor [weak self] in
                    let criteria = try? await item.asset.load(.preferredDisplayCriteria)
                    if let self, self.apple.currentItem === item { self.displayCriteria = criteria }
                }
                return
            }
            #endif
            let media = VLCMedia(url: url)
            media.addOption(":network-caching=\(bufferMs)")
            self.player.media = media
            self.player.play()
            #else
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = Double(bufferMs) / 1000
            self.player.replaceCurrentItem(with: item)
            self.player.play()
            #endif
        }
        pendingOpen = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (hadStream ? 0.4 : 0), execute: work)
        startPolling()
    }

    /// Closes whatever stream is open (its network connection included). True if one was.
    @discardableResult
    private func closeCurrent() -> Bool {
        #if canImport(VLCKitSPM)
        var had = false
        #if os(tvOS)
        if apple.currentItem != nil {
            apple.pause()
            apple.replaceCurrentItem(with: nil)
            displayCriteria = nil
            had = true
        }
        #endif
        guard player.media != nil else { return had }
        player.stop()
        player.media = nil
        return true
        #else
        guard player.currentItem != nil else { return false }
        player.pause()
        player.replaceCurrentItem(with: nil)
        return true
        #endif
    }

    /// Opens the current stream again from scratch (Apple TV: after full screen, when the TV switching its
    /// refresh rate back can leave the picture black).
    func reload(bufferMs: Int) {
        guard let url = currentURL else { return }
        currentURL = nil
        play(url, bufferMs: bufferMs)
    }

    func togglePause() {
        #if canImport(VLCKitSPM)
        #if os(tvOS)
        if usesApplePlayer {
            if apple.rate > 0 { apple.pause() } else { apple.play() }
            return
        }
        #endif
        if player.isPlaying { player.pause() } else { player.play() }
        #else
        if player.rate > 0 { player.pause() } else { player.play() }
        #endif
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pendingOpen?.cancel()
        pendingOpen = nil
        closeCurrent()
        currentURL = nil
        status = .idle
        onChange?()
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        // Between closing one stream and opening the next there's nothing to look at.
        if pendingOpen != nil { return }
        #if canImport(VLCKitSPM)
        #if os(tvOS)
        if usesApplePlayer {
            pollApple()
            return
        }
        #endif
        switch player.state {
        case .opening:
            status = .opening
        case .buffering:
            status = player.isPlaying ? .playing : .buffering
        case .playing:
            status = .playing
        case .paused:
            status = .paused
        case .error:
            status = .failed("This stream couldn't be opened. Try another stream for this game.")
        case .ended:
            status = .ended
        case .stopped:
            if status == .playing { status = .ended }
        default:
            break
        }
        let size = player.videoSize
        if size.height > 0 { resolution = Self.label(size.height) }
        // Frozen for 4 seconds: restart quietly; if it keeps happening, move on.
        let watching = !resolution.isEmpty && (status == .playing || status == .buffering || status == .opening)
        switch freezeWatch.check(progress: Double(player.time.intValue), watching: watching) {
        case .restart: restartQuietly()
        case .skip: onRepeatedFreezing?()
        case .none: break
        }
        // Frame rate: asked once per stream, after it has been playing for 2 seconds (asking VLC for track
        // details while a stream is still starting up can crash).
        if status == .playing {
            playingPolls += 1
            if playingPolls == 4 && frameRate == 0, let fps = Self.videoFrameRate(player.media) { frameRate = fps }
            if playingPolls == 4 && audio.isEmpty, let sound = Self.soundLabel(player.media) { audio = sound }
        }
        #else
        guard let item = player.currentItem else { return }
        switch item.status {
        case .failed:
            status = .failed("Apple's player can't play this stream. Add the VLCKit package in Xcode for the built-in VLC engine.")
        case .readyToPlay:
            switch player.timeControlStatus {
            case .playing: status = .playing
            case .paused: status = .paused
            default: status = .buffering
            }
        default:
            status = .opening
        }
        if item.presentationSize.height > 0 { resolution = Self.label(item.presentationSize.height) }
        #endif
    }

    #if canImport(VLCKitSPM) && os(tvOS)
    /// Apple's player (4K channels): its state, size and frame rate; if it hasn't shown a picture after 8 seconds (or
    /// fails), the same channel opens on VLC instead.
    private func pollApple() {
        if appleLayer.frame != view.bounds {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            appleLayer.frame = view.bounds
            CATransaction.commit()
        }
        guard let item = apple.currentItem else { return }
        let noPicture = item.presentationSize.height == 0
        if item.status == .failed || (noPicture && Date().timeIntervalSince(appleOpenedAt) > 8) {
            if let fallback = fallbackURL {
                fallbackURL = nil
                wantApple = false
                open(fallback, bufferMs: lastBufferMs, quiet: false)
            } else {
                status = .failed("This stream couldn't be opened. Try another stream for this game.")
            }
            return
        }
        switch item.status {
        case .readyToPlay:
            switch apple.timeControlStatus {
            case .playing: status = .playing
            case .paused: status = .paused
            default: status = .buffering
            }
        default:
            status = .opening
        }
        if item.presentationSize.height > 0 { resolution = Self.label(item.presentationSize.height) }
        let watching = !resolution.isEmpty && (status == .playing || status == .buffering)
        switch freezeWatch.check(progress: item.currentTime().seconds, watching: watching) {
        case .restart: restartQuietly()
        case .skip: onRepeatedFreezing?()
        case .none: break
        }
        if status == .playing {
            playingPolls += 1
            if playingPolls >= 4 && frameRate == 0,
               let track = item.tracks.first(where: { $0.assetTrack?.mediaType == .video }), track.currentVideoFrameRate > 0 {
                var fps = Double(track.currentVideoFrameRate)
                if fps > 61 { fps /= 2 }
                frameRate = fps
            }
        }
    }
    #endif

    #if canImport(VLCKitSPM)
    /// The audio track as "Stereo", "5.1 Dolby" and so on, from VLC's track details.
    private static func soundLabel(_ media: VLCMedia?) -> String? {
        guard let tracks = media?.tracksInformation as? [[AnyHashable: Any]] else { return nil }
        for track in tracks where (track["type"] as? String) == "audio" {
            let channels = (track["channels_number"] as? NSNumber)?.intValue ?? 0
            let layout: String
            switch channels {
            case 0: layout = ""
            case 1: layout = "Mono"
            case 2: layout = "Stereo"
            case 6: layout = "5.1"
            case 8: layout = "7.1"
            default: layout = "\(channels) ch"
            }
            // VLC's codec code is four letters packed into a number, first letter lowest.
            var codec = ""
            if let raw = (track["codec"] as? NSNumber)?.uint32Value {
                let bytes = [raw & 0xff, (raw >> 8) & 0xff, (raw >> 16) & 0xff, (raw >> 24) & 0xff]
                let fourcc = String(bytes: bytes.map { UInt8($0) }, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
                switch fourcc {
                case "a52": codec = "Dolby"
                case "eac3": codec = "Dolby+"
                case "dts": codec = "DTS"
                case "mlp", "trhd": codec = "TrueHD"
                default: codec = ""
                }
            }
            let label = [layout, codec].filter { !$0.isEmpty }.joined(separator: " ")
            return label.isEmpty ? nil : label
        }
        return nil
    }

    /// Reads the video track's frame rate. Interlaced TV streams often report double (100 for 50i), so
    /// anything over 60 is halved.
    private static func videoFrameRate(_ media: VLCMedia?) -> Double? {
        guard let tracks = media?.tracksInformation as? [[AnyHashable: Any]] else { return nil }
        for track in tracks where (track["type"] as? String) == "video" {
            let num = (track["frame_rate_num"] as? NSNumber)?.doubleValue ?? 0
            let den = (track["frame_rate_den"] as? NSNumber)?.doubleValue ?? 0
            guard num > 0, den > 0 else { continue }
            var fps = num / den
            if fps > 61 { fps /= 2 }
            return fps
        }
        return nil
    }
    #endif

    /// "60 fps", "59.94 fps", "25 fps".
    static func fpsLabel(_ fps: Double) -> String {
        guard fps > 0 else { return "" }
        let rounded = fps.rounded()
        if abs(fps - rounded) < 0.05 { return "\(Int(rounded)) fps" }
        return String(format: "%.2f fps", fps)
    }

    private static func label(_ height: CGFloat) -> String {
        if height >= 2000 { return "4K" }
        if height >= 1000 { return "1080p" }
        if height >= 700 { return "720p" }
        return "\(Int(height))p"
    }
}
