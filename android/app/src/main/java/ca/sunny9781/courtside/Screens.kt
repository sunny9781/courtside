package ca.sunny9781.courtside

import android.view.KeyEvent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Sensors
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.nativeKeyCode
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import androidx.tv.material3.Icon
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date

@Composable
fun CourtsideApp(model: AppModel) {
    Box(Modifier.fillMaxSize().background(Theme.bg)) {
        if (model.credentials == null) LoginScreen(model) else Shell(model)
    }
}

// MARK: Login

@Composable
fun LoginScreen(model: AppModel) {
    var server by remember { mutableStateOf("") }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    Column(
        Modifier.fillMaxSize().padding(40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Label("Courtside", size = 30.sp, weight = FontWeight.Bold)
        Spacer(Modifier.height(6.dp))
        Label("Sign in with your Xtream Codes details", size = 14.sp, color = Theme.muted)
        Spacer(Modifier.height(24.dp))
        Field("Server (http://example.com:8080)", server, { server = it }, KeyboardType.Uri)
        Field("Username", username, { username = it })
        Field("Password", password, { password = it }, KeyboardType.Password, secret = true)
        Spacer(Modifier.height(12.dp))
        TvButton(onClick = {
            if (working) return@TvButton
            working = true
            error = null
            scope.launch {
                error = model.signIn(Credentials(server.trim(), username.trim(), password))
                working = false
            }
        }, background = Theme.accent) { focused ->
            Label(if (working) "Signing in…" else "Sign in", size = 15.sp, weight = FontWeight.SemiBold,
                color = if (focused) Theme.bg else Theme.onAccent, modifier = Modifier.padding(horizontal = 28.dp, vertical = 10.dp))
        }
        error?.let {
            Spacer(Modifier.height(12.dp))
            Label(it, size = 13.sp, color = Theme.losing, maxLines = 3)
        }
    }
}

@Composable
private fun Field(hint: String, value: String, onChange: (String) -> Unit, type: KeyboardType = KeyboardType.Text, secret: Boolean = false) {
    var focused by remember { mutableStateOf(false) }
    Box(
        Modifier.width(420.dp).padding(vertical = 5.dp).clip(RoundedCornerShape(10.dp)).background(Theme.card)
            .border(1.5.dp, if (focused) Theme.accent else Theme.border, RoundedCornerShape(10.dp))
            .padding(horizontal = 14.dp, vertical = 10.dp)
    ) {
        if (value.isEmpty()) Label(hint, size = 14.sp, color = Theme.muted)
        BasicTextField(
            value = value, onValueChange = onChange, singleLine = true,
            textStyle = TextStyle(color = Theme.text, fontSize = 14.sp),
            cursorBrush = SolidColor(Theme.accent),
            visualTransformation = if (secret) PasswordVisualTransformation() else VisualTransformation.None,
            keyboardOptions = KeyboardOptions(keyboardType = type),
            modifier = Modifier.fillMaxWidth().onFocusChanged { focused = it.isFocused }
        )
    }
}

// MARK: Shell

@Composable
fun Shell(model: AppModel) {
    // Back: full screen → the player at the top; game screen → Home list; EPG/Settings → Home; Home → leaves the app.
    BackHandler(enabled = model.nowPlaying != null || model.openGameId != null || model.tab != Tab.HOME) {
        when {
            model.nowPlaying != null -> model.closePlayer()
            model.openGameId != null -> model.openGameId = null
            else -> model.tab = Tab.HOME
        }
    }
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().padding(top = Theme.margin)) {
            TopBar(model)
            model.pinned?.let { item -> PlayerStrip(model, item) }
            Box(Modifier.weight(1f).fillMaxWidth()) {
                when (model.tab) {
                    Tab.HOME -> if (model.openGameId != null) GameScreen(model, model.openGameId!!) else HomeScreen(model)
                    Tab.EPG -> EpgScreen(model)
                    Tab.SETTINGS -> SettingsScreen(model)
                }
            }
        }
        model.nowPlaying?.let { FullScreenPlayer(model, it) }
        model.notice?.let { message ->
            Box(Modifier.fillMaxWidth().padding(top = 24.dp), contentAlignment = Alignment.TopCenter) {
                Box(Modifier.clip(RoundedCornerShape(20.dp)).background(Color.Black.copy(alpha = 0.8f))
                    .padding(horizontal = 18.dp, vertical = 8.dp)) {
                    Label(message, size = 14.sp, weight = FontWeight.SemiBold)
                }
            }
            LaunchedEffect(message) {
                delay(5000)
                if (model.notice == message) model.notice = null
            }
        }
    }
}

