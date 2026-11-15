import SwiftUI
import AppKit

/// The player pinned under the top bar. Appears only while something is playing, in the same spot on every screen,
/// and keeps playing as you move between Home, games, EPG and Settings. On a game's screen it's combined with the
/// score (see GameDetailView), so `details` is what sits beside the video.
///
/// Hovering over the video shows a see-through bar along its bottom: resolution and frame rate, then shrink to a
/// slim bar (keeps the sound), full screen, pop out to its own window, and stop (ends the stream, so it stops
/// using a connection). Click the video for full screen.
struct PinnedPlayerBar<Details: View>: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @AppStorage(Prefs.pinnedCollapsed) private var collapsed = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @ObservedObject private var controller = PlaybackController.shared
    @State private var hovering = false
    let item: NowPlaying
    /// True while full screen is showing the stream (the video can only be in one place).
    let hidden: Bool
    /// Drawn as a card in the page (the game screen) rather than a strip under the top bar.
    var card = false
    /// One line for the slim panel (the score on a game screen); otherwise the title.
    var slimTitle: String? = nil
    @ViewBuilder let details: () -> Details

    private let videoHeight: CGFloat = 190

    /// Collapsed, or showing in its own window: the whole panel shrinks to one slim row.
    private var slim: Bool { collapsed || model.poppedOut }

    var body: some View {
        VStack(spacing: 0) {
            if slim {
                slimRow
                    .padding(.horizontal, card ? 16 : 24)
                    .padding(.vertical, card ? 12 : 8)
            } else {
                HStack(alignment: .top, spacing: 22) {
                    video
                    details()
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(.horizontal, card ? 20 : 24)
                .padding(.vertical, card ? 20 : 12)
            }
        }
        .background {
            if card {
                RoundedRectangle(cornerRadius: 20).fill(Theme.card)
            } else {
                Theme.card.overlay(alignment: .bottom) { Rectangle().fill(Theme.raised).frame(height: 1) }
            }
        }
        .task(id: "\(item.channel.id)|\(hidden)") {
            // Already playing this (e.g. coming back from full screen): play() carries on without reconnecting.
            guard !hidden, let url = model.streamURL(for: item.channel, hls: !PlaybackController.usesVLC) else { return }
            controller.play(url, bufferMs: bufferMs)
            model.checkConnectionsSoon()
        }
        .onChange(of: controller.resolution) {
            if !hidden, !controller.resolution.isEmpty { model.recordQuality(item.channel.id, controller.resolution) }
        }
        .onChange(of: controller.frameRate) {
            if !hidden { model.recordFrameRate(item.channel.id, controller.frameRate) }
        }
    }

    private var videoWidth: CGFloat { videoHeight * 16 / 9 }

    private var video: some View {
        ZStack {
            Color.black
            if !hidden && !model.poppedOut {
                VideoSurface(view: controller.view)
                switch controller.status {
                case .opening, .buffering:
                    ProgressView().controlSize(.small)
                case .failed:
                    Text("This stream couldn't be opened").font(.system(size: 11)).foregroundStyle(Theme.muted)
                default:
                    EmptyView()
                }
                // Catches clicks (the video view would swallow them).
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { fullScreen() }
            }
        }
        .frame(width: videoWidth, height: videoHeight)
        .overlay(alignment: .bottom) {
            if hovering { controls.transition(.opacity) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
    }

    private var badges: some View {
        HStack(spacing: 6) {
            if !controller.resolution.isEmpty { Badge(text: controller.resolution).fixedSize() }
            if controller.frameRate > 0 { Badge(text: PlaybackController.fpsLabel(controller.frameRate)).fixedSize() }
        }
    }

    private func buttons(glass: Bool) -> some View {
        HStack(spacing: glass ? 6 : 8) {
            RoundIconButton(symbol: slim ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
                            help: slim ? "Show the player" : "Shrink to a slim bar (keeps playing)", glass: glass) {
                withAnimation(.easeOut(duration: 0.2)) {
                    if model.poppedOut { dismissWindow(id: PopOutPlayer.windowID); collapsed = false } else { collapsed.toggle() }
                }
            }
            RoundIconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Full screen", glass: glass) { fullScreen() }
            RoundIconButton(symbol: model.poppedOut ? "rectangle.inset.filled.and.person.filled" : "macwindow.on.rectangle",
                            help: model.poppedOut ? "Bring the player back into the app" : "Open in its own window", glass: glass) { popOut() }
            RoundIconButton(symbol: "stop.fill", help: "Stop (frees the connection)", glass: glass) { stop() }
        }
    }

    /// Over the bottom of the video while hovering: quality on the left, buttons on the right.
    private var controls: some View {
        HStack(spacing: 6) {
            badges
            Spacer(minLength: 4)
            buttons(glass: true)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .padding(.top, 22)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
    }

    /// Collapsed (or popped out): everything in one slim row.
    private var slimRow: some View {
        HStack(spacing: 12) {
            Image(systemName: model.poppedOut ? "macwindow.on.rectangle" : "speaker.wave.2.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(slimTitle ?? model.playerTitle(item))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(model.poppedOut ? "\(item.channel.name) · playing in its own window" : item.channel.name)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            badges
            Spacer(minLength: 8)
            buttons(glass: false)
        }
    }

    /// Full screen covers the app, or, when the player has its own window, puts that window full screen
    /// (on whichever display it's on) and leaves the app alone.
    private func fullScreen() {
        if model.poppedOut, let window = PopOutPlayer.window {
            window.makeKeyAndOrderFront(nil)
            window.toggleFullScreen(nil)
            return
        }
        model.play(item.channel, gameTitle: item.gameTitle, lineup: item.lineup)
    }

    private func popOut() {
        if model.poppedOut {
            dismissWindow(id: PopOutPlayer.windowID)
        } else {
            model.poppedOut = true          // the bar lets go of the video first
            openWindow(id: PopOutPlayer.windowID)
        }
    }

    private func stop() {
        if model.poppedOut { dismissWindow(id: PopOutPlayer.windowID) }
        controller.stop()
        model.pinned = nil
        model.checkConnectionsSoon()
    }
}

extension PinnedPlayerBar where Details == PinnedInfo {
    init(item: NowPlaying, hidden: Bool) {
        self.init(item: item, hidden: hidden, card: false, slimTitle: nil) { PinnedInfo(item: item) }
    }
}

/// Beside the video everywhere except a game's own screen: what's playing.
struct PinnedInfo: View {
    @EnvironmentObject var model: AppModel
    let item: NowPlaying

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model.playerTitle(item))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
            Text(item.channel.name)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            if let now = model.currentProgramme(item.channel), !now.title.isEmpty {
                Text("On now: \(now.title)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.soft)
                    .lineLimit(2)
            }
        }
        .padding(.top, 4)
    }
}

/// The player in its own window, separate from the app's: move it to another display, resize it, put it full
/// screen there, and keep using the app in its own window. Picking another stream in the app plays it here.
/// Closing the window puts the video back in the app's player.
struct PopOutPlayer: View {
    static let windowID = "player"

    /// The pop-out window, if it's open.
    static var window: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(windowID) == true && $0.isVisible }
    }
    @EnvironmentObject var model: AppModel
    @ObservedObject private var controller = PlaybackController.shared
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var showInfo = true

    var body: some View {
        ZStack {
            Color.black
            if model.poppedOut, model.pinned != nil {
                VideoSurface(view: controller.view)
            }
            if controller.status == .opening || controller.status == .buffering { ProgressView() }
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { NSApp.keyWindow?.toggleFullScreen(nil) }
                .onTapGesture { showInfo.toggle() }
        }
        .overlay(alignment: .bottomLeading) {
            if showInfo, let item = model.pinned {
                HStack(spacing: 8) {
                    Text(model.playerTitle(item)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Text(item.channel.name).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                    if !controller.resolution.isEmpty { Badge(text: controller.resolution) }
                    if controller.frameRate > 0 { Badge(text: PlaybackController.fpsLabel(controller.frameRate)) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.6)))
                .padding(14)
                .task {
                    try? await Task.sleep(for: .seconds(4))
                    showInfo = false
                }
            }
        }
        .frame(minWidth: 480, minHeight: 270)
        .aspectRatio(16 / 9, contentMode: .fit)
        .background(Color.black)
        .navigationTitle(model.pinned.map { model.playerTitle($0) } ?? "Courtside")
        .onAppear { model.poppedOut = true }
        .onDisappear {
            // Give the window a moment to let go of the video before the pinned player takes it back.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                model.poppedOut = false
            }
        }
        .onChange(of: model.pinned == nil) { if model.pinned == nil { dismissWindow(id: Self.windowID) } }
        .onChange(of: model.nowPlaying != nil) { if model.nowPlaying != nil { dismissWindow(id: Self.windowID) } }
    }
}
