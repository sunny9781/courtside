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
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
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
    // Phones and tablets: the touch app (like the iPhone app).
    if (!Device.tv) { PhoneApp(model); return }
    Box(Modifier.fillMaxSize().background(Theme.bg)) {
        when {
            model.credentials == null -> LoginScreen(model)
            model.editingAccount -> LoginScreen(model, model.credentials) { model.editingAccount = false }
            else -> Shell(model)
        }
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
fun LoginScreen(model: AppModel, editing: Credentials? = null, onDone: (() -> Unit)? = null) {
    var server by remember { mutableStateOf(editing?.server ?: "") }
    var username by remember { mutableStateOf(editing?.username ?: "") }
    var password by remember { mutableStateOf(editing?.password ?: "") }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    Row(Modifier.fillMaxSize().padding(40.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Label("Courtside", size = 30.sp, weight = FontWeight.Bold)
        Spacer(Modifier.height(6.dp))
        Label(if (editing == null) "Sign in with your Xtream Codes details" else "Change your Xtream Codes details",
            size = 14.sp, color = Theme.muted)
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
                val creds = Credentials(server.trim(), username.trim(), password)
                error = if (editing == null) model.signIn(creds) else model.updateAccount(creds)
                working = false
                if (error == null) onDone?.invoke()
            }
        }, background = Theme.accent) { focused ->
            Label(if (working) (if (editing == null) "Signing in…" else "Checking…") else (if (editing == null) "Sign in" else "Save"),
                size = 15.sp, weight = FontWeight.SemiBold,
                color = if (focused) Theme.bg else Theme.onAccent, modifier = Modifier.padding(horizontal = 28.dp, vertical = 10.dp))
        }
        if (onDone != null) {
            Spacer(Modifier.height(8.dp))
            TvButton(onClick = onDone) { focused ->
                Label("Cancel", size = 14.sp, color = if (focused) Theme.bg else Theme.muted,
                    modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp))
            }
            BackHandler { onDone() }
        }
        error?.let {
            Spacer(Modifier.height(12.dp))
            Label(it, size = 13.sp, color = Theme.losing, maxLines = 3)
        }
    }
    // Set up from your phone (2.6): the TV serves a sign-in page on the home network.
    Spacer(Modifier.width(48.dp))
    Box(Modifier.width(1.dp).height(320.dp).background(Theme.border))
    Spacer(Modifier.width(48.dp))
    PhoneSetupPanel { creds ->
        val result = if (editing == null) model.signIn(creds) else model.updateAccount(creds)
        if (result == null) onDone?.invoke()
        result
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
    val keyboard = androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
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
                keyboardOptions = KeyboardOptions(keyboardType = type, imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                keyboardActions = androidx.compose.foundation.text.KeyboardActions(
                    onDone = { keyboard?.hide(); onDone() }, onSearch = { keyboard?.hide(); onDone() }),
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
    // Back goes up one level at a time: full screen → the player; a game → its card on Home; a page (games, channels,
    // a setting) → its left panel, on the selected item; the left panel → the tab you're on in the rail down the left
    // edge; the EPG or Settings tab → Home; the Home tab → leaves the app.
    BackHandler(enabled = full || model.openGameId != null || model.tab != Tab.HOME || !model.tabsFocused) {
        when {
            model.nowPlaying != null -> model.closePlayer()
            model.tabsFocused && model.tab != Tab.HOME -> { model.tab = Tab.HOME; model.focusMoves.tryEmit("tabs") }
            model.openGameId != null -> model.closeGame()
            model.sideFocused -> model.focusMoves.tryEmit("tabs")
            else -> model.focusMoves.tryEmit("side")
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
    LaunchedEffect(Playback.audio, current?.channel?.id) {
        current?.let { model.recordAudio(it.channel.id, Playback.audio) }
    }
    LaunchedEffect(Playback.hdr, current?.channel?.id) {
        current?.let { model.recordHdr(it.channel.id, Playback.hdr) }
    }
    AfterFullScreen(model, "strip") { strip.focus("video") }
    // Update messages ("Turn on Courtside here…", "The update didn't install…") show as a notice.
    LaunchedEffect(Updater.message) { Updater.message?.let { model.notice = it } }

    Box(
        Modifier.fillMaxSize().onPreviewKeyEvent { e ->
            // Holding select stopped the corner player: the rest of that press (it's still held) mustn't reach
            // whatever has focus now (it opened that channel's Favourites menu).
            if (model.swallowSelect && e.nativeKeyEvent.keyCode in listOf(KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER,
                    KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_BUTTON_A)) {
                if (e.type == KeyEventType.KeyUp) model.swallowSelect = false
                true
            } else false
        }.onKeyEvent { e ->
            // Play/Pause on the remote stops the player at the top (and frees the connection).
            if (e.type == KeyEventType.KeyDown && !full && model.pinned != null &&
                e.key.nativeKeyCode in listOf(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PAUSE, KeyEvent.KEYCODE_MEDIA_STOP)
            ) { model.stopPinned(); true } else false
        }
    ) {
        // No top bar (2.4): the tabs and the status (connections, EPG, version) are in the rail down the left edge, so
        // every page starts at the top of the screen.
        Column(Modifier.fillMaxSize().padding(start = RAIL_WIDTH, top = Theme.margin).alpha(if (full) 0f else 1f).enterAt({ full }) { FocusRequester.Default }) {
            Box(Modifier.weight(1f).fillMaxWidth()) {
            // Left off the left edge of a page goes to the rail; right off the right edge goes nowhere.
            Box(Modifier.fillMaxSize().focusProperties {
                exit = { d ->
                    if (d == FocusDirection.Right || d == FocusDirection.Next || d == FocusDirection.Previous || d == FocusDirection.Up || d == FocusDirection.Down)
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
            // The player: bottom-left corner, the same spot on every tab. Each tab's left panel sits on top of it and
            // the page fills the space to its right.
            // Under it, one line across the very bottom: what's playing. Fixed in place; pages scroll under it.
            model.pinned?.let { item -> NowPlayingBar(model, item, Modifier.align(Alignment.BottomStart)) }
            model.pinned?.let { item -> PlayerStrip(model, item, strip, Modifier.align(Alignment.BottomStart).padding(bottom = Theme.margin + Theme.barHeight)) }
            }
        }
        // The video: one view for the corner and full screen, which only changes size. Moving the stream between two
        // views made some channels flash black, wait, or stop when leaving full screen.
        if (model.nowPlaying != null || model.pinned != null) {
            val b = model.cornerBounds
            val density = androidx.compose.ui.platform.LocalDensity.current
            val place = when {
                full -> Modifier.fillMaxSize()
                b != null -> with(density) {
                    Modifier.offset { androidx.compose.ui.unit.IntOffset(b.left.toInt(), b.top.toInt()) }
                        .size(b.width.toDp(), b.height.toDp())
                }
                else -> Modifier.size(0.dp)
            }
            PlayerVideo(place)
        }
        // After the video, so the open rail (and its shade over the page) draws on top of the player in the corner.
        if (!full) NavRail(model)
        model.nowPlaying?.let { FullScreenPlayer(model, it) }
        model.notice?.let { message ->
            Box(Modifier.fillMaxWidth().padding(top = 24.dp), contentAlignment = Alignment.TopCenter) {
                Box(Modifier.clip(RoundedCornerShape(20.dp)).background(Color.Black.copy(alpha = 0.8f))
                    .padding(horizontal = 18.dp, vertical = 8.dp)) {
                    Label(message, size = 14.sp, weight = FontWeight.SemiBold)
                }
            }
            LaunchedEffect(message) {
                delay(if (message.length > 80) 12_000 else 5000)
                if (model.notice == message) model.notice = null
            }
        }
    }
}

/** How wide the rail down the left edge is while you're on a page (icons only), and when you move onto it. */
val RAIL_WIDTH = 56.dp
private val RAIL_OPEN = 214.dp

/**
 * The tabs (Home, EPG, Settings) down the left edge, where every move starts: left from a left panel opens it, right
 * goes back into the page's left panel. Closed it's a strip of icons, with the connections, the EPG time and a dot
 * when an update is ready at the bottom; open it shows names, the full status and the version button, over the page.
 * Moving through the tabs shows a page once you stop on its tab; clicking, or pressing right, is instant.
 */
@Composable
fun NavRail(model: AppModel) {
    val context = LocalContext.current
    val tabs = remember { FocusTargets() }
    val settle = rememberSettle()
    val scope = rememberCoroutineScope()
    val focusManager = androidx.compose.ui.platform.LocalFocusManager.current
    var open by remember { mutableStateOf(false) }
    // Back from a left panel: to the tab you're on.
    LaunchedEffect(Unit) {
        model.focusMoves.collect { if (it == "tabs") { settle.cancel(); delay(30); tabs.focus(model.tab) } }
    }
    // Into the page's left menu, on its selected item (the sport, category or section), never straight into the
    // games: the same as Back from a page in reverse. The rail closes as focus leaves it.
    fun intoPage(waitForPage: Boolean) {
        scope.launch {
            if (waitForPage) { androidx.compose.runtime.withFrameNanos { }; androidx.compose.runtime.withFrameNanos { } }
            model.focusMoves.tryEmit("side")
            delay(120)
            if (model.tabsFocused && runCatching { model.leftPanel.requestFocus() }.isFailure) focusManager.moveFocus(FocusDirection.Right)
        }
    }
    val width by animateDpAsState(if (open) RAIL_OPEN else RAIL_WIDTH,
        androidx.compose.animation.core.tween(if (Perf.slowSettle) 0 else 140), label = "rail")
    if (open) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.55f)))
    Column(Modifier.width(width).fillMaxHeight().background(if (open) Theme.card else Theme.bg)
        .onFocusChanged {
            open = it.hasFocus
            model.tabsFocused = it.hasFocus
            if (!it.hasFocus) settle.flush()
        }
        .onPreviewKeyEvent { e ->
            // Right: into the page's left panel (the selected sport, category or section), after showing the tab
            // you stopped on.
            if (e.type != KeyEventType.KeyDown || e.key.nativeKeyCode != KeyEvent.KEYCODE_DPAD_RIGHT) return@onPreviewKeyEvent false
            intoPage(settle.flush())
            true
        }
        .enterAt { tabs[model.tab] }
        .padding(horizontal = 8.dp, vertical = Theme.margin),
        verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.height(34.dp).padding(horizontal = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            if (open) {
                Label("Court", size = 17.sp, weight = FontWeight.Bold)
                Label("side", size = 17.sp, weight = FontWeight.Bold, color = Theme.accent)
            } else Label("C", size = 17.sp, weight = FontWeight.Bold, color = Theme.accent)
        }
        for (tab in Tab.entries) {
            TvButton(onClick = { settle.now { model.tab = tab }; intoPage(true) }, selected = model.tab == tab,
                onFocus = { if (model.tab != tab) settle.later { model.tab = tab } else settle.cancel() },
                modifier = Modifier.fillMaxWidth().tracked(tabs, tab)) { focused ->
                val color = if (focused) Theme.bg else if (model.tab == tab) Theme.accent else Theme.muted
                Row(Modifier.height(40.dp).padding(horizontal = 10.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(when (tab) { Tab.HOME -> Icons.Filled.Home; Tab.EPG -> Icons.Filled.Tv; Tab.SETTINGS -> Icons.Filled.Tune },
                        tab.title, tint = color, modifier = Modifier.size(20.dp))
                    if (open) Label(tab.title, size = 15.sp, weight = FontWeight.SemiBold,
                        color = if (focused) Theme.bg else Theme.text)
                }
            }
        }
        Spacer(Modifier.weight(1f))
        RailStatus(model, open)
        if (open) {
            // The version is the update button: one click checks for a new version and installs it. When one has
            // already downloaded by itself it shows "Install update".
            // 2.20: "Download update vX" (found, not fetched yet) → "Downloading vX · 40%" → "Install update vX" →
            // Android's installer. With nothing new, the version number: pressing it checks.
            val ready = Updater.readyVersion
            val available = Updater.availableVersion
            var busy by remember { mutableStateOf(false) }
            TvButton(onClick = {
                if (busy || Updater.downloading != null) Unit
                else if (ready != null) scope.launch { Updater.installLatest(context) }
                else if (available != null) scope.launch { Updater.check(context, userInitiated = true, download = true) }
                else scope.launch {
                    busy = true
                    Updater.check(context, userInitiated = true, download = false)
                    busy = false
                    if (Updater.availableVersion == null) model.notice = Updater.message ?: "You have the latest version."
                }
            }, background = if (ready != null || available != null) Theme.accent else Color.Transparent, modifier = Modifier.fillMaxWidth()) { focused ->
                Row(Modifier.padding(horizontal = 10.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    val color = if (focused) Theme.bg else if (ready != null || available != null) Theme.onAccent else Theme.muted
                    Icon(if (ready != null || available != null) Icons.Filled.Download else if (Updater.checking) Icons.Filled.HourglassTop else Icons.Filled.Refresh,
                        null, tint = color, modifier = Modifier.size(14.dp))
                    val dl = Updater.downloading
                    Label(when {
                        dl != null -> "Downloading $dl" + (Updater.downloadProgress?.let { " · ${(it * 100).toInt()}%" } ?: "…")
                        Updater.installing || busy -> "Checking…"
                        ready != null -> "Install update v$ready"
                        available != null -> "Download update v$available"
                        else -> "v${BuildConfig.VERSION_NAME}"
                    }, size = 12.sp, weight = FontWeight.SemiBold, color = color)
                }
            }
        }
    }
}

/**
 * Connections in use ("1/2", orange at the limit) and when the EPG was downloaded ("Refreshing EPG 45%" while it
 * downloads): full lines when the rail is open, short ones under the icons when it's closed. A dot: an update is ready.
 */
@Composable
private fun RailStatus(model: AppModel, open: Boolean) {
    val a = model.account
    val max = a?.maxConnections ?: 0
    val active = a?.activeConnections ?: 0
    val atLimit = max > 0 && active >= max
    val epgShort = when {
        model.refreshWaiting -> "EPG…"
        model.loading -> "EPG…"
        model.guideLoading -> "EPG…"
        else -> model.updatedAt?.let { clockTime(it).substringBefore(' ') }
    }
    val epgLong = when {
        model.refreshWaiting -> "EPG refreshes after this stream"
        model.loading -> "Refreshing EPG · channels…"
        model.guideLoading -> "Refreshing EPG…"
        else -> model.updatedAt?.let { "EPG ${clockTime(it)}" }
    }
    if (open) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.fillMaxWidth().height(1.dp).background(Theme.border))
            if (max > 0) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Filled.People, null, tint = if (atLimit) Theme.accent else Theme.muted, modifier = Modifier.size(15.dp))
                Label("$active/$max connections", size = 12.sp, weight = FontWeight.SemiBold, color = if (atLimit) Theme.accent else Theme.soft)
            }
            epgLong?.let {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Filled.Schedule, null, tint = Theme.muted, modifier = Modifier.size(15.dp))
                    Label(it, size = 12.sp, color = Theme.muted, maxLines = 2)
                }
            }
        }
    } else {
        Column(Modifier.fillMaxWidth().padding(bottom = 4.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (max > 0) Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Filled.People, null, tint = if (atLimit) Theme.accent else Theme.muted, modifier = Modifier.size(15.dp))
                Label("$active/$max", size = 10.sp, weight = FontWeight.SemiBold, color = if (atLimit) Theme.accent else Theme.muted)
            }
            epgShort?.let {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Filled.Schedule, null, tint = if (model.guideLoading) Theme.accent else Theme.muted, modifier = Modifier.size(15.dp))
                    Label(it, size = 10.sp, color = if (model.guideLoading) Theme.accent else Theme.muted)
                }
            }
            if (Updater.readyVersion != null || Updater.availableVersion != null || Updater.downloading != null)
                Box(Modifier.size(8.dp).clip(RoundedCornerShape(4.dp)).background(Theme.accent))
        }
    }
}