/** Home, EPG and Settings in the middle (moving across them switches straight away); version on the right. */
@Composable
fun TopBar(model: AppModel) {
    val context = LocalContext.current
    Box(Modifier.fillMaxWidth().padding(horizontal = Theme.margin).height(44.dp)) {
        Row(Modifier.align(Alignment.Center), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            for (tab in Tab.entries) {
                TvButton(onClick = { model.tab = tab; model.openGameId = null }, selected = model.tab == tab,
                    onFocus = { if (model.tab != tab) model.tab = tab }) { focused ->
                    Label(tab.title, size = 15.sp, weight = FontWeight.SemiBold,
                        color = if (focused) Theme.bg else if (model.tab == tab) Theme.text else Theme.muted,
                        modifier = Modifier.padding(horizontal = 18.dp, vertical = 8.dp))
                }
            }
        }
        Row(Modifier.align(Alignment.CenterEnd), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Updater.readyVersion?.let { v ->
                TvButton(onClick = { Updater.install(context) }, background = Theme.accent) { focused ->
                    Label("Install update $v", size = 12.sp, weight = FontWeight.SemiBold,
                        color = if (focused) Theme.bg else Theme.onAccent, modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp))
                }
            }
            if (model.loading) Label("Updating…", size = 12.sp, color = Theme.muted)
            else model.updatedAt?.let {
                Label("Updated ${DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(it))} · v${BuildConfig.VERSION_NAME}",
                    size = 12.sp, color = Theme.muted)
            }
        }
    }
}

// MARK: Player

/** The video. Only one view shows the player at a time: the newest one takes it. */
@Composable
fun PlayerVideo(modifier: Modifier = Modifier) {
    AndroidView(
        factory = { ctx ->
            PlayerView(ctx).apply {
                useController = false
                resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                setShutterBackgroundColor(android.graphics.Color.BLACK)
                isFocusable = false
                player = Playback.player
            }
        },
        onRelease = { view -> if (view.player === Playback.player) view.player = null },
        modifier = modifier.background(Color.Black)
    )
}

/** The player at the top of every screen while something plays. Click the video for full screen. */
@Composable
fun PlayerStrip(model: AppModel, item: NowPlaying) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = Theme.margin, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        TvButton(onClick = { model.play(item.channel, item.gameTitle, item.lineup) }, focusedScale = 1.03f,
            modifier = Modifier.size(Theme.playerWidth, Theme.playerWidth * 9 / 16)) { _ ->
            if (model.nowPlaying == null) PlayerVideo(Modifier.fillMaxSize().padding(2.dp).clip(RoundedCornerShape(8.dp)))
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Label(model.playerTitle(item), size = 16.sp, weight = FontWeight.Bold)
            Label(item.channel.name, size = 12.sp, color = Theme.muted)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (Playback.resolution.isNotEmpty()) Badge(Playback.resolution)
                if (Playback.frameRate > 0) Badge(Playback.fpsLabel(Playback.frameRate))
            }
        }
    }
}

