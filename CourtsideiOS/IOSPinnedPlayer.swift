import SwiftUI

/// The player pinned above the tabs. Appears only while something is playing, in the same spot on every screen,
/// and keeps playing as you move between tabs, sports and games.
/// Under the video: resolution and frame rate, then hide video (keeps the sound), full screen and stop (ends the
/// stream, so it stops using a connection). Drag the handle at the bottom to resize it (it stays 16:9); drag it
/// all the way up to hide the video.
struct IOSPinnedPlayer: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    /// Width as a share of the screen; 0 means the default (full width on iPhone, under half on iPad).
    @AppStorage(Prefs.pinnedVideoScale) private var scale: Double = 0
    @AppStorage(Prefs.pinnedCollapsed) private var collapsed = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject private var playback = IOSPlayback.shared
    @ObservedObject private var cast = CastManager.shared
    @State private var available: CGFloat = 360
    @State private var dragStart: CGFloat?
    let item: NowPlaying

    private var minWidth: CGFloat { min(available, 180) }
    private var videoWidth: CGFloat {
        let share = scale > 0 ? scale : (sizeClass == .regular ? 0.45 : 1)
        return min(available, max(minWidth, available * share))
    }
    /// Title beside the video when there's room, under it otherwise.
    private var titleBeside: Bool { available - videoWidth >= 190 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if collapsed {
                collapsedBar
            } else {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        video
                        buttons
                        if !titleBeside { titles }
                    }
                    .frame(width: videoWidth)
                    if titleBeside {
                        titles.padding(.top, 2)
                        Spacer(minLength: 0)
                    }
                }
                handle
            }
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .background(Theme.bg)
        .onGeometryChange(for: CGFloat.self) { $0.size.width - 32 } action: { available = max(200, $0) }
        .task(id: item.channel.id) { start() }
        .onChange(of: cast.deviceName) { start() }
        .onChange(of: playback.resolution) {
            if !playback.resolution.isEmpty { model.recordQuality(item.channel.id, playback.resolution) }
        }
        .onChange(of: playback.frameRate) { model.recordFrameRate(item.channel.id, playback.frameRate) }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.playerTitle(item)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(2)
            Text(item.channel.name).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
        }
    }

    /// Right under the video.
    private var buttons: some View {
        HStack(spacing: 8) {
            if !playback.resolution.isEmpty { IOSBadge(text: playback.resolution) }
            if playback.frameRate > 0 { IOSBadge(text: PlaybackController.fpsLabel(playback.frameRate)) }
            Spacer(minLength: 4)
            smallButton("rectangle.compress.vertical") { withAnimation(.easeOut(duration: 0.2)) { collapsed = true } }
            smallButton("arrow.up.left.and.arrow.down.right") { fullScreen() }
            smallButton("stop.fill") { stop() }
        }
    }

    /// Drag down for a bigger player, up for a smaller one; past the smallest size it hides the video.
    private var handle: some View {
        Capsule()
            .fill(Theme.muted.opacity(dragStart == nil ? 0.45 : 0.9))
            .frame(width: 44, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if dragStart == nil { dragStart = videoWidth }
                        let width = (dragStart ?? videoWidth) + value.translation.height * 16 / 9
                        scale = Double(min(available, max(minWidth, width)) / available)
                    }
                    .onEnded { value in
                        let width = (dragStart ?? videoWidth) + value.translation.height * 16 / 9
                        dragStart = nil
                        if width < minWidth - 80 { withAnimation(.easeOut(duration: 0.2)) { collapsed = true } }
                    }
            )
    }

    private func start() {
        guard !DemoData.isOn else { return }
        if cast.isCasting {
            playback.stop()
            if let url = model.streamURL(for: item.channel, hls: true) {
                cast.cast(url, title: model.playerTitle(item), subtitle: item.channel.name)
            }
        } else {
            playback.play(item.channel, model: model, bufferMs: bufferMs)
        }
    }

    private func fullScreen() {
        model.play(item.channel, gameTitle: item.gameTitle, lineup: item.lineup)
    }

    /// Ends the stream (frees the connection) and hides the player.
    private func stop() {
        playback.stop()
        model.pinned = nil
        model.checkConnectionsSoon()
    }

    private var video: some View {
        ZStack {
            Color.black
            if cast.isCasting {
                Label("Playing on \(cast.deviceName ?? "Chromecast")", systemImage: "tv.and.mediabox")
                    .font(.footnote).foregroundStyle(Theme.muted)
            } else {
                IOSVideo()
                if playback.av.pipActive {
                    Label("Playing in picture in picture", systemImage: "pip").font(.footnote).foregroundStyle(Theme.muted)
                } else {
                    switch playback.status {
                    case .opening, .buffering: ProgressView()
                    case .failed: Text("This stream couldn't be opened").font(.footnote).foregroundStyle(Theme.muted)
                    default: EmptyView()
                    }
                }
            }
        }
        .frame(width: videoWidth, height: videoWidth * 9 / 16)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { fullScreen() }
    }

    private var collapsedBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.2.fill").foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.playerTitle(item)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(item.channel.name).font(.caption2).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            smallButton("rectangle.expand.vertical") { withAnimation(.easeOut(duration: 0.2)) { collapsed = false } }
            smallButton("arrow.up.left.and.arrow.down.right") { fullScreen() }
            smallButton("stop.fill") { stop() }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { collapsed = false } }
        .gesture(DragGesture(minimumDistance: 12).onEnded { value in
            if value.translation.height > 20 { withAnimation(.easeOut(duration: 0.2)) { collapsed = false } }
        })
    }

    private func smallButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.soft)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.raised))
        }
        .buttonStyle(.plain)
    }
}
