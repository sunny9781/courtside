package ca.sunny9781.courtside

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Icon
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The phone app (portrait, touch first), laid out like the iPhone app: the player pinned at the top while something
 * plays, Home / EPG / Settings tabs along the bottom, and the controls you use most (sports, leagues, favourites,
 * the filter, settings sections) at the bottom in reach of the thumb. It shares everything else (provider,
 * matching, scores, the one player) with the TV app.
 */
object PhoneUi {
    /** In picture in picture: only the video shows. */
    var inPip by mutableStateOf(false)
    /** The pinned player folded into one line (the sound carries on). */
    var collapsed by mutableStateOf(false)
    /** EPG: opened groups (node ids), then possibly a category ("cat:<id>") at the end. */
    var epgPath by mutableStateOf<List<String>>(emptyList())
    /** Full screen came from turning the phone sideways: turning it back closes it. */
    var fullByRotation = false
}

@Composable
fun PhoneApp(model: AppModel) {
    Box(Modifier.fillMaxSize().background(Theme.bg)) {
        when {
            model.credentials == null -> PhoneLogin(model)
            model.editingAccount -> PhoneLogin(model, model.credentials) { model.editingAccount = false }
            else -> PhoneShell(model)
        }
    }
}

@Composable
fun isLandscape(): Boolean =
    LocalConfiguration.current.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE

@Composable
private fun PhoneShell(model: AppModel) {
    val full = model.nowPlaying != null
    val pip = PhoneUi.inPip
    val current = model.nowPlaying ?: model.pinned
    // Remember the quality, frame rate and sound each channel really plays with.
    LaunchedEffect(Playback.resolution, current?.channel?.id) { current?.let { model.recordQuality(it.channel.id, Playback.resolution) } }
    LaunchedEffect(Playback.frameRate, current?.channel?.id) { current?.let { model.recordFrameRate(it.channel.id, Playback.frameRate) } }
    LaunchedEffect(Playback.audio, current?.channel?.id) { current?.let { model.recordAudio(it.channel.id, Playback.audio) } }
    LaunchedEffect(Playback.hdr, current?.channel?.id) { current?.let { model.recordHdr(it.channel.id, Playback.hdr) } }
    LaunchedEffect(Updater.message) { Updater.message?.let { model.notice = it } }

    // Back: full screen → the player at the top; a game → Home; an EPG category → the level above; another tab → Home.
    BackHandler(enabled = full || (model.tab == Tab.HOME && model.openGameId != null) ||
        (model.tab == Tab.EPG && PhoneUi.epgPath.isNotEmpty()) || model.tab != Tab.HOME) {
        when {
            model.nowPlaying != null -> model.closePlayer()
            model.tab == Tab.HOME && model.openGameId != null -> model.closeGame()
            model.tab == Tab.EPG && PhoneUi.epgPath.isNotEmpty() -> PhoneUi.epgPath = PhoneUi.epgPath.dropLast(1)
            else -> model.tab = Tab.HOME
        }
    }
    // Full screen opened by turning the phone sideways closes when it's turned back upright.
    val landscape = isLandscape()
    LaunchedEffect(landscape) {
        if (!landscape && PhoneUi.fullByRotation) {
            PhoneUi.fullByRotation = false
            if (model.nowPlaying != null) model.closePlayer()
        }
    }
    LaunchedEffect(full) { if (!full) PhoneUi.fullByRotation = false }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
            val item = model.pinned
            if (item != null && !full) PinnedPlayer(model, item) else SideEffect { model.cornerBounds = null }
            Box(Modifier.weight(1f).fillMaxWidth()) {
                when (model.tab) {
                    Tab.HOME -> {
                        val open = model.openGameId
                        if (open != null) PhoneGame(model, open) else PhoneHome(model)
                    }
                    Tab.EPG -> PhoneEpg(model)
                    Tab.SETTINGS -> PhoneSettings(model)
                }
                model.notice?.let { message ->
                    Box(Modifier.align(Alignment.BottomCenter).padding(bottom = 90.dp, start = 16.dp, end = 16.dp)
                        .clip(RoundedCornerShape(22.dp)).background(Theme.raised).padding(horizontal = 18.dp, vertical = 11.dp)) {
                        Label(message, size = 14.sp, weight = FontWeight.Medium, maxLines = 3)
                    }
                    LaunchedEffect(message) {
                        delay(if (message.length > 80) 8000 else 4000)
                        if (model.notice == message) model.notice = null
                    }
                }
            }
            TabBar(model)
        }
        // The video: one view for the pinned player and full screen, which only moves and changes size.
        if (full || model.pinned != null) {
            val b = model.cornerBounds
            val density = LocalDensity.current
            val place = when {
                full || pip -> Modifier.fillMaxSize()
                b != null -> with(density) {
                    Modifier.offset { IntOffset(b.left.toInt(), b.top.toInt()) }.size(b.width.toDp(), b.height.toDp())
                }
                else -> Modifier.size(0.dp)
            }
            PlayerVideo(place)
            if (!full && !pip && b != null) model.pinned?.let { item ->
                with(density) {
                    PinnedOverlay(model, item, Modifier.offset { IntOffset(b.left.toInt(), b.top.toInt()) }
                        .size(b.width.toDp(), b.height.toDp()))
                }
            }
        }
        if (!pip) model.nowPlaying?.let { PhoneFullScreen(model, it) }
    }
}