/** Full screen: up/down switch streams, Play/Pause pauses, Back returns to the player at the top. */
@Composable
fun FullScreenPlayer(model: AppModel, item: NowPlaying) {
    val focus = remember { FocusRequester() }
    var showInfo by remember { mutableStateOf(true) }
    var poke by remember { mutableIntStateOf(0) }
    LaunchedEffect(poke, item.channel.id) {
        showInfo = true
        delay(4000)
        showInfo = false
    }
    LaunchedEffect(Unit) { focus.requestFocus() }
    Box(
        Modifier.fillMaxSize().background(Color.Black).focusRequester(focus).focusable()
            .onKeyEvent { e ->
                if (e.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (e.key.nativeKeyCode) {
                    KeyEvent.KEYCODE_DPAD_UP -> { model.step(-1); poke++; true }
                    KeyEvent.KEYCODE_DPAD_DOWN -> { model.step(1); poke++; true }
                    KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PLAY, KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                        Playback.togglePause(); poke++; true
                    }
                    KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_DPAD_LEFT,
                    KeyEvent.KEYCODE_DPAD_RIGHT -> { poke++; true }
                    else -> false
                }
            }
    ) {
        PlayerVideo(Modifier.fillMaxSize())
        if (Playback.resolution.isEmpty() && Playback.status != Playback.Status.FAILED) {
            Label("Opening ${item.channel.name}…", size = 16.sp, color = Theme.soft, modifier = Modifier.align(Alignment.Center))
        }
        if (Playback.status == Playback.Status.FAILED) {
            Label("This stream couldn't be opened. Press up or down for another stream.", size = 16.sp,
                color = Theme.soft, maxLines = 2, modifier = Modifier.align(Alignment.Center))
        }
        if (showInfo) {
            Row(
                Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                    .background(Color.Black.copy(alpha = 0.6f)).padding(horizontal = 24.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Column(Modifier.weight(1f)) {
                    Label(model.playerTitle(item), size = 17.sp, weight = FontWeight.Bold)
                    val pos = item.lineup.indexOfFirst { it.id == item.channel.id } + 1
                    Label(if (item.lineup.size > 1) "${item.channel.name} · $pos of ${item.lineup.size} · up/down to switch"
                          else item.channel.name, size = 12.sp, color = Theme.soft)
                }
                if (Playback.resolution.isNotEmpty()) Badge(Playback.resolution)
                if (Playback.frameRate > 0) Badge(Playback.fpsLabel(Playback.frameRate))
            }
        }
    }
}

// MARK: Home

private fun sportOrder(model: AppModel): List<Sport> {
    fun rank(s: Sport): Int {
        val g = model.games(s)
        return when {
            g.any { it.state == GameState.LIVE } -> 0
            g.any { it.state == GameState.UPCOMING } -> 1
            g.isNotEmpty() -> 2
            else -> 3
        }
    }
    return Sport.entries.sortedBy { rank(it) }
}

@Composable
fun HomeScreen(model: AppModel) {
    var inPane by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxSize().padding(horizontal = Theme.margin)) {
        SportList(model, compact = inPane, onFocusList = { inPane = false },
            modifier = Modifier.width(if (inPane) 72.dp else Theme.playerWidth))
        Spacer(Modifier.width(18.dp))
        GamesPane(model, onFocusPane = { inPane = true }, modifier = Modifier.weight(1f))
    }
}

@Composable
private fun SportList(model: AppModel, compact: Boolean, onFocusList: () -> Unit, modifier: Modifier) {
    val sports = sportOrder(model)
    LazyColumn(modifier.fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(3.dp),
        contentPadding = PaddingValues(vertical = 8.dp)) {
        item {
            val live = model.games.count { it.state == GameState.LIVE }
            SportRow(Icons.Filled.Sensors, "Live Now", live, model.games.size, compact,
                selected = model.homeSelection == HomeSelection.LiveNow) {
                onFocusList()
                model.homeSelection = HomeSelection.LiveNow
            }
        }
        items(sports) { sport ->
            val games = model.games(sport)
            val selected = when (val s = model.homeSelection) {
                is HomeSelection.OfSport -> s.sport == sport
                is HomeSelection.OfLeague -> League.all.firstOrNull { it.id == s.leagueId }?.sport == sport
                else -> false
            }
            SportRow(sport.icon, sport.title, games.count { it.state == GameState.LIVE }, games.size, compact, selected,
                dimmed = games.isEmpty()) {
                onFocusList()
                if (!selected) model.homeSelection = HomeSelection.OfSport(sport)
            }
        }
    }
}

