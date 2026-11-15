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

    func makeUIView(context: Context) -> UIView {
        // The video never takes taps, so tapping it shows the controls (and the resolution and frame rate).
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
