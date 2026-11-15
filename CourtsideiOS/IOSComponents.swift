import SwiftUI
import UIKit

/// Team logo with the abbreviation as a fallback.
struct IOSTeamLogo: View {
    let team: Team
    var size: CGFloat = 30

    var body: some View {
        Group {
            if let url = team.logo {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    fallback
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
    }

    private var fallback: some View {
        Text(team.abbr.isEmpty ? String(team.name.prefix(3)).uppercased() : team.abbr)
            .font(.system(size: size * 0.32, weight: .bold))
            .foregroundStyle(Theme.soft)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.raised))
    }
}

struct IOSLeagueLogo: View {
    @EnvironmentObject var model: AppModel
    let league: League
    var size: CGFloat = 22

    var body: some View {
        if let url = model.leagueLogos[league.id] {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color.clear
            }
            .frame(width: size, height: size)
        } else {
            Image(systemName: league.sport.symbol)
                .font(.system(size: size * 0.6))
                .foregroundStyle(Theme.accent)
                .frame(width: size, height: size)
        }
    }
}

/// Small rounded label: "LIVE", "1080p", "4K", "60 fps".
struct IOSBadge: View {
    let text: String
    var fill: Color = Theme.raised
    var color: Color = Theme.soft

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(fill))
            .fixedSize()
    }
}

struct IOSChannelIcon: View {
    let url: URL?
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    symbol
                }
            } else {
                symbol
            }
        }
        .frame(width: size, height: size)
    }

    private var symbol: some View {
        Image(systemName: "tv")
            .font(.system(size: size * 0.45))
            .foregroundStyle(Theme.muted)
    }
}

/// "1/2": connections in use on the IPTV account. Orange at the limit.
struct IOSConnectionsPill: View {
    let account: AccountInfo?

    var body: some View {
        if let max = account?.maxConnections, max > 0 {
            let active = account?.activeConnections ?? 0
            let full = active >= max
            Label("\(active)/\(max)", systemImage: "person.2.fill")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(full ? Theme.onAccent : Theme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(full ? Theme.accent : Theme.raised))
        }
    }
}

/// A filter chip (sports and leagues on Home).
struct IOSChip<Label: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 36)
                .foregroundStyle(selected ? Theme.bg : Theme.soft)
                .background(Capsule().fill(selected ? Theme.text : Theme.card))
                .overlay(Capsule().stroke(selected ? Color.clear : Theme.border, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct IOSVideoSurface: UIViewRepresentable {
    let view: UIView

    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// The mini player on the game screen. Plays only the stream you tapped, and hands over to full screen without
/// reconnecting. Nothing plays here while Picture in Picture is showing (that would use a second connection).
struct IOSMiniPlayer: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @AppStorage(Prefs.guidePreview) private var enabled = true
    @ObservedObject private var controller = PlaybackController.shared
    @ObservedObject private var pip = PiPManager.shared
    let channel: Channel?
    var onExpand: (() -> Void)?

    private var url: URL? {
        channel.flatMap { model.streamURL(for: $0, hls: !PlaybackController.usesVLC) }
    }

    private var showsVideo: Bool {
        enabled && channel != nil && model.nowPlaying == nil && !pip.active && !DemoData.isOn
    }

    var body: some View {
        ZStack {
            Color.black
            if showsVideo {
                IOSVideoSurface(view: controller.view)
                switch controller.status {
                case .opening, .buffering:
                    ProgressView()
                case .failed:
                    Text("This stream couldn't be opened")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                default:
                    EmptyView()
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: pip.active ? "pip" : "play.rectangle")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.muted)
                    Text(pip.active ? "Playing in picture in picture"
                         : (channel?.name ?? "Tap a stream to play it here. Tap it again for full screen."))
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
            }

            if showsVideo, let onExpand {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: onExpand) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(.black.opacity(0.55)))
                        }
                        .padding(10)
                    }
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onExpand?() }
        .task(id: "\(channel?.id ?? 0)|\(model.nowPlaying == nil)|\(enabled)|\(pip.active)") {
            guard model.nowPlaying == nil, !pip.active, !DemoData.isOn else { return }
            guard enabled, channel != nil, let url else {
                if model.backgroundChannel == nil { controller.stop() }
                return
            }
            controller.play(url, bufferMs: bufferMs)
            model.previewChannel = channel
        }
        .onChange(of: controller.resolution) {
            if showsVideo, let channel, !controller.resolution.isEmpty {
                model.recordQuality(channel.id, controller.resolution)
            }
        }
        .onChange(of: controller.frameRate) {
            if showsVideo, let channel { model.recordFrameRate(channel.id, controller.frameRate) }
        }
        .onAppear { model.miniPlayers += 1 }
        .onDisappear {
            model.miniPlayers -= 1
            if model.nowPlaying == nil { controller.stop() }
        }
    }
}
