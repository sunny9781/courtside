import SwiftUI

/// A game: the mini player pinned at the top, the score, then every stream (4K, PPV for fights, then by country).
/// Tap a stream to play it in the mini player; tap it again, double-tap the player, or turn the phone sideways
/// for full screen.
struct IOSGameView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage(Prefs.hideSD) private var hideSD = true
    @State private var previewID: Int?
    @State private var showLocal = false
    let gameID: String

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

    private var sections: [StreamSection] {
        let uhd = mainStreams.filter { $0.qualityRank == 4 }
        let fight = game?.league.sport == .fighting
        let ppv = fight ? mainStreams.filter { $0.qualityRank != 4 && $0.isPPV } : []
        let ppvIDs = Set(ppv.map(\.id))
        var order: [String] = []
        var groups: [String: [StreamMatch]] = [:]
        for match in mainStreams where match.qualityRank != 4 && !ppvIDs.contains(match.id) {
            let name = match.country ?? "Other"
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(match)
        }
        if let i = order.firstIndex(of: "Other"), order.count > 1 { order.append(order.remove(at: i)) }
        var out = (uhd.isEmpty ? [] : [StreamSection(name: "4K", streams: uhd)])
            + (ppv.isEmpty ? [] : [StreamSection(name: "PPV", streams: ppv)])
            + order.map { StreamSection(name: $0, streams: groups[$0] ?? []) }
        if showLocal {
            let mainIDs = Set(mainStreams.map(\.id))
            let extras = allStreams.filter { !mainIDs.contains($0.id) }
            if !extras.isEmpty { out.append(StreamSection(name: "Local stations and likely channels", streams: extras)) }
        }
        return out
    }

    private var streams: [StreamMatch] { sections.flatMap(\.streams) }
    private var lineup: [Channel] { streams.map(\.channel) }
    private var previewChannel: Channel? { streams.first { $0.channel.id == previewID }?.channel }

    var body: some View {
        VStack(spacing: 0) {
            IOSMiniPlayer(channel: previewChannel, onExpand: previewChannel == nil ? nil : { fullScreen() })
                .padding(.horizontal)
                .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let game { score(game) }

                    HStack(alignment: .firstTextBaseline) {
                        Text("All streams").font(.title3.bold()).foregroundStyle(Theme.text)
                        Text("\(streams.count)").foregroundStyle(Theme.muted)
                    }

                    if sections.isEmpty {
                        Text(model.channels.isEmpty ? "Channels are still loading…" : "No streams found for this game yet.")
                            .foregroundStyle(Theme.muted)
                    }

                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            if sections.count > 1 {
                                HStack(spacing: 6) {
                                    Text(section.name.uppercased()).font(.caption.bold()).foregroundStyle(Theme.muted)
                                    Text("\(section.streams.count)").font(.caption).foregroundStyle(Theme.muted.opacity(0.7))
                                }
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 10)], spacing: 10) {
                                ForEach(section.streams) { match in
                                    IOSStreamRow(match: match,
                                                 quality: model.measuredQuality[match.channel.id] ?? match.quality,
                                                 frameRate: model.measuredFrameRate[match.channel.id],
                                                 previewing: match.channel.id == previewID)
                                        .onTapGesture { tap(match) }
                                }
                            }
                        }
                    }

                    if extraCount > 0 {
                        Button(showLocal ? "Hide local stations and likely channels"
                                         : "Show \(extraCount) local stations and likely channels") {
                            showLocal.toggle()
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
        }
        .background(Theme.bg)
        .navigationTitle(game?.league.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Coming back from another tab: keep the stream that was playing. Otherwise opening a game plays its
            // first stream; after that, only tapping plays something else.
            if let bg = model.backgroundChannel, allStreams.contains(where: { $0.channel.id == bg.id }) {
                previewID = bg.id
            } else if previewID == nil {
                previewID = streams.first?.channel.id
            }
            model.backgroundChannel = nil
        }
        .onChange(of: verticalSizeClass) {
            // Turning the phone sideways while something plays goes full screen.
            if verticalSizeClass == .compact, previewChannel != nil, model.nowPlaying == nil { fullScreen() }
        }
    }

    private func tap(_ match: StreamMatch) {
        if previewID == match.channel.id {
            fullScreen()
        } else {
            previewID = match.channel.id
        }
    }

    private func fullScreen() {
        guard let channel = previewChannel, let game else { return }
        model.play(channel, gameTitle: game.title, lineup: lineup)
    }

    private func score(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                IOSLeagueLogo(league: game.league, size: 20)
                Text(game.headerText)
                    .font(.caption.bold())
                    .foregroundStyle(game.state == .live ? Theme.accent : Theme.soft)
            }
            if game.isEvent && !game.hasSides {
                Text(game.eventTitle).font(.title2.bold()).foregroundStyle(Theme.text)
                if !game.eventDetail.isEmpty {
                    Text(game.eventDetail).foregroundStyle(Theme.soft)
                }
            } else {
                teamLine(game.away, game: game)
                teamLine(game.home, game: game)
            }
            let info = [game.state == .upcoming ? "Starts \(game.startText)" : "", game.venue,
                        game.broadcasters.isEmpty ? "" : "On " + game.broadcasters.joined(separator: ", ")]
                .filter { !$0.isEmpty }
            if !info.isEmpty {
                Text(info.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
    }

    private func teamLine(_ team: Team, game: Game) -> some View {
        HStack(spacing: 12) {
            IOSTeamLogo(team: team, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(team.name).font(.headline).foregroundStyle(Theme.text).lineLimit(2)
                if game.state != .upcoming && team.hasLongScore {
                    Text(team.score)
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(game.scoreColor(team))
                }
                if !team.record.isEmpty {
                    Text(team.record).font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            if game.state != .upcoming && !team.hasLongScore {
                Text(team.score)
                    .font(.system(size: 30, weight: .bold).monospacedDigit())
                    .foregroundStyle(game.scoreColor(team))
            }
        }
    }
}

/// One stream: name, category, why it matched, quality and frame rate.
struct IOSStreamRow: View {
    let match: StreamMatch
    let quality: String
    var frameRate: Double?
    var previewing = false

    var body: some View {
        HStack(spacing: 12) {
            IOSChannelIcon(url: match.channel.icon, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(match.channel.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(previewing ? Theme.accent : Theme.text)
                    .lineLimit(2)
                if !match.channel.categoryName.isEmpty {
                    Label(match.channel.categoryName, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(Theme.soft)
                        .lineLimit(1)
                }
                Text(match.reason).font(.caption2).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                if !quality.isEmpty {
                    IOSBadge(text: quality, fill: quality == "4K" ? Theme.accent : Theme.raised,
                             color: quality == "4K" ? Theme.onAccent : Theme.soft)
                }
                if let frameRate { IOSBadge(text: PlaybackController.fpsLabel(frameRate)) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(previewing ? Theme.accent : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
    }
}
