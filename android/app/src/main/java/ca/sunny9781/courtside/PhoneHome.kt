package ca.sunny9781.courtside

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Icon
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

private fun phoneSport(s: HomeSelection): Sport? = when (s) {
    is HomeSelection.OfSport -> s.sport
    is HomeSelection.OfLeague -> League.all.firstOrNull { it.id == s.leagueId }?.sport
    else -> null
}

private fun phoneSorted(games: List<Game>) = games.sortedWith(
    compareBy<Game> { when (it.state) { GameState.LIVE -> 0; GameState.UPCOMING -> 1; else -> 2 } }.thenBy { it.start ?: Long.MAX_VALUE })

private data class Sec(val id: String, val league: League, val games: List<Game>)

/** Pull down to download fresh channels and guide (with a spinner until it's done). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PullToRefresh(model: AppModel, modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    var pulled by remember { mutableStateOf(false) }
    LaunchedEffect(pulled) {
        if (!pulled) return@LaunchedEffect
        delay(800)
        snapshotFlow { model.loading }.first { !it }
        pulled = false
    }
    val state = androidx.compose.material3.pulltorefresh.rememberPullToRefreshState()
    androidx.compose.material3.pulltorefresh.PullToRefreshBox(
        isRefreshing = pulled, onRefresh = { pulled = true; model.refresh(force = true) }, modifier = modifier, state = state,
        indicator = {
            androidx.compose.material3.pulltorefresh.PullToRefreshDefaults.Indicator(state = state, isRefreshing = pulled,
                modifier = Modifier.align(Alignment.TopCenter), containerColor = Theme.raised, color = Theme.accent)
        }, content = content)
}

/**
 * Home: today's games for the sport you pick, as score cards two to a row, under a heading per league. The sports
 * and leagues are chips along the bottom, starting from the right edge. Tap a game for its streams.
 */
@Composable
fun PhoneHome(model: AppModel) {
    val sports = model.orderedSports()
    // Opens on the top sport (no Live Now page), and follows the top sport while everything loads, until you pick one.
    LaunchedEffect(model.homeSelection, sports.firstOrNull()) {
        val top = sports.firstOrNull() ?: return@LaunchedEffect
        val following = !model.pickedSport && System.currentTimeMillis() - model.openedAt < 90_000
        if (model.homeSelection == HomeSelection.LiveNow ||
            (following && model.homeSelection is HomeSelection.OfSport && model.homeSelection != HomeSelection.OfSport(top))) {
            model.homeSelection = HomeSelection.OfSport(top)
        }
    }
    val selection = model.homeSelection
    val sport = phoneSport(selection)
    Column(Modifier.fillMaxSize()) {
        PullToRefresh(model, Modifier.weight(1f).fillMaxWidth()) {
            if (sport != null && sport in model.home.channelSports) SportChannelList(model, sport)
            else GameList(model, selection, sport)
        }
        HomeBottomBar(model, sport)
    }
}

