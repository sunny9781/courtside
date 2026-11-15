import SwiftUI

/// A game, laid out like the Mac: Back, then one panel with the mini player beside the score, then every stream.
/// Moving onto a stream plays it in the mini player; clicking it goes full screen (no reconnect).
struct TVGameView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: TVNav
    @AppStorage(Prefs.hideSD) private var hideSD = true
    @State private var showLocal = false
    @AppStorage(Prefs.showForeignStreams) private var showForeign = false
    /// Sections folded shut (4K, USA, Other…), by name.
    @State private var folded: Set<String> = []
    @State private var previewID: Int?
    @FocusState private var focusedStream: Int?
    let gameID: String

    /// Looked up each time so the score stays live.
    private var game: Game? { model.games.first { $0.id == gameID } }

    private var allStreams: [StreamMatch] {
        let all = model.matches[gameID] ?? []
        return hideSD ? all.filter { $0.quality != "SD" } : all
    }

    /// 4K, PPV for fights, the league's own channels, home-country broadcasters, other countries (StreamSections).
    private var listing: StreamSections.Result {
        guard let game else { return .empty }
        return StreamSections.build(allStreams, league: game.league)
    }

    private var sections: [StreamSections.Section] { listing.sections }

    private var streams: [StreamMatch] {
        sections.flatMap(\.streams) + (showForeign ? listing.foreign.flatMap(\.streams) : []) + (showLocal ? listing.extras : [])
    }

    /// On-screen order, which is also what swiping up and down flips through while watching.
    private var lineup: [Channel] { streams.map(\.channel) }

    /// The stream playing in the mini player: only one you clicked (nothing plays just by moving around).
    private var previewChannel: Channel? {
        streams.first { $0.channel.id == previewID }?.channel
    }

    /// Click once to play in the mini player, click the same stream again for full screen.
    private func select(_ match: StreamMatch, game: Game) {
        if previewID == match.channel.id {
            model.play(match.channel, gameTitle: game.title, lineup: lineup)
        } else {
            previewID = match.channel.id
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack {
                TVBackButton { if !nav.homePath.isEmpty { nav.homePath.removeLast() } }
                Spacer()
            }

            if let game {
                hero(game)
                streamList(game)
            } else {
                Text("This game is no longer on today's schedule.")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.muted)
                Spacer()
            }
        }
        .padding(.horizontal, TVLayout.margin)
        .padding(.top, 10)
        .defaultFocus($focusedStream, previewID ?? streams.first?.channel.id)
        .onAppear {
            // Coming back from another tab: keep showing the stream that was playing. Otherwise opening a game
            // plays its first stream; after that, only clicking plays something else.
            if let bg = model.backgroundChannel, allStreams.contains(where: { $0.channel.id == bg.id }) {
                previewID = bg.id
            } else if previewID == nil {
                previewID = streams.first?.channel.id
            }
            model.backgroundChannel = nil
        }
        .onExitCommand { if !nav.homePath.isEmpty { nav.homePath.removeLast() } }
    }

    // MARK: Top: mini player, score, details

    private func hero(_ game: Game) -> some View {
        HStack(alignment: .top, spacing: 44) {
            TVPreview(channel: previewChannel, placeholder: "Click a stream to play it here.\nClick it again for full screen.")
                .frame(width: 560, height: 315)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    TVLeagueLogo(league: game.league, size: 40)
                    Text(game.headerText)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(game.state == .live ? Theme.accent : Theme.soft)
                }

                if game.isEvent && !game.hasSides {
                    Text(game.eventTitle)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    if !game.eventDetail.isEmpty {
                        Text(game.eventDetail)
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.soft)
                    }
                } else {
                    teamLine(game.away, game: game)
                    teamLine(game.home, game: game)
                }

                details(game)
            }
            .frame(maxWidth: 700, alignment: .leading)

            if !game.isEvent, !game.away.linescores.isEmpty {
                boxScore(game)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 315, alignment: .top)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: TVLayout.corner).fill(Theme.card))
    }

    private func teamLine(_ team: Team, game: Game) -> some View {
        HStack(spacing: 20) {
            TVTeamLogo(team: team, size: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(team.name)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                if game.state != .upcoming && team.hasLongScore {
                    Text(team.score)
                        .font(.system(size: 28, weight: .bold).monospacedDigit())
                        .foregroundStyle(game.scoreColor(team))
                }
                if !team.record.isEmpty {
                    Text(team.record)
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 16)
            if game.state != .upcoming && !team.hasLongScore {
                Text(team.score)
                    .font(.system(size: 52, weight: .bold).monospacedDigit())
                    .foregroundStyle(game.scoreColor(team))
            }
        }
    }

    private func details(_ game: Game) -> some View {
        var lines: [String] = []
        if game.state == .upcoming { lines.append("Starts \(game.startText)") }
        if !game.venue.isEmpty { lines.append(game.venue) }
        if !game.broadcasters.isEmpty { lines.append("On " + game.broadcasters.joined(separator: ", ")) }
        return Text(lines.joined(separator: "  ·  "))
            .font(.system(size: 21))
            .foregroundStyle(Theme.muted)
            .lineLimit(2)
    }

    private func boxScore(_ game: Game) -> some View {
        let periods = max(game.away.linescores.count, game.home.linescores.count)
        return Grid(alignment: .trailing, horizontalSpacing: 22, verticalSpacing: 12) {
            GridRow {
                Text("")
                ForEach(0..<periods, id: \.self) { i in
                    Text("\(i + 1)").foregroundStyle(Theme.muted)
                }
                Text("T").foregroundStyle(Theme.muted)
            }
            ForEach([game.away, game.home], id: \.abbr) { team in
                GridRow {
                    Text(team.abbr).foregroundStyle(Theme.soft).gridColumnAlignment(.leading)
                    ForEach(0..<periods, id: \.self) { i in
                        Text(i < team.linescores.count ? team.linescores[i] : "–").foregroundStyle(Theme.text)
                    }
                    Text(team.score).bold().foregroundStyle(game.scoreColor(team))
                }
            }
        }
        .font(.system(size: 22).monospacedDigit())
        .padding(24)
        .background(RoundedRectangle(cornerRadius: TVLayout.corner).fill(Theme.raised.opacity(0.5)))
    }

    // MARK: Streams

    private func sectionView(_ section: StreamSections.Section, game: Game) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            // Click a section's name to fold it shut or open it.
            Button {
                if folded.contains(section.name) { folded.remove(section.name) } else { folded.insert(section.name) }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: folded.contains(section.name) ? "chevron.right" : "chevron.down")
                        .font(.system(size: 20, weight: .bold))
                    Text(section.name.uppercased())
                        .font(.system(size: 22, weight: .bold))
                    Text("\(section.streams.count)")
                        .font(.system(size: 20))
                        .opacity(0.6)
                }
            }
            .buttonStyle(TVPillButtonStyle())
            if !folded.contains(section.name) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 520), spacing: 34, alignment: .top)],
                          alignment: .leading, spacing: 34) {
                    ForEach(section.streams) { match in
                        Button {
                            select(match, game: game)
                        } label: {
                            TVStreamCell(match: match,
                                         quality: model.measuredQuality[match.channel.id] ?? match.quality,
                                         frameRate: model.measuredFrameRate[match.channel.id],
                                         previewing: match.channel.id == previewChannel?.id)
                        }
                        .buttonStyle(.card)
                        .focused($focusedStream, equals: match.channel.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func streamList(_ game: Game) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 34) {
                if sections.isEmpty {
                    Text(model.channels.isEmpty ? "Channels are still loading…" : "No streams found for this game yet.")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.muted)
                }
                ForEach(sections) { sectionView($0, game: game) }

                // Foreign-language countries, folded into one group.
                if !listing.foreign.isEmpty {
                    Button(showForeign ? "Hide foreign-language streams (\(listing.foreignCount))"
                                       : "Show foreign-language streams (\(listing.foreignCount))") {
                        showForeign.toggle()
                    }
                    .buttonStyle(TVPillButtonStyle())
                    .font(.system(size: 22, weight: .semibold))
                    if showForeign {
                        ForEach(listing.foreign) { sectionView($0, game: game) }
                    }
                }

                // Local stations and "usually on" guesses, at the very bottom.
                if !listing.extras.isEmpty {
                    Button(showLocal ? "Hide local stations and likely channels"
                                     : "Show \(listing.extras.count) local stations and likely channels") {
                        showLocal.toggle()
                    }
                    .buttonStyle(TVPillButtonStyle())
                    .font(.system(size: 22, weight: .semibold))
                    if showLocal {
                        sectionView(StreamSections.Section(name: "Local and likely", streams: listing.extras), game: game)
                    }
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 36)
        }
        // Clipped, so streams scrolling up disappear under the edge instead of drawing over the player and score.
        // The padding inside leaves room for a focused stream to grow.
        .padding(.horizontal, -36)
    }
}

/// One stream, like the Mac panel: name, its category, why it matched, and its quality.
struct TVStreamCell: View {
    @EnvironmentObject var model: AppModel
    let match: StreamMatch
    let quality: String
    var frameRate: Double? = nil
    var previewing = false

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            TVChannelIcon(url: match.channel.icon, size: 60)
            VStack(alignment: .leading, spacing: 6) {
                Text(match.channel.name)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(previewing ? Theme.accent : Theme.text)
                    .lineLimit(2)
                if !match.channel.categoryName.isEmpty {
                    Label(match.channel.categoryName, systemImage: "folder")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Theme.soft)
                        .lineLimit(1)
                }
                Text(match.reason)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                if !quality.isEmpty {
                    TVBadge(text: quality, fill: quality == "4K" ? Theme.accent : Theme.raised,
                            color: quality == "4K" ? Theme.onAccent : Theme.soft)
                }
                if let frameRate {
                    TVBadge(text: PlaybackController.fpsLabel(frameRate))
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 140, alignment: .leading)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(previewing ? Theme.accent : Color.clear, lineWidth: 3))
    }
}