@Composable
private fun TabBar(model: AppModel) {
    Column(Modifier.fillMaxWidth().background(Theme.sidebar)) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(Theme.border))
        Row(Modifier.fillMaxWidth().height(56.dp)) {
            for ((tab, icon) in listOf(Tab.HOME to Icons.Filled.Home, Tab.EPG to Icons.Filled.Tv, Tab.SETTINGS to Icons.Filled.Tune)) {
                val on = model.tab == tab
                Column(Modifier.weight(1f).fillMaxHeight().clickable(remember { MutableInteractionSource() }, null) {
                    // Tapping Home again while in a game goes back to the games.
                    if (on && tab == Tab.HOME && model.openGameId != null) model.closeGame()
                    else if (on && tab == Tab.EPG) PhoneUi.epgPath = emptyList()
                    model.tab = tab
                }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                    Icon(icon, tab.title, tint = if (on) Theme.accent else Theme.muted, modifier = Modifier.size(24.dp))
                    Spacer(Modifier.height(2.dp))
                    Label(tab.title, size = 11.sp, weight = FontWeight.SemiBold, color = if (on) Theme.accent else Theme.muted)
                }
            }
        }
    }
}

// MARK: Pinned player

/**
 * The player pinned above the tabs while something plays, in the same spot on every tab. Tap the video for its
 * quality and the buttons (fold, full screen, stop); double-tap for full screen. Folded, it's one line and the sound
 * carries on.
 */
@Composable
private fun PinnedPlayer(model: AppModel, item: NowPlaying) {
    Column(Modifier.fillMaxWidth().background(Theme.bg).padding(horizontal = 12.dp).padding(top = 6.dp, bottom = 8.dp)) {
        if (PhoneUi.collapsed) {
            SideEffect { model.cornerBounds = null }
            CollapsedBar(model, item)
            return@Column
        }
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val screenHeight = LocalConfiguration.current.screenHeightDp.dp
            // Full width when upright; sideways, no more than 40% of the screen's height.
            val width = if (isLandscape()) minOf(maxWidth, screenHeight * 0.4f * 16 / 9) else maxWidth
            val beside = maxWidth - width >= 190.dp
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Column(Modifier.width(width), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.fillMaxWidth().height(width * 9 / 16).clip(RoundedCornerShape(10.dp)).background(Color.Black)
                        .onGloballyPositioned { model.cornerBounds = it.boundsInRoot() })
                    if (!beside) PinnedTitles(model, item)
                }
                if (beside) Box(Modifier.padding(top = 2.dp)) { PinnedTitles(model, item) }
            }
        }
    }
}

@Composable
private fun PinnedTitles(model: AppModel, item: NowPlaying) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Label(model.playerTitle(item), size = 14.sp, weight = FontWeight.SemiBold, modifier = Modifier.weight(1f, fill = false))
        Label("· ${item.channel.name}", size = 12.sp, color = Theme.muted)
    }
}