@Composable
private fun GameList(model: AppModel, selection: HomeSelection, sport: Sport?) {
    val sections = when (selection) {
        is HomeSelection.OfSport -> model.leagues(selection.sport).mapNotNull { l ->
            val g = model.gamesIn(l.id)
            if (g.isEmpty()) null else Sec(l.id, l, phoneSorted(g))
        }
        is HomeSelection.OfLeague -> League.all.firstOrNull { it.id == selection.leagueId }?.let {
            listOf(Sec(it.id, it, phoneSorted(model.gamesIn(it.id))))
        } ?: emptyList()
        else -> emptyList()
    }
    var openFinished by remember { mutableStateOf(setOf<String>()) }
    var redZoneOpen by remember { mutableStateOf(false) }
    val nflLive = (sport == Sport.FOOTBALL) && model.gamesIn("nfl").any { it.state == GameState.LIVE }
    val redZone = if (nflLive) model.redZoneChannels() else emptyList()

    fun LazyListScope.cards(games: List<Game>, prefix: String) {
        items(games.chunked(2), key = { "$prefix:${it.first().id}" }, contentType = { "cards" }) { row ->
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 5.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                for (game in row) PhoneGameCard(model, game, Modifier.weight(1f)) { model.openGameId = game.id }
                if (row.size < 2) Spacer(Modifier.weight(1f))
            }
        }
    }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 12.dp)) {
        item(key = "status") { HomeStatus(model) }
        if (redZone.isNotEmpty()) {
            item(key = "rz") { Fold("NFL RedZone · ${redZone.size}", redZoneOpen, Theme.accent) { redZoneOpen = !redZoneOpen } }
            if (redZoneOpen) items(redZone, key = { "rz:${it.id}" }) { ch ->
                PhoneChannelRow(model, ch, model.pinned?.channel?.id == ch.id) { tapChannel(model, ch, redZone) }
            }
        }
        if (sections.isEmpty()) item(key = "empty") {
            Label(if (model.loading || model.games.isEmpty()) "Loading today's games…" else "No games today.",
                size = 15.sp, color = Theme.muted, modifier = Modifier.padding(16.dp))
        }
        for (s in sections) {
            item(key = "h:${s.id}") {
                Row(Modifier.padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    LeagueLogo(model, s.league, 24.dp)
                    Label(s.league.name, size = 20.sp, weight = FontWeight.Bold)
                }
            }
            val finished = s.games.filter { it.state == GameState.FINISHED }
            val shown = s.games.filter { g ->
                when {
                    g.state == GameState.FINISHED -> s.id in openFinished
                    else -> true
                }
            }
            cards(shown, s.id)
            if (finished.isNotEmpty()) item(key = "fin:${s.id}") {
                Fold("Finished · ${finished.size}", s.id in openFinished) {
                    openFinished = if (s.id in openFinished) openFinished - s.id else openFinished + s.id
                }
            }
        }
    }
}

/** The update that's ready to install, the EPG download, and anything that went wrong. */
@Composable
private fun HomeStatus(model: AppModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        val ready = Updater.readyVersion
        val downloading = Updater.downloading
        if (ready != null || downloading != null) {
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Theme.card)
                .clickable(enabled = ready != null && downloading == null) { scope.launch { Updater.installLatest(context) } }
                .padding(horizontal = 14.dp, vertical = 11.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(Icons.Filled.SystemUpdate, null, tint = Theme.accent, modifier = Modifier.size(20.dp))
                Label(if (downloading != null) "Downloading $downloading${Updater.downloadProgress?.let { " · ${(it * 100).toInt()}%" } ?: ""}"
                      else "Courtside $ready is ready", size = 14.sp, weight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                if (downloading == null) Label("Install", size = 14.sp, weight = FontWeight.Bold, color = Theme.accent)
            }
        }
        when {
            model.refreshWaiting -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Filled.Schedule, null, tint = Theme.muted, modifier = Modifier.size(14.dp))
                Label("EPG refreshes after this stream", size = 12.sp, weight = FontWeight.SemiBold, color = Theme.muted)
            }
            model.loading -> Label("Refreshing channels…", size = 12.sp, weight = FontWeight.SemiBold, color = Theme.muted)
            model.guideLoading -> Label("Refreshing EPG…", size = 12.sp, weight = FontWeight.SemiBold, color = Theme.muted)
        }
        model.error?.let { e ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Filled.Warning, null, tint = Theme.muted, modifier = Modifier.size(14.dp))
                Label(e, size = 12.sp, color = Theme.muted, maxLines = 3)
            }
        }
    }
}

/** "Later today · 6" / "Finished · 6": tap to show or hide them. */
@Composable
private fun Fold(title: String, open: Boolean, color: Color = Theme.muted, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(if (open) Icons.Filled.ExpandMore else Icons.Filled.ChevronRight, null, tint = color, modifier = Modifier.size(16.dp))
        Label(title, size = 14.sp, weight = FontWeight.SemiBold, color = color)
    }
}

