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
            HStack(spacing: 5) {
                Image(systemName: "person.2.fill")
                Text("\(active)/\(max)")
            }
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

/// The mini player (game and EPG screens). Plays only what you tapped, keeps going when you switch tabs, and
/// hands over to full screen without reconnecting. Swiping up to leave the app floats it in Picture in Picture.
struct IOSMiniPlayer: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @AppStorage(Prefs.guidePreview) private var enabled = true
    @ObservedObject private var playback = IOSPlayback.shared
    @ObservedObject private var cast = CastManager.shared
    let channel: Channel?
    var placeholder = "Tap a stream to play it here. Tap it again for full screen."
    var onExpand: (() -> Void)?

    private var showsVideo: Bool {
        enabled && channel != nil && model.nowPlaying == nil && !cast.isCasting && !DemoData.isOn
    }

    var body: some View {
        ZStack {
            Color.black
            if showsVideo {
                IOSVideo()
                if playback.av.pipActive {
                    Label("Playing in picture in picture", systemImage: "pip")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                } else {
                    switch playback.status {
                    case .opening, .buffering:
                        ProgressView()
                    case .failed:
                        Text("This stream couldn't be opened").font(.footnote).foregroundStyle(Theme.muted)
                    default:
                        EmptyView()
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: cast.isCasting ? "tv.and.mediabox" : "play.rectangle")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.muted)
                    Text(cast.deviceName.map { "Connected to \($0). Tap a stream to play it there." }
                         ?? (channel?.name ?? placeholder))
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
        .task(id: "\(channel?.id ?? 0)|\(model.nowPlaying == nil)|\(enabled)|\(cast.isCasting)") {
            guard model.nowPlaying == nil, !DemoData.isOn else { return }
            guard let channel else { return }
            if cast.isCasting {
                // Connected to a Chromecast: the stream goes there.
                if let url = model.streamURL(for: channel, hls: true) {
                    cast.cast(url, title: channel.name, subtitle: "Courtside")
                }
                return
            }
            guard enabled else { return }
            playback.play(channel, model: model, bufferMs: bufferMs)
            model.previewChannel = channel
        }
        .onChange(of: playback.resolution) {
            if showsVideo, let channel, !playback.resolution.isEmpty {
                model.recordQuality(channel.id, playback.resolution)
            }
        }
        .onChange(of: playback.frameRate) {
            if showsVideo, let channel { model.recordFrameRate(channel.id, playback.frameRate) }
        }
        .onAppear { model.miniPlayers += 1 }
        .onDisappear {
            model.miniPlayers -= 1
            // Switching tabs keeps it playing (the next screen picks it up); leaving the game stops it.
            if model.nowPlaying == nil && model.backgroundChannel == nil && !playback.av.pipActive {
                playback.stop()
            }
        }
    }
}
