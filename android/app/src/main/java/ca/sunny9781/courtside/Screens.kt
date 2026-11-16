@file:OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)

package ca.sunny9781.courtside

import android.view.KeyEvent
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.focusable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.nativeKeyCode
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
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

@Composable
fun CourtsideApp(model: AppModel) {
    Box(Modifier.fillMaxSize().background(Theme.bg)) {
        if (model.credentials == null) LoginScreen(model) else Shell(model)
    }
}

/** Runs `action` once full screen closes, when it was opened from `from` ("strip", "game", "epg"). */
@Composable
fun AfterFullScreen(model: AppModel, from: String, action: () -> Unit) {
    val full = model.nowPlaying != null
    var was by remember { mutableStateOf(full) }
    LaunchedEffect(full) {
        if (was && !full && model.fullScreenFrom == from) {
            delay(250)
            action()
        }
        was = full
    }
}

/** Right at the end of a row goes on to the start of the next one, and left at the start back to the row above. */
@Composable
fun Modifier.wrapRows(): Modifier {
    val focus = androidx.compose.ui.platform.LocalFocusManager.current
    return this.onPreviewKeyEvent { e ->
        if (e.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
        when (e.key.nativeKeyCode) {
            KeyEvent.KEYCODE_DPAD_RIGHT -> focus.moveFocus(FocusDirection.Right) || focus.moveFocus(FocusDirection.Next)
            KeyEvent.KEYCODE_DPAD_LEFT -> focus.moveFocus(FocusDirection.Left) || focus.moveFocus(FocusDirection.Previous)
            else -> false
        }
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

/**
 * A text box. Moving onto it only highlights it; clicking it opens the keyboard (like the Apple TV app), and moving
 * away closes it again.
 */
@Composable
fun Field(hint: String, value: String, onChange: (String) -> Unit, type: KeyboardType = KeyboardType.Text,
          secret: Boolean = false, width: androidx.compose.ui.unit.Dp = 420.dp, onDone: () -> Unit = {}) {
    var focused by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf(false) }
    val input = remember { FocusRequester() }
    var typing by remember { mutableStateOf(false) }
    LaunchedEffect(editing) { if (editing) runCatching { input.requestFocus() } }
    TvButton(onClick = { editing = true }, focusedScale = 1f, background = Theme.card,
        modifier = Modifier.width(width).padding(vertical = 5.dp).onFocusChanged { if (it.hasFocus) focused = true else if (!editing) focused = false }) { _ ->
        Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Theme.card)
            .border(1.5.dp, if (focused || editing) Theme.accent else Theme.border, RoundedCornerShape(10.dp))
            .padding(horizontal = 14.dp, vertical = 10.dp)) {
            if (value.isEmpty()) Label(hint, size = 14.sp, color = Theme.muted)
            BasicTextField(
                value = value, onValueChange = onChange, singleLine = true,
                textStyle = TextStyle(color = Theme.text, fontSize = 14.sp),
                cursorBrush = SolidColor(Theme.accent),
                visualTransformation = if (secret) PasswordVisualTransformation() else VisualTransformation.None,
                keyboardOptions = KeyboardOptions(keyboardType = type),
                keyboardActions = androidx.compose.foundation.text.KeyboardActions(onDone = { onDone() }, onSearch = { onDone() }),
                modifier = Modifier.fillMaxWidth().focusProperties { canFocus = editing }.focusRequester(input)
                    .onFocusChanged {
                        if (it.isFocused) typing = true
                        else if (typing) { typing = false; editing = false; focused = false }
                    }
            )
        }
    }
}

// MARK: Shell

