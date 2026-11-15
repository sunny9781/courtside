import SwiftUI

/// A game: the score at the top, then every stream for it, 4K first and then by country.
struct TVGameView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.hideSD) private var hideSD = true
    @State private var showLocal = false
    let gameID: String

    /// Looked up each time so the score stays live.
    private var game: Game? { model.games.first { $0.id == gameID } }

    private var allStreams: [StreamMatch] {
        let all = model.matches[gameID] ?? []
        return hideSD ? all.filter { $0.quality != "SD" } : all
    }

    private var mainStreams: [StreamMatch] {
        let main = allStreams.filter { !$0.hidden }
        return main.isEmpty ? allStreams : main
    }

    private var extraCount: Int { allStreams.count - mainStreams.count }

    struct StreamSection: Identifiable {
        let name: String
        let streams: [StreamMatch]
        var id: String { name }
    }

    /// Same order as the Mac: 4K, then countries (best first), "Other" last, then the extras when shown.
    private var sections: [StreamSection] {
        let uhd = mainStreams.filter { $0.qualityRank == 4 }
        var order: [String] = []
        var groups: [String: [StreamMatch]] = [:]
        for match in mainStreams where match.qualityRank != 4 {
            let name = match.country ?? "Other"
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(match)
        }
        if let i = order.firstIndex(of: "Other"), order.count > 1 {
            order.append(order.remove(at: i))
        }
        var out = (uhd.isEmpty ? [] : [StreamSection(name: "4K", streams: uhd)])
            + order.map { StreamSection(name: $0, streams: groups[$0] ?? []) }
        if showLocal {
            let mainIDs = Set(mainStreams.map(\.id))
            let extras = allStreams.filter { !mainIDs.contains($0.id) }
            if !extras.isEmpty { out.append(StreamSection(name: "Local stations and likely channels", streams: extras)) }
        }
        return out
    }

    /// On-screen order, which is also what swiping up and down flips through while watching.
    private var lineup: [Channel] { sections.flatMap(\.streams).map(\.channel) }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 44) {
                if let game {
                    hero(game)
                    streamList(game)
                } else {
                    Text("This game is no longer on today's schedule.")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
    }

    // MARK: Score

    private func hero(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                if game.state == .live {
                    TVBadge(text: "LIVE", fill: Theme.accent, color: Theme.onAccent)
                }
                Text("\(game.league.name) · \(game.tvStatus)")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.soft)
            }

            if game.isEvent && !game.hasSides {
                Text(game.eventTitle)
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(Theme.text)
                if !game.eventDetail.isEmpty {
                    Text(game.eventDetail)
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.soft)
                }
            } else {
                HStack(alignment: .center, spacing: 48) {
                    teamBlock(game.away, game: game)
                    Text(game.state == .upcoming ? "at" : "–")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                    teamBlock(game.home, game: game)
                }
            }

            let info = [game.venue, game.broadcasters.isEmpty ? "" : "On " + game.broadcasters.joined(separator: ", ")]
                .filter { !$0.isEmpty }
            if !info.isEmpty {
                Text(info.joined(separator: "  ·  "))
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24).fill(Theme.card))
    }

    private func teamBlock(_ team: Team, game: Game) -> some View {
        HStack(spacing: 24) {
            TVTeamLogo(team: team, size: 110)
            VStack(alignment: .leading, spacing: 6) {
                Text(team.name)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if !team.record.isEmpty {
                    Text(team.record)
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.muted)
                }
            }
            if game.state != .upcoming {
                Text(team.score)
                    .font(.system(size: 72, weight: .bold).monospacedDigit())
                    .foregroundStyle(game.scoreColor(team))
            }
        }
    }

    // MARK: Streams

    @ViewBuilder
    private func streamList(_ game: Game) -> some View {
        if sections.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text(model.channels.isEmpty ? "Channels are still loading…" : "No streams found for this game yet.")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.muted)
                if extraCount > 0 { extrasButton }
            }
        } else {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(section.name.uppercased())  \(section.streams.count)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.muted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 540), spacing: 40)], alignment: .leading, spacing: 40) {
                        ForEach(section.streams) { match in
                            Button {
                                model.play(match.channel, gameTitle: game.title, lineup: lineup)
                            } label: {
                                TVStreamCell(match: match, quality: model.measuredQuality[match.channel.id] ?? match.quality)
                            }
                            .buttonStyle(.card)
                        }
                    }
                }
            }
            if extraCount > 0 { extrasButton }
        }
    }

    private var extrasButton: some View {
        Button(showLocal ? "Hide local stations and likely channels"
                         : "Show \(extraCount) local stations and likely channels") {
            showLocal.toggle()
        }
    }
}

/// One stream: channel logo, name, what's on now, and its quality.
struct TVStreamCell: View {
    @EnvironmentObject var model: AppModel
    let match: StreamMatch
    let quality: String

    var body: some View {
        HStack(spacing: 20) {
            TVChannelIcon(url: match.channel.icon, size: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(match.channel.name)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                if !match.channel.categoryName.isEmpty {
                    Label(match.channel.categoryName, systemImage: "folder")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Theme.soft)
                        .lineLimit(1)
                }
                if let now = model.currentProgramme(match.channel), !now.title.isEmpty {
                    Text(now.title)
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if !quality.isEmpty {
                TVBadge(text: quality, fill: quality == "4K" ? Theme.accent : Theme.raised,
                        color: quality == "4K" ? Theme.onAccent : Theme.soft)
            }
        }
        .padding(22)
        .frame(width: 540, height: 150, alignment: .leading)
        .background(Theme.card)
    }
}