@Composable
private fun SportRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector, name: String, live: Int, total: Int, compact: Boolean,
    selected: Boolean, dimmed: Boolean = false, onFocus: () -> Unit
) {
    TvButton(onClick = onFocus, selected = selected, onFocus = onFocus, modifier = Modifier.fillMaxWidth()) { focused ->
        val color = if (focused) Theme.bg else if (dimmed) Theme.muted else Theme.text
        Row(Modifier.padding(horizontal = 10.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, contentDescription = name, tint = color, modifier = Modifier.size(18.dp))
            if (!compact) {
                Spacer(Modifier.width(10.dp))
                Label(name, size = 14.sp, weight = FontWeight.SemiBold, color = color, modifier = Modifier.weight(1f))
            } else {
                Spacer(Modifier.weight(1f))
            }
            if (live > 0) Badge("$live", fill = Theme.accent, color = Theme.onAccent)
            else if (total > 0) Label("$total", size = 11.sp, color = if (focused) Theme.bg else Theme.muted)
        }
    }
}

@Composable
private fun GamesPane(model: AppModel, onFocusPane: () -> Unit, modifier: Modifier) {
    val selection = model.homeSelection
    val sport = when (selection) {
        is HomeSelection.OfSport -> selection.sport
        is HomeSelection.OfLeague -> League.all.firstOrNull { it.id == selection.leagueId }?.sport
        else -> null
    }
    val games = when (selection) {
        is HomeSelection.LiveNow -> model.games.filter { it.state == GameState.LIVE }
        is HomeSelection.OfSport -> model.games(selection.sport)
        is HomeSelection.OfLeague -> model.games.filter { it.league.id == selection.leagueId }
    }.sortedWith(compareBy<Game> { when (it.state) { GameState.LIVE -> 0; GameState.UPCOMING -> 1; else -> 2 } }
        .thenBy { it.start ?: Long.MAX_VALUE })
    Column(modifier.fillMaxHeight()) {
        if (sport != null && sport.leagues.size > 1) {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp), contentPadding = PaddingValues(vertical = 8.dp)) {
                item {
                    val g = model.games(sport)
                    Chip("All", g.count { it.state == GameState.LIVE }, g.size, selection is HomeSelection.OfSport) {
                        onFocusPane(); model.homeSelection = HomeSelection.OfSport(sport)
                    }
                }
                items(sport.leagues) { league ->
                    val g = model.games.filter { it.league.id == league.id }
                    Chip(league.name, g.count { it.state == GameState.LIVE }, g.size,
                        (selection as? HomeSelection.OfLeague)?.leagueId == league.id) {
                        onFocusPane(); model.homeSelection = HomeSelection.OfLeague(league.id)
                    }
                }
            }
        }
        if (games.isEmpty()) {
            Label(when {
                model.loading && model.games.isEmpty() -> "Loading today's games…"
                model.error != null -> model.error!!
                selection is HomeSelection.LiveNow -> "Nothing live right now."
                else -> "No games today."
            }, size = 14.sp, color = Theme.muted, maxLines = 3, modifier = Modifier.padding(top = 16.dp))
        }
        LazyVerticalGrid(GridCells.Adaptive(250.dp), horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp), contentPadding = PaddingValues(vertical = 8.dp)) {
            items(games, key = { it.id }) { game ->
                GameCard(model, game, showLeague = selection is HomeSelection.LiveNow, onFocus = onFocusPane) {
                    model.openGameId = game.id
                }
            }
        }
    }
}