/** Over the pinned video: the spinner before the first picture, and after a tap, the quality and the buttons. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun PinnedOverlay(model: AppModel, item: NowPlaying, modifier: Modifier) {
    var show by remember { mutableStateOf(false) }
    var tick by remember { mutableIntStateOf(0) }
    LaunchedEffect(tick) { if (show) { delay(4000); show = false } }
    Box(modifier.combinedClickable(remember { MutableInteractionSource() }, null,
        onDoubleClick = { model.play(item.channel, item.gameTitle, item.lineup, from = "strip") }) { show = !show; tick++ }) {
        Box(Modifier.align(Alignment.Center)) {
            when {
                Playback.status == Playback.Status.FAILED ->
                    Label("This stream couldn't be opened", size = 12.sp, color = Theme.muted)
                Playback.resolution.isEmpty() && Playback.status in setOf(Playback.Status.OPENING, Playback.Status.BUFFERING, Playback.Status.IDLE) ->
                    Spinner(28.dp)
            }
        }
        AnimatedVisibility(show, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.BottomCenter)) {
            Row(Modifier.fillMaxWidth().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.75f))))
                .padding(start = 10.dp, end = 10.dp, top = 26.dp, bottom = 10.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (Playback.resolution.isNotEmpty()) Badge(Playback.resolution)
                if (Playback.hdr.isNotEmpty()) Badge(Playback.hdr)
                if (Playback.frameRate > 0) Badge(Playback.fpsLabel(Playback.frameRate))
                if (Playback.audio.isNotEmpty()) Badge(Playback.audio)
                Spacer(Modifier.weight(1f))
                RoundButton(Icons.Filled.UnfoldLess, "Fold") { PhoneUi.collapsed = true }
                RoundButton(Icons.Filled.Fullscreen, "Full screen") { model.play(item.channel, item.gameTitle, item.lineup, from = "strip") }
                RoundButton(Icons.Filled.Stop, "Stop") { model.stopPinned() }
            }
        }
    }
}

@Composable
private fun CollapsedBar(model: AppModel, item: NowPlaying) {
    Row(Modifier.fillMaxWidth().height(52.dp).clip(RoundedCornerShape(12.dp)).background(Theme.card)
        .clickable { PhoneUi.collapsed = false }.padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(Icons.Filled.GraphicEq, null, tint = Theme.accent, modifier = Modifier.size(18.dp))
        Column(Modifier.weight(1f)) {
            Label(model.playerTitle(item), size = 14.sp, weight = FontWeight.SemiBold)
            Label(item.channel.name, size = 11.sp, color = Theme.muted)
        }
        RoundButton(Icons.Filled.UnfoldMore, "Show the video", fill = Theme.raised) { PhoneUi.collapsed = false }
        RoundButton(Icons.Filled.Fullscreen, "Full screen", fill = Theme.raised) { model.play(item.channel, item.gameTitle, item.lineup, from = "strip") }
        RoundButton(Icons.Filled.Stop, "Stop", fill = Theme.raised) { model.stopPinned() }
    }
}

// MARK: Full screen

/**
 * Full screen. Tap: show or hide the controls. Swipe up or down: back to the player at the top. The arrows switch to
 * the previous / next stream for this game (or channel in this category). Leaving the app keeps it playing in
 * picture in picture. A stream that fails or stalls for 10 seconds switches to the next one when that's turned on.
 */
