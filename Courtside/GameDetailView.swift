import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.hideSD) private var hideSD = true
    @State private var showLocal = false
    @AppStorage(Prefs.showForeignStreams) private var showForeign = false
    /// The filter box in the top bar.
    @Binding var search: String
    @State private var listWidth: CGFloat = 800
    /// Sections folded shut (4K, USA, Other…), by name.
    @State private var folded: Set<String> = []
    let game: Game
    let onBack: () -> Void

    private var allStreams: [StreamMatch] {
        let all = model.matches[game.id] ?? []
        return hideSD ? all.filter { $0.quality != "SD" } : all
    }

    /// 4K, PPV for fights, the league's own channels, home-country broadcasters, other countries (see
    /// StreamSections), filtered by the search field and the foreign-language toggle.
    private var listing: StreamSections.Result {
        StreamSections.build(allStreams, league: game.league, search: search)
    }

    private var sections: [StreamSections.Section] { listing.sections }

    /// Everything showing, in on-screen order: what up/down flips through while watching.
    private var streams: [StreamMatch] {
        sections.flatMap(\.streams) + (showForeign ? listing.foreign.flatMap(\.streams) : [])
            + (showLocal ? listing.extras : [])
    }

    private var title: String { game.title }

    /// The stream in the pinned player, if it's one of this game's.
    private var previewChannel: Channel? {
        guard let pinned = model.pinned?.channel, allStreams.contains(where: { $0.channel.id == pinned.id }) else { return nil }
        return pinned
    }

    /// Click: play in the pinned player at the top.
    private func preview(_ channel: Channel) {
        model.pin(channel, gameTitle: title, lineup: streams.map(\.channel))
    }

    /// Double-click: full screen.
    private func watch(_ channel: Channel) {
        model.pin(channel, gameTitle: title, lineup: streams.map(\.channel))
        model.play(channel, gameTitle: title, lineup: streams.map(\.channel))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fixed at the top: the player and score (Back is in the top bar). Only the streams scroll.
            if !model.pinnedIsFrom(gameID: game.id) {
                hero
                    .padding(.horizontal, 32)
                    .padding(.top, 20)
                    .padding(.bottom, 16)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    if listing.sections.isEmpty && listing.foreign.isEmpty {
                        Banner(text: search.isEmpty ? "No channels on your provider matched this game yet. If you know which channel has it, find it in the EPG."
                                                    : "No streams match \"\(search)\".",
                               icon: "magnifyingglass")
                    }

                    // The search box sits at the right end of the first section's line.
                    ForEach(listing.sections) { sectionView($0) }

                    // Foreign-language countries, folded into one group.
                    if !listing.foreign.isEmpty {
                        groupHeader("Foreign streams", count: listing.foreignCount, open: showForeign) {
                            showForeign.toggle()
                        }
                        if showForeign {
                            ForEach(listing.foreign) { sectionView($0) }
                                .padding(.leading, 18)
                        }
                    }

                    // Local stations and "usually on" guesses, at the very bottom.
                    if !listing.extras.isEmpty {
                        groupHeader("Local stations and likely channels", count: listing.extras.count, open: showLocal) {
                            showLocal.toggle()
                        }
                        if showLocal {
                            grid(listing.extras)
                                .padding(.leading, 18)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { listWidth = $0 }
                .padding(.horizontal, 32)
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            // Opening a game plays its first stream in the pinned player, unless one of its streams already is.
            if previewChannel == nil, let first = streams.firstToPlay(model.measuredQuality) { preview(first.channel) }
        }
    }

    /// A section: its name (click to fold it) and its streams.


    private func sectionView(_ section: StreamSections.Section) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if folded.contains(section.name) { folded.remove(section.name) } else { folded.insert(section.name) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(folded.contains(section.name) ? 0 : 90))
                    Text(section.name.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.soft)
                    Text("\(section.streams.count)")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Theme.muted)
                .padding(.leading, 4)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !folded.contains(section.name) {
                grid(section.streams)
            }
        }
    }

    /// A bigger header for the groups at the bottom (foreign languages, local stations).
    private func groupHeader(_ title: String, count: Int, open: Bool, toggle: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { toggle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(open ? 90 : 0))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("\(count)")
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    /// Not lazy: a lazy grid guesses row heights as cards wrap, which made the page scroll on past the last
    /// stream. A game only has a few dozen streams.
    /// Each card is as wide as its text (within limits), so more fit on a row. Not lazy: a lazy grid guesses row
    /// heights, which made the page scroll on past the last stream.
    private func grid(_ list: [StreamMatch]) -> some View {
        FlowLayout(spacing: 10, minItemWidth: 200, maxItemWidth: 460, uniformHeight: true) {
            ForEach(list) { match in
                StreamRow(match: match, previewing: match.channel.id == previewChannel?.id,
                          onSelect: { preview(match.channel) },
                          onWatch: { watch(match.channel) })
            }
        }
    }

    /// The score and game info. The player is in the strip under the top bar, like on every other screen.
    /// The score and game info. While one of this game's streams plays, they're in the player strip instead
    /// (beside the video), so the page is just the streams.
    @ViewBuilder
    private var hero: some View {
        if !model.pinnedIsFrom(gameID: game.id) {
            GameScorePanel(game: game)
                .frame(height: 200)
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 20).fill(Theme.card))
        }
    }
}