/** Live games as an orange number, otherwise today's games in grey. */
@Composable
private fun Chip(name: String, live: Int, total: Int, selected: Boolean, onFocus: () -> Unit) {
    TvButton(onClick = onFocus, selected = selected, onFocus = onFocus, shape = RoundedCornerShape(18.dp),
        modifier = Modifier.border(1.dp, Theme.border, RoundedCornerShape(18.dp))) { focused ->
        Row(Modifier.padding(horizontal = 14.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Label(name, size = 13.sp, weight = FontWeight.SemiBold, color = if (focused) Theme.bg else Theme.text)
            if (live > 0) Badge("$live", fill = Theme.accent, color = Theme.onAccent)
            else if (total > 0) Label("$total", size = 11.sp, color = if (focused) Theme.bg else Theme.muted)
        }
    }
}

@Composable
private fun GameCard(model: AppModel, game: Game, showLeague: Boolean, onFocus: () -> Unit, onClick: () -> Unit) {
    val streams = model.streams(game.id).filter { !it.hidden }
    TvButton(onClick = onClick, onFocus = onFocus, background = Theme.card, modifier = Modifier.fillMaxWidth()) { focused ->
        val text = if (focused) Theme.bg else Theme.text
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Label((if (showLeague) game.league.name + " · " else "") +
                        (if (game.state == GameState.LIVE) "LIVE · " else "") + game.statusText,
                    size = 11.sp, weight = FontWeight.Bold,
                    color = if (game.state == GameState.LIVE) Theme.accent else if (focused) Theme.bg else Theme.muted,
                    modifier = Modifier.weight(1f))
                if (streams.any { it.is4K }) Badge("4K", fill = Theme.accent, color = Theme.onAccent)
                if (streams.isNotEmpty()) Label("  ${streams.size}", size = 11.sp, color = if (focused) Theme.bg else Theme.muted)
            }
            if (game.isEvent && !game.hasSides) {
                Label(game.eventTitle, size = 15.sp, weight = FontWeight.SemiBold, color = text, maxLines = 2)
                if (game.eventDetail.isNotEmpty()) Label(game.eventDetail, size = 12.sp, color = if (focused) Theme.bg else Theme.muted)
            } else {
                for (team in listOf(game.away, game.home)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Logo(team.logo, 24.dp, team.abbr)
                        Spacer(Modifier.width(8.dp))
                        Label(team.shortName.ifEmpty { team.name }, size = 15.sp, weight = FontWeight.SemiBold, color = text,
                            modifier = Modifier.weight(1f))
                        if (game.state != GameState.UPCOMING) {
                            Label(team.score, size = if (team.hasLongScore) 12.sp else 17.sp, weight = FontWeight.Bold,
                                color = if (focused) Theme.bg else scoreColor(game, team))
                        }
                    }
                }
            }
        }
    }
}

// MARK: Game screen

@Composable
fun GameScreen(model: AppModel, gameId: String) {
    val context = LocalContext.current
    val game = model.games.firstOrNull { it.id == gameId }
    if (game == null) {
        Label("This game isn't on today's schedule any more.", size = 14.sp, color = Theme.muted, modifier = Modifier.padding(Theme.margin))
        return
    }
    val all = model.streams(gameId)
    val listing = StreamSections.build(all, game.league)
    var folded by remember { mutableStateOf(setOf<String>()) }
    var showForeign by remember { mutableStateOf(Prefs.showForeign(context)) }
    var showLocal by remember { mutableStateOf(false) }
    val shown = listing.sections.flatMap { it.streams } +
        (if (showForeign) listing.foreign.flatMap { it.streams } else emptyList()) +
        (if (showLocal) listing.extras else emptyList())
    val lineup = shown.map { it.channel }
    val pinnedHere = model.pinned?.channel?.id?.let { id -> all.any { it.channel.id == id } } == true

    // Opening a game plays its first stream in the player at the top (unless one of its streams already is).
    LaunchedEffect(gameId, all.isNotEmpty()) {
        if (!pinnedHere) shown.firstOrNull()?.let { model.pin(it.channel, game.title, lineup) }
    }

    fun select(m: StreamMatch) {
        if (model.pinned?.channel?.id == m.channel.id) model.play(m.channel, game.title, lineup)
        else model.pin(m.channel, game.title, lineup)
    }

    LazyVerticalGrid(GridCells.Adaptive(260.dp), modifier = Modifier.fillMaxSize().padding(horizontal = Theme.margin),
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp),
        contentPadding = PaddingValues(vertical = 8.dp)) {
        if (!pinnedHere) {
            item(span = { GridItemSpan(maxLineSpan) }) { ScoreHeader(game) }
        }
        if (all.isEmpty()) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                Label(if (model.channels.isEmpty()) "Channels are still loading…" else "No streams found for this game yet.",
                    size = 14.sp, color = Theme.muted)
            }
        }
        for (section in listing.sections) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                SectionHeader(section.name, section.streams.size, open = section.name !in folded) {
                    folded = if (section.name in folded) folded - section.name else folded + section.name
                }
            }
            if (section.name !in folded) items(section.streams, key = { "s${section.name}${it.channel.id}" }) { m ->
                StreamCard(m, playing = model.pinned?.channel?.id == m.channel.id) { select(m) }
            }
        }
        if (listing.foreign.isNotEmpty()) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                GroupButton("Foreign streams", listing.foreignCount, showForeign) {
                    showForeign = !showForeign
                    Prefs.setShowForeign(context, showForeign)
                }
            }
            if (showForeign) for (section in listing.foreign) {
                item(span = { GridItemSpan(maxLineSpan) }) { SectionHeader(section.name, section.streams.size, true) {} }
                items(section.streams, key = { "f${section.name}${it.channel.id}" }) { m ->
                    StreamCard(m, playing = model.pinned?.channel?.id == m.channel.id) { select(m) }
                }
            }
        }
        if (listing.extras.isNotEmpty()) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                GroupButton("Local stations and likely channels", listing.extras.size, showLocal) { showLocal = !showLocal }
            }
            if (showLocal) items(listing.extras, key = { "x${it.channel.id}" }) { m ->
                StreamCard(m, playing = model.pinned?.channel?.id == m.channel.id) { select(m) }
            }
        }
    }
}

