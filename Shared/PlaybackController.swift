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
    /// The sound: "Stereo", "5.1 Dolby", "5.1 Dolby+".
    @Published var audio = ""
    /// "HDR10", "HLG" or "Dolby Vision" when the 4K player shows HDR as HDR (Apple TV); empty otherwise.
    @Published var dynamicRange = ""
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
    #endif
    #if os(tvOS)
    /// What the TV should switch to for the 4K player (frame rate, HDR), from the stream itself; applied in full screen.
    @Published private(set) var displayCriteria: AVDisplayCriteria?
    /// The current stream plays on the 4K player.
    @Published private(set) var usesHDREngine = false
    #endif
    #if canImport(VLCKitSPM) && os(tvOS) && canImport(KSPlayer)
    /// Apple TV: 4K channels play with FFmpeg + VideoToolbox (HDREngine), in the same view, so HDR reaches the TV as
    /// HDR (VLC turns it into a dark standard-range picture). Everything else stays on VLC.
    private let hdr = HDREngine()
    /// Streams the 4K player couldn't show this session: they go straight to VLC next time.
    private var hdrFailed: Set<URL> = []
    #endif
    #if !canImport(VLCKitSPM)
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
        #if os(tvOS) && canImport(KSPlayer)
        hdr.onDisplayCriteria = { [weak self] criteria in
            guard let self, self.usesHDREngine else { return }
            self.displayCriteria = criteria
        }
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

    /// Whether this build has the 4K player (Apple TV).
    static var hasHDREngine: Bool {
        #if canImport(VLCKitSPM) && os(tvOS) && canImport(KSPlayer)
        return true
        #else
        return false
        #endif
    }

    /// `hdr`: play with the 4K player (Apple TV, 4K channels); if it shows no picture, the same stream opens on VLC.
    func play(_ url: URL, bufferMs: Int, hdr wantsHDR: Bool = false) {
        if url == currentURL, status != .idle, status != .ended {
            if case .failed = status {} else {
                if status == .paused { togglePause() }
                return
            }
        }
        freezeWatch.reset()
        #if canImport(VLCKitSPM) && os(tvOS) && canImport(KSPlayer)
        wantHDR = wantsHDR && !hdrFailed.contains(url)
        #endif
        open(url, bufferMs: bufferMs, quiet: false)
    }

    #if canImport(VLCKitSPM) && os(tvOS) && canImport(KSPlayer)
    private var wantHDR = false
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
            dynamicRange = ""
            playingPolls = 0
        }
        // One connection at a time: close the old stream first and give the provider a moment to see it gone
        // before opening the next, so switching (or flipping quickly through channels) never counts as two.
        // Flipping fast only opens the channel you stop on.
        pendingOpen?.cancel()
        let gap = closeCurrent()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.currentURL == url else { return }
            self.pendingOpen = nil
            #if canImport(VLCKitSPM)
            #if os(tvOS) && canImport(KSPlayer)
            self.usesHDREngine = self.wantHDR
            self.displayCriteria = nil
            if self.wantHDR {
                self.hdr.open(url, in: self.view, bufferMs: bufferMs)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + gap, execute: work)
        startPolling()
    }

    /// Closes whatever stream is open (its network connection included). Returns how long to wait before opening
    /// the next one, so the provider sees the old connection gone first (0 when nothing was open).
    @discardableResult
    private func closeCurrent() -> Double {
        #if canImport(VLCKitSPM)
        var gap = 0.0
        #if os(tvOS) && canImport(KSPlayer)
        // FFmpeg closes its connection on its own thread: give it longer than VLC.
        if hdr.close() { gap = 1.0 }
        usesHDREngine = false
        displayCriteria = nil
        #endif
        guard player.media != nil else { return gap }
        player.stop()
        player.media = nil
        return max(gap, 0.4)
        #else
        guard player.currentItem != nil else { return 0 }
        player.pause()
        player.replaceCurrentItem(with: nil)
        return 0.4
        #endif
    }

    /// Opens the current stream again from scratch (Apple TV: after full screen, when the TV switching its
    /// refresh rate back can leave the picture black).
    func reload(bufferMs: Int) {
        guard let url = currentURL else { return }
        currentURL = nil
        #if os(tvOS)
        play(url, bufferMs: bufferMs, hdr: usesHDREngine)
        #else
        play(url, bufferMs: bufferMs)
        #endif
    }

    func togglePause() {
        #if canImport(VLCKitSPM)
        #if os(tvOS) && canImport(KSPlayer)
        if usesHDREngine {
            hdr.togglePause()
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
        #if os(tvOS) && canImport(KSPlayer)
        if usesHDREngine {
            pollHDR()
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

    #if canImport(VLCKitSPM) && os(tvOS) && canImport(KSPlayer)
    /// The 4K player: its state, size, frame rate, sound and HDR. If it shows no picture within 6 seconds (or fails),
    /// it is closed completely first and only then the same stream opens on VLC, so there's never a second connection.
    private func pollHDR() {
        let noPicture = hdr.height == 0
        if hdr.failed || (noPicture && Date().timeIntervalSince(hdr.openedAt) > 6) {
            guard let url = currentURL else { return }
            hdrFailed.insert(url)
            wantHDR = false
            // open() closes the 4K player and waits for its connection to go before VLC starts.
            open(url, bufferMs: lastBufferMs, quiet: false)
            return
        }
        if hdr.ended {
            status = .ended
            return
        }
        if hdr.isPaused {
            status = .paused
        } else if hdr.isPlaying && !noPicture {
            status = hdr.isBuffering ? .buffering : .playing
        } else {
            status = hdr.isReady ? .buffering : .opening
        }
        if !noPicture { resolution = Self.label(hdr.height) }
        let watching = !resolution.isEmpty && (status == .playing || status == .buffering)
        switch freezeWatch.check(progress: hdr.time, watching: watching) {
        case .restart: restartQuietly()
        case .skip: onRepeatedFreezing?()
        case .none: break
        }
        if status == .playing {
            playingPolls += 1
            if playingPolls >= 4 && frameRate == 0 { frameRate = hdr.frameRate }
            if playingPolls >= 4 && audio.isEmpty, let sound = hdr.soundLabel { audio = sound }
            if playingPolls >= 4 && dynamicRange.isEmpty { dynamicRange = hdr.dynamicRangeLabel }
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
