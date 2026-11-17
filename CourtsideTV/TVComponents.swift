import SwiftUI

enum TVLayout {
    /// Left and right margin on every screen (TVs crop the edges).
    static let margin: CGFloat = 20
    /// The left column on Home while you're on the games: icons and counts only.
    static let compactSidebar: CGFloat = 170
    /// Width of the left column on Home, EPG and Settings.
    /// Width of the player's video at the top.
    static let playerWidth: CGFloat = 448
    /// The text beside the player's video starts this far from the video.
    static let playerGap: CGFloat = 36
    static let sidebar: CGFloat = playerWidth   // same width as the player's video
    /// Height of the player in the bottom-left corner plus equal gaps above and below it: the left panels stop this
    /// far from the bottom while something plays, so they sit on top of the player.
    /// The one-line now-playing bar along the very bottom of the screen, under the player.
    static let barHeight: CGFloat = 46
    static let playerInset: CGFloat = playerWidth * 9 / 16 + margin * 2 + barHeight

    /// A channel-name column wide enough for the longest name on one line (within reason), the same for every row.
    static func nameWidth(_ channels: [Channel]) -> CGFloat {
        min(max(CGFloat(channels.map(\.name.count).max() ?? 0) * 13 + 90, 408), 820)
    }
    static let corner: CGFloat = 20
}

// MARK: Buttons

/// A list row that turns white when focused, the usual Apple TV look. `selected` keeps a grey fill.
struct TVRowButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, selected: selected)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .foregroundStyle(focused ? Theme.bg : Theme.text)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(focused ? Theme.text : (selected ? Theme.raised : Color.clear))
                )
                .scaleEffect(focused ? 1.03 : (configuration.isPressed ? 0.98 : 1))
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// The big Home / EPG / Settings pills in the top bar.
struct TVTabButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, selected: selected)
    }

    private struct Pill: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .font(.system(size: 28, weight: .semibold))
                .padding(.horizontal, 34)
                .frame(height: 70)
                .foregroundStyle(focused ? Theme.bg : (selected ? Theme.text : Theme.muted))
                .background(Capsule().fill(focused ? Theme.text : (selected ? Theme.raised : Color.clear)))
                .scaleEffect(focused ? 1.06 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// A filter chip (league filters on Home). Selected: grey; focused: white.
struct TVChipButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Chip(configuration: configuration, selected: selected)
    }

    private struct Chip: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .padding(.horizontal, 24)
                .frame(height: 58)
                .foregroundStyle(focused ? Theme.bg : (selected ? Theme.text : Theme.soft))
                .background(Capsule().fill(focused ? Theme.text : (selected ? Theme.raised : Color.clear)))
                .overlay(Capsule().stroke(selected || focused ? Color.clear : Theme.border, lineWidth: 2))
                .scaleEffect(focused ? 1.06 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// "‹ Back" in the top-left of a screen. The remote's Back button does the same.
struct TVBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Back", systemImage: "chevron.left")
                .font(.system(size: 24, weight: .semibold))
        }
        .buttonStyle(TVPillButtonStyle())
    }
}

/// A compact pill button (Back, Show more…).
struct TVPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration)
    }

    private struct Pill: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .padding(.horizontal, 28)
                .frame(height: 60)
                .foregroundStyle(focused ? Theme.bg : Theme.text)
                .background(Capsule().fill(focused ? Theme.text : Theme.raised))
                .scaleEffect(focused ? 1.06 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// Text-only button that lights up when focused ("Updated 8:15 PM" in the top bar).
struct TVQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Quiet(configuration: configuration)
    }

    private struct Quiet: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .padding(.horizontal, 22)
                .frame(height: 56)
                .foregroundStyle(focused ? Theme.bg : Theme.muted)
                .background(Capsule().fill(focused ? Theme.text : Color.clear))
                .scaleEffect(focused ? 1.05 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

// MARK: Small pieces

/// "1/2" connections in use on the IPTV account. Orange at the limit.
struct TVConnectionsPill: View {
    let account: AccountInfo?

    var body: some View {
        if let max = account?.maxConnections, max > 0 {
            let active = account?.activeConnections ?? 0
            let full = active >= max
            Label("\(active)/\(max)", systemImage: "person.2.fill")
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .foregroundStyle(full ? Theme.onAccent : Theme.muted)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(Capsule().fill(full ? Theme.accent : Theme.raised))
        }
    }
}

/// Team logo with the abbreviation as a fallback.
struct TVTeamLogo: View {
    let team: Team
    var size: CGFloat = 56

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

/// League logo (from the schedule feed), or the league name in a pill.
struct TVLeagueLogo: View {
    @EnvironmentObject var model: AppModel
    let league: League
    var size: CGFloat = 40

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
                .font(.system(size: size * 0.55))
                .foregroundStyle(Theme.accent)
                .frame(width: size, height: size)
        }
    }
}