/** Tap once to play in the player at the top; tap the one that's playing for full screen. */
fun tapChannel(model: AppModel, channel: Channel, lineup: List<Channel>, gameTitle: String? = null) {
    if (model.pinned?.channel?.id == channel.id) model.play(channel, model.pinned?.gameTitle ?: gameTitle, model.pinned?.lineup ?: lineup, from = "home")
    else model.pin(channel, gameTitle, lineup.ifEmpty { listOf(channel) })
}

/** A sport with channels instead of scores (pickleball): its channels under a heading per category. */
@Composable
private fun SportChannelList(model: AppModel, sport: Sport) {
    val games = model.games(sport)
    val channels = games.flatMap { model.streams(it.id) }.map { it.channel }.distinctBy { it.id }
        .sortedWith(compareBy({ !it.name.lowercase().contains(sport.title.lowercase()) }, { it.name }))
    val byCategory = channels.groupBy { it.categoryName.ifEmpty { "Other" } }
    val lineup = byCategory.values.flatten()
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 12.dp)) {
        item(key = "status") { HomeStatus(model) }
        if (channels.isEmpty()) item(key = "none") {
            Label("Nothing on today.", size = 15.sp, color = Theme.muted, modifier = Modifier.padding(16.dp))
        }
        for ((category, list) in byCategory) {
            item(key = "h:$category") {
                Label(category.uppercase(), size = 11.sp, weight = FontWeight.Bold, color = Theme.muted,
                    modifier = Modifier.padding(start = 16.dp, top = 14.dp, bottom = 4.dp))
            }
            items(list, key = { "c:${it.id}" }) { ch ->
                PhoneChannelRow(model, ch, model.pinned?.channel?.id == ch.id, showTags = true) { tapChannel(model, ch, lineup) }
            }
        }
    }
}