@Composable
private fun PhoneFullScreen(model: AppModel, item: NowPlaying) {
    val view = LocalView.current
    val activity = LocalContext.current as? MainActivity
    // Hide the status and navigation bars (a swipe from the edge brings them back for a moment).
    DisposableEffect(Unit) {
        val window = activity?.window
        val bars = window?.let { androidx.core.view.WindowCompat.getInsetsController(it, view) }
        bars?.systemBarsBehavior = androidx.core.view.WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        bars?.hide(androidx.core.view.WindowInsetsCompat.Type.systemBars())
        onDispose { bars?.show(androidx.core.view.WindowInsetsCompat.Type.systemBars()) }
    }
    var showControls by remember { mutableStateOf(true) }
    var poke by remember { mutableIntStateOf(0) }
    var flip by remember { mutableStateOf<String?>(null) }
    var flipTick by remember { mutableIntStateOf(0) }
    var tried by remember { mutableStateOf(setOf(item.channel.id)) }
    var automatic by remember { mutableStateOf(false) }
    val pos = item.lineup.indexOfFirst { it.id == item.channel.id } + 1
    fun message(text: String, seconds: Long = 4) { flip = text; flipTick++ }

    LaunchedEffect(poke, item.channel.id, Playback.status) {
        if (poke > 0) showControls = true
        delay(4000)
        if (Playback.status == Playback.Status.PLAYING) showControls = false
    }
    LaunchedEffect(flipTick) {
        val text = flip ?: return@LaunchedEffect
        delay(if (text.contains("Switched") || text.contains("left")) 4000 else 2000)
        flip = null
    }
    LaunchedEffect(item.channel.id) {
        if (automatic) automatic = false
        else {
            tried = setOf(item.channel.id)
            if (item.lineup.size > 1 && poke > 0) message("$pos of ${item.lineup.size} · ${item.channel.name}")
        }
    }
    // Stalled or stopped: the next stream nobody has tried yet, USA and Canada first (Settings › Playback).
    LaunchedEffect(item.channel.id) {
        var stalledFor = 0
        var attempt = Playback.attempt
        while (true) {
            delay(1000)
            if (Playback.attempt != attempt) { attempt = Playback.attempt; stalledFor = 0 }
            if (!model.settings.autoSwitch || item.lineup.size < 2) continue
            val why = when (Playback.status) {
                Playback.Status.FAILED, Playback.Status.ENDED -> "The stream stopped"
                Playback.Status.BUFFERING, Playback.Status.OPENING -> { stalledFor++; if (stalledFor >= 10) "The stream stalled" else null }
                else -> { stalledFor = 0; null }
            } ?: continue
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
    val density = LocalDensity.current
    Box(Modifier.fillMaxSize()
        .clickable(remember { MutableInteractionSource() }, null) { if (showControls) showControls = false else { showControls = true; poke++ } }
        .pointerInput(Unit) {
            var total = 0f
            detectVerticalDragGestures(onDragStart = { total = 0f }, onDragEnd = {
                if (kotlin.math.abs(total) > with(density) { 60.dp.toPx() }) model.closePlayer()
            }) { _, dy -> total += dy }
        }) {
        Box(Modifier.align(Alignment.Center)) {
            when (Playback.status) {
                Playback.Status.OPENING, Playback.Status.IDLE -> Column(horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Spinner(36.dp)
                    Label("Opening ${item.channel.name}…", size = 14.sp, color = Color.White.copy(alpha = 0.8f))
                }
                Playback.Status.BUFFERING -> if (Playback.resolution.isEmpty()) Column(horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Spinner(36.dp)
                    Label("Buffering…", size = 14.sp, color = Color.White.copy(alpha = 0.8f))
                }
                Playback.Status.FAILED -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(Icons.Filled.Warning, null, tint = Theme.accent, modifier = Modifier.size(36.dp))
                    Label("This stream couldn't be opened.", size = 15.sp, color = Color.White.copy(alpha = 0.85f))
                    PillButton("Try again") { Playback.stop(); model.play(item.channel, item.gameTitle, item.lineup) }
                }
                Playback.Status.ENDED -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Label("The stream stopped.", size = 15.sp, color = Color.White.copy(alpha = 0.85f))
                    PillButton("Reconnect") { Playback.stop(); model.play(item.channel, item.gameTitle, item.lineup) }
                }
                Playback.Status.PAUSED -> Icon(Icons.Filled.Pause, null, tint = Color.White.copy(alpha = 0.85f), modifier = Modifier.size(54.dp))
                else -> {}
            }
        }
        flip?.let {
            Box(Modifier.align(Alignment.TopCenter).padding(top = 60.dp).clip(RoundedCornerShape(20.dp))
                .background(Color.Black.copy(alpha = 0.75f)).padding(horizontal = 16.dp, vertical = 10.dp)) {
                Label(it, size = 14.sp, weight = FontWeight.SemiBold, color = Color.White, maxLines = 2)
            }
        }
        if (showControls) {
            Row(Modifier.align(Alignment.TopCenter).fillMaxWidth().windowInsetsPadding(WindowInsets.displayCutout)
                .padding(horizontal = 20.dp, vertical = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                RoundButton(Icons.Filled.Close, "Close", size = 42.dp) { model.closePlayer() }
                Spacer(Modifier.weight(1f))
                if (android.os.Build.VERSION.SDK_INT >= 26 && activity != null &&
                    activity.packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE))
                    RoundButton(Icons.Filled.PictureInPictureAlt, "Picture in picture", size = 42.dp) { activity.enterPip() }
                RoundButton(if (Playback.status == Playback.Status.PAUSED) Icons.Filled.PlayArrow else Icons.Filled.Pause,
                    "Pause", size = 42.dp) { Playback.togglePause(); poke++ }
            }
            Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.8f))))
                .windowInsetsPadding(WindowInsets.displayCutout).padding(start = 20.dp, end = 20.dp, top = 40.dp, bottom = 18.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
            // The streams watched before this one, most recent on the left (as many as fit): tap one to go back to it.
            val recents = model.recentStreams(item, limit = 4)
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                val fits = maxOf(0, ((maxWidth - 92.dp + 8.dp) / (168.dp)).toInt())
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    ReconnectButton(picked = false, modifier = Modifier.clickable { poke++; Playback.reconnect() })
                    if (recents.isNotEmpty()) ClearRecentButton(picked = false, modifier = Modifier.clickable { poke++; model.clearWatched() })
                    recents.take(fits).forEach { r ->
                        RecentCard(model, r, picked = false, width = 160.dp,
                            modifier = Modifier.clickable { poke++; model.play(r.channel, r.gameTitle, r.lineup) })
                    }
                }
            }
            Row(Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Label(model.playerTitle(item), size = 17.sp, weight = FontWeight.Bold, color = Color.White)
                    Label(if (item.lineup.size > 1) "${item.channel.name} · $pos of ${item.lineup.size}" else item.channel.name,
                        size = 12.sp, color = Color.White.copy(alpha = 0.75f))
                }
                if (Playback.resolution.isNotEmpty()) Badge(Playback.resolution)
                if (Playback.hdr.isNotEmpty()) Badge(Playback.hdr)
                if (Playback.frameRate > 0) Badge(Playback.fpsLabel(Playback.frameRate))
                if (Playback.audio.isNotEmpty()) Badge(Playback.audio)
                if (item.lineup.size > 1) {
                    RoundButton(Icons.Filled.KeyboardArrowUp, "Previous stream", size = 42.dp) { poke++; model.step(-1) }
                    RoundButton(Icons.Filled.KeyboardArrowDown, "Next stream", size = 42.dp) { poke++; model.step(1) }
                }
            }
            }
        }
    }
}

