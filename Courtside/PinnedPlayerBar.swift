import SwiftUI
import AppKit

/// The player pinned under the top bar. Appears only while something is playing, in the same spot on every screen,
/// and keeps playing as you move between Home, games, EPG and Settings. Beside the video: what's playing, with its
/// resolution and frame rate; on a game's screen, the score fills the space to the right.
///
/// Hovering over the video shows see-through buttons along its bottom: shrink to a slim bar (keeps the sound), full screen, pop out to its own window, and stop (ends the stream, so it stops
/// using a connection). Click the video for full screen. Drag the handle under it to resize (it stays 16:9).
struct PinnedPlayerBar<Details: View>: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @AppStorage(Prefs.pinnedCollapsed) private var collapsed = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @ObservedObject private var controller = PlaybackController.shared
    @State private var hovering = false
    @State private var dragStart: Double?
    @AppStorage(Prefs.pinnedVideoHeight) private var videoHeight: Double = 190
    let item: NowPlaying
    /// True while full screen is showing the stream (the video can only be in one place).
    let hidden: Bool
    /// Multiview (2.44) shows the stream in its own tiles while it's open.
    @ObservedObject private var multiview = Multiview.shared
    /// The video is somewhere else (full screen or multiview): it can only be in one place.
    private var away: Bool { hidden || multiview.active }
    /// Drawn as a card in the page (the game screen) rather than a strip under the top bar.
    var card = false
    /// One line for the slim panel (the score on a game screen); otherwise the title.
    var slimTitle: String? = nil
    /// The biggest the video may be (half the window), so the rest of the page never gets pushed off screen.
    var maxVideoHeight: CGFloat = 620
    /// Gets the video's height, so what's beside it can scale to match.
    @ViewBuilder let details: (CGFloat) -> Details

    /// The dragged size, kept within the limits for this window.
    private var height: CGFloat { min(CGFloat(videoHeight), max(Self.minHeight, maxVideoHeight)) }

    /// Smallest size where the quality and buttons still fit on one line over the video.
    static var minHeight: Double { 165 }
    static var maxHeight: Double { 620 }

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
                    // Never taller than the video, so the strip is the same size on every screen.
                    details(height)
                        .frame(maxWidth: .infinity, maxHeight: height, alignment: .topLeading)
                        .clipped()
                }
                .padding(.horizontal, card ? 20 : 24)
                .padding(.top, card ? 20 : 12)
                .padding(.bottom, 2)
                resizeHandle
            }
        }
        .background {
            if card {
                RoundedRectangle(cornerRadius: 20).fill(Theme.card)
            } else {
                Theme.card.overlay(alignment: .bottom) { Rectangle().fill(Theme.raised).frame(height: 1) }
            }
        }
        .task(id: "\(item.channel.id)|\(away)") {
            // Already playing this (e.g. coming back from full screen): play() carries on without reconnecting.
            guard !away, let url = model.streamURL(for: item.channel, hls: !PlaybackController.usesVLC) else { return }
            controller.play(url, bufferMs: bufferMs)
            model.checkConnectionsSoon()
        }
        .onChange(of: controller.resolution) {
            if !away, !controller.resolution.isEmpty { model.recordQuality(item.channel.id, controller.resolution) }
        }
        .onChange(of: controller.frameRate) {
            if !away { model.recordFrameRate(item.channel.id, controller.frameRate) }
        }
        .onChange(of: controller.audio) {
            if !away { model.recordAudio(item.channel.id, controller.audio) }
        }
        .onChange(of: controller.soundHeard) {
            if !away, controller.soundHeard { model.soundHeard(item.channel.id) }
        }
    }

    private var videoWidth: CGFloat { height * 16 / 9 }

    private var video: some View {
        ZStack {
            Color.black
            if !away && !model.poppedOut {
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
        .frame(width: videoWidth, height: height)
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
            if !controller.audio.isEmpty { Badge(text: controller.audio).fixedSize() }
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

    /// Over the bottom of the video while hovering: the buttons, on the right.
    private var controls: some View {
        HStack(spacing: 6) {
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

    /// Drag down for a bigger player, up for a smaller one (it stays 16:9). Past the smallest size it shrinks to
    /// the slim bar.
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
                        if dragStart == nil { dragStart = Double(height) }
                        videoHeight = min(Double(max(Self.minHeight, maxVideoHeight)),
                                          max(Self.minHeight, (dragStart ?? videoHeight) + value.translation.height))
                    }
                    .onEnded { value in
                        if (dragStart ?? videoHeight) + value.translation.height < Self.minHeight - 40 {
                            withAnimation(.easeOut(duration: 0.2)) { collapsed = true }
                        }
                        dragStart = nil
                    }
            )
            .help("Drag to resize the player")
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

extension PinnedPlayerBar where Details == PinnedDetails {
    /// On a game's screen (while one of its streams plays), pass the game: its score fills the space on the right.
    init(item: NowPlaying, hidden: Bool, game: Game? = nil, maxVideoHeight: CGFloat = 620) {
        self.init(item: item, hidden: hidden, card: false, slimTitle: game.map { GameScorePanel(game: $0).slimScore },
                  maxVideoHeight: maxVideoHeight) { height in
            PinnedDetails(item: item, game: game, height: height)
        }
    }
}

/// Beside the video: what's playing, and on a game's screen the score and game info to the right of it.
struct PinnedDetails: View {
    let item: NowPlaying
    let game: Game?
    let height: CGFloat

    @State private var width: CGFloat = 900

    /// Everything stays; it just gets smaller to fit. The full-size layout needs about 245 points of height and,
    /// with the score, about 900 of width.
    private var scale: CGFloat {
        let byHeight = height / 245
        let byWidth = game == nil ? 1 : width / 900
        return min(1, max(0.45, min(byHeight, byWidth)))
    }

    var body: some View {
        Group {
            if let game {
                HStack(alignment: .top, spacing: 26 * scale) {
                    PinnedInfo(item: item, scale: scale)
                        .frame(width: 260 * scale, alignment: .topLeading)
                    Rectangle().fill(Theme.raised).frame(width: 1)
                    GameScorePanel(game: game, scale: scale)
                }
            } else {
                PinnedInfo(item: item, scale: min(1, height / 245))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// What's playing: title, channel, resolution and frame rate, and what's on now.
struct PinnedInfo: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var controller = PlaybackController.shared
    let item: NowPlaying
    /// Below 1 when there's less room beside the video.
    var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: max(3, 5 * scale)) {
            Text(model.playerTitle(item))
                .font(.system(size: max(12, 17 * scale), weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(item.channel.name)
                .font(.system(size: max(10, 12 * scale)))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            if !controller.resolution.isEmpty || controller.frameRate > 0 {
                HStack(spacing: 6) {
                    if !controller.resolution.isEmpty { Badge(text: controller.resolution).fixedSize() }
                    if controller.frameRate > 0 { Badge(text: PlaybackController.fpsLabel(controller.frameRate)).fixedSize() }
            if !controller.audio.isEmpty { Badge(text: controller.audio).fixedSize() }
                }
            }
            // Like the TVs' now-playing bar: what's on with its times and progress, and what's next.
            if let now = model.currentProgramme(item.channel) {
                let next = model.guide[item.channel.epgID]?.first { $0.start >= now.end }
                if !now.title.isEmpty && (item.gameTitle == nil || now.title != item.gameTitle) {
                    Text(now.title)
                        .font(.system(size: max(10, 12 * scale)))
                        .foregroundStyle(Theme.soft)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    Text("\(now.start.formatted(date: .omitted, time: .shortened)) – \(now.end.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: max(10, 11 * scale)))
                        .foregroundStyle(Theme.muted)
                        .fixedSize()
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        let total = max(now.end.timeIntervalSince(now.start), 1)
                        ProgressView(value: min(max(context.date.timeIntervalSince(now.start) / total, 0), 1))
                            .progressViewStyle(.linear)
                            .tint(Theme.accent)
                            .frame(maxWidth: 160)
                    }
                }
                if let next, !next.title.isEmpty {
                    Text("Next \(next.start.formatted(date: .omitted, time: .shortened))  \(next.title)")
                        .font(.system(size: max(10, 11 * scale)))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                // A game on now: jump to all of its streams.
                if item.gameTitle == nil, let gameID = model.guideLinks[Matcher.linkKey(item.channel.epgID, now.start)] {
                    Button("All streams for this game") {
                        NotificationCenter.default.post(name: .openGame, object: gameID)
                    }
                    .buttonStyle(GhostButtonStyle())
                    .padding(.top, 2)
                }
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
                    if !controller.audio.isEmpty { Badge(text: controller.audio) }
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
