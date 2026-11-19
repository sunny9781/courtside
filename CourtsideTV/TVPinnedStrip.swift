import SwiftUI
import UIKit

/// The player in the bottom-left corner: shown only while something plays, in the same spot on every screen, and it
/// keeps playing as you move between Home, games, EPG and Settings. Each screen's left panel sits on top of it and
/// the page fills the space to its right. Move down onto the video and click it for full screen. Play/Pause on the
/// remote stops it.
struct TVPinnedStrip: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: TVNav
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @ObservedObject private var controller = PlaybackController.shared
    let item: NowPlaying
    let game: Game?

    var body: some View {
        // Just the video, in the bottom-left corner of every screen (like the Android TV app).
        Button {
            model.play(item.channel, gameTitle: item.gameTitle, lineup: item.lineup)
        } label: {
            ZStack {
                Color.black
                if model.nowPlaying == nil && !DemoData.isOn {
                    TVVideoSurface(view: controller.view)
                }
            }
            .frame(width: TVLayout.playerWidth, height: TVLayout.playerWidth * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: TVLayout.corner))
        }
        .buttonStyle(.card)
        .disabled(nav.tabsFocused)
        .task(id: "\(item.channel.id)|\(model.nowPlaying == nil)") {
            guard model.nowPlaying == nil, !DemoData.isOn else { return }
            // Back from full screen this is the same stream, and play() carries on without reconnecting.
            model.startStream(item.channel, on: controller, bufferMs: bufferMs)
            model.checkConnectionsSoon()
        }
        .onChange(of: controller.resolution) {
            if model.nowPlaying == nil, !controller.resolution.isEmpty { model.recordQuality(item.channel.id, controller.resolution) }
        }
        .onChange(of: controller.frameRate) {
            if model.nowPlaying == nil { model.recordFrameRate(item.channel.id, controller.frameRate) }
        }
        .onChange(of: controller.audio) {
            if model.nowPlaying == nil { model.recordAudio(item.channel.id, controller.audio) }
        }
    }
}

/// What's playing, on one line along the very bottom of the screen: the channel, what's on with its times and
/// progress, and what's next. It never takes focus; pages scroll under it.
struct TVNowPlayingBar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var controller = PlaybackController.shared
    let item: NowPlaying

    var body: some View {
        let channel = item.channel
        let now = model.currentProgramme(channel)
        let title = item.gameTitle ?? (now?.title.isEmpty == false ? now!.title : channel.name)
        VStack(spacing: 0) {
            // The same gap above the line as between the player and the line, so pages scrolling under it have room.
            Color.clear.frame(height: TVLayout.margin)
            Rectangle().fill(Theme.raised).frame(height: 2)
            HStack(spacing: 18) {
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 17)).foregroundStyle(Theme.accent)
                Text(channel.name).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.soft).lineLimit(1)
                if !controller.resolution.isEmpty { TVBadge(text: controller.resolution) }
                if controller.frameRate > 0 { TVBadge(text: PlaybackController.fpsLabel(controller.frameRate)) }
                if !controller.audio.isEmpty { TVBadge(text: controller.audio) }
                if !controller.dynamicRange.isEmpty { TVBadge(text: controller.dynamicRange) }
                Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
                if let now {
                    if !now.title.isEmpty && now.title != title {
                        Text(now.title).font(.system(size: 20)).foregroundStyle(Theme.soft).lineLimit(1)
                    }
                    Text("\(now.start.formatted(date: .omitted, time: .shortened)) – \(now.end.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 19)).foregroundStyle(Theme.muted).fixedSize()
                    ProgressView(value: min(max(Date().timeIntervalSince(now.start) / max(now.end.timeIntervalSince(now.start), 1), 0), 1))
                        .tint(Theme.accent).frame(width: 160)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, TVLayout.margin + 8)
            .frame(maxHeight: .infinity)
            // Sits right at the bottom of the screen: a small gap under the text, no more.
            .padding(.bottom, 4)
        }
        .frame(height: TVLayout.barHeight + TVLayout.margin)
        .frame(maxWidth: .infinity)
        .background(Theme.bg)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

/// Hold Play/Pause on the remote: the player in the corner goes full screen (on Android TV this is a long press of
/// Back, but tvOS keeps holding Back for itself: it goes to the Apple TV Home screen). A short press still stops the
/// player in the corner, and pauses in full screen.
enum TVRemoteHold {
    /// When a hold last started or ended: the press that ends a hold isn't also taken as a short press.
    static var lastHold = Date.distantPast
    static var justHeld: Bool { Date().timeIntervalSince(lastHold) < 0.6 }
}

struct TVPlayPauseHold: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> HoldView {
        let view = HoldView()
        view.action = action
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: HoldView, context: Context) {
        view.action = action
    }

    final class HoldView: UIView {
        var action: (() -> Void)?
        private var recognizer: UILongPressGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            guard let window else { return }
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            hold.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
            hold.minimumPressDuration = 0.6
            hold.cancelsTouchesInView = false
            window.addGestureRecognizer(hold)
            recognizer = hold
        }

        @objc private func held(_ g: UILongPressGestureRecognizer) {
            switch g.state {
            case .began:
                TVRemoteHold.lastHold = Date()
                action?()
            case .ended, .cancelled:
                // Only after a hold began (a short press ends as .failed and stays a short press).
                TVRemoteHold.lastHold = Date()
            default: break
            }
        }
    }
}
