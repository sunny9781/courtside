import SwiftUI

/// A list row that turns white when focused, the usual Apple TV look.
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
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(focused ? Theme.bg : Theme.text)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(focused ? Theme.text : (selected ? Theme.raised : Color.clear))
                )
                .scaleEffect(focused ? 1.03 : (configuration.isPressed ? 0.98 : 1))
                .animation(.easeOut(duration: 0.15), value: focused)
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

/// Small rounded label: "LIVE", "1080p", "4K".
struct TVBadge: View {
    let text: String
    var fill: Color = Theme.raised
    var color: Color = Theme.soft

    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(fill))
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

extension Game {
    /// "LIVE · Q3 4:12", "7:30 PM" or "Final".
    var tvStatus: String {
        switch state {
        case .upcoming:
            if let start {
                return Calendar.current.isDateInToday(start)
                    ? start.formatted(date: .omitted, time: .shortened)
                    : start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            }
            return statusText
        case .live, .finished:
            return statusText
        }
    }
}

/// Favourites first, then sports with games today, then the rest, each in your saved order, without hidden ones.
@MainActor
func tvSportOrder(model: AppModel) -> [Sport] {
    let defaults = UserDefaults.standard
    let hidden = Sport.hidden(defaults.string(forKey: Prefs.hiddenSports) ?? "")
    let favs = Set((defaults.string(forKey: Prefs.favoriteSports) ?? "")
        .split(separator: ",").compactMap { Sport(rawValue: String($0)) })
    let order = Sport.ordered(defaults.string(forKey: Prefs.sportOrder) ?? "").filter { !hidden.contains($0) }
    func rank(_ s: Sport) -> Int {
        if favs.contains(s) { return 0 }
        return model.games(for: s).isEmpty ? 2 : 1
    }
    return order.enumerated()
        .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
        .map(\.element)
}

/// Live games first, then upcoming by start time, then finished.
func tvSorted(_ games: [Game]) -> [Game] {
    func rank(_ g: Game) -> Int {
        switch g.state {
        case .live: return 0
        case .upcoming: return 1
        case .finished: return 2
        }
    }
    return games.sorted {
        (rank($0), $0.start ?? .distantFuture) < (rank($1), $1.start ?? .distantFuture)
    }
}