/// A stream card for the grid: full name and why it matched (wrapping, never cut off) and badges.
/// Click plays it in the mini player (the card lights up); double-click goes full screen.
struct StreamRow: View {
    @EnvironmentObject var model: AppModel
    let match: StreamMatch
    let previewing: Bool
    let onSelect: () -> Void
    let onWatch: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            CardButton(radius: 10, action: onSelect) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(match.channel.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(previewing ? Theme.accent : Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if !match.channel.categoryName.isEmpty {
                            Label(match.channel.categoryName, systemImage: "folder")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.soft)
                                .labelStyle(.titleAndIcon)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 4) {
                        if !match.quality.isEmpty {
                            Badge(text: match.quality)
                        }
                        if let fps = model.measuredFrameRate[match.channel.id] {
                            Badge(text: PlaybackController.fpsLabel(fps))
                        }
                    }
                    .fixedSize()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 54, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(previewing ? Theme.accent : Color.clear, lineWidth: 1.5))
            }
            .simultaneousGesture(TapGesture(count: 2).onEnded { onWatch() })
            .help("Click to play in the mini player, double-click for full screen")
        }
    }
}


/// A game's score, box score, venue, start time and broadcasters: on the game screen, or beside the video in the
/// player strip while one of the game's streams plays.
struct GameScorePanel: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    /// Below 1 in the player strip, where everything has to fit the video's height (it grows as you drag the
    /// player bigger).
    var scale: CGFloat = 1
    /// Venue, start time and broadcasters to the right (left out when there isn't room).
    var showsInfo = true

    private func z(_ size: CGFloat, min floor: CGFloat = 9) -> CGFloat { max(floor, size * scale) }

    /// The slim player bar's one line: "TOR 78 – 81 BOS · Q3 4:12".
    var slimScore: String {
        if game.isEvent && !game.hasSides { return game.eventTitle }
        if game.state == .upcoming { return "\(game.away.abbr) at \(game.home.abbr) · \(game.statusText)" }
        return "\(game.away.abbr) \(game.away.score) – \(game.home.score) \(game.home.abbr) · \(game.statusText)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: z(28)) {
            VStack(alignment: .leading, spacing: z(14, min: 4)) {
                Text(statusLine)
                    .font(.system(size: z(12, min: 10), weight: .semibold))
                    .foregroundStyle(game.state == .live ? Theme.accent : Theme.muted)
                if game.isEvent {
                    EventLines(game: game, big: true)
                } else {
                    scoreLine(game.away)
                    scoreLine(game.home)
                }
            }
            .frame(minWidth: z(240, min: 110), maxWidth: 420, alignment: .topLeading)

            if showsInfo {
                Rectangle().fill(Theme.raised).frame(width: 1)
                gameInfo
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func scoreLine(_ team: Team) -> some View {
        HStack(spacing: z(12, min: 6)) {
            TeamBadge(abbr: team.abbr, logo: team.logo, size: z(50, min: 26))
            VStack(alignment: .leading, spacing: 2) {
                Text(team.shortName)
                    .font(Theme.display(z(28, min: 15)))
                    .foregroundStyle(Theme.text)
                    .lineLimit(scale < 1 ? 1 : 2)
                    .minimumScaleFactor(0.7)
                if team.hasLongScore {
                    Text(team.score)
                        .font(.system(size: z(20, min: 12), weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(game.scoreColor(team))
                }
                if !team.record.isEmpty {
                    Text(team.record)
                        .font(.system(size: z(12, min: 10)))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 12)
            if !team.hasLongScore {
                Text(team.score)
                    .font(Theme.display(z(30, min: 16)))
                    .monospacedDigit()
                    .foregroundStyle(game.scoreColor(team))
            }
        }
    }

    /// Box score by period, venue and broadcasters: what fills the space beside the score.
    private var gameInfo: some View {
        VStack(alignment: .leading, spacing: z(14, min: 5)) {
            let periods = max(game.away.linescores.count, game.home.linescores.count)
            if !game.isEvent && periods > 0 {
                Grid(alignment: .trailing, horizontalSpacing: z(14, min: 8), verticalSpacing: z(8, min: 3)) {
                    GridRow {
                        Text("").gridColumnAlignment(.leading)
                        ForEach(0..<periods, id: \.self) { i in
                            Text(periodLabel(i))
                        }
                        Text("T")
                    }
                    .font(.system(size: z(11, min: 9), weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    ForEach([game.away, game.home], id: \.self) { team in
                        GridRow {
                            Text(team.abbr)
                                .font(.system(size: z(13, min: 10), weight: .semibold))
                                .foregroundStyle(Theme.soft)
                                .gridColumnAlignment(.leading)
                            ForEach(0..<periods, id: \.self) { i in
                                Text(i < team.linescores.count ? team.linescores[i] : "–")
                            }
                            Text(team.score)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.text)
                        }
                        .font(.system(size: z(14, min: 11)))
                        .monospacedDigit()
                        .foregroundStyle(Theme.soft)
                    }
                }
                .padding(z(14, min: 7))
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised.opacity(0.5)))
            }

            if !game.venue.isEmpty {
                Label(game.venue, systemImage: "mappin.and.ellipse")
                    .font(.system(size: z(12, min: 10)))
                    .foregroundStyle(Theme.soft)
                    .lineLimit(scale < 1 ? 1 : 2)
            }
            if let start = game.start {
                Label(start.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    .font(.system(size: z(12, min: 10)))
                    .foregroundStyle(Theme.soft)
            }
            if !broadcasterLine.isEmpty {
                Label(broadcasterLine.replacingOccurrences(of: "Broadcasters: ", with: ""), systemImage: "tv")
                    .font(.system(size: z(12, min: 10)))
                    .foregroundStyle(Theme.soft)
                    .lineLimit(scale < 1 ? 1 : 3)
            }
        }
    }

    /// Q1–Q4 for basketball and football, P1–P3 for hockey, H1–H2 for soccer, innings for baseball; OT after.
    private func periodLabel(_ i: Int) -> String {
        let n = i + 1
        switch game.league.sport {
        case .basketball where game.league.id.hasPrefix("ncaam"):
            return n <= 2 ? "\(n)H" : (n == 3 ? "OT" : "\(n - 2)OT")
        case .basketball, .football, .aussieRules, .lacrosse:
            return n <= 4 ? "Q\(n)" : (n == 5 ? "OT" : "\(n - 4)OT")
        case .hockey:
            return n <= 3 ? "P\(n)" : (n == 4 ? "OT" : "SO")
        case .soccer, .rugby:
            return n <= 2 ? "\(n)H" : "ET"
        default:
            return "\(n)"
        }
    }

    /// "Broadcasters: ABC · Canada: Sportsnet, TVA Sports", from ESPN and the official league schedules.
    private var broadcasterLine: String {
        var parts: [String] = []
        let confirmed = (model.extraBroadcasts[game.id] ?? []).filter(\.confirmed)
        let general = game.broadcasters + confirmed.filter { $0.country == nil }.map(\.name)
        var seen = Set<String>()
        let generalUnique = general.filter { seen.insert($0.lowercased()).inserted }
        if !generalUnique.isEmpty { parts.append(generalUnique.joined(separator: ", ")) }
        let byCountry = Dictionary(grouping: confirmed.filter { $0.country != nil }, by: { $0.country ?? "" })
        for country in byCountry.keys.sorted() {
            let names = byCountry[country]!.map(\.name).filter { seen.insert($0.lowercased()).inserted }
            if !names.isEmpty { parts.append("\(country): \(names.joined(separator: ", "))") }
        }
        return parts.isEmpty ? "" : "Broadcasters: " + parts.joined(separator: " · ")
    }

    private var statusLine: String {
        if game.isChannel { return "\(game.league.name.uppercased()) · CHANNEL" }
        switch game.state {
        case .live: return "\(game.league.name.uppercased()) · LIVE · \(game.statusText)"
        case .upcoming: return "\(game.league.name.uppercased()) · STARTS \(game.statusText)"
        case .finished: return "\(game.league.name.uppercased()) · \(game.statusText.uppercased())"
        }
    }
}

/// Lays items out left to right at their own width (between a minimum and maximum), wrapping onto new rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 10
    var minItemWidth: CGFloat = 0
    var maxItemWidth: CGFloat = .infinity
    /// Every item as tall as the tallest one (stream cards line up in neat rows).
    var uniformHeight = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 1000
        let frames = arrange(width: width, subviews: subviews)
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(width: bounds.width, subviews: subviews)
        for (view, frame) in zip(subviews, frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        let sizes: [CGSize] = subviews.map { view in
            let ideal = view.sizeThatFits(.unspecified).width
            let w = min(width, min(maxItemWidth, max(minItemWidth, ideal)))
            return CGSize(width: w, height: view.sizeThatFits(ProposedViewSize(width: w, height: nil)).height)
        }
        let tallest = sizes.map(\.height).max() ?? 0
        for size in sizes {
            let w = size.width
            let h = uniformHeight ? tallest : size.height
            if x > 0 && x + w > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: w, height: h))
            x += w + spacing
            rowHeight = max(rowHeight, h)
        }
        return frames
    }
}
