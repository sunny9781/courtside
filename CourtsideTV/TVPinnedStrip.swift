import SwiftUI

/// The player under the top bar, like the Mac and iPhone: shown only while something plays, in the same spot on
/// every screen, and it keeps playing as you move between Home, games, EPG and Settings. Beside the video: what's
/// playing with its resolution and frame rate, and the score when it's a game. Move up onto the video and click it
/// for full screen (it can't take focus straight from the tabs, so pressing down from them still lands on the
/// page). Play/Pause on the remote stops it.
struct TVPinnedStrip: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: TVNav
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @ObservedObject private var controller = PlaybackController.shared
    let item: NowPlaying
    let game: Game?

    var body: some View {
        HStack(alignment: .top, spacing: TVLayout.playerGap) {
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

            VStack(alignment: .leading, spacing: 8) {
                Text(model.playerTitle(item))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(item.channel.name)
                    .font(.system(size: 21))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    if !controller.resolution.isEmpty { TVBadge(text: controller.resolution) }
                    if controller.frameRate > 0 { TVBadge(text: PlaybackController.fpsLabel(controller.frameRate)) }
                }
                Spacer(minLength: 0)
                Text("Move up to the video and click for full screen · Play/Pause stops")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.muted.opacity(0.8))
            }
            .frame(maxWidth: game == nil ? .infinity : 520, alignment: .leading)

            if let game {
                Rectangle().fill(Theme.raised).frame(width: 2)
                score(game)
            }
            Spacer(minLength: 0)
        }
        .frame(height: TVLayout.playerWidth * 9 / 16)
        .padding(.horizontal, TVLayout.margin)
        .padding(.vertical, 18)
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

    private func score(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(game.headerText)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(game.state == .live ? Theme.accent : Theme.soft)
            if game.isEvent && !game.hasSides {
                Text(game.eventTitle)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
            } else {
                teamLine(game.away, game: game)
                teamLine(game.home, game: game)
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
    }

    private func teamLine(_ team: Team, game: Game) -> some View {
        HStack(spacing: 16) {
            TVTeamLogo(team: team, size: 50)
            Text(team.name)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 12)
            if game.state != .upcoming {
                Text(team.score)
                    .font(.system(size: team.hasLongScore ? 26 : 40, weight: .bold).monospacedDigit())
                    .foregroundStyle(game.scoreColor(team))
                    .lineLimit(1)
            }
        }
    }
}
