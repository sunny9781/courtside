import SwiftUI

enum TVLayout {
    /// Left and right margin on every screen (TVs crop the edges).
    static let margin: CGFloat = 20
    /// Width of the left column on Home, EPG and Settings.
    /// Width of the player's video at the top.
    static let playerWidth: CGFloat = 448
    /// The text beside the player's video starts this far from the video.
    static let playerGap: CGFloat = 36
    static let sidebar: CGFloat = playerWidth   // same width as the player's video
    /// Height of the player in the bottom-left corner plus equal gaps above and below it: the left panels stop this
    /// far from the bottom while something plays, so they sit on top of the player.
    /// The one-line now-playing bar along the very bottom of the screen, under the player.
    static let barHeight: CGFloat = 40
    /// (The panels' lists add their own 20-point padding at the end, so no extra gap here: the space above the player
    /// matches the space to its left.)
    static let playerInset: CGFloat = playerWidth * 9 / 16 + margin + barHeight

    /// The channel column: the same fixed width on every screen (long names scroll on the row you're on).
    static func nameWidth(_ channels: [Channel]) -> CGFloat { TVChannelRow.channelWidth }
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
                SmallLogoImage(url: url, size: size) {
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
            SmallLogoImage(url: url, size: size) {
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
                SmallLogoImage(url: url, size: size) {
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

/// One line of text in a fixed column. On the row you're on (`active`), text too long for the column slides along
/// inside it and back; otherwise it ends in "…". Like the Android TV app's EPG.
struct TVScrollingText: View {
    let text: String
    let font: Font
    var active: Bool
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        Group {
            if active {
                Text(text).font(font).lineLimit(1).fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
                    .offset(x: offset)
                    // minWidth 0: the column keeps its own width, however long the text (it scrolls inside it).
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
                    .clipped()
                    .task(id: "\(text)|\(Int(textWidth))|\(Int(boxWidth))") {
                        offset = 0
                        let distance = textWidth - boxWidth
                        guard distance > 1 else { return }
                        let seconds = Double(distance) / 70
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(1.2))
                            guard !Task.isCancelled else { break }
                            withAnimation(.linear(duration: seconds)) { offset = -distance }
                            try? await Task.sleep(for: .seconds(seconds + 1.2))
                            guard !Task.isCancelled else { break }
                            offset = 0
                        }
                    }
            } else {
                Text(text).font(font).lineLimit(1)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

extension View {
    /// A shortcut at the edge of a screen: pressing this direction (where there's nothing more to move to) switches
    /// to another tab (right on a Home game goes to the EPG; left on the EPG's categories goes to Home).
    func tvEdgeJump(_ direction: MoveCommandDirection, to tab: TVTab) -> some View {
        onMoveCommand { moved in
            if moved == direction { NotificationCenter.default.post(name: .tvSwitchTab, object: tab) }
        }
    }
}
