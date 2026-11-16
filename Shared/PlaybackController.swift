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

    func play(_ url: URL, bufferMs: Int) {
        if url == currentURL, status != .idle, status != .ended {
            if case .failed = status {} else {
                if status == .paused { togglePause() }
                return
            }
        }
        freezeWatch.reset()
        open(url, bufferMs: bufferMs, quiet: false)
    }

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
            playingPolls = 0
        }
        #if canImport(VLCKitSPM)
        let media = VLCMedia(url: url)
        media.addOption(":network-caching=\(bufferMs)")
        player.media = media
        player.play()
        #else
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = Double(bufferMs) / 1000
        player.replaceCurrentItem(with: item)
        player.play()
        #endif
        startPolling()
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
        if player.isPlaying { player.pause() } else { player.play() }
        #else
        if player.rate > 0 { player.pause() } else { player.play() }
        #endif
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        #if canImport(VLCKitSPM)
        player.stop()
        #else
        player.pause()
        player.replaceCurrentItem(with: nil)
        #endif
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
        #if canImport(VLCKitSPM)
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

    #if canImport(VLCKitSPM)
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