// MARK: Sign in

@Composable
fun PhoneLogin(model: AppModel, editing: Credentials? = null, onDone: (() -> Unit)? = null) {
    var server by remember { mutableStateOf(editing?.server ?: "") }
    var username by remember { mutableStateOf(editing?.username ?: "") }
    var password by remember { mutableStateOf(editing?.password ?: "") }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    if (onDone != null) BackHandler { onDone() }
    Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).verticalScroll(rememberScrollState())
        .padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Spacer(Modifier.height(40.dp))
        Icon(Icons.Filled.SportsBasketball, null, tint = Theme.accent, modifier = Modifier.size(56.dp))
        Label("Courtside", size = 32.sp, weight = FontWeight.Bold)
        Label(if (editing == null) "Sign in with your IPTV provider's Xtream Codes login." else "Change your Xtream Codes login.",
            size = 14.sp, color = Theme.muted, maxLines = 2, align = androidx.compose.ui.text.style.TextAlign.Center)
        Spacer(Modifier.height(4.dp))
        Column(Modifier.widthIn(max = 460.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            TouchField("Server, for example http://example.com:8080", server, { server = it }, KeyboardType.Uri)
            TouchField("Username", username, { username = it })
            TouchField("Password", password, { password = it }, KeyboardType.Password, secret = true)
            error?.let { Label(it, size = 13.sp, color = Theme.losing, maxLines = 4) }
            val ready = !working && server.isNotBlank() && username.isNotBlank() && password.isNotEmpty()
            Box(Modifier.fillMaxWidth().height(50.dp).clip(RoundedCornerShape(12.dp)).background(Theme.accent)
                .alpha(if (ready || working) 1f else 0.5f).clickable(enabled = ready) {
                    working = true
                    error = null
                    scope.launch {
                        val creds = Credentials(server.trim(), username.trim(), password)
                        error = if (editing == null) model.signIn(creds) else model.updateAccount(creds)
                        working = false
                        if (error == null) onDone?.invoke()
                    }
                }, contentAlignment = Alignment.Center) {
                Label(if (working) (if (editing == null) "Signing in…" else "Checking…") else (if (editing == null) "Sign in" else "Save"),
                    size = 16.sp, weight = FontWeight.Bold, color = Theme.onAccent)
            }
            if (onDone != null) Box(Modifier.fillMaxWidth().clickable { onDone() }.padding(10.dp), contentAlignment = Alignment.Center) {
                Label("Cancel", size = 15.sp, color = Theme.muted)
            }
        }
    }
}

// MARK: Small pieces

