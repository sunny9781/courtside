import SwiftUI

/// A game as a mini EPG (like the Android TV app): its stream categories on the left ("All" first, then each
/// section, Foreign, and Local), sitting on top of the player, and that category's channels on the right with what's
/// on now and next and each stream's quality. Click a channel to play it in the player, again for full screen.
struct TVGameView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: TVNav
    @AppStorage(Prefs.hideSD) private var hideSD = true
    @State private var selected = "All"
    @FocusState private var focusedCategory: String?
    @FocusState private var focusedStream: Int?
    let gameID: String

    private var game: Game? { model.games.first { $0.id == gameID } }

    private var allStreams: [StreamMatch] {
        let all = model.matches[gameID] ?? []
        return hideSD ? all.filter { $0.quality != "SD" } : all
    }

    private var listing: StreamSections.Result {
        guard let game else { return .empty }
        return StreamSections.build(allStreams, league: game.league,
                                   measured: model.measuredQuality, fps: model.measuredFrameRate)
    }

    private var main: [StreamMatch] { listing.sections.flatMap(\.streams) }

    /// Every group of streams, in order; "All" lists them all under these names.
    private var groups: [(name: String, streams: [StreamMatch])] {
        var out: [(name: String, streams: [StreamMatch])] = []
        for section in listing.sections { out.append((section.name, section.streams)) }
        if !listing.foreign.isEmpty { out.append(("Foreign", listing.foreign.flatMap(\.streams))) }
        if !listing.extras.isEmpty { out.append(("Local and likely", listing.extras)) }
        return out
    }

    private var categories: [(name: String, streams: [StreamMatch])] {
        let g = groups
        return [("All", g.flatMap(\.streams))] + g
    }

    private var current: [StreamMatch] { categories.first { $0.name == selected }?.streams ?? main }

    private var previewChannel: Channel? {
        guard let pinned = model.pinned?.channel, model.pinnedIsFrom(gameID: gameID) else { return nil }
        return pinned
    }

    private func select(_ match: StreamMatch, game: Game) {
        let lineup = current.map(\.channel)
        if previewChannel?.id == match.channel.id {
            model.play(match.channel, gameTitle: game.title, lineup: lineup)
        } else {
            model.pin(match.channel, gameTitle: game.title, lineup: lineup)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: TVLayout.playerGap) {
            if let game {
                categoryList
                    // Left on the categories (the screen's left edge) goes back, like Back.
                    .onMoveCommand { if $0 == .left, !nav.homePath.isEmpty { nav.homePath.removeLast() } }
                    .frame(width: TVLayout.sidebar)
                    .padding(.bottom, model.pinned != nil ? TVLayout.playerInset : TVLayout.margin)
                    .focusSection()
                channelList(game)
                    .focusSection()
            } else {
                Text("This game is no longer on today's schedule.")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.muted)
                Spacer()
            }
        }
        .padding(.horizontal, TVLayout.margin)
        .defaultFocus($focusedStream, previewChannel?.id ?? main.firstToPlay(model.measuredQuality)?.channel.id)
        .onAppear {
            // Opening a game plays its first stream that isn't 4K in the player (unless one of its streams already is).
            if previewChannel == nil, let first = main.firstToPlay(model.measuredQuality), let game {
                model.pin(first.channel, gameTitle: game.title, lineup: main.map(\.channel))
            }
        }
        .onChange(of: focusedCategory) {
            if let focusedCategory, focusedCategory != selected { selected = focusedCategory }
        }
        .onExitCommand { if !nav.homePath.isEmpty { nav.homePath.removeLast() } }
        // Back from full screen: focus goes back to the stream you were watching.
        .onChange(of: model.nowPlaying == nil) {
            guard model.nowPlaying == nil, let id = model.lastPlayedChannelID else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                focusedStream = id
            }
        }
    }

    private var categoryList: some View {
        ScrollView(.vertical) {
            VStack(spacing: 6) {
                ForEach(categories, id: \.name) { item in
                    Button { selected = item.name } label: {
                        HStack {
                            Text(item.name)
                                .font(.system(size: 26, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(item.streams.count)")
                                .font(.system(size: 21))
                                .opacity(0.6)
                        }
                    }
                    .buttonStyle(TVRowButtonStyle(selected: selected == item.name))
                    .focused($focusedCategory, equals: item.name)
                }
            }
            .padding(.vertical, 20)
        }
        .defaultFocus($focusedCategory, selected)
    }

    private func channelList(_ game: Game) -> some View {
        let list = current
        // Names on one line: as wide as the longest one needs (within reason), the same for every row.
        let nameWidth = TVLayout.nameWidth(list.map(\.channel))
        // "All": each group's name above its streams (just a heading).
        let shown = selected == "All" ? groups : [(name: selected, streams: list)]
        return ScrollView(.vertical) {
            LazyVStack(spacing: 6) {
                if list.isEmpty {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(model.channels.isEmpty ? "Channels are still loading…" : "No streams found for this game yet.")
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.muted)
                        Button("Back to the games") { if !nav.homePath.isEmpty { nav.homePath.removeLast() } }
                            .font(.system(size: 22, weight: .semibold))
                            .buttonStyle(TVPillButtonStyle())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 22)
                }
                ForEach(shown, id: \.name) { group in
                    if selected == "All" && !group.streams.isEmpty {
                        Text(group.name.uppercased())
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 22)
                            .padding(.top, 14)
                    }
                    ForEach(group.streams) { match in
                        Button { select(match, game: game) } label: {
                            TVChannelRow(channel: match.channel, playing: match.channel.id == previewChannel?.id,
                                         badge: model.measuredQuality[match.channel.id] ?? match.quality, nameWidth: nameWidth,
                                         showNext: false)
                        }
                        .buttonStyle(TVRowButtonStyle())
                        .focused($focusedStream, equals: match.channel.id)
                    }
                }
            }
            .padding(.vertical, 20)
        }
        // Runs to the bottom of the screen, under the now-playing bar (the last row can scroll clear of it).
        .contentMargins(.bottom, model.pinned != nil ? TVLayout.barHeight + TVLayout.margin : TVLayout.margin, for: .scrollContent)
    }
}
