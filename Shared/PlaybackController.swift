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

    func play(_ url: URL, bufferMs: Int) {
        if url == currentURL, status != .idle, status != .ended {
            if case .failed = status {} else {
                if status == .paused { togglePause() }
                return
            }
        }
        currentURL = url
        status = .opening
        onChange?()
        resolution = ""
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

    private static func label(_ height: CGFloat) -> String {
        if height >= 2000 { return "4K" }
        if height >= 1000 { return "1080p" }
        if height >= 700 { return "720p" }
        return "\(Int(height))p"
    }
}