@Composable
private fun ScoreHeader(game: Game) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Theme.card).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Label(game.headerText, size = 12.sp, weight = FontWeight.Bold,
            color = if (game.state == GameState.LIVE) Theme.accent else Theme.muted)
        if (game.isEvent && !game.hasSides) {
            Label(game.eventTitle, size = 18.sp, weight = FontWeight.Bold)
        } else for (team in listOf(game.away, game.home)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Logo(team.logo, 28.dp, team.abbr)
                Spacer(Modifier.width(10.dp))
                Label(team.name, size = 17.sp, weight = FontWeight.Bold, modifier = Modifier.weight(1f))
                if (game.state != GameState.UPCOMING) Label(team.score, size = 20.sp, weight = FontWeight.Bold, color = scoreColor(game, team))
            }
        }
    }
}

@Composable
private fun SectionHeader(name: String, count: Int, open: Boolean, onClick: () -> Unit) {
    TvButton(onClick = onClick, modifier = Modifier.padding(top = 4.dp)) { focused ->
        Row(Modifier.padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(if (open) Icons.Filled.ExpandMore else Icons.Filled.ChevronRight, contentDescription = null,
                tint = if (focused) Theme.bg else Theme.muted, modifier = Modifier.size(16.dp))
            Label(name.uppercase(), size = 12.sp, weight = FontWeight.Bold, color = if (focused) Theme.bg else Theme.soft)
            Label("$count", size = 12.sp, color = if (focused) Theme.bg else Theme.muted)
        }
    }
}

@Composable
private fun GroupButton(title: String, count: Int, open: Boolean, onClick: () -> Unit) {
    TvButton(onClick = onClick, background = Theme.card, modifier = Modifier.fillMaxWidth().padding(top = 6.dp)) { focused ->
        Row(Modifier.padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(if (open) Icons.Filled.ExpandMore else Icons.Filled.ChevronRight, contentDescription = null,
                tint = if (focused) Theme.bg else Theme.muted, modifier = Modifier.size(18.dp))
            Label(title, size = 14.sp, weight = FontWeight.SemiBold, color = if (focused) Theme.bg else Theme.text)
            Label("$count", size = 12.sp, color = if (focused) Theme.bg else Theme.muted)
        }
    }
}

