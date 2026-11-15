import SwiftUI

/// The player pinned under the top bar. Appears only while something is playing, in the same spot on every screen,
/// and keeps playing as you move between Home, games, EPG and Settings.
/// Click the video for full screen (or double-click); collapse hides the video but keeps the sound; close stops it.
struct PinnedPlayerBar: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @ObservedObject private var controller = PlaybackController.shared
    @State private var collapsed = false
    let item: NowPlaying
    /// True while full screen is showing the stream (the video can only be in one place).
    let hidden: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            if !collapsed { video }

            VStack(alignment: .leading, spacing: 5) {
                Text(model.playerTitle(item))
                    .font(.system(size: collapsed ? 14 : 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(item.channel.name)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    if !controller.resolution.isEmpty { Badge(text: controller.resolution) }
                    if controller.frameRate > 0 { Badge(text: PlaybackController.fpsLabel(controller.frameRate)) }
                    if item.lineup.count > 1 {
                        let position = (item.lineup.firstIndex(where: { $0.id == item.channel.id }) ?? 0) + 1
                        Text("\(position) of \(item.lineup.count)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                    }
                }
                if !collapsed, let now = model.currentProgramme(item.channel), item.gameTitle != nil, !now.title.isEmpty {
                    Text("On now: \(now.title)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.soft)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if item.lineup.count > 1 {
                    RoundIconButton(symbol: "chevron.up", help: "Previous stream") { model.stepPinned(-1) }
                    RoundIconButton(symbol: "chevron.down", help: "Next stream") { model.stepPinned(1) }
                }
                RoundIconButton(symbol: controller.status == .paused ? "play.fill" : "pause.fill",
                                help: controller.status == .paused ? "Play" : "Pause") { controller.togglePause() }
                RoundIconButton(symbol: collapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
                                help: collapsed ? "Show the video" : "Hide the video (keeps playing)") {
                    withAnimation(.easeOut(duration: 0.2)) { collapsed.toggle() }
                }
                RoundIconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Full screen") { fullScreen() }
                RoundIconButton(symbol: "xmark", help: "Stop") { close() }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, collapsed ? 8 : 12)
        .background(Theme.card)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.raised).frame(height: 1) }
        .task(id: "\(item.channel.id)|\(hidden)") {
            guard !hidden, let url = model.streamURL(for: item.channel, hls: !PlaybackController.usesVLC) else { return }
            if url == controller.currentURL {
                controller.play(url, bufferMs: bufferMs)   // already playing: carries on, no reconnect
                return
            }
            controller.play(url, bufferMs: bufferMs)
        }
        .onChange(of: controller.resolution) {
            if !hidden, !controller.resolution.isEmpty { model.recordQuality(item.channel.id, controller.resolution) }
        }
        .onChange(of: controller.frameRate) {
            if !hidden { model.recordFrameRate(item.channel.id, controller.frameRate) }
        }
    }

    private var video: some View {
        ZStack {
            Color.black
            if !hidden {
                VideoSurface(view: controller.view)
                switch controller.status {
                case .opening, .buffering:
                    ProgressView().controlSize(.small)
                case .failed:
                    Text("This stream couldn't be opened").font(.system(size: 11)).foregroundStyle(Theme.muted)
                default:
                    EmptyView()
                }
            }
            // Catches clicks (the video view would swallow them).
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { fullScreen() }
                .onTapGesture { fullScreen() }
        }
        .frame(width: 288, height: 162)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .help("Click for full screen")
    }

    private func fullScreen() {
        model.play(item.channel, gameTitle: item.gameTitle, lineup: item.lineup)
    }

    private func close() {
        controller.stop()
        model.pinned = nil
    }
}
