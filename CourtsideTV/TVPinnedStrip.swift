import SwiftUI

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
            guard model.nowPlaying == nil, !DemoData.isOn,
                  let url = model.streamURL(for: item.channel, hls: !PlaybackController.usesVLC) else { return }
            // Back from full screen this is the same stream, and play() carries on without reconnecting.
            controller.play(url, bufferMs: bufferMs)
            model.checkConnectionsSoon()
        }
        .onChange(of: controller.resolution) {
            if model.nowPlaying == nil, !controller.resolution.isEmpty { model.recordQuality(item.channel.id, controller.resolution) }
        }
        .onChange(of: controller.frameRate) {
            if model.nowPlaying == nil { model.recordFrameRate(item.channel.id, controller.frameRate) }
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
        let next = now.flatMap { n in model.guide[channel.epgID]?.first { $0.start >= n.end } }
        let title = item.gameTitle ?? (now?.title.isEmpty == false ? now!.title : channel.name)
        VStack(spacing: 0) {
            Rectangle().fill(Theme.raised).frame(height: 2)
            HStack(spacing: 18) {
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 17)).foregroundStyle(Theme.accent)
                Text(channel.name).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.soft).lineLimit(1)
                if !controller.resolution.isEmpty { TVBadge(text: controller.resolution) }
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
                if let next {
                    Text("Next: \(next.start.formatted(date: .omitted, time: .shortened))  \(next.title)")
                        .font(.system(size: 19)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, TVLayout.margin + 8)
            .frame(maxHeight: .infinity)
        }
        .frame(height: TVLayout.barHeight)
        .frame(maxWidth: .infinity)
        .background(Theme.bg)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}