@Composable
fun Shell(model: AppModel) {
    val full = model.nowPlaying != null
    val strip = remember { FocusTargets() }
    // Back: full screen → the player at the top; game screen → Home list; EPG/Settings → Home; Home → leaves the app.
    BackHandler(enabled = full || model.openGameId != null || model.tab != Tab.HOME) {
        when {
            model.nowPlaying != null -> model.closePlayer()
            model.tab != Tab.HOME -> model.tab = Tab.HOME
            model.openGameId != null -> model.closeGame()
        }
    }
    // Remember the quality and frame rate each channel really plays at (they beat what its name says).
    val current = model.nowPlaying ?: model.pinned
    LaunchedEffect(Playback.resolution, current?.channel?.id) {
        current?.let { model.recordQuality(it.channel.id, Playback.resolution) }
    }
    LaunchedEffect(Playback.frameRate, current?.channel?.id) {
        current?.let { model.recordFrameRate(it.channel.id, Playback.frameRate) }
    }
    AfterFullScreen(model, "strip") { strip.focus("video") }

    Box(
        Modifier.fillMaxSize().onKeyEvent { e ->
            // Play/Pause on the remote stops the player at the top (and frees the connection).
            if (e.type == KeyEventType.KeyDown && !full && model.pinned != null &&
                e.key.nativeKeyCode in listOf(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PAUSE, KeyEvent.KEYCODE_MEDIA_STOP)
            ) { model.stopPinned(); true } else false
        }
    ) {
        Column(Modifier.fillMaxSize().padding(top = Theme.margin).alpha(if (full) 0f else 1f).enterAt({ full }) { FocusRequester.Default }) {
            TopBar(model)
            model.pinned?.let { item -> PlayerStrip(model, item, strip) }
            // Moving left or right off the edge of a page goes nowhere (not up to the top bar).
            Box(Modifier.weight(1f).fillMaxWidth().focusProperties {
                exit = { d ->
                    if (d == FocusDirection.Left || d == FocusDirection.Right || d == FocusDirection.Next || d == FocusDirection.Previous)
                        FocusRequester.Cancel else FocusRequester.Default
                }
            }.focusGroup()) {
                when (model.tab) {
                    Tab.HOME -> {
                        val open = model.openGameId
                        if (open != null) GameScreen(model, open) else HomeScreen(model)
                    }
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

/** Home, EPG and Settings in the middle (moving across them switches straight away); "Updated 9:10 PM" on the right. */
@Composable
fun TopBar(model: AppModel) {
    val context = LocalContext.current
    val tabs = remember { FocusTargets() }
    Box(Modifier.fillMaxWidth().padding(horizontal = Theme.margin).height(40.dp)) {
        // Coming back up to the tabs lands on the one you're on, so it doesn't switch by accident.
        Row(Modifier.align(Alignment.Center).onFocusChanged { model.tabsFocused = it.hasFocus }.enterAt { tabs[model.tab] },
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            for (tab in Tab.entries) {
                TvButton(onClick = { model.tab = tab }, selected = model.tab == tab, shape = RoundedCornerShape(20.dp),
                    onFocus = { if (model.tab != tab) model.tab = tab }, modifier = Modifier.tracked(tabs, tab)) { focused ->
                    Row(Modifier.padding(horizontal = 18.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        val color = if (focused) Theme.bg else if (model.tab == tab) Theme.text else Theme.muted
                        when (tab) {
                            Tab.EPG -> Icon(Icons.Filled.Tv, null, tint = color, modifier = Modifier.size(15.dp))
                            Tab.SETTINGS -> Icon(Icons.Filled.Tune, null, tint = color, modifier = Modifier.size(15.dp))
                            else -> {}
                        }
                        Label(tab.title, size = 15.sp, weight = FontWeight.SemiBold, color = color)
                    }
                }
            }
        }
        Row(Modifier.align(Alignment.CenterEnd), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Updater.readyVersion?.let { v ->
                TvButton(onClick = { Updater.install(context) }, background = Theme.accent) { focused ->
                    Label("Install update $v", size = 12.sp, weight = FontWeight.SemiBold,
                        color = if (focused) Theme.bg else Theme.onAccent, modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp))
                }
            }
            if (model.loading) {
                Label("Downloading channels…", size = 12.sp, color = Theme.muted)
            } else model.updatedAt?.let { at ->
                // Like the Apple TV app: "Updated 9:10 PM" is itself the refresh button.
                TvButton(onClick = { model.refresh(force = true) }) { focused ->
                    Row(Modifier.padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                        Icon(Icons.Filled.Refresh, null, tint = if (focused) Theme.bg else Theme.muted, modifier = Modifier.size(13.dp))
                        Label("Updated ${clockTime(at)} · v${BuildConfig.VERSION_NAME}", size = 12.sp,
                            color = if (focused) Theme.bg else Theme.muted)
                    }
                }
            }
        }
    }
}

// MARK: Player

/** The video. Only one view shows the player at a time: the newest one takes it. */
@Composable
fun PlayerVideo(modifier: Modifier = Modifier, small: Boolean = false) {
    AndroidView(
        factory = { ctx ->
            // The player at the top draws into a texture: a 4K or HDR stream there doesn't switch the TV into HDR
            // or another refresh rate. Full screen uses a real video surface, so HDR works there.
            (android.view.LayoutInflater.from(ctx).inflate(if (small) R.layout.player_texture else R.layout.player_surface, null) as PlayerView).apply {
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

/**
 * The player under the tabs, in the same spot on every screen while something plays. Move up onto the video and
 * click it for full screen (it can't take focus straight from the tabs, so pressing down from them lands on the
 * page). Play/Pause on the remote stops it.
 */
@Composable
fun PlayerStrip(model: AppModel, item: NowPlaying, targets: FocusTargets) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = Theme.margin, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        TvButton(onClick = { model.play(item.channel, item.gameTitle, item.lineup, from = "strip") }, focusedScale = 1.03f,
            modifier = Modifier.focusProperties { canFocus = !model.tabsFocused }.tracked(targets, "video")
                .size(Theme.playerWidth, Theme.playerWidth * 9 / 16)) { _ ->
            if (model.nowPlaying == null) PlayerVideo(Modifier.fillMaxSize().padding(2.dp).clip(RoundedCornerShape(8.dp)), small = true)
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.padding(top = 2.dp)) {
            Label(model.playerTitle(item), size = 16.sp, weight = FontWeight.Bold)
            Label(item.channel.name, size = 11.sp, color = Theme.muted)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (Playback.resolution.isNotEmpty()) Badge(Playback.resolution)
                if (Playback.frameRate > 0) Badge(Playback.fpsLabel(Playback.frameRate))
            }
        }
    }
}

/**
 * Full screen. Up/down: previous/next stream for this game (or channel in this category). Any other button shows
 * the info bar. Play/Pause pauses. Back returns to the player at the top. A stream that fails, stops or buffers for
 * 10 seconds switches to the next one (USA and Canada first).
 */
@Composable
fun FullScreenPlayer(model: AppModel, item: NowPlaying) {
    val focus = remember { FocusRequester() }
    var showInfo by remember { mutableStateOf(true) }
    var poke by remember { mutableIntStateOf(0) }
    var flip by remember { mutableStateOf<String?>(null) }
    var flipTick by remember { mutableIntStateOf(0) }
    var tried by remember { mutableStateOf(setOf(item.channel.id)) }
    var automatic by remember { mutableStateOf(false) }
    val pos = item.lineup.indexOfFirst { it.id == item.channel.id } + 1

    fun message(text: String) { flip = text; flipTick++ }

    LaunchedEffect(poke, item.channel.id, Playback.status) {
        showInfo = true
        delay(4000)
        if (Playback.status == Playback.Status.PLAYING) showInfo = false
    }
    LaunchedEffect(flipTick) {
        if (flip == null) return@LaunchedEffect
        delay(if (flip!!.contains("Switched") || flip!!.contains("left")) 4000 else 2000)
        flip = null
    }
    LaunchedEffect(item.channel.id) {
        if (automatic) automatic = false
        else {
            if (tried.isNotEmpty() && item.channel.id !in tried && item.lineup.size > 1) message("$pos of ${item.lineup.size} · ${item.channel.name}")
            tried = setOf(item.channel.id)
        }
    }
    // Stalled or stopped: try the next stream nobody has tried yet, USA and Canada first.
    LaunchedEffect(item.channel.id) {
        var stalledFor = 0
        var attempt = Playback.attempt
        while (true) {
            delay(1000)
            // Trying the stream's other format starts the clock again.
            if (Playback.attempt != attempt) { attempt = Playback.attempt; stalledFor = 0 }
            if (!model.settings.autoSwitch || item.lineup.size < 2) continue
            val why = when (Playback.status) {
                Playback.Status.FAILED, Playback.Status.ENDED -> "The stream stopped"
                Playback.Status.BUFFERING, Playback.Status.OPENING -> { stalledFor++; if (stalledFor >= 10) "The stream stalled" else null }
                else -> { stalledFor = 0; null }
            } ?: continue
            stalledFor = 0
            val untried = item.lineup.filter { it.id !in tried }
            val next = untried.firstOrNull { Matcher.country(it) in listOf<String?>("USA", "Canada") } ?: untried.firstOrNull()
            if (next == null) { message("$why. No other streams left to try."); break }
            tried = tried + next.id
            automatic = true
            model.play(next, item.gameTitle, item.lineup)
            message("$why. Switched to ${next.name}")
            break
        }
    }
    LaunchedEffect(Unit) { focus.requestFocus() }

    Box(
        Modifier.fillMaxSize().background(Color.Black).focusRequester(focus).focusable()
            .onKeyEvent { e ->
                if (e.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (e.key.nativeKeyCode) {
                    KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_CHANNEL_UP -> { model.step(-1); poke++; true }
                    KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_CHANNEL_DOWN -> { model.step(1); poke++; true }
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
        Box(Modifier.align(Alignment.Center)) {
            when (Playback.status) {
                Playback.Status.FAILED -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(Icons.Filled.Warning, null, tint = Theme.accent, modifier = Modifier.size(32.dp))
                    Label("This stream couldn't be opened.", size = 15.sp, color = Theme.soft)
                    Label(if (item.lineup.size > 1) "Press up or down for another stream." else "Press Back to choose another channel.",
                        size = 13.sp, color = Theme.muted)
                }
                Playback.Status.ENDED -> Label("The stream stopped. Press up or down for another stream.", size = 15.sp, color = Theme.soft)
                Playback.Status.PAUSED -> Icon(Icons.Filled.Pause, null, tint = Theme.text.copy(alpha = 0.85f), modifier = Modifier.size(44.dp))
                else -> if (Playback.resolution.isEmpty()) Label("Opening ${item.channel.name}…", size = 15.sp, color = Theme.soft)
            }
        }
        flip?.let {
            Box(Modifier.align(Alignment.TopCenter).padding(top = 30.dp).clip(RoundedCornerShape(20.dp))
                .background(Color.Black.copy(alpha = 0.75f)).padding(horizontal = 16.dp, vertical = 9.dp)) {
                Label(it, size = 14.sp, weight = FontWeight.SemiBold)
            }
        }
        if (showInfo) {
            Row(
                Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                    .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.85f))))
                    .padding(horizontal = 40.dp, vertical = 22.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                ChannelIcon(item.channel.icon, 36.dp)
                Column(Modifier.weight(1f)) {
                    Label(model.playerTitle(item), size = 17.sp, weight = FontWeight.Bold)
                    Label(if (item.lineup.size > 1) "${item.channel.name} · $pos of ${item.lineup.size} · Press up or down to switch"
                          else item.channel.name, size = 12.sp, color = Theme.soft)
                }
                if (Playback.resolution.isNotEmpty()) Badge(Playback.resolution)
                if (Playback.frameRate > 0) Badge(Playback.fpsLabel(Playback.frameRate))
            }
        }
    }
}

// MARK: Home

/**
 * Home, like the Apple TV app: Live Now and the sports down the left, games on the right. Moving onto a sport shows
 * its games; clicking a game opens its streams. Coming back from the games lands on the sport you left.
 */
@Composable
fun HomeScreen(model: AppModel) {
    val back = model.returnToGame
    var inPane by remember { mutableStateOf(back != null) }
    val side = remember { FocusTargets() }
    val pane = remember { FocusTargets() }
    var lastGame by remember { mutableStateOf(back) }
    val width by animateDpAsState(if (inPane) 64.dp else Theme.playerWidth, label = "sidebar")

    // Back from a game: focus goes to its card.
    LaunchedEffect(Unit) {
        val id = model.returnToGame ?: return@LaunchedEffect
        model.returnToGame = null
        repeat(10) {
            delay(50)
            if (pane.focus("game:$id")) return@LaunchedEffect
        }
    }

    Row(Modifier.fillMaxSize().padding(horizontal = Theme.margin).enterAt {
        side[sidebarKey(model.homeSelection)]
    }) {
        SportList(model, side, compact = inPane,
            modifier = Modifier.width(width).onFocusChanged { if (it.hasFocus) inPane = false }
                .enterAt { side[sidebarKey(model.homeSelection)] })
        Spacer(Modifier.width(if (inPane) 14.dp else 18.dp))
        GamesPane(model, pane, onOpen = { lastGame = it; model.openGameId = it }, onFocusGame = { lastGame = it },
            modifier = Modifier.weight(1f).onFocusChanged { if (it.hasFocus) inPane = true }
                .enterAt { pane["game:$lastGame"] })
    }
}

private fun sidebarKey(s: HomeSelection): String = when (s) {
    is HomeSelection.LiveNow -> "live"
    is HomeSelection.OfSport -> s.sport.name
    is HomeSelection.OfLeague -> League.all.firstOrNull { it.id == s.leagueId }?.sport?.name ?: "live"
}

private fun selectedSport(s: HomeSelection): Sport? = when (s) {
    is HomeSelection.OfSport -> s.sport
    is HomeSelection.OfLeague -> League.all.firstOrNull { it.id == s.leagueId }?.sport
    else -> null
}

@Composable
private fun SportList(model: AppModel, targets: FocusTargets, compact: Boolean, modifier: Modifier) {
    val sports = model.orderedSports()
    val favs = model.settings.favoriteSet
    val open = selectedSport(model.homeSelection)
    Column(modifier.fillMaxHeight().verticalScroll(rememberScrollState()).padding(vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp)) {
        val shown = model.games.filter { it.league.sport in sports }
        SportRow(targets, "live", Icons.Filled.Sensors, "Live Now", shown.count { it.state == GameState.LIVE }, shown.size,
            "${model.games.size} today", compact, selected = model.homeSelection == HomeSelection.LiveNow) {
            if (model.homeSelection != HomeSelection.LiveNow) model.homeSelection = HomeSelection.LiveNow
        }
        Spacer(Modifier.height(8.dp))
        for (sport in sports) {
            val games = model.games(sport)
            SportRow(targets, sport.name, sport.icon, sport.title, games.count { it.state == GameState.LIVE }, games.size,
                if (games.isEmpty()) "No games" else "${games.size} today", compact, selected = open == sport,
                favorite = sport in favs, dimmed = games.isEmpty()) {
                // Coming back to the sport whose league you picked on the right keeps that league.
                if (open != sport) model.homeSelection = HomeSelection.OfSport(sport)
            }
        }
    }
}

/** Live games as an orange number; otherwise today's count. Moving onto a row shows its games. */
@Composable
private fun SportRow(
    targets: FocusTargets, key: String, icon: androidx.compose.ui.graphics.vector.ImageVector, name: String, live: Int,
    total: Int, detail: String, compact: Boolean, selected: Boolean, favorite: Boolean = false, dimmed: Boolean = false,
    select: () -> Unit
) {
    TvButton(onClick = select, selected = selected, onFocus = select,
        modifier = Modifier.fillMaxWidth().tracked(targets, key).alpha(if (dimmed) 0.5f else 1f)) { focused ->
        val color = if (focused) Theme.bg else Theme.text
        Row(Modifier.padding(horizontal = 10.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, contentDescription = name, tint = color, modifier = Modifier.size(18.dp))
            if (compact) {
                Spacer(Modifier.weight(1f))
                if (live > 0) Badge("$live", fill = Theme.accent, color = Theme.onAccent)
                else if (total > 0) Label("$total", size = 11.sp, color = color.copy(alpha = 0.6f))
            } else {
                Spacer(Modifier.width(10.dp))
                Label(name, size = 14.sp, weight = FontWeight.SemiBold, color = color)
                if (favorite) {
                    Spacer(Modifier.width(5.dp))
                    Icon(Icons.Filled.Favorite, null, tint = Theme.accent, modifier = Modifier.size(10.dp))
                }
                Spacer(Modifier.weight(1f).widthIn(min = 6.dp))
                if (live > 0) Badge("$live", fill = Theme.accent, color = Theme.onAccent)
                else Label(detail, size = 11.sp, color = color.copy(alpha = 0.6f))
            }
        }
    }
}

private data class PaneSection(val id: String, val title: String, val icon: androidx.compose.ui.graphics.vector.ImageVector?,
                               val league: League?, val games: List<Game>)

private fun sortedGames(games: List<Game>) = games.sortedWith(
    compareBy<Game> { when (it.state) { GameState.LIVE -> 0; GameState.UPCOMING -> 1; else -> 2 } }.thenBy { it.start ?: Long.MAX_VALUE })

@Composable
private fun GamesPane(model: AppModel, targets: FocusTargets, onOpen: (String) -> Unit, onFocusGame: (String) -> Unit,
                      modifier: Modifier) {
    val selection = model.homeSelection
    val sport = selectedSport(selection)
    val sections: List<PaneSection> = when (selection) {
        // Only games that are live right now, by sport.
        is HomeSelection.LiveNow -> model.orderedSports().mapNotNull { s ->
            val g = model.games(s).filter { it.state == GameState.LIVE }
            if (g.isEmpty()) null else PaneSection(s.name, s.title, s.icon, null, sortedGames(g))
        }
        is HomeSelection.OfSport -> model.leagues(selection.sport).mapNotNull { l ->
            val g = model.games.filter { it.league.id == l.id }
            if (g.isEmpty()) null else PaneSection(l.id, l.name, null, l, sortedGames(g))
        }
        is HomeSelection.OfLeague -> League.all.firstOrNull { it.id == selection.leagueId }?.let { l ->
            listOf(PaneSection(l.id, l.name, null, l, sortedGames(model.games.filter { it.league.id == l.id })))
        } ?: emptyList()
    }
    LazyVerticalGrid(GridCells.Adaptive(230.dp), modifier = modifier.fillMaxHeight().wrapRows(), state = model.homeGrid,
        horizontalArrangement = Arrangement.spacedBy(14.dp), verticalArrangement = Arrangement.spacedBy(14.dp),
        contentPadding = PaddingValues(top = 8.dp, bottom = 16.dp, start = 6.dp, end = 6.dp)) {
        if (sport != null && model.leagues(sport).size > 1) {
            item(span = { GridItemSpan(maxLineSpan) }, key = "chips") { LeagueChips(model, sport, targets) }
        }
        if (sections.isEmpty()) {
            item(span = { GridItemSpan(maxLineSpan) }, key = "empty") {
                Label(when {
                    model.error != null -> model.error!!
                    model.loading && model.games.isEmpty() -> "Loading today's games…"
                    selection is HomeSelection.LiveNow -> "Nothing live right now."
                    else -> "No games today."
                }, size = 14.sp, color = Theme.muted, maxLines = 3, modifier = Modifier.padding(top = 8.dp))
            }
        }
        for (section in sections) {
            item(span = { GridItemSpan(maxLineSpan) }, key = "h:${section.id}") {
                Row(Modifier.padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (section.league != null) LeagueLogo(model, section.league, 22.dp)
                    else section.icon?.let { Icon(it, null, tint = Theme.accent, modifier = Modifier.size(16.dp)) }
                    Label(section.title, size = 15.sp, weight = FontWeight.Bold)
                }
            }
            items(section.games, key = { "${section.id}:${it.id}" }) { game ->
                GameCard(model, game, showLeague = selection is HomeSelection.LiveNow,
                    modifier = Modifier.tracked(targets, "game:${game.id}"),
                    onFocus = { onFocusGame(game.id) }) { onOpen(game.id) }
            }
        }
    }
}

/** "All · NBA · WNBA · NCAA Men…", leagues with live games first. Moving across them switches straight away. */
@Composable
private fun LeagueChips(model: AppModel, sport: Sport, targets: FocusTargets) {
    val leagues = model.leagues(sport)
    val ordered = leagues.withIndex().sortedWith(compareBy({ (_, l) ->
        val g = model.games.filter { it.league.id == l.id }
        if (g.any { it.state == GameState.LIVE }) 0 else if (g.isEmpty()) 2 else 1
    }, { it.index })).map { it.value }
    val selection = model.homeSelection
    Row(Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        val all = model.games(sport)
        Chip(targets, "chip:all", null, "All", all.count { it.state == GameState.LIVE }, all.size,
            selection == HomeSelection.OfSport(sport), model) {
            if (model.homeSelection != HomeSelection.OfSport(sport)) model.homeSelection = HomeSelection.OfSport(sport)
        }
        for (league in ordered) {
            val g = model.games.filter { it.league.id == league.id }
            Chip(targets, "chip:${league.id}", league, league.name, g.count { it.state == GameState.LIVE }, g.size,
                (selection as? HomeSelection.OfLeague)?.leagueId == league.id, model, dimmed = g.isEmpty()) {
                if ((model.homeSelection as? HomeSelection.OfLeague)?.leagueId != league.id) model.homeSelection = HomeSelection.OfLeague(league.id)
            }
        }
    }
}

@Composable
private fun Chip(targets: FocusTargets, key: String, league: League?, name: String, live: Int, total: Int, selected: Boolean,
                 model: AppModel, dimmed: Boolean = false, select: () -> Unit) {
    TvButton(onClick = select, selected = selected, onFocus = select, shape = RoundedCornerShape(18.dp),
        modifier = Modifier.tracked(targets, key).alpha(if (dimmed) 0.5f else 1f)
            .border(1.dp, if (selected) Color.Transparent else Theme.border, RoundedCornerShape(18.dp))) { focused ->
        Row(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            if (league != null) LeagueLogo(model, league, 15.dp)
            Label(name, size = 12.sp, weight = FontWeight.SemiBold, color = if (focused) Theme.bg else Theme.text)
            if (live > 0) Badge("$live", fill = Theme.accent, color = Theme.onAccent)
            else if (total > 0) Label("$total", size = 10.sp, color = if (focused) Theme.bg else Theme.muted)
        }
    }
}

/** Status and stream count on top, then both teams with logos and scores. */
@Composable
private fun GameCard(model: AppModel, game: Game, showLeague: Boolean, modifier: Modifier, onFocus: () -> Unit, onClick: () -> Unit) {
    val main = model.mainStreams(game.id)
    val count = main.size
    TvButton(onClick = onClick, onFocus = onFocus, background = Theme.card, focusedScale = 1.05f,
        modifier = modifier.fillMaxWidth().heightIn(min = 96.dp)) { focused ->
        val text = if (focused) Theme.bg else Theme.text
        val soft = if (focused) Theme.bg else Theme.soft
        Column(Modifier.padding(12.dp).alpha(when (game.state) { GameState.UPCOMING -> 0.6f; GameState.FINISHED -> 0.85f; else -> 1f }),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Label(if (showLeague) "${game.league.name} · ${cardHeader(game)}" else cardHeader(game), size = 10.sp,
                    weight = FontWeight.Bold, color = if (game.state == GameState.LIVE) Theme.accent else soft,
                    modifier = Modifier.weight(1f))
                if (main.any { it.is4K }) Badge("4K", fill = Theme.accent, color = Theme.onAccent)
                Label(if (count == 0) "No streams" else "$count", size = 10.sp,
                    color = if (count == 0) Theme.losing else if (focused) Theme.bg else Theme.muted)
                if (count > 0) Icon(Icons.Filled.LiveTv, null, tint = if (focused) Theme.bg else Theme.muted, modifier = Modifier.size(10.dp))
            }
            if (game.isEvent && !game.hasSides) {
                Label(game.eventTitle, size = 14.sp, weight = FontWeight.Bold, color = text, maxLines = 2)
                if (game.eventDetail.isNotEmpty()) Label(game.eventDetail, size = 11.sp, color = soft, maxLines = 2)
            } else {
                for (team in listOf(game.away, game.home)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Logo(team.logo, 24.dp, team.abbr)
                        Spacer(Modifier.width(8.dp))
                        Column(Modifier.weight(1f)) {
                            Label(team.shortName.ifEmpty { team.name }, size = 14.sp, weight = FontWeight.SemiBold, color = text)
                            if (game.state != GameState.UPCOMING && team.hasLongScore) {
                                Label(team.score, size = 11.sp, weight = FontWeight.Bold, color = if (focused) Theme.bg else scoreColor(game, team))
                            }
                        }
                        if (game.state != GameState.UPCOMING && !team.hasLongScore) {
                            Label(team.score, size = 17.sp, weight = FontWeight.Bold, color = if (focused) Theme.bg else scoreColor(game, team))
                        }
                    }
                }
            }
        }
    }
}

// MARK: Game screen

/**
 * A game: the score (until one of its streams plays in the player at the top), then every stream in sections.
 * Opening it plays the first stream at the top; click a stream to play it there, click it again for full screen.
 */
@Composable
fun GameScreen(model: AppModel, gameId: String) {
    val game = model.games.firstOrNull { it.id == gameId }
    if (game == null) {
        Label("This game is no longer on today's schedule.", size = 14.sp, color = Theme.muted, modifier = Modifier.padding(Theme.margin))
        return
    }
    val targets = remember { FocusTargets() }
    val s = model.settings
    val all = model.streams(gameId).let { list -> if (s.hideSD) list.filter { it.quality != "SD" } else list }
    val listing = StreamSections.build(all, game.league)
    var folded by remember { mutableStateOf(setOf<String>()) }
    var showLocal by remember { mutableStateOf(false) }
    val shown = listing.sections.flatMap { it.streams } +
        (if (s.showForeign) listing.foreign.flatMap { it.streams } else emptyList()) +
        (if (showLocal) listing.extras else emptyList())
    val lineup = shown.map { it.channel }
    val pinnedHere = model.pinnedIsFrom(gameId)
    val previewId = if (pinnedHere) model.pinned?.channel?.id else null

    // Opening a game plays its first stream in the player at the top (unless one of its streams already is), and
    // focus starts on the stream that's playing.
    LaunchedEffect(gameId, all.isNotEmpty()) {
        var id = previewId
        if (!pinnedHere) shown.firstOrNull()?.let { model.pin(it.channel, game.title, lineup); id = it.channel.id }
        delay(80)
        // Focus always lands somewhere on this screen (not on the Home list hidden behind it).
        targets.focus("s:$id") || targets.focus("foreign") || targets.focus("local") || targets.focus("back")
    }
    // Back from full screen: focus goes back to the stream you were watching.
    AfterFullScreen(model, "game") { targets.focus("s:${model.lastPlayedChannelId}") }

    fun select(m: StreamMatch) {
        if (previewId == m.channel.id) model.play(m.channel, game.title, lineup, from = "game")
        else model.pin(m.channel, game.title, lineup)
    }

    Column(Modifier.fillMaxSize().background(Theme.bg).padding(horizontal = Theme.margin)) {
        if (!pinnedHere) Hero(model, game)
        LazyVerticalGrid(GridCells.Adaptive(270.dp),
            modifier = Modifier.fillMaxSize().wrapRows().enterAt { targets["s:$previewId"] },
            horizontalArrangement = Arrangement.spacedBy(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp),
            contentPadding = PaddingValues(vertical = 10.dp, horizontal = 6.dp)) {
            if (listing.sections.isEmpty()) {
                item(span = { GridItemSpan(maxLineSpan) }, key = "none") {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Label(if (model.channels.isEmpty()) "Channels are still loading…" else "No streams found for this game yet.",
                            size = 14.sp, color = Theme.muted)
                        if (listing.foreign.isEmpty() && listing.extras.isEmpty()) {
                            Pill("Back to the games", Modifier.tracked(targets, "back")) { model.closeGame() }
                        }
                    }
                }
            }
            fun section(name: String, streams: List<StreamMatch>, prefix: String) {
                item(span = { GridItemSpan(maxLineSpan) }, key = "$prefix:h:$name") {
                    // Click a section's name to fold it shut or open it.
                    SectionHeader(name, streams.size, open = name !in folded) {
                        folded = if (name in folded) folded - name else folded + name
                    }
                }
                if (name !in folded) items(streams, key = { "$prefix:$name:${it.channel.id}" }) { m ->
                    StreamCell(model, m, previewing = m.channel.id == previewId, modifier = Modifier.tracked(targets, "s:${m.channel.id}")) { select(m) }
                }
            }
            for (sec in listing.sections) section(sec.name, sec.streams, "m")
            // Foreign-language countries, folded into one group.
            if (listing.foreign.isNotEmpty()) {
                item(span = { GridItemSpan(maxLineSpan) }, key = "foreign") {
                    Pill(if (s.showForeign) "Hide foreign streams (${listing.foreignCount})" else "Show foreign streams (${listing.foreignCount})",
                        Modifier.tracked(targets, "foreign")) {
                        s.showForeign = !s.showForeign
                    }
                }
                if (s.showForeign) for (sec in listing.foreign) section(sec.name, sec.streams, "f")
            }
            // Local stations and "usually on" guesses, at the very bottom.
            if (listing.extras.isNotEmpty()) {
                item(span = { GridItemSpan(maxLineSpan) }, key = "local") {
                    Pill(if (showLocal) "Hide local stations and likely channels" else "Show ${listing.extras.size} local stations and likely channels",
                        Modifier.tracked(targets, "local")) {
                        showLocal = !showLocal
                    }
                }
                if (showLocal) section("Local and likely", listing.extras, "x")
            }
        }
    }
}

@Composable
private fun Hero(model: AppModel, game: Game) {
    Row(Modifier.fillMaxWidth().padding(top = 4.dp).clip(RoundedCornerShape(12.dp)).background(Theme.card).padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(22.dp)) {
        Column(Modifier.widthIn(max = 380.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                LeagueLogo(model, game.league, 20.dp)
                Label(cardHeader(game), size = 12.sp, weight = FontWeight.Bold,
                    color = if (game.state == GameState.LIVE) Theme.accent else Theme.soft)
            }
            if (game.isEvent && !game.hasSides) {
                Label(game.eventTitle, size = 20.sp, weight = FontWeight.Bold, maxLines = 2)
                if (game.eventDetail.isNotEmpty()) Label(game.eventDetail, size = 13.sp, color = Theme.soft)
            } else for (team in listOf(game.away, game.home)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Logo(team.logo, 30.dp, team.abbr)
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Label(team.name, size = 16.sp, weight = FontWeight.SemiBold)
                        if (game.state != GameState.UPCOMING && team.hasLongScore) Label(team.score, size = 13.sp, weight = FontWeight.Bold, color = scoreColor(game, team))
                        if (team.record.isNotEmpty()) Label(team.record, size = 10.sp, color = Theme.muted)
                    }
                    if (game.state != GameState.UPCOMING && !team.hasLongScore) Label(team.score, size = 24.sp, weight = FontWeight.Bold, color = scoreColor(game, team))
                }
            }
            val lines = buildList {
                if (game.state == GameState.UPCOMING) add("Starts ${startText(game)}")
                if (game.venue.isNotEmpty()) add(game.venue)
                if (game.broadcasters.isNotEmpty()) add("On " + game.broadcasters.joinToString(", "))
            }
            if (lines.isNotEmpty()) Label(lines.joinToString("  ·  "), size = 11.sp, color = Theme.muted, maxLines = 2)
        }
        if (!game.isEvent && game.away.linescores.isNotEmpty()) BoxScore(game)
    }
}