@Composable
private fun StreamCard(m: StreamMatch, playing: Boolean, onClick: () -> Unit) {
    TvButton(onClick = onClick, background = Theme.card,
        modifier = Modifier.fillMaxWidth().outline(playing)) { focused ->
        Row(Modifier.padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Label(m.channel.name, size = 14.sp, weight = FontWeight.SemiBold,
                    color = if (focused) Theme.bg else if (playing) Theme.accent else Theme.text)
                if (m.channel.categoryName.isNotEmpty()) Label(m.channel.categoryName, size = 11.sp, color = if (focused) Theme.bg else Theme.soft)
                Label(m.reason, size = 10.sp, color = if (focused) Theme.bg else Theme.muted)
            }
            if (m.quality.isNotEmpty()) Badge(m.quality, fill = if (m.qualityRank == 4) Theme.accent else Theme.raised,
                color = if (m.qualityRank == 4) Theme.onAccent else Theme.soft)
        }
    }
}

// MARK: EPG (next update)

@Composable
fun EpgScreen(model: AppModel) {
    Column(Modifier.fillMaxSize().padding(Theme.margin * 2), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Label("The EPG is coming in the next update.", size = 18.sp, weight = FontWeight.Bold)
        Label("${model.channels.size} channels in ${model.categories.size} categories are loaded.", size = 13.sp, color = Theme.muted)
    }
}

// MARK: Settings

@Composable
fun SettingsScreen(model: AppModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var matchRate by remember { mutableStateOf(Prefs.matchFrameRate(context)) }
    LazyColumn(Modifier.fillMaxSize().padding(horizontal = Theme.margin * 3), verticalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = PaddingValues(vertical = 12.dp)) {
        item { Label("Account", size = 16.sp, weight = FontWeight.Bold) }
        item {
            val a = model.account
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Label("Username: ${model.credentials?.username ?: ""}", size = 13.sp, color = Theme.soft)
                Label("Status: ${a?.status ?: "–"}", size = 13.sp, color = Theme.soft)
                Label("Expires: ${a?.expires?.let { DateFormat.getDateInstance(DateFormat.LONG).format(Date(it * 1000)) } ?: "No expiry date"}",
                    size = 13.sp, color = Theme.soft)
                Label("Connections: ${a?.activeConnections ?: 0} of ${a?.maxConnections ?: 0} in use (as your provider reports it)",
                    size = 13.sp, color = Theme.soft)
            }
        }
        item { Spacer(Modifier.height(8.dp)); Label("Player", size = 16.sp, weight = FontWeight.Bold) }
        item {
            TvButton(onClick = { matchRate = !matchRate; Prefs.setMatchFrameRate(context, matchRate) }, background = Theme.card,
                modifier = Modifier.fillMaxWidth()) { focused ->
                Row(Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
                    Label("Match the TV's refresh rate to the stream (full screen)", size = 13.sp,
                        color = if (focused) Theme.bg else Theme.text, modifier = Modifier.weight(1f))
                    Label(if (matchRate) "On" else "Off", size = 13.sp, weight = FontWeight.SemiBold, color = if (focused) Theme.bg else Theme.accent)
                }
            }
        }
        item { Spacer(Modifier.height(8.dp)); Label("Updates", size = 16.sp, weight = FontWeight.Bold) }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Label("Version ${BuildConfig.VERSION_NAME} (build ${BuildConfig.VERSION_CODE})", size = 13.sp, color = Theme.soft)
                TvButton(onClick = { scope.launch { Updater.check(context, userInitiated = true) } }, background = Theme.card) { focused ->
                    Label(if (Updater.checking) "Checking…" else "Check for updates", size = 13.sp,
                        color = if (focused) Theme.bg else Theme.text, modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp))
                }
                Updater.readyVersion?.let { v ->
                    TvButton(onClick = { Updater.install(context) }, background = Theme.accent) { focused ->
                        Label("Install $v", size = 13.sp, color = if (focused) Theme.bg else Theme.onAccent,
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp))
                    }
                }
                Updater.message?.let { Label(it, size = 12.sp, color = Theme.muted) }
            }
        }
        item {
            Row(Modifier.fillMaxWidth().padding(top = 20.dp), horizontalArrangement = Arrangement.End) {
                TvButton(onClick = { model.signOut() }, background = Theme.card) { focused ->
                    Label("Sign out", size = 13.sp, color = if (focused) Theme.bg else Theme.losing,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                }
            }
        }
    }
}
