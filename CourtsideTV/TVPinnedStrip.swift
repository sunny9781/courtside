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
