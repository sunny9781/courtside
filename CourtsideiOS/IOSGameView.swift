import SwiftUI

/// A game: the mini player pinned at the top, the score, then every stream (4K, PPV for fights, then by country).
/// Tap a stream to play it in the mini player; tap it again, double-tap the player, or turn the phone sideways
/// for full screen.
struct IOSGameView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage(Prefs.hideSD) private var hideSD = true
    @State private var showLocal = false
    @AppStorage(Prefs.showForeignStreams) private var showForeign = false
    @State private var search = ""
    @State private var folded: Set<String> = []
    let gameID: String

    private var game: Game? { model.game(gameID) }

    private var allStreams: [StreamMatch] {
        let all = model.matches[gameID] ?? []
        return hideSD ? all.filter { $0.quality != "SD" } : all
    }

    /// 4K, PPV for fights, the league's own channels, home-country broadcasters, other countries (StreamSections).
    private var listing: StreamSections.Result {
        guard let game else { return .empty }
        return StreamSections.build(allStreams, league: game.league, search: search,
                                   measured: model.measuredQuality, fps: model.measuredFrameRate,
                                   hdr: model.measuredHDR, audio: model.measuredAudio)
    }

    private var sections: [StreamSections.Section] { listing.sections }

    /// Everything showing, in on-screen order: what swiping up and down flips through while watching.
    private var streams: [StreamMatch] {
        sections.flatMap(\.streams) + (showForeign ? listing.foreign.flatMap(\.streams) : []) + (showLocal ? listing.extras : [])
    }
    private var lineup: [Channel] { streams.map(\.channel) }
    /// The stream in the pinned player, if it's one of this game's.
    private var previewID: Int? {
        guard let id = model.pinned?.channel.id, allStreams.contains(where: { $0.channel.id == id }) else { return nil }
        return id
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // While one of this game's streams plays, the score is in the player at the top.
                    if let game, !model.pinnedIsFrom(gameID: gameID) { score(game) }

                    // Only worth a filter when there are more than 10 streams (or one is already typed).
                    if allStreams.filter({ !$0.hidden }).count > 10 || !search.isEmpty {
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                            TextField("Filter", text: $search)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            if !search.isEmpty {
                                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                    }
                    }

                    if sections.isEmpty {
                        Text(model.channels.isEmpty ? "Channels are still loading…"
                             : (search.isEmpty ? "No streams found for this game yet." : "No streams match \"\(search)\"."))
                            .foregroundStyle(Theme.muted)
                    }

                    ForEach(sections) { sectionView($0) }

                    // Foreign-language countries, folded into one group.
                    if !listing.foreign.isEmpty {
                        groupHeader("Foreign streams", count: listing.foreignCount, open: showForeign) { showForeign.toggle() }
                        if showForeign {
                            ForEach(listing.foreign) { sectionView($0) }
                        }
                    }

                    // Local stations and "usually on" guesses, at the very bottom.
                    if !listing.extras.isEmpty {
                        groupHeader("Local stations and likely channels", count: listing.extras.count, open: showLocal) { showLocal.toggle() }
                        if showLocal {
                            sectionView(StreamSections.Section(name: "Local and likely", streams: listing.extras), header: false)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
        }
        .background(Theme.bg)
        .navigationTitle(game?.league.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        // No back button or title bar, to save space: swipe from the left edge to go back.
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // Opening a game plays its first stream in the pinned player (unless one of its streams is already
            // playing); after that, only tapping plays something else.
            if previewID == nil, let first = streams.firstToPlay(model.measuredQuality), let game {
                model.pin(first.channel, gameTitle: game.title, lineup: lineup)
            }
        }
        .onChange(of: verticalSizeClass) {
            // Turning the phone sideways while one of this game's streams plays goes full screen.
            if verticalSizeClass == .compact, previewID != nil, model.nowPlaying == nil { fullScreen() }
        }
    }

    /// header: false for a list already under its own heading (Local stations and likely channels).
    private func sectionView(_ section: StreamSections.Section, header: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if header {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if folded.contains(section.name) { folded.remove(section.name) } else { folded.insert(section.name) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .rotationEffect(.degrees(folded.contains(section.name) ? 0 : 90))
                    Text(section.name.uppercased()).font(.caption.bold())
                    Text("\(section.streams.count)").font(.caption).opacity(0.7)
                    Spacer()
                }
                .foregroundStyle(Theme.muted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            }
            if !header || !folded.contains(section.name) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 10)], spacing: 10) {
                    ForEach(section.streams) { match in
                        IOSStreamRow(match: match,
                                     quality: model.measuredQuality[match.channel.id] ?? match.quality,
                                     frameRate: model.measuredFrameRate[match.channel.id],
                                     audio: model.measuredAudio[match.channel.id],
                                     hdr: model.measuredHDR[match.channel.id],
                                     previewing: match.channel.id == previewID)
                            .onTapGesture { tap(match) }
                    }
                }
            }
        }
    }

    private func groupHeader(_ title: String, count: Int, open: Bool, toggle: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .rotationEffect(.degrees(open ? 90 : 0))
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text("\(count)").font(.caption)
                Spacer()
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Tap once to play it in the pinned player at the top, tap again for full screen.
    private func tap(_ match: StreamMatch) {
        guard let game else { return }
        if previewID == match.channel.id {
            fullScreen()
        } else {
            model.pin(match.channel, gameTitle: game.title, lineup: lineup)
        }
    }

    private func fullScreen() {
        guard let pinned = model.pinned, previewID != nil else { return }
        model.play(pinned.channel, gameTitle: pinned.gameTitle, lineup: pinned.lineup)
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
            let info = [game.state == .upcoming && !game.isChannel ? "Starts \(game.startText)" : "", game.venue,
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
    var audio: String?
    var hdr: String?
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
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                if !quality.isEmpty {
                    IOSBadge(text: quality, fill: quality == "4K" ? Theme.accent : Theme.raised,
                             color: quality == "4K" ? Theme.onAccent : Theme.soft)
                }
                if let hdr, !hdr.isEmpty { IOSBadge(text: hdr) }
                if let frameRate { IOSBadge(text: PlaybackController.fpsLabel(frameRate)) }
                HStack(spacing: 4) {
                    if let audio, !audio.isEmpty { IOSBadge(text: audio) }
                    ReliabilityDot(channelID: match.channel.id, size: 7, padding: 4)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(previewing ? Theme.accent : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
    }
}