/** Leagues (when the sport has more than one) above the sports, both starting from the right edge. */
@Composable
private fun HomeBottomBar(model: AppModel, sport: Sport?) {
    val selection = model.homeSelection
    val favs = model.settings.favoriteSet
    Column(Modifier.fillMaxWidth().background(Theme.sidebar.copy(alpha = 0.96f)).padding(vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (sport != null && model.leagues(sport).size > 1) TrailingRow {
            // Right to left: All nearest the thumb, then the most popular league (NBA, WNBA, NCAA...).
            for (league in model.leagues(sport).reversed()) {
                val g = model.gamesIn(league.id)
                val live = g.count { it.state == GameState.LIVE }
                TouchChip((selection as? HomeSelection.OfLeague)?.leagueId == league.id, Modifier.alpha(if (g.isEmpty()) 0.5f else 1f),
                    onClick = { model.pickedSport = true; model.homeSelection = HomeSelection.OfLeague(league.id) }) { color ->
                    LeagueLogo(model, league, 18.dp)
                    Label(league.name, size = 14.sp, weight = FontWeight.SemiBold, color = color)
                    if (live > 0) Badge("$live", fill = Theme.accent, color = Theme.onAccent)
                    else if (g.isNotEmpty()) Label("${g.size}", size = 13.sp, color = color.copy(alpha = 0.6f))
                }
            }
            TouchChip(selection == HomeSelection.OfSport(sport), onClick = {
                model.pickedSport = true; model.homeSelection = HomeSelection.OfSport(sport)
            }) { color -> Label("All", size = 14.sp, weight = FontWeight.SemiBold, color = color) }
        }
        TrailingRow {
            // Right to left: the top sports nearest the thumb. Sports with nothing today are left out (unless picked
            // or a favourite).
            val shown = model.orderedSports().filter { model.games(it).isNotEmpty() || it == sport || it in favs }
            for (s in shown.reversed()) {
                val games = model.games(s)
                val channelOnly = s in model.home.channelSports
                val live = if (channelOnly) 0 else games.count { it.state == GameState.LIVE }
                TouchChip(s == sport, onClick = {
                    model.pickedSport = true
                    if (phoneSport(model.homeSelection) != s) model.homeSelection = HomeSelection.OfSport(s)
                }) { color ->
                    Icon(s.icon, s.title, tint = color, modifier = Modifier.size(20.dp))
                    if (live > 0) Badge("$live", fill = Theme.accent, color = Theme.onAccent)
                    else if (games.isNotEmpty()) Label("${games.size}", size = 13.sp, weight = FontWeight.SemiBold, color = color.copy(alpha = 0.6f))
                }
            }
        }
    }
}

/** A game card: status, 4K and stream count on top, then both teams with logos and scores. Two to a row. */
@Composable
private fun PhoneGameCard(model: AppModel, game: Game, modifier: Modifier, onClick: () -> Unit) {
    val main = model.mainStreams(game.id)
    Column(modifier.clip(RoundedCornerShape(14.dp)).background(Theme.card).clickable(onClick = onClick)
        .alpha(when (game.state) { GameState.UPCOMING -> 0.6f; GameState.FINISHED -> 0.85f; else -> 1f })
        .padding(10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Label(cardHeader(game), size = 11.sp, weight = FontWeight.Bold,
                color = if (game.state == GameState.LIVE) Theme.accent else Theme.soft, modifier = Modifier.weight(1f))
            if (main.any { it.is4K }) Badge("4K", fill = Theme.accent, color = Theme.onAccent)
            if (main.isEmpty()) Label("None", size = 11.sp, color = Theme.losing)
            else {
                Label("${main.size}", size = 11.sp, color = Theme.muted)
                Icon(Icons.Filled.LiveTv, null, tint = Theme.muted, modifier = Modifier.size(11.dp))
            }
        }
        if (game.isEvent && !game.hasSides) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Label(game.eventTitle, size = 14.sp, weight = FontWeight.SemiBold, maxLines = 2)
                if (game.eventDetail.isNotEmpty()) Label(game.eventDetail, size = 13.sp, color = Theme.soft, maxLines = 2)
            }
        } else for (team in listOf(game.away, game.home)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Logo(team.logo, 22.dp, team.abbr)
                val name = team.shortName.ifEmpty { team.name }
                Column(Modifier.weight(1f)) {
                    Label(if (team.abbr.isNotEmpty() && name.length > 11) team.abbr else name, size = 14.sp, weight = FontWeight.SemiBold, maxLines = 2)
                    if (game.state != GameState.UPCOMING && team.hasLongScore)
                        Label(team.score, size = 13.sp, weight = FontWeight.Bold, color = scoreColor(game, team))
                }
                if (game.state != GameState.UPCOMING && !team.hasLongScore)
                    Label(team.score, size = 17.sp, weight = FontWeight.Bold, color = scoreColor(game, team))
            }
        }
    }
}

// MARK: Game screen

/**
 * A game: the score (until one of its streams plays at the top), then every stream in foldable sections (4K, PPV,
 * the league's channels, by country), foreign streams and local stations folded at the bottom. Opening it plays its
 * first stream that isn't 4K; tap a stream to play it at the top, tap it again (or turn the phone sideways) for full
 * screen.
 */