@Composable
private fun BoxScore(game: Game) {
    val periods = maxOf(game.away.linescores.size, game.home.linescores.size)
    Column(Modifier.clip(RoundedCornerShape(10.dp)).background(Theme.raised.copy(alpha = 0.5f)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)) {
        @Composable
        fun cell(text: String, color: Color, bold: Boolean = false, w: Int = 22) =
            Label(text, size = 11.sp, color = color, weight = if (bold) FontWeight.Bold else FontWeight.Normal,
                modifier = Modifier.width(w.dp))
        Row {
            cell("", Theme.muted, w = 36)
            for (i in 0 until periods) cell("${i + 1}", Theme.muted)
            cell("T", Theme.muted)
        }
        for (team in listOf(game.away, game.home)) Row {
            cell(team.abbr, Theme.soft, w = 36)
            for (i in 0 until periods) cell(team.linescores.getOrElse(i) { "–" }, Theme.text)
            cell(team.score, scoreColor(game, team), bold = true)
        }
    }
}

@Composable
private fun SectionHeader(name: String, count: Int, open: Boolean, onClick: () -> Unit) {
    TvButton(onClick = onClick, shape = RoundedCornerShape(16.dp)) { focused ->
        Row(Modifier.padding(horizontal = 10.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(if (open) Icons.Filled.ExpandMore else Icons.Filled.ChevronRight, contentDescription = null,
                tint = if (focused) Theme.bg else Theme.text, modifier = Modifier.size(15.dp))
            Label(name.uppercase(), size = 12.sp, weight = FontWeight.Bold, color = if (focused) Theme.bg else Theme.text)
            Label("$count", size = 11.sp, color = if (focused) Theme.bg else Theme.muted)
        }
    }
}

@Composable
fun Pill(title: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    TvButton(onClick = onClick, background = Theme.raised, shape = RoundedCornerShape(16.dp), modifier = modifier) { focused ->
        Label(title, size = 12.sp, weight = FontWeight.SemiBold, color = if (focused) Theme.bg else Theme.text,
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 7.dp))
    }
}