// MARK: Player

/** The video. Only one view shows the player at a time: the newest one takes it. */
@Composable
fun PlayerVideo(modifier: Modifier = Modifier) {
    AndroidView(
        factory = { ctx ->
            // The real video surface (like other IPTV apps): smooth for 4K, and HDR at the right brightness. Whether
            // the TV switches into HDR is up to its own Match content setting; the refresh rate only switches in full
            // screen (Playback.setFullScreen).
            (android.view.LayoutInflater.from(ctx).inflate(R.layout.player_surface, null) as PlayerView).apply {
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
 * page). Play/Pause on the remote stops it, and so does holding select on the video (remotes without Play/Pause,
 * like the Chromecast's).
 */
@Composable
fun PlayerStrip(model: AppModel, item: NowPlaying, targets: FocusTargets, modifier: Modifier = Modifier) {
    TvButton(onClick = { model.play(item.channel, item.gameTitle, item.lineup, from = "strip") }, focusedScale = 1f,
        onLongClick = { model.swallowSelect = true; model.stopPinned(); model.notice = "Stopped" },
        modifier = modifier.focusProperties { canFocus = !model.tabsFocused }
            .focusProperties { up = model.leftPanel }
            .tracked(targets, "video").size(Theme.playerWidth, Theme.playerWidth * 9 / 16)) { _ ->
        // The video itself is drawn by the shell in this spot (one view for the corner and full screen); this only
        // says where, inside the focus outline.
        Box(Modifier.fillMaxSize().padding(3.dp).onGloballyPositioned { model.cornerBounds = it.boundsInRoot() })
    }
}

/**
 * What's playing, on one line along the very bottom of the screen (under the player, across to the right edge): the
 * channel, what's on with its times and progress, and what's next. It never takes focus; pages scroll under it.
 */
@Composable
fun NowPlayingBar(model: AppModel, item: NowPlaying, modifier: Modifier = Modifier) {
    val channel = item.channel
    val now = model.currentProgramme(channel)
    val title = model.playerTitle(item)
    // The same gap above the line as between the player and the line, so pages scrolling under it have room.
    Column(modifier.fillMaxWidth().height(Theme.barHeight + Theme.margin).background(Theme.bg)) {
        Spacer(Modifier.height(Theme.margin - 1.dp))
        Box(Modifier.fillMaxWidth().height(1.dp).background(Theme.border))
        Row(Modifier.fillMaxSize().padding(horizontal = Theme.margin), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            Icon(Icons.Filled.GraphicEq, null, tint = Theme.accent, modifier = Modifier.size(13.dp))
            if (!Perf.noLogos) ChannelIcon(channel.icon, 22.dp)
            Label(channel.name, size = 13.sp, weight = FontWeight.SemiBold, color = Theme.soft)
            if (Playback.resolution.isNotEmpty()) Badge(Playback.resolution)
            if (Playback.hdr.isNotEmpty()) Badge(Playback.hdr)
            if (Playback.frameRate > 0) Badge(Playback.fpsLabel(Playback.frameRate))
            if (Playback.audio.isNotEmpty()) Badge(Playback.audio)
            Label(title, size = 14.sp, weight = FontWeight.Bold, modifier = Modifier.weight(1f, fill = false))
            if (now != null) {
                if (now.title.isNotEmpty() && now.title != title) Label(now.title, size = 13.sp, color = Theme.soft,
                    modifier = Modifier.weight(1f, fill = false))
                Label("${clockTime(now.start)} – ${clockTime(now.end)}", size = 13.sp, color = Theme.muted)
                val total = (now.end - now.start).toFloat()
                ProgressLine(if (total > 0) (System.currentTimeMillis() - now.start) / total else 0f, false, width = 100.dp)
            }
            // The EPG refresh, at the right end (the closed rail only has room for "EPG…").
            val epg = when {
                model.refreshWaiting -> "EPG refreshes after this stream"
                model.guideLoading -> "Refreshing EPG…"
                else -> null
            }
            if (epg != null) {
                Spacer(Modifier.weight(1f))
                Label(epg, size = 12.sp, color = Theme.muted)
            }
        }
    }
}

/** Room the left panels leave under them for the player in the corner. */
fun topInset(model: AppModel) = if (model.pinned != null) Theme.stripHeight else 0.dp

/** Room the pages on the right leave at the bottom for the now-playing bar (they scroll under it). */
fun barInset(model: AppModel) = if (model.pinned != null) Theme.barHeight + Theme.margin else 0.dp

/**
 * Full screen. Up/down: previous/next stream for this game (or channel in this category). Any other button shows
 * the info bar. The centre button shows the stream information and the streams watched before (most recent on the
 * left): left/right picks one, the centre button plays it, Back hides them. Play/Pause pauses. Back returns to the player at the top. A stream that fails, stops or buffers for
 * 10 seconds switches to the next one (USA and Canada first).
 */
@Composable
fun FullScreenPlayer(model: AppModel, item: NowPlaying) {
    val focus = remember { FocusRequester() }
    var showInfo by remember { mutableStateOf(true) }
    var poke by remember { mutableIntStateOf(0) }
    // The stream information panel: the remote's centre button shows it (and hides it again).
    var showDetails by remember { mutableStateOf(false) }
    var detailsTick by remember { mutableIntStateOf(0) }
    LaunchedEffect(detailsTick) { if (showDetails) { delay(8000); showDetails = false } }
    val recents = model.recentStreams(item, limit = 5)
    // What's picked in the strip: -2 = Reconnect, -1 = the bin, 0… = a recent stream.
    var recentIndex by remember { mutableIntStateOf(0) }
    val stripItems = listOf(-2) + (if (recents.isEmpty()) emptyList() else listOf(-1) + recents.indices)
    val picked = recentIndex.takeIf { it in stripItems } ?: stripItems.getOrElse(2) { -2 }
    // Back hides the information first, then closes full screen.
    BackHandler(enabled = showDetails) { showDetails = false }
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
            // Flipping by hand: the channel shows in the bar along the bottom, not at the top as well.
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

    // See-through: the video is drawn underneath by the shell (the same view as the corner player).
    Box(
        Modifier.fillMaxSize().focusRequester(focus).focusable()
            .onKeyEvent { e ->
                if (e.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (e.key.nativeKeyCode) {
                    KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_CHANNEL_UP -> { model.step(-1); poke++; true }
                    KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_CHANNEL_DOWN -> { model.step(1); poke++; true }
                    KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PLAY, KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                        Playback.togglePause(); poke++; true
                    }
                    KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> {
                        if (showDetails) {
                            // The strip is showing: reconnect, clear the list (the bin), or play the picked stream.
                            showDetails = false
                            when (picked) {
                                -2 -> { Playback.reconnect(); message("Reconnecting…") }
                                -1 -> model.clearWatched()
                                else -> recents[picked].let { model.play(it.channel, it.gameTitle, it.lineup) }
                            }
                        } else {
                            recentIndex = if (recents.isEmpty()) -2 else 0
                            showDetails = true
                        }
                        detailsTick++; poke++; true
                    }
                    KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT -> {
                        if (showDetails) {
                            val d = if (e.key.nativeKeyCode == KeyEvent.KEYCODE_DPAD_LEFT) -1 else 1
                            recentIndex = stripItems[(stripItems.indexOf(picked) + d).coerceIn(0, stripItems.size - 1)]
                            detailsTick++
                        }
                        poke++; true
                    }
                    else -> false
                }
            }
    ) {
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
                else -> {}
            }
        }
        flip?.let {
            Box(Modifier.align(Alignment.TopCenter).padding(top = 30.dp).clip(RoundedCornerShape(20.dp))
                .background(Color.Black.copy(alpha = 0.75f)).padding(horizontal = 16.dp, vertical = 9.dp)) {
                Label(it, size = 14.sp, weight = FontWeight.SemiBold)
            }
        }
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
        if (showDetails) {
            Column(Modifier.padding(horizontal = 40.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Label(when (picked) {
                    -2 -> "RECONNECT TO THIS STREAM · OK"
                    -1 -> "CLEAR RECENT STREAMS · OK"
                    else -> "RECENTLY WATCHED · OK TO SWITCH"
                }, size = 9.sp, weight = FontWeight.Bold, color = Theme.muted)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ReconnectButton(picked = picked == -2)
                    if (recents.isNotEmpty()) ClearRecentButton(picked = picked == -1)
                    recents.forEachIndexed { i, r ->
                        RecentCard(model, r, picked = i == picked, width = 165.dp)
                    }
                }
            }
        }
        if (showInfo || showDetails) {
            Row(
                Modifier.fillMaxWidth()
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
                if (Playback.hdr.isNotEmpty()) Badge(Playback.hdr)
                if (Playback.frameRate > 0) Badge(Playback.fpsLabel(Playback.frameRate))
                if (Playback.audio.isNotEmpty()) Badge(Playback.audio)
            }
        }
        }
    }
}

/** Clears the recent streams: a bin at the left of the strip, as see-through as the cards. */
@Composable
fun ClearRecentButton(picked: Boolean, modifier: Modifier = Modifier) =
    StripIcon(Icons.Filled.Delete, "Clear recent streams", picked, modifier)

/** Closes and reopens the stream (for a feed that's stuck or looping): first in the strip. */
@Composable
fun ReconnectButton(picked: Boolean, modifier: Modifier = Modifier) =
    StripIcon(Icons.Filled.Refresh, "Reconnect", picked, modifier)

@Composable
private fun StripIcon(icon: androidx.compose.ui.graphics.vector.ImageVector, description: String, picked: Boolean,
                      modifier: Modifier) {
    Box(modifier.size(38.dp).clip(RoundedCornerShape(10.dp))
        .background(Color.Black.copy(alpha = if (picked) 0.35f else 0.18f))
        .border(if (picked) 2.dp else 1.dp, if (picked) Theme.accent else Color.White.copy(alpha = 0.08f), RoundedCornerShape(10.dp)),
        contentAlignment = Alignment.Center) {
        Icon(icon, description, tint = Color.White.copy(alpha = if (picked) 0.9f else 0.6f), modifier = Modifier.size(18.dp))
    }
}

/** A recently watched stream in full screen: channel logo, what was on (or the game), and the channel. Mostly see-through. */
@Composable
fun RecentCard(model: AppModel, recent: NowPlaying, picked: Boolean, width: androidx.compose.ui.unit.Dp,
               modifier: Modifier = Modifier) {
    Row(modifier.width(width).clip(RoundedCornerShape(10.dp))
        .background(Color.Black.copy(alpha = if (picked) 0.35f else 0.18f))
        .border(if (picked) 2.dp else 1.dp, if (picked) Theme.accent else Color.White.copy(alpha = 0.08f), RoundedCornerShape(10.dp))
        .padding(horizontal = 9.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        ChannelIcon(recent.channel.icon, 24.dp)
        Column(Modifier.weight(1f)) {
            Label(model.playerTitle(recent), size = 11.sp, weight = FontWeight.SemiBold, color = Color.White, maxLines = 1)
            Label(recent.channel.name, size = 9.sp, color = Color.White.copy(alpha = 0.7f), maxLines = 1)
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
    val side = remember { FocusTargets() }
    val pane = remember { FocusTargets() }
    var lastGame by remember { mutableStateOf(back) }
    // Pressing down from the tabs lands on the first game (left goes to the sports); with no games, on the sports.
    var firstGame by remember { mutableStateOf<String?>(null) }
    // Live Now isn't listed any more (each sport shows its live games): it stands for the first sport.
    val sports = model.orderedSports()
    LaunchedEffect(model.homeSelection, sports.firstOrNull()) {
        val top = sports.firstOrNull() ?: return@LaunchedEffect
        val following = !model.pickedSport && System.currentTimeMillis() - model.openedAt < 90_000
        if (model.homeSelection == HomeSelection.LiveNow || (following && model.homeSelection is HomeSelection.OfSport && model.homeSelection != HomeSelection.OfSport(top))) {
            model.homeSelection = HomeSelection.OfSport(top)
            // The highlight on the left follows it too.
            if (model.sideFocused) { delay(30); side.focus(top.name) }
        }
    }

    // 2.4: a sport with several leagues lists them beside it. Right from the sport moves into its leagues, and the
    // sports fold to a strip of icons to make room; going back onto the sports opens them out again.
    val leagueTargets = remember { FocusTargets() }
    var folded by remember { mutableStateOf(false) }
    var leaguesFocused by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    fun leagueKey() = (model.homeSelection as? HomeSelection.OfLeague)?.let { "lg:${it.leagueId}" } ?: "lg:all"
    fun hasLeagues(sel: HomeSelection): Boolean {
        val sp = selectedSport(sel) ?: return false
        return sp !in model.home.channelSports && model.leagues(sp).size > 1
    }
    val canFold = hasLeagues(model.homeSelection)
    LaunchedEffect(canFold) { if (!canFold) folded = false }
    fun openLeagues(): Boolean {
        if (!hasLeagues(model.homeSelection)) return false
        folded = true
        scope.launch { repeat(10) { delay(30); if (leagueTargets.focus(leagueKey())) return@launch } }
        return true
    }
    // Back from the games: the selected league (when the leagues are out), otherwise the selected sport.
    LaunchedEffect(Unit) {
        model.focusMoves.collect {
            if (it != "side") return@collect
            // The first time after the app starts: the top sport (usually a favourite), whatever was selected.
            if (!model.homeEnteredFromRail) {
                model.homeEnteredFromRail = true
                val top = model.orderedSports().firstOrNull()
                if (top != null) {
                    folded = false
                    model.homeSelection = HomeSelection.OfSport(top)
                    delay(30)
                    side.focus(top.name)
                    return@collect
                }
            }
            if (folded && leagueTargets.focus(leagueKey())) Unit else side.focus(sidebarKey(model.homeSelection))
        }
    }
    // Back from a league: its sport (the sports open out again).
    BackHandler(enabled = folded && leaguesFocused && model.nowPlaying == null) { side.focus(sidebarKey(model.homeSelection)) }
    // Back from a game: focus goes to its card.
    LaunchedEffect(Unit) {
        val id = model.returnToGame ?: return@LaunchedEffect
        model.returnToGame = null
        repeat(10) {
            delay(50)
            if (pane.focus("game:$id")) return@LaunchedEffect
        }
    }

    // The sports (and leagues) on top of the player (the same width, both starting at the left end of the now-playing
    // bar), the games to the right, down to the bottom of the screen beside the player.
    Row(Modifier.fillMaxSize().padding(end = Theme.margin)
        .enterAt { firstGame?.let { "game:$it" }?.takeIf { it in pane.live }?.let { pane[it] } ?: side[sidebarKey(model.homeSelection)] }) {
        Row(Modifier.width(Theme.playerWidth).padding(bottom = topInset(model)).focusRequester(model.leftPanel)
            .onFocusChanged { model.sideFocused = it.hasFocus; if (it.hasFocus) model.homeEnteredFromRail = true }
            .enterAt { if (folded) leagueTargets[leagueKey()] else side[sidebarKey(model.homeSelection)] }) {
            SportList(model, side, compact = folded, onRight = { openLeagues() },
                modifier = (if (folded) Modifier.width(48.dp) else Modifier.weight(1f))
                    .onFocusChanged { if (it.hasFocus) folded = false }
                    .enterAt { side[sidebarKey(model.homeSelection)] })
            val sport = selectedSport(model.homeSelection)
            if (folded && sport != null) {
                Box(Modifier.padding(vertical = 8.dp).width(1.dp).fillMaxHeight().background(Theme.border))
                Spacer(Modifier.width(6.dp))
                LeagueList(model, sport, leagueTargets, Modifier.weight(1f).onFocusChanged { leaguesFocused = it.hasFocus }
                    .enterAt { leagueTargets[leagueKey()] })
            }
        }
        Spacer(Modifier.width(16.dp))
        GamesPane(model, pane, onOpen = { lastGame = it; model.openGameId = it }, onFocusGame = { lastGame = it },
            onFirst = { firstGame = it },
            modifier = Modifier.weight(1f).enterAt { pane["game:$lastGame"] })
    }
}

private fun sidebarKey(s: HomeSelection): String = when (s) {
    is HomeSelection.LiveNow -> ""
    is HomeSelection.OfSport -> s.sport.name
    is HomeSelection.OfLeague -> League.all.firstOrNull { it.id == s.leagueId }?.sport?.name ?: ""
}

private fun selectedSport(s: HomeSelection): Sport? = when (s) {
    is HomeSelection.OfSport -> s.sport
    is HomeSelection.OfLeague -> League.all.firstOrNull { it.id == s.leagueId }?.sport
    else -> null
}

@Composable
private fun SportList(model: AppModel, targets: FocusTargets, compact: Boolean, onRight: () -> Boolean = { false }, modifier: Modifier) {
    val sports = model.orderedSports()
    val favs = model.settings.favoriteSet
    val open = selectedSport(model.homeSelection)
    // Moving through the list shows a sport's games once you stop on it, so passing several sports doesn't draw
    // the games for each one. Clicking, or pressing right into the games, is instant.
    val settle = rememberSettle()
    // Holding the select button on a sport: favourite or hide it.
    var prompt by remember { mutableStateOf<HoldPrompt?>(null) }
    prompt?.let { p -> HoldMenu(p) { prompt = null } }
    fun choose(s: HomeSelection, now: Boolean) {
        if (model.homeSelection != s) model.pickedSport = true
        val apply = { if (model.homeSelection != s) model.homeSelection = s }
        if (now) settle.now(apply) else settle.later(apply)
    }
    val focusManager = androidx.compose.ui.platform.LocalFocusManager.current
    val scope = rememberCoroutineScope()
    Column(modifier.fillMaxHeight().onPreviewKeyEvent { e ->
            // Right: show the sport you stopped on first, then into its leagues (when it has several) or its games.
            if (e.type != KeyEventType.KeyDown || e.key.nativeKeyCode != KeyEvent.KEYCODE_DPAD_RIGHT) return@onPreviewKeyEvent false
            val flushed = settle.flush()
            when {
                onRight() -> true
                flushed -> {
                    scope.launch {
                        androidx.compose.runtime.withFrameNanos { }
                        androidx.compose.runtime.withFrameNanos { }
                        focusManager.moveFocus(FocusDirection.Right)
                    }
                    true
                }
                else -> false
            }
        }
        .verticalScroll(rememberScrollState()).padding(vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp)) {
        // Sports with live scores | sports that are channels (pickleball) | sports with nothing today. (No Live Now row:
        // each sport already shows its live games.)
        val home = model.home
        var firstGroup = true
        for (group in listOf(home.scoreSports, home.channelSports, home.emptySports)) {
            if (group.isEmpty()) continue
            if (!firstGroup) Box(Modifier.fillMaxWidth().padding(horizontal = if (compact) 6.dp else 10.dp, vertical = 5.dp).height(1.dp).background(Theme.border))
            firstGroup = false
            for (sport in group) {
                val games = model.games(sport)
                val channelOnly = sport in home.channelSports
                SportRow(targets, sport.name, sport.icon, sport.title, if (channelOnly) 0 else games.count { it.state == GameState.LIVE },
                    games.size, when { games.isEmpty() -> "No games"; channelOnly -> "Channels"; else -> "${games.size} today" },
                    compact, selected = open == sport, favorite = sport in favs, dimmed = games.isEmpty(),
                    onHold = {
                        val fav = sport in favs
                        prompt = HoldPrompt(sport.title, listOf(
                            HoldOption(if (fav) "Remove from Favourites" else "Add to Favourites",
                                if (fav) Icons.Filled.HeartBroken else Icons.Filled.Favorite) { model.settings.toggleFavorite(sport) },
                            HoldOption("Hide", Icons.Filled.VisibilityOff) {
                                model.setSportHidden(sport, true)
                                if (open == sport) model.homeSelection = HomeSelection.LiveNow
                                model.notice = "${sport.title} is hidden. Settings › Hidden brings it back."
                            }))
                    },
                    // Coming back to the sport whose league you picked on the right keeps that league.
                    onFocus = { if (selectedSport(model.homeSelection) != sport) choose(HomeSelection.OfSport(sport), false) else settle.cancel() }) {
                    if (selectedSport(model.homeSelection) != sport) choose(HomeSelection.OfSport(sport), true)
                    // Clicking a sport with several leagues opens them beside it, the same as pressing right.
                    onRight()
                }
            }
        }
    }
}

/** Live games as an orange number; otherwise today's count. Moving onto a row shows its games. */
@Composable
private fun SportRow(
    targets: FocusTargets, key: String, icon: androidx.compose.ui.graphics.vector.ImageVector, name: String, live: Int,
    total: Int, detail: String, compact: Boolean, selected: Boolean, favorite: Boolean = false, dimmed: Boolean = false,
    onFocus: () -> Unit = {}, onHold: (() -> Unit)? = null, select: () -> Unit
) {
    TvButton(onClick = select, selected = selected, onFocus = onFocus, onLongClick = onHold,
        modifier = Modifier.fillMaxWidth().tracked(targets, key).alpha(if (dimmed) 0.5f else 1f)) { focused ->
        val color = if (focused) Theme.bg else Theme.text
        if (compact) {
            // Folded (the leagues are out): just the icon, orange for the sport you're in, a dot when it has live games.
            Box(Modifier.fillMaxWidth().height(34.dp), contentAlignment = Alignment.Center) {
                Icon(icon, contentDescription = name, tint = if (focused) Theme.bg else if (selected) Theme.accent else Theme.muted,
                    modifier = Modifier.size(18.dp))
                if (live > 0) Box(Modifier.align(Alignment.TopEnd).padding(top = 5.dp, end = 7.dp).size(6.dp)
                    .clip(RoundedCornerShape(3.dp)).background(Theme.accent))
            }
        } else Row(Modifier.padding(horizontal = 10.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, contentDescription = name, tint = color, modifier = Modifier.size(18.dp))
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

/**
 * Sized for the sport's typical team name and score (most cards fit without cutting off a name; the odd very long
 * one is shortened), so each sport gets as many cards to a row as it can.
 */
private fun cardWidth(games: List<Game>): androidx.compose.ui.unit.Dp {
    val needs = games.map { g ->
        if (g.isEvent && !g.hasSides) minOf(g.eventTitle.length, 26)
        else listOf(g.away, g.home).maxOf { t ->
            val name = t.shortName.ifEmpty { t.name }.length
            if (t.hasLongScore) maxOf(name, t.score.length) else name + t.score.length + 2
        }
    }.sorted()
    if (needs.isEmpty()) return 200.dp
    val typical = needs[(needs.size * 3 / 4).coerceAtMost(needs.size - 1)]   // 3 in 4 cards fit fully
    return (64 + typical * 8).coerceIn(180, 280).dp
}

private data class PaneSection(val id: String, val title: String, val icon: androidx.compose.ui.graphics.vector.ImageVector?,
                               val league: League?, val games: List<Game>)

private fun sortedGames(games: List<Game>) = games.sortedWith(
    compareBy<Game> { when (it.state) { GameState.LIVE -> 0; GameState.UPCOMING -> 1; else -> 2 } }.thenBy { it.start ?: Long.MAX_VALUE })

@Composable
private fun GamesPane(model: AppModel, targets: FocusTargets, onOpen: (String) -> Unit, onFocusGame: (String) -> Unit,
                      onFirst: (String?) -> Unit = {}, modifier: Modifier) {
    val selection = model.homeSelection
    val sport = selectedSport(selection)
    val sections: List<PaneSection> = when (selection) {
        // Only games that are live right now, under a heading per league (NBA, NCAA, NFL...), like a sport's page.
        is HomeSelection.LiveNow -> model.orderedSports().flatMap { s -> model.leagues(s) }.mapNotNull { l ->
            val live = model.gamesIn(l.id).filter { it.state == GameState.LIVE }
            if (live.isEmpty()) null else PaneSection(l.id, l.name, null, l, sortedGames(live))
        }
        is HomeSelection.OfSport -> model.leagues(selection.sport).mapNotNull { l ->
            val g = model.gamesIn(l.id)
            if (g.isEmpty()) null else PaneSection(l.id, l.name, null, l, sortedGames(g))
        }
        is HomeSelection.OfLeague -> League.all.firstOrNull { it.id == selection.leagueId }?.let { l ->
            listOf(PaneSection(l.id, l.name, null, l, sortedGames(model.gamesIn(l.id))))
        } ?: emptyList()
    }
    // A sport with no live scores but channels (pickleball): its channels as an EPG list, not score cards.
    if (sport != null && sport in model.home.channelSports) {
        SportChannels(model, sport, targets, modifier)
        return
    }
    // Finished games fold into one row at the bottom ("Finished · 6", click to show them), so a page mostly draws the
    // games that are live or coming up.
    // Lite mode only (2.2): games starting more than 2 hours from now fold the same way ("Later today · 18"), so a
    // busy day (31 basketball games) mostly draws what's live or about to start. Elsewhere they're ordinary cards.
    val soon = System.currentTimeMillis() + 2 * 3600_000L
    val foldLater = Perf.foldLater
    fun isLater(g: Game) = foldLater && g.state == GameState.UPCOMING && (g.start ?: 0L) > soon
    val open = sections.map { it.copy(games = it.games.filter { g -> g.state != GameState.FINISHED && !isLater(g) }) }
        .filter { it.games.isNotEmpty() }
    val later = sections.flatMap { it.games.filter { g -> isLater(g) } }
    val finished = sections.flatMap { it.games.filter { g -> g.state == GameState.FINISHED } }
    // Finished games show by default; Lite mode folds them (less to draw).
    var showFinished by remember(selection) { mutableStateOf(!Perf.foldFinished) }
    val first = open.firstOrNull()?.games?.firstOrNull()?.id ?: if (showFinished) finished.firstOrNull()?.id else null
    SideEffect { onFirst(first) }
    // Right on the last card of a row goes nowhere (no jumping to another tab).
    val toEpg = Modifier
    var showLater by remember(selection) { mutableStateOf(false) }
    // NFL RedZone: while any NFL game is live, its channels sit in a folder at the top of Live Now and Football.
    val nflLive = selection.let { it is HomeSelection.LiveNow || selectedSport(it) == Sport.FOOTBALL ||
        (it is HomeSelection.OfLeague && it.leagueId == "nfl") } && model.gamesIn("nfl").any { it.state == GameState.LIVE }
    val redZone = if (nflLive) model.redZoneChannels() else emptyList()
    var showRedZone by remember(selection) { mutableStateOf(false) }
    // An EPG-like list, like the channel sports: a row per game (status, the teams and scores), under a heading per
    // league. It runs to the bottom of the screen, under the now-playing bar.
    BehindPlayerBar(model) {
    BoxWithConstraints(modifier.fillMaxHeight()) {
    // Score cards, as many to a row as fit (each at least CARD_MIN_WIDTH wide).
    val cols = maxOf(1, ((maxWidth - 8.dp) / (CARD_MIN_WIDTH + 8.dp)).toInt())
    // One list item per row of cards.
    val listScope = rememberCoroutineScope()
    // Focusing the first row of a section (or of the list) scrolls up far enough to show its heading, so the league
    // names above the cards are never cut off at the top.
    fun showHeading(rowKey: String, headed: Boolean, first: Boolean) {
        listScope.launch {
            androidx.compose.runtime.withFrameNanos { }
            val state = model.homeList
            val rowInfo = state.layoutInfo.visibleItemsInfo.firstOrNull { it.key == rowKey } ?: return@launch
            val target = if (first) 0 else if (headed) rowInfo.index - 1 else return@launch
            val shown = state.layoutInfo.visibleItemsInfo.firstOrNull { it.index == target }
            if (shown == null || shown.offset < state.layoutInfo.viewportStartOffset) state.animateScrollToItem(maxOf(0, target))
        }
    }
    fun LazyListScope.cardRows(games: List<Game>, prefix: String, headed: Boolean = false, first: Boolean = false) {
        items(games.chunked(cols), key = { "$prefix:${it.first().id}" }, contentType = { "cards" }) { row ->
            val firstRow = row.first().id == games.firstOrNull()?.id
            Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEachIndexed { i, game ->
                    val main = model.mainStreams(game.id)
                    GameCard(game, main.size, main.any { it.is4K },
                        modifier = Modifier.weight(1f).tracked(targets, "game:${game.id}")
                            .then(if (i == row.size - 1) toEpg else Modifier),
                        onFocus = {
                            onFocusGame(game.id)
                            if (firstRow && (headed || first)) showHeading("$prefix:${row.first().id}", headed, first)
                        }) { onOpen(game.id) }
                }
                repeat(cols - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
    Column(Modifier.fillMaxHeight()) {
    LazyColumn(Modifier.weight(1f), state = model.homeList, verticalArrangement = Arrangement.spacedBy(2.dp),
        contentPadding = PaddingValues(top = 6.dp, bottom = 6.dp + barInset(model))) {
        if (redZone.isNotEmpty()) {
            item(key = "redzone", contentType = "finished") {
                FoldRow("NFL RedZone · ${redZone.size}", showRedZone, Modifier.tracked(targets, "redzone")) { showRedZone = !showRedZone }
            }
            if (showRedZone) items(redZone, key = { "rz:${it.id}" }, contentType = { "channel" }) { ch ->
                val playing = model.pinned?.channel?.id
                ChannelRow(model, ch, ch.id == playing, Modifier.tracked(targets, "rz:${ch.id}"), showNext = false,
                    onFocus = { }) {
                    if (ch.id == playing) model.play(ch, null, redZone, from = "home") else model.pin(ch, null, redZone)
                }
            }
        }
        // Only when there's nothing at all (no "Nothing live or coming up": the folds below say it).
        if (open.isEmpty() && (model.error != null || (later.isEmpty() && finished.isEmpty()))) {
            item(key = "empty") {
                Label(when {
                    model.error != null -> model.error!!
                    model.loading && model.games.isEmpty() -> "Loading today's games…"
                    else -> "No games today."
                }, size = 14.sp, color = Theme.muted, maxLines = 3, modifier = Modifier.padding(10.dp))
            }
        }
        for (section in open) {
            if (section.title.isNotEmpty() && open.size > 1) item(key = "h:${section.id}", contentType = "heading") {
                Row(Modifier.padding(start = 10.dp, top = 10.dp, bottom = 2.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                    if (section.league != null) LeagueLogo(model, section.league, 15.dp)
                    Label(section.title.uppercase(), size = 10.sp, weight = FontWeight.Bold, color = Theme.muted)
                }
            }
            // Same content type: switching sports reuses the rows already built (new text, same row) instead of
            // building new ones.
            cardRows(section.games, section.id, headed = section.title.isNotEmpty() && open.size > 1,
                first = section == open.first() && redZone.isEmpty())
        }
        if (later.isNotEmpty()) {
            item(key = "later", contentType = "finished") {
                FoldRow("Later today · ${later.size}", showLater, Modifier.tracked(targets, "later")) { showLater = !showLater }
            }
            if (showLater) cardRows(later, "l")
        }
        if (finished.isNotEmpty() && !Perf.foldFinished) {
            // 2.30: finished games under their own plain heading (not a fold), always shown.
            item(key = "finished", contentType = "heading") {
                Row(Modifier.padding(start = 10.dp, top = 10.dp, bottom = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                    Label("FINISHED", size = 10.sp, weight = FontWeight.Bold, color = Theme.muted)
                }
            }
            cardRows(finished, "f")
        } else if (finished.isNotEmpty()) {
            // Lite mode's "Finished games" option still folds them.
            item(key = "finished", contentType = "finished") {
                TvButton(onClick = { showFinished = !showFinished }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
                    .tracked(targets, "finished")) { focused ->
                    Row(Modifier.padding(horizontal = 10.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                        val color = if (focused) Theme.bg else Theme.muted
                        Icon(if (showFinished) Icons.Filled.ExpandMore else Icons.Filled.ChevronRight, null, tint = color,
                            modifier = Modifier.size(14.dp))
                        Label("Finished · ${finished.size}", size = 12.sp, weight = FontWeight.SemiBold, color = color)
                    }
                }
            }
            if (showFinished) cardRows(finished, "f")
        }
    }
    }
    }
    }
}

private val CARD_MIN_WIDTH = 200.dp

/**
 * A game as a score card: when (or LIVE and the clock), its 4K tag and number of streams, then each team with its
 * logo and score. Upcoming games are dimmer, so live games stand out. Lite mode: no scores or logos.
 */
@Composable
private fun GameCard(game: Game, streams: Int, has4K: Boolean, modifier: Modifier, onFocus: () -> Unit, onClick: () -> Unit) {
    // Only plain values come in (not the whole app model), so when the scores update, a card whose game didn't
    // change isn't drawn again.
    TvButton(onClick = onClick, onFocus = onFocus, modifier = modifier, background = Theme.card,
        shape = RoundedCornerShape(12.dp)) { focused ->
        val text = if (focused) Theme.bg else Theme.text
        val dim = if (game.state == GameState.UPCOMING && !focused) 0.7f else 1f
        Column(Modifier.fillMaxWidth().padding(horizontal = 11.dp, vertical = 9.dp).alpha(dim),
            verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                val status = when {
                    Perf.noScores && game.state == GameState.LIVE -> "LIVE"
                    game.state == GameState.UPCOMING -> startText(game)
                    else -> cardHeader(game)
                }
                Label(status, size = 11.sp, weight = FontWeight.Bold,
                    color = if (focused) Theme.bg else if (game.state == GameState.LIVE) Theme.accent else Theme.muted,
                    modifier = Modifier.weight(1f))
                if (has4K) Badge("4K", fill = Theme.accent, color = Theme.onAccent)
                Label(if (streams == 0) "None" else "$streams", size = 11.sp, weight = FontWeight.SemiBold,
                    color = if (streams == 0 && !focused) Theme.losing else if (focused) Theme.bg else Theme.muted)
                if (streams > 0) Icon(Icons.Filled.LiveTv, null, tint = if (focused) Theme.bg else Theme.muted,
                    modifier = Modifier.size(11.dp))
            }
            if (game.isEvent && !game.hasSides) {
                Column(Modifier.heightIn(min = 50.dp)) {
                    Label(game.eventTitle, size = 13.sp, weight = FontWeight.SemiBold, color = text, maxLines = 2)
                    if (game.eventDetail.isNotEmpty()) Label(game.eventDetail, size = 11.sp, color = text.copy(alpha = 0.75f))
                }
            } else {
                val showScore = game.state != GameState.UPCOMING && !Perf.noScores
                for (team in listOf(game.away, game.home)) {
                    Row(Modifier.height(22.dp), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (!Perf.noLogos) Logo(team.logo, 20.dp, team.abbr)
                        Label(team.shortName.ifEmpty { team.name }, size = 13.sp, weight = FontWeight.SemiBold, color = text,
                            modifier = Modifier.weight(1f))
                        if (showScore && team.score.isNotEmpty()) Label(team.score, size = 15.sp, weight = FontWeight.Bold,
                            color = if (focused) Theme.bg else scoreColor(game, team))
                    }
                }
            }
        }
    }
}

/** A folded group on Home ("Finished · 6", "Later today · 18"): click to show or hide its games. */
@Composable
private fun FoldRow(title: String, open: Boolean, modifier: Modifier, onClick: () -> Unit) {
    TvButton(onClick = onClick, modifier = modifier.fillMaxWidth().padding(top = 8.dp)) { focused ->
        Row(Modifier.padding(horizontal = 10.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            val color = if (focused) Theme.bg else Theme.muted
            Icon(if (open) Icons.Filled.ExpandMore else Icons.Filled.ChevronRight, null, tint = color, modifier = Modifier.size(14.dp))
            Label(title, size = 12.sp, weight = FontWeight.SemiBold, color = color)
        }
    }
}

/** Every channel showing the sport (its own channels and today's shows), like the EPG. Click to play, again for full screen. */
@Composable
private fun SportChannels(model: AppModel, sport: Sport, targets: FocusTargets, modifier: Modifier) {
    val games = model.games(sport)
    val channels = games.flatMap { model.streams(it.id) }.map { it.channel }.distinctBy { it.id }
        .sortedWith(compareBy({ !it.name.lowercase().contains(sport.title.lowercase()) }, { it.name }))
    val playing = model.pinned?.channel?.id
    var last by remember { mutableStateOf<String?>(null) }
    AfterFullScreen(model, "home") { targets.focus("ch:${model.lastPlayedChannelId}") }
    // Under a heading per category they come from (like the game screen), names on one line.
    val byCategory = channels.groupBy { it.categoryName.ifEmpty { "Other" } }
    val lineup = byCategory.values.flatten()
    val nameWidth = nameWidthFor(channels)
    BehindPlayerBar(model) {
    LazyColumn(modifier.fillMaxHeight().enterAt { targets[last ?: "ch:$playing"] },
        verticalArrangement = Arrangement.spacedBy(2.dp), contentPadding = PaddingValues(top = 8.dp, bottom = 8.dp + barInset(model))) {
        for ((category, list) in byCategory) {
            item(key = "h:$category") {
                Label(category.uppercase(), size = 10.sp, weight = FontWeight.Bold, color = Theme.muted,
                    modifier = Modifier.padding(start = 10.dp, top = 8.dp, bottom = 2.dp))
            }
            items(list, key = { "ch:${it.id}" }, contentType = { "channel" }) { ch ->
                val k = "ch:${ch.id}"
                ChannelRow(model, ch, ch.id == playing, Modifier.tracked(targets, k), nameWidth = nameWidth, showNext = false,
                    onFocus = { last = k }) {
                    if (ch.id == playing) model.play(ch, null, lineup, from = "home") else model.pin(ch, null, lineup)
                }
            }
        }
    }
    }
}

/**
 * A sport's leagues beside its icon: "All" first, then the most popular league first (`Sport.leagues` order), so
 * the list never moves. Moving through it shows a league's games once you stop; clicking, or right, is instant.
 */
@Composable
private fun LeagueList(model: AppModel, sport: Sport, targets: FocusTargets, modifier: Modifier) {
    val selection = model.homeSelection
    val settle = rememberSettle()
    fun choose(s: HomeSelection, now: Boolean) {
        val apply = { if (model.homeSelection != s) model.homeSelection = s }
        if (now) settle.now(apply) else settle.later(apply)
    }
    Column(modifier.fillMaxHeight().flushOn(settle, androidx.compose.ui.focus.FocusDirection.Right)
        .verticalScroll(rememberScrollState()).padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Label(sport.title.uppercase(), size = 10.sp, weight = FontWeight.Bold, color = Theme.muted,
            modifier = Modifier.padding(start = 10.dp, top = 2.dp, bottom = 4.dp))
        val all = model.games(sport)
        LeagueRow(targets, "lg:all", null, "All", all.count { it.state == GameState.LIVE }, all.size,
            selection == HomeSelection.OfSport(sport), model, onFocus = { choose(HomeSelection.OfSport(sport), false) }) {
            choose(HomeSelection.OfSport(sport), true)
        }
        for (league in model.leagues(sport)) {
            val g = model.gamesIn(league.id)
            val s = HomeSelection.OfLeague(league.id)
            LeagueRow(targets, "lg:${league.id}", league, league.name, g.count { it.state == GameState.LIVE }, g.size,
                selection == s, model, dimmed = g.isEmpty(), onFocus = { choose(s, false) }) { choose(s, true) }
        }
    }
}

@Composable
private fun LeagueRow(targets: FocusTargets, key: String, league: League?, name: String, live: Int, total: Int, selected: Boolean,
                      model: AppModel, dimmed: Boolean = false, onFocus: () -> Unit, select: () -> Unit) {
    TvButton(onClick = select, selected = selected, onFocus = onFocus,
        modifier = Modifier.fillMaxWidth().tracked(targets, key).alpha(if (dimmed) 0.5f else 1f)) { focused ->
        val color = if (focused) Theme.bg else Theme.text
        Row(Modifier.padding(horizontal = 10.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (league != null && !Perf.noLogos) LeagueLogo(model, league, 15.dp)
            Label(name, size = 14.sp, weight = FontWeight.SemiBold, color = color, modifier = Modifier.weight(1f))
            if (live > 0) Badge("$live", fill = Theme.accent, color = Theme.onAccent)
            else if (total > 0) Label("$total", size = 11.sp, color = color.copy(alpha = 0.6f))
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
                        // Lite mode leaves the logos out (names and scores only).
                        if (!Perf.noLogos) {
                            Logo(team.logo, 24.dp, team.abbr)
                            Spacer(Modifier.width(8.dp))
                        }
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
    val cats = remember { FocusTargets() }
    val rows = remember { FocusTargets() }
    val s = model.settings
    val all = model.streams(gameId).let { list -> if (s.hideSD) list.filter { it.quality != "SD" } else list }
    // Measured quality as it was when the screen opened, so rows don't jump around while you flip through them.
    val listing = remember(all, game.league) { StreamSections.build(all, game.league, measured = model.measuredQuality,
        fps = model.measuredFrameRate, hdr = model.measuredHdr, audio = model.measuredAudio) }
    // A mini EPG for this game: its stream categories on the left ("All" first), the channels on the right.
    val main = listing.sections.flatMap { it.streams }
    // Every group of streams, in order; "All" lists them all under these names.
    val groups = buildList {
        for (sec in listing.sections) add(sec.name to sec.streams)
        if (listing.foreign.isNotEmpty()) add("Foreign" to listing.foreign.flatMap { it.streams })
        if (listing.extras.isNotEmpty()) add("Local and likely" to listing.extras)
    }
    val everything = groups.flatMap { it.second }
    val categories = listOf("All" to everything) + groups
    var selected by remember(gameId) { mutableStateOf("All") }
    val catSettle = rememberSettle()
    val current = categories.firstOrNull { it.first == selected }?.second ?: everything
    // Names on one line: as wide as the longest one needs (within reason), the same for every row so columns line up.
    val nameWidth = nameWidthFor(current.map { it.channel })
    val lineup = current.map { it.channel }
    val pinnedHere = model.pinnedIsFrom(gameId)
    val previewId = if (pinnedHere) model.pinned?.channel?.id else null
    var lastRow by remember { mutableStateOf<String?>(null) }

    // Opening a game plays its first stream that isn't 4K (or the first, if they all are) in the player, unless one
    // of its streams already is; focus starts on the stream that's playing.
    LaunchedEffect(gameId, all.isNotEmpty()) {
        var id = previewId
        // Lite mode has no player in the corner, so nothing starts until you pick a stream.
        if (!pinnedHere && !model.settings.liteNoAutoplay && !model.settings.liteNoCorner) (main.firstOrNull { m ->
            !(m.is4K || m.quality == "4K" || model.measuredQuality[m.channel.id] == "4K" ||
                Categories.isUHD(m.channel.name) || Categories.isUHD(m.channel.categoryName))
        } ?: main.firstOrNull())
            ?.let { model.pin(it.channel, game.title, main.map { m -> m.channel }); id = it.channel.id }
        delay(80)
        rows.focus("s:$id") || cats.focus("cat:All")
    }
    // Back from full screen: focus goes back to the stream you were watching.
    AfterFullScreen(model, "game") { rows.focus("s:${model.lastPlayedChannelId}") }

    fun select(m: StreamMatch) {
        if (previewId == m.channel.id) model.play(m.channel, game.title, lineup, from = "game")
        else model.pin(m.channel, game.title, lineup)
    }

    Row(Modifier.fillMaxSize().background(Theme.bg).padding(end = Theme.margin).enterAt { rows["s:$previewId"] },
        horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        // Categories, on top of the player.
        LazyColumn(Modifier.width(Theme.playerWidth).fillMaxHeight().padding(bottom = topInset(model)).focusRequester(model.leftPanel)
            .onFocusChanged { model.sideFocused = it.hasFocus }
            .flushOn(catSettle, androidx.compose.ui.focus.FocusDirection.Right).enterAt { cats["cat:$selected"] },
            verticalArrangement = Arrangement.spacedBy(3.dp), contentPadding = PaddingValues(vertical = 8.dp)) {
            items(categories, key = { it.first }) { (name, streams) ->
                CategoryRow(cats, "cat:$name", null, name, "${streams.size}", selected == name,
                    onFocus = { if (selected != name) catSettle.later { selected = name } else catSettle.cancel() }) {
                    catSettle.now { selected = name }
                }
            }
        }
        // The channels in that category, like the EPG: what's on now and next, and the stream's quality.
        Box(Modifier.weight(1f).fillMaxHeight()) { BehindPlayerBar(model) {
        LazyColumn(Modifier.fillMaxSize().enterAt { rows[lastRow ?: "s:$previewId"] },
            verticalArrangement = Arrangement.spacedBy(2.dp), contentPadding = PaddingValues(top = 6.dp, bottom = 6.dp + barInset(model))) {
            if (current.isEmpty()) item(key = "none") {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(10.dp)) {
                    Label(if (model.channels.isEmpty()) "Channels are still loading…" else "No streams found for this game yet.",
                        size = 14.sp, color = Theme.muted)
                    Pill("Back to the games", Modifier.tracked(rows, "back")) { model.closeGame() }
                }
            }
            // "All": each group's name above its streams (just a heading).
            val shownGroups = if (selected == "All") groups else listOf(selected to current)
            for ((name, streams) in shownGroups) {
                if (selected == "All" && streams.isNotEmpty()) item(key = "h:$name") {
                    Label(name.uppercase(), size = 10.sp, weight = FontWeight.Bold, color = Theme.muted,
                        modifier = Modifier.padding(start = 10.dp, top = 8.dp, bottom = 2.dp))
                }
                items(streams, key = { "$name:${it.channel.id}" }, contentType = { "stream" }) { m ->
                    val k = "s:${m.channel.id}"
                    ChannelRow(model, m.channel, m.channel.id == previewId, Modifier.tracked(rows, k),
                        badge = model.measuredQuality[m.channel.id] ?: m.quality, nameWidth = nameWidth, showNext = false,
                        onFocus = { lastRow = k }) { select(m) }
                }
            }
        } } }
    }
}

/** Marks an item in a WrapGrid that takes a whole row (section names, buttons). */
private object FullRow : androidx.compose.ui.layout.ParentDataModifier {
    override fun androidx.compose.ui.unit.Density.modifyParentData(parentData: Any?): Any = FullRow
}

fun Modifier.fullRow(): Modifier = this.then(FullRow)

/**
 * A grid that flows around the player in the bottom-left corner: rows that reach down to `blockedFrom` (where the
 * player starts, measured on the unscrolled page) start to the player's right, so nothing is ever hidden behind it,
 * even when scrolled. Cells line up in the same columns throughout; full-row items take whatever width the row has.
 */
@Composable
fun WrapGrid(obstacleWidth: androidx.compose.ui.unit.Dp, blockedFrom: androidx.compose.ui.unit.Dp,
             cellWidth: androidx.compose.ui.unit.Dp, spacing: androidx.compose.ui.unit.Dp, modifier: Modifier = Modifier,
             content: @Composable () -> Unit) {
    androidx.compose.ui.layout.Layout(content, modifier) { measurables, constraints ->
        val width = constraints.maxWidth
        val gap = spacing.roundToPx()
        val obstW = obstacleWidth.roundToPx()
        val limit = blockedFrom.roundToPx()
        val columns = maxOf(1, (width + gap) / (cellWidth.roundToPx() + gap))
        val cell = (width - gap * (columns - 1)) / columns
        val firstFreeCol = if (obstW > 0) minOf(columns - 1, (obstW + gap + cell + gap - 1) / (cell + gap)) else 0
        fun blocked(top: Int, height: Int) = obstW > 0 && top + height > limit
        val placed = mutableListOf<Triple<androidx.compose.ui.layout.Placeable, Int, Int>>()
        var y = 0
        var x = 0
        var rowH = 0
        var inRow = false
        fun newLine() { if (inRow) y += rowH + gap; rowH = 0; inRow = false; x = 0 }
        val headerGuess = 40.dp.roundToPx()
        for (m in measurables) {
            if (m.parentData === FullRow) {
                newLine()
                val start = if (blocked(y, headerGuess)) obstW + gap else 0
                val p = m.measure(androidx.compose.ui.unit.Constraints.fixedWidth(maxOf(0, width - start)))
                placed.add(Triple(p, start, y))
                y += p.height + gap
            } else {
                val p = m.measure(androidx.compose.ui.unit.Constraints.fixedWidth(cell))
                if (!inRow) x = if (blocked(y, p.height)) firstFreeCol * (cell + gap) else 0
                else if (x + cell > width) {
                    newLine()
                    x = if (blocked(y, p.height)) firstFreeCol * (cell + gap) else 0
                }
                placed.add(Triple(p, x, y))
                rowH = maxOf(rowH, p.height)
                inRow = true
                x += cell + gap
            }
        }
        val height = if (inRow) y + rowH else maxOf(0, y - gap)
        layout(width, height) { for ((p, px, py) in placed) p.place(px, py) }
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
                if (game.state == GameState.UPCOMING && !game.isChannel) add("Starts ${startText(game)}")
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
            ReliabilityDot(m.channel.id)
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (quality.isNotEmpty()) Badge(quality, fill = if (quality == "4K") Theme.accent else Theme.raised,
                    color = if (quality == "4K") Theme.onAccent else Theme.soft)
                if (fps != null && fps > 0) Badge(Playback.fpsLabel(fps))
            }
        }
    }
}

/** Full screen, the centre button: the channel (which stream of how many), what's on now and next, the picture and sound. */