@Composable
fun PhoneGame(model: AppModel, gameId: String) {
    val game = model.games.firstOrNull { it.id == gameId }
    if (game == null) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Label("This game is no longer on today's schedule.", size = 15.sp, color = Theme.muted, maxLines = 2)
            PillButton("Back to the games") { model.closeGame() }
        }
        return
    }
    val s = model.settings
    var search by remember(gameId) { mutableStateOf("") }
    var showLocal by remember(gameId) { mutableStateOf(false) }
    var folded by remember(gameId) { mutableStateOf(setOf<String>()) }
    val all = model.streams(gameId).let { list -> if (s.hideSD) list.filter { it.quality != "SD" } else list }
    val listing = remember(all, game.league, search) {
        StreamSections.build(all, game.league, search, model.measuredQuality, model.measuredFrameRate,
            model.measuredHdr, model.measuredAudio)
    }
    val sections = listing.sections
    val lineup = (sections.flatMap { it.streams } + (if (s.showForeign) listing.foreign.flatMap { it.streams } else emptyList()) +
        (if (showLocal) listing.extras else emptyList())).map { it.channel }
    val pinnedHere = model.pinnedIsFrom(gameId)
    val previewId = if (pinnedHere) model.pinned?.channel?.id else null

    // Opening a game plays its first stream that isn't 4K, unless one of its streams already plays.
    LaunchedEffect(gameId, all.isNotEmpty()) {
        if (pinnedHere || all.isEmpty()) return@LaunchedEffect
        val main = StreamSections.build(all, game.league, measured = model.measuredQuality, fps = model.measuredFrameRate,
            hdr = model.measuredHdr, audio = model.measuredAudio).sections.flatMap { it.streams }
        (main.firstOrNull { m ->
            !(m.is4K || m.quality == "4K" || model.measuredQuality[m.channel.id] == "4K" ||
                Categories.isUHD(m.channel.name) || Categories.isUHD(m.channel.categoryName))
        } ?: main.firstOrNull())?.let { model.pin(it.channel, game.title, main.map { m -> m.channel }) }
    }
    // Turning the phone sideways while one of this game's streams plays goes full screen.
    val landscape = isLandscape()
    LaunchedEffect(landscape) {
        val p = model.pinned
        if (landscape && p != null && !Cast.connected && model.pinnedIsFrom(gameId) && model.nowPlaying == null) {
            PhoneUi.fullByRotation = true
            model.play(p.channel, p.gameTitle, p.lineup, from = "game")
        }
    }
    fun tap(m: StreamMatch) {
        if (previewId == m.channel.id) model.play(m.channel, game.title, lineup, from = "game")
        else model.pin(m.channel, game.title, lineup)
    }

    fun LazyListScope.section(sec: StreamSections.Section, header: Boolean = true) {
        val open = !header || sec.name !in folded
        if (header) item(key = "h:${sec.name}") {
            Row(Modifier.fillMaxWidth().clickable { folded = if (sec.name in folded) folded - sec.name else folded + sec.name }
                .padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Filled.ChevronRight, null, tint = Theme.muted, modifier = Modifier.size(14.dp).rotate(if (open) 90f else 0f))
                Label(sec.name.uppercase(), size = 12.sp, weight = FontWeight.Bold, color = Theme.muted)
                Label("${sec.streams.size}", size = 12.sp, color = Theme.muted.copy(alpha = 0.7f))
            }
        }
        if (open) items(sec.streams, key = { "${sec.name}:${it.channel.id}" }, contentType = { "stream" }) { m ->
            StreamRow(model, m, m.channel.id == previewId, Modifier.padding(horizontal = 16.dp, vertical = 5.dp)) { tap(m) }
        }
    }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 8.dp, bottom = 30.dp)) {
        if (!pinnedHere) item(key = "score") { ScoreCard(model, game) }
        if (all.count { !it.hidden } > 10 || search.isNotEmpty()) item(key = "filter") {
            TouchField("Filter", search, { search = it }, height = 40.dp, leading = Icons.Filled.Search,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
        }
        if (sections.isEmpty()) item(key = "none") {
            Label(when {
                model.channels.isEmpty() -> "Channels are still loading…"
                search.isEmpty() -> "No streams found for this game yet."
                else -> "No streams match \"$search\"."
            }, size = 15.sp, color = Theme.muted, maxLines = 2, modifier = Modifier.padding(16.dp))
        }
        for (sec in sections) section(sec)
        if (listing.foreign.isNotEmpty()) {
            item(key = "foreign") { GroupHeader("Foreign streams", listing.foreignCount, s.showForeign) { s.showForeign = !s.showForeign } }
            if (s.showForeign) for (sec in listing.foreign) section(sec)
        }
        if (listing.extras.isNotEmpty()) {
            item(key = "local") { GroupHeader("Local stations and likely channels", listing.extras.size, showLocal) { showLocal = !showLocal } }
            if (showLocal) section(StreamSections.Section("Local and likely", listing.extras), header = false)
        }
    }
}

