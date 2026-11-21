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
    /// "HDR10", "HLG", "Dolby Vision" when the stream is HDR (Apple TV's HDR player only; VLC doesn't say).
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
    #if os(tvOS) && canImport(KSPlayer)
    /// Apple TV: 4K channels play with the HDR player (KSPlayer, see HDRPlayer), in the same view, so HDR reaches the
    /// TV as HDR (VLC turns it into a dark standard-range picture). Everything else stays on VLC.
    private let hdr = HDRPlayer()
    /// Streams the HDR player couldn't show this session: they go straight to VLC next time.
    private var hdrFailed: Set<URL> = []
    #endif
    #if os(tvOS)
    /// The current stream plays with the HDR player.
    @Published private(set) var usesHDRPlayer = false
    /// What the TV should switch to for it (frame rate, HDR), from the stream itself; applied in full screen.
    @Published private(set) var displayCriteria: AVDisplayCriteria?
    #endif
    #else
    private let player = AVPlayer()
    private let playerLayer = AVPlayerLayer()
    #endif

    /// Apple TV has the HDR player (KSPlayer) for 4K.
    static var hasHDRPlayer: Bool {
        #if os(tvOS) && canImport(KSPlayer)
        return true
        #else
        return false
        #endif
    }

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
    /// (Not called any more since 2.5: hiccups are waited out and dropped streams reconnect.)
    var onRepeatedFreezing: (() -> Void)?
    /// When the stream dropped after showing a picture and started being reopened (nil while it plays).
    private var droppedSince: Date?
    private var lastReconnect = Date.distantPast
    private let freezeWatch = FreezeWatch()
    private var lastBufferMs = 2000
    /// The next stream, waiting for the old one's connection to close (see open).
    private var pendingOpen: DispatchWorkItem?

    /// `hdrPlayer`: play with the HDR player (Apple TV, 4K channels), falling back to VLC on the same stream if it
    /// shows nothing.
    func play(_ url: URL, bufferMs: Int, hdrPlayer: Bool = false) {
        if url == currentURL, status != .idle, status != .ended {
            if case .failed = status {} else {
                if status == .paused { togglePause() }
                return
            }
        }
        freezeWatch.reset()
        droppedSince = nil
        StreamStats.shared.begin(url)
        #if os(tvOS) && canImport(KSPlayer)
        wantHDR = hdrPlayer && !hdrFailed.contains(url)
        #endif
        open(url, bufferMs: bufferMs, quiet: false)
    }

    #if os(tvOS) && canImport(KSPlayer)
    private var wantHDR = false
    #endif

    /// The stream dropped after it had shown a picture (the provider closed it, or the network went): open the same
    /// stream again instead of stopping, every 3 seconds for up to 2 minutes, showing it as buffering. The old
    /// connection is already gone, so this never makes two. False for a stream that never showed a picture (a
    /// stream that doesn't work, which should fail as before) or after 2 minutes of trying.
    private func reconnectAfterDrop() -> Bool {
        guard !resolution.isEmpty, currentURL != nil else { return false }
        let now = Date()
        if droppedSince == nil { StreamStats.shared.dropped() }
        let since = droppedSince ?? now
        droppedSince = since
        guard now.timeIntervalSince(since) < 120 else { return false }
        status = .buffering
        if now.timeIntervalSince(lastReconnect) >= 3 {
            lastReconnect = now
            restartQuietly()
        }
        return true
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
            audio = ""
            dynamicRange = ""
            playingPolls = 0
        }
        // One connection at a time: close the old stream first and give the provider a moment to see it gone
        // before opening the next, so switching (or flipping quickly through channels) never counts as two.
        // Flipping fast only opens the channel you stop on.
        pendingOpen?.cancel()
        #if os(tvOS) && canImport(KSPlayer)
        let closingHDR = hdr.isOpen
        #else
        let closingHDR = false
        #endif
        let hadStream = closeCurrent()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.currentURL == url else { return }
            self.pendingOpen = nil
            ConnLog.add("Opened \(ConnLog.stream(url))\(quiet ? " again (it froze)" : "")")
            #if canImport(VLCKitSPM)
            #if os(tvOS) && canImport(KSPlayer)
            self.usesHDRPlayer = self.wantHDR
            self.displayCriteria = nil
            if self.wantHDR {
                self.hdr.onDisplayCriteria = { [weak self] criteria in
                    guard let self, self.usesHDRPlayer else { return }
                    self.displayCriteria = criteria
                }
                self.hdr.open(url, bufferMs: bufferMs, in: self.view)
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
        // The HDR player's connection closes from its own thread: give it a little longer.
        DispatchQueue.main.asyncAfter(deadline: .now() + (closingHDR ? 1.0 : (hadStream ? 0.4 : 0)), execute: work)
        startPolling()
    }

    /// Closes whatever stream is open (its network connection included). True if one was.
    @discardableResult
    private func closeCurrent() -> Bool {
        #if canImport(VLCKitSPM)
        var had = false
        #if os(tvOS) && canImport(KSPlayer)
        if hdr.isOpen {
            hdr.close()
            displayCriteria = nil
            had = true
        }
        #endif
        guard player.media != nil else {
            if had { ConnLog.add("Closed \(ConnLog.stream(currentURL)) (HDR player)") }
            return had
        }
        ConnLog.add("Closed \(ConnLog.stream(player.media?.url))")
        player.stop()
        player.media = nil
        return true
        #else
        guard player.currentItem != nil else { return false }
        ConnLog.add("Closed \(ConnLog.stream((player.currentItem?.asset as? AVURLAsset)?.url))")
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
        #if os(tvOS) && canImport(KSPlayer)
        play(url, bufferMs: bufferMs, hdrPlayer: wantHDR)
        #else
        play(url, bufferMs: bufferMs)
        #endif
    }

    func togglePause() {
        #if canImport(VLCKitSPM)
        #if os(tvOS) && canImport(KSPlayer)
        if usesHDRPlayer {
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
        StreamStats.shared.end()
        timer?.invalidate()
        timer = nil
        pendingOpen?.cancel()
        pendingOpen = nil
        closeCurrent()
        currentURL = nil
        #if os(tvOS)
        usesHDRPlayer = false
        #endif
        status = .idle
        onChange?()
    }

    private func startPolling() {
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

    private func poll() {
        // Between closing one stream and opening the next there's nothing to look at.
        if pendingOpen != nil { return }
        #if canImport(VLCKitSPM)
        #if os(tvOS) && canImport(KSPlayer)
        if usesHDRPlayer {
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
            if !reconnectAfterDrop() { status = .failed("This stream couldn't be opened. Try another stream for this game.") }
        case .ended:
            if !reconnectAfterDrop() { status = .ended }
        case .stopped:
            if status == .playing, !reconnectAfterDrop() { status = .ended }
        default:
            break
        }
        if status == .playing { droppedSince = nil }
        let size = player.videoSize
        if size.height > 0 { resolution = Self.label(size.height) }
        // Hiccups are waited out with the connection open; only 10 seconds without progress reopens the stream.
        let watching = !resolution.isEmpty && (status == .playing || status == .buffering || status == .opening)
        switch freezeWatch.check(progress: Double(player.time.intValue), watching: watching) {
        case .restart: StreamStats.shared.froze(); restartQuietly()
        case .skip: onRepeatedFreezing?()
        case .none: break
        }
        // Frame rate: asked once per stream, after it has been playing for 2 seconds (asking VLC for track
        // details while a stream is still starting up can crash).
        if status == .playing {
            playingPolls += 1
            if playingPolls == 4 && frameRate == 0, let fps = Self.videoFrameRate(player.media) { frameRate = fps }
            // Sound: asked every 2 seconds until VLC knows it. Still nothing after 8 seconds of picture: "No sound"
            // (2.17, a dead audio feed), replaced if the sound turns up later.
            if playingPolls >= 4 && playingPolls % 4 == 0 && (audio.isEmpty || audio == StreamSections.noSound),
               let sound = Self.soundLabel(player.media) { audio = sound }
            if playingPolls == 16 && audio.isEmpty { audio = StreamSections.noSound }
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

    #if os(tvOS) && canImport(KSPlayer)
    /// The HDR player (4K channels): its state, size, frame rate and sound. If it shows no picture within 7 seconds
    /// (or fails before showing one), it is closed and, once its connection is gone, the same stream opens on VLC.
    private func pollHDR() {
        // (Not while reopening a stream that dropped: that one has worked, so it stays on the HDR player.)
        let noPicture = !hdr.hasShownPicture && droppedSince == nil
        if noPicture && (hdr.state == .failed || Date().timeIntervalSince(hdr.openedAt) > 7) {
            if let url = currentURL {
                hdrFailed.insert(url)
                wantHDR = false
                open(url, bufferMs: lastBufferMs, quiet: false)   // closes the HDR player first
            }
            return
        }
        switch hdr.state {
        case .opening: status = .opening
        case .buffering: status = .buffering
        case .playing: status = .playing
        case .paused: status = .paused
        case .ended:
            if !reconnectAfterDrop() { status = .ended }
        case .failed:
            if !reconnectAfterDrop() { status = .failed("This stream couldn't be opened. Try another stream for this game.") }
        }
        if status == .playing { droppedSince = nil }
        let height = hdr.videoHeight
        if height > 0 { resolution = Self.label(height) }
        let watching = !resolution.isEmpty && (status == .playing || status == .buffering)
        switch freezeWatch.check(progress: hdr.time, watching: watching) {
        case .restart: StreamStats.shared.froze(); restartQuietly()
        case .skip: onRepeatedFreezing?()
        case .none: break
        }
        if status == .playing {
            playingPolls += 1
            if playingPolls >= 4 && frameRate == 0 {
                let fps = hdr.frameRate
                if fps > 0 { frameRate = fps }
            }
            if playingPolls >= 4 && (audio.isEmpty || audio == StreamSections.noSound), let sound = hdr.sound, !sound.isEmpty { audio = sound }
            if playingPolls == 16 && audio.isEmpty { audio = StreamSections.noSound }
            if playingPolls >= 4 && dynamicRange.isEmpty, let range = hdr.dynamicRangeLabel { dynamicRange = range }
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
