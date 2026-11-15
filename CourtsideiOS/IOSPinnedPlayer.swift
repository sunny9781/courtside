import SwiftUI

/// The player pinned above the tabs. Appears only while something is playing, in the same spot on every screen,
/// and keeps playing as you move between tabs, sports and games.
/// Buttons: collapse (hide the video, keep the sound), full screen, close (stop).
struct IOSPinnedPlayer: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject private var playback = IOSPlayback.shared
    @ObservedObject private var cast = CastManager.shared
    @State private var collapsed = false
    let item: NowPlaying

    var body: some View {
        Group {
            if collapsed {
                collapsedBar
            } else if sizeClass == .regular {
                HStack(alignment: .top, spacing: 16) {
                    video.frame(width: 400)
                    details
                    Spacer(minLength: 0)
                }
                .padding(.horizontal)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    video
                    details
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Theme.bg)
        .task(id: item.channel.id) { start() }
        .onChange(of: cast.deviceName) { start() }
        .onChange(of: playback.resolution) {
            if !playback.resolution.isEmpty { model.recordQuality(item.channel.id, playback.resolution) }
        }
        .onChange(of: playback.frameRate) { model.recordFrameRate(item.channel.id, playback.frameRate) }
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

    private func close() {
        playback.stop()
        model.pinned = nil
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
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                overlayButton("chevron.up") { withAnimation(.easeOut(duration: 0.2)) { collapsed = true } }
                overlayButton("arrow.up.left.and.arrow.down.right") { fullScreen() }
                overlayButton("xmark") { close() }
            }
            .padding(8)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { fullScreen() }
    }

    private var details: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.playerTitle(item)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(item.channel.name).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 6)
            if !playback.resolution.isEmpty { IOSBadge(text: playback.resolution) }
            if playback.frameRate > 0 { IOSBadge(text: PlaybackController.fpsLabel(playback.frameRate)) }
            if item.lineup.count > 1 {
                smallButton("chevron.left") { model.stepPinned(-1) }
                smallButton("chevron.right") { model.stepPinned(1) }
            }
        }
    }

    private var collapsedBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.2.fill").foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.playerTitle(item)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(item.channel.name).font(.caption2).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            smallButton("chevron.down") { withAnimation(.easeOut(duration: 0.2)) { collapsed = false } }
            smallButton("arrow.up.left.and.arrow.down.right") { fullScreen() }
            smallButton("xmark") { close() }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { collapsed = false } }
    }

    private func overlayButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.black.opacity(0.55)))
        }
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