@Composable
private fun GroupHeader(title: String, count: Int, open: Boolean, onClick: () -> Unit) {
    Row(Modifier.padding(horizontal = 16.dp, vertical = 6.dp).fillMaxWidth().height(44.dp).clip(RoundedCornerShape(10.dp))
        .background(Theme.card).clickable(onClick = onClick).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(Icons.Filled.ChevronRight, null, tint = Theme.muted, modifier = Modifier.size(16.dp).rotate(if (open) 90f else 0f))
        Label(title, size = 14.sp, weight = FontWeight.SemiBold, modifier = Modifier.weight(1f, fill = false))
        Label("$count", size = 12.sp, color = Theme.muted)
    }
}

@Composable
private fun ScoreCard(model: AppModel, game: Game) {
    Column(Modifier.padding(horizontal = 16.dp, vertical = 6.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Theme.card)
        .padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            LeagueLogo(model, game.league, 20.dp)
            Label(cardHeader(game), size = 12.sp, weight = FontWeight.Bold, color = if (game.state == GameState.LIVE) Theme.accent else Theme.soft)
        }
        if (game.isEvent && !game.hasSides) {
            Label(game.eventTitle, size = 22.sp, weight = FontWeight.Bold, maxLines = 3)
            if (game.eventDetail.isNotEmpty()) Label(game.eventDetail, size = 14.sp, color = Theme.soft, maxLines = 3)
        } else for (team in listOf(game.away, game.home)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Logo(team.logo, 40.dp, team.abbr)
                Column(Modifier.weight(1f)) {
                    Label(team.name, size = 17.sp, weight = FontWeight.SemiBold, maxLines = 2)
                    if (game.state != GameState.UPCOMING && team.hasLongScore)
                        Label(team.score, size = 18.sp, weight = FontWeight.Bold, color = scoreColor(game, team))
                    if (team.record.isNotEmpty()) Label(team.record, size = 12.sp, color = Theme.muted)
                }
                if (game.state != GameState.UPCOMING && !team.hasLongScore)
                    Label(team.score, size = 30.sp, weight = FontWeight.Bold, color = scoreColor(game, team))
            }
        }
        val info = listOfNotNull(
            if (game.state == GameState.UPCOMING && !game.isChannel) "Starts ${startText(game)}" else null,
            game.venue.ifEmpty { null },
            if (game.broadcasters.isEmpty()) null else "On " + game.broadcasters.joinToString(", "))
        if (info.isNotEmpty()) Label(info.joinToString(" · "), size = 12.sp, color = Theme.muted, maxLines = 3)
    }
}

/** One stream: its logo, name and category, and the quality, frame rate and sound it plays with. */
@Composable
private fun StreamRow(model: AppModel, m: StreamMatch, previewing: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val quality = model.measuredQuality[m.channel.id] ?: m.quality
    val fps = model.measuredFrameRate[m.channel.id]
    val sound = model.measuredAudio[m.channel.id]
    val hdr = model.measuredHdr[m.channel.id]
    val shape = RoundedCornerShape(12.dp)
    Row(modifier.fillMaxWidth().clip(shape).background(Theme.card)
        .border(2.dp, if (previewing) Theme.accent else Color.Transparent, shape).clickable(onClick = onClick).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        ChannelIcon(m.channel.icon, 34.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Label(m.channel.name, size = 14.sp, weight = FontWeight.SemiBold, color = if (previewing) Theme.accent else Theme.text, maxLines = 2)
            val now = model.currentProgramme(m.channel)
            if (now != null && now.title.isNotEmpty()) Label(now.title, size = 12.sp, color = Theme.soft, maxLines = 2)
            if (m.channel.categoryName.isNotEmpty()) Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Icon(Icons.Filled.Folder, null, tint = Theme.muted, modifier = Modifier.size(11.dp))
                Label(m.channel.categoryName, size = 11.sp, color = Theme.muted)
            }
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (quality.isNotEmpty()) Badge(quality, fill = if (quality == "4K") Theme.accent else Theme.raised,
                color = if (quality == "4K") Theme.onAccent else Theme.soft)
            if (fps != null && fps > 0) Badge(Playback.fpsLabel(fps))
            if (!sound.isNullOrEmpty()) Badge(sound)
            if (!hdr.isNullOrEmpty()) Badge(hdr)
        }
    }
}