/// Small rounded label: "LIVE", "1080p", "4K".
struct TVBadge: View {
    let text: String
    var fill: Color = Theme.raised
    var color: Color = Theme.soft

    var body: some View {
        Text(text)
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(Capsule().fill(fill))
            .fixedSize()
    }
}

/// Channel logo from the provider, or a TV symbol.
struct TVChannelIcon: View {
    let url: URL?
    var size: CGFloat = 64

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
            .font(.system(size: size * 0.4))
            .foregroundStyle(Theme.muted)
    }
}

/// Section heading: "CANADA  3".
struct TVSectionTitle: View {
    let text: String
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(text.uppercased())
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(Theme.muted)
                .kerning(1)
            if let count {
                Text("\(count)")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.muted.opacity(0.7))
            }
        }
    }
}

// MARK: Mini player

struct TVVideoSurface: UIViewRepresentable {
    let view: UIView

    func makeUIView(context: Context) -> UIView {
        // In a container of its own: when the video moves (full screen and back to the player strip) the place
        // it left can't pull it back out, which left the strip black after closing full screen.
        let container = UIView()
        container.backgroundColor = .black
        container.isUserInteractionEnabled = false
        view.isUserInteractionEnabled = false   // clicks go to the player, which shows the info bar
        view.removeFromSuperview()
        view.frame = container.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(view)
        return container
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// The mini player on the game and EPG screens, like the Mac's: plays the stream you're on after a short
/// pause (so moving through a list doesn't open every stream), and hands over to full screen without
/// reconnecting.
struct TVPreview: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @AppStorage(Prefs.guidePreview) private var enabled = true
    @ObservedObject private var controller = PlaybackController.shared
    let channel: Channel?
    var placeholder: String? = nil
    /// Shown (not played) when nothing is playing, e.g. the channel you're on in the EPG.
    var showing: Channel? = nil

    private var url: URL? {
        channel.flatMap { model.streamURL(for: $0, hls: !PlaybackController.usesVLC) }
    }

    private var showsVideo: Bool { enabled && channel != nil && model.nowPlaying == nil && !DemoData.isOn }

    var body: some View {
        ZStack {
            Color.black
            if showsVideo {
                TVVideoSurface(view: controller.view)
                switch controller.status {
                case .opening, .buffering:
                    ProgressView()
                case .failed:
                    Text("Preview unavailable")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.muted)
                default:
                    EmptyView()
                }
            } else {
                VStack(spacing: 14) {
                    TVChannelIcon(url: (channel ?? showing)?.icon, size: 90)
                    if let shown = channel ?? showing {
                        Text(shown.name)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.soft)
                            .lineLimit(1)
                            .padding(.horizontal, 20)
                    }
                    if channel == nil, let placeholder {
                        Text(placeholder)
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: TVLayout.corner))
        .task(id: "\(channel?.id ?? 0)|\(model.nowPlaying == nil)|\(enabled)") {
            guard model.nowPlaying == nil, !DemoData.isOn else { return }
            guard enabled, channel != nil, let url else {
                controller.stop()
                return
            }
            if url == controller.currentURL {
                controller.play(url, bufferMs: bufferMs)
                model.previewChannel = channel
                return
            }
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
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
            if model.nowPlaying == nil && model.backgroundChannel == nil { controller.stop() }
        }
    }
}
