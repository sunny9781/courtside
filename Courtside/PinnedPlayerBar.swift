import SwiftUI
import AppKit

/// The player pinned under the top bar. Appears only while something is playing, in the same spot on every screen,
/// and keeps playing as you move between Home, games, EPG and Settings. On a game's screen it's combined with the
/// score (see GameDetailView), so `details` is what sits beside the video.
///
/// Under the video: resolution and frame rate, then hide video (keeps the sound), full screen, pop out to its own
/// window, and stop (ends the stream, so it stops using a connection). Drag the bottom edge to make it bigger or
/// smaller; it stays 16:9. Click the video for full screen.
struct PinnedPlayerBar<Details: View>: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @AppStorage(Prefs.pinnedVideoHeight) private var videoHeight: Double = 162
    @AppStorage(Prefs.pinnedCollapsed) private var collapsed = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @ObservedObject private var controller = PlaybackController.shared
    @State private var dragStart: Double?
    let item: NowPlaying
    /// True while full screen is showing the stream (the video can only be in one place).
    let hidden: Bool
    /// Drawn as a card in the page (the game screen) rather than a strip under the top bar.
    var card = false
    @ViewBuilder let details: () -> Details

    static var minHeight: Double { 100 }
    static var maxHeight: Double { 620 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 22) {
                if collapsed {
                    controls(compact: true)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        video
                        controls(compact: false)
                    }
                    .frame(width: videoWidth)
                }
                details()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, card ? 20 : 24)
            .padding(.top, card ? 20 : 12)
            .padding(.bottom, collapsed ? (card ? 20 : 10) : 4)

            if !collapsed { resizeHandle }
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
            if model.poppedOut {
                VStack(spacing: 10) {
                    Image(systemName: "macwindow.on.rectangle").font(.system(size: 22)).foregroundStyle(Theme.muted)
                    Text("Playing in its own window").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Button("Bring it back") { dismissWindow(id: PopOutPlayer.windowID) }
                        .buttonStyle(GhostButtonStyle())
                }
            } else if !hidden {
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
                    .help("Click for full screen")
            }
        }
        .frame(width: videoWidth, height: videoHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Under the video: quality on the left, buttons on the right. Collapsed, the same buttons sit in a small pill.
    private func controls(compact: Bool) -> some View {
        HStack(spacing: 8) {
            if compact {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
            }
            if !controller.resolution.isEmpty { Badge(text: controller.resolution) }
            if controller.frameRate > 0 { Badge(text: PlaybackController.fpsLabel(controller.frameRate)) }
            if !compact { Spacer(minLength: 4) }
            RoundIconButton(symbol: collapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
                            help: collapsed ? "Show the video" : "Hide the video (keeps playing)") {
                withAnimation(.easeOut(duration: 0.2)) { collapsed.toggle() }
            }
            RoundIconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Full screen") { fullScreen() }
            RoundIconButton(symbol: model.poppedOut ? "rectangle.inset.filled.and.person.filled" : "macwindow.on.rectangle",
                            help: model.poppedOut ? "Bring the player back" : "Pop out to its own window") { popOut() }
            RoundIconButton(symbol: "stop.fill", help: "Stop (frees the connection)") { stop() }
        }
        .padding(compact ? 8 : 0)
        .background {
            if compact { Capsule().fill(Theme.raised.opacity(0.6)) }
        }
    }

    /// Drag down for a bigger player, up for a smaller one.
    private var resizeHandle: some View {
        Capsule()
            .fill(Theme.muted.opacity(dragStart == nil ? 0.45 : 0.9))
            .frame(width: 44, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 16)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStart == nil { dragStart = videoHeight }
                        videoHeight = min(Self.maxHeight, max(Self.minHeight, (dragStart ?? videoHeight) + value.translation.height))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .help("Drag to resize the player")
    }

    private func fullScreen() {
        if model.poppedOut { dismissWindow(id: PopOutPlayer.windowID) }
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
        self.init(item: item, hidden: hidden, card: false) { PinnedInfo(item: item) }
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

/// The player in its own window (resizable, and can go full screen on another display).
/// Closing the window puts the video back in the pinned player.
struct PopOutPlayer: View {
    static let windowID = "player"
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