/** One stream: name, its category, why it matched, and its quality. */
@Composable
private fun StreamCell(model: AppModel, m: StreamMatch, previewing: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val quality = model.measuredQuality[m.channel.id] ?: m.quality
    val fps = model.measuredFrameRate[m.channel.id]
    TvButton(onClick = onClick, background = Theme.card, modifier = modifier.fillMaxWidth().height(60.dp).outline(previewing)) { focused ->
        Row(Modifier.fillMaxSize().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ChannelIcon(m.channel.icon, 30.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Label(m.channel.name, size = 13.sp, weight = FontWeight.SemiBold, maxLines = 2,
                    color = if (focused) Theme.bg else if (previewing) Theme.accent else Theme.text)
                if (m.channel.categoryName.isNotEmpty()) Row(verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    Icon(Icons.Filled.Folder, null, tint = if (focused) Theme.bg else Theme.soft, modifier = Modifier.size(10.dp))
                    Label(m.channel.categoryName, size = 10.sp, color = if (focused) Theme.bg else Theme.soft)
                }
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (quality.isNotEmpty()) Badge(quality, fill = if (quality == "4K") Theme.accent else Theme.raised,
                    color = if (quality == "4K") Theme.onAccent else Theme.soft)
                if (fps != null && fps > 0) Badge(Playback.fpsLabel(fps))
            }
        }
    }
}