/** A text box for touch: tap to type. */
@Composable
fun TouchField(hint: String, value: String, onChange: (String) -> Unit, type: KeyboardType = KeyboardType.Text,
               secret: Boolean = false, height: Dp = 50.dp, leading: ImageVector? = null, modifier: Modifier = Modifier,
               onDone: () -> Unit = {}) {
    val keyboard = androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
    Row(modifier.fillMaxWidth().height(height).clip(RoundedCornerShape(12.dp)).background(Theme.card)
        .padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (leading != null) Icon(leading, null, tint = Theme.muted, modifier = Modifier.size(18.dp))
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (value.isEmpty()) Label(hint, size = 15.sp, color = Theme.muted)
            BasicTextField(
                value = value, onValueChange = onChange, singleLine = true,
                textStyle = TextStyle(color = Theme.text, fontSize = 15.sp),
                cursorBrush = SolidColor(Theme.accent),
                visualTransformation = if (secret) PasswordVisualTransformation() else VisualTransformation.None,
                keyboardOptions = KeyboardOptions(keyboardType = type, autoCorrectEnabled = false,
                    capitalization = androidx.compose.ui.text.input.KeyboardCapitalization.None,
                    imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                keyboardActions = androidx.compose.foundation.text.KeyboardActions(onDone = { keyboard?.hide(); onDone() }),
                modifier = Modifier.fillMaxWidth()
            )
        }
        if (value.isNotEmpty() && !secret) Icon(Icons.Filled.Cancel, "Clear", tint = Theme.muted,
            modifier = Modifier.size(18.dp).clip(CircleShape).clickable { onChange("") })
    }
}

/** A filter chip (sports, leagues, favourites, settings sections): white when selected. */
@Composable
fun TouchChip(selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit, content: @Composable RowScope.(Color) -> Unit) {
    val color = if (selected) Theme.bg else Theme.soft
    Row(modifier.height(36.dp).clip(RoundedCornerShape(18.dp)).background(if (selected) Theme.text else Theme.card)
        .border(1.dp, if (selected) Color.Transparent else Theme.border, RoundedCornerShape(18.dp))
        .clickable(onClick = onClick).padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) { content(color) }
}

/**
 * A row of chips along the bottom that starts from the right edge (the thumb's side) and scrolls left if it doesn't
 * fit; centred when it does. Give it the chips right to left.
 */
@Composable
fun TrailingRow(content: @Composable RowScope.() -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val width = maxWidth
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState(), reverseScrolling = true)) {
            Row(Modifier.widthIn(min = width).padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically) {
                // Built right to left: reverse the order so the first chip given sits on the right.
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) { content() }
            }
        }
    }
}

@Composable
fun RoundButton(icon: ImageVector, description: String, size: Dp = 34.dp, fill: Color = Color.White.copy(alpha = 0.2f),
                onClick: () -> Unit) {
    Box(Modifier.size(size).clip(CircleShape).background(fill).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(icon, description, tint = Color.White, modifier = Modifier.size(size * 0.5f))
    }
}

@Composable
fun PillButton(title: String, onClick: () -> Unit) {
    Box(Modifier.clip(RoundedCornerShape(20.dp)).background(Theme.accent).clickable(onClick = onClick)
        .padding(horizontal = 20.dp, vertical = 10.dp)) {
        Label(title, size = 14.sp, weight = FontWeight.Bold, color = Theme.onAccent)
    }
}

@Composable
fun Spinner(size: Dp) {
    androidx.compose.material3.CircularProgressIndicator(color = Theme.accent, trackColor = Color.Transparent,
        strokeWidth = 3.dp, modifier = Modifier.size(size))
}

/** A thin progress bar (what's on now, the EPG download). */
@Composable
fun ThinProgress(fraction: Float, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().height(3.dp).clip(RoundedCornerShape(2.dp)).background(Theme.raised)) {
        Box(Modifier.fillMaxHeight().fillMaxWidth(fraction.coerceIn(0f, 1f)).background(Theme.accent))
    }
}

/** "1/2": connections in use on the provider account, orange at the limit. */
@Composable
fun ConnectionsPill(account: AccountInfo?) {
    val max = account?.maxConnections ?: return
    if (max <= 0) return
    val active = account.activeConnections ?: 0
    val full = active >= max
    Row(Modifier.clip(RoundedCornerShape(14.dp)).background(if (full) Theme.accent else Theme.raised)
        .padding(horizontal = 10.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        Icon(Icons.Filled.People, null, tint = if (full) Theme.onAccent else Theme.muted, modifier = Modifier.size(14.dp))
        Label("$active/$max", size = 13.sp, weight = FontWeight.SemiBold, color = if (full) Theme.onAccent else Theme.muted)
    }
}
