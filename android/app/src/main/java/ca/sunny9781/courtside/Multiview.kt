@file:kotlin.OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)

package ca.sunny9781.courtside

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import androidx.tv.material3.Icon
import kotlinx.coroutines.delay

/**
 * A multiview tile's own player (2.30): a second ExoPlayer, separate from Playback, made when the tile opens and
 * released when it closes. TS only (no HLS fallback). Same rules as normal playback: a picture frozen for 10 s is
 * reopened (FreezeWatch), and a stream that had shown a picture and drops is opened again (every 3 s, up to 2 min).
 * Its trouble never touches the other tile. Stream addresses are never logged (they hold the login).
 */
@OptIn(UnstableApi::class)
class TilePlayer(private val context: Context, private val name: String) {
    var player by mutableStateOf<ExoPlayer?>(null)
        private set
    var status by mutableStateOf(Playback.Status.IDLE)
        private set
    var resolution by mutableStateOf("")
        private set
    /** The stream has shown its first picture since it was last opened. */
    var hasPicture by mutableStateOf(false)
        private set
    private var url: String? = null
    private var label = ""
    /** The stream has shown a picture at some point (a drop after that reopens it instead of failing). */
    private var everPicture = false
    private var volume = 0f
    private val freeze = FreezeWatch()
    private val handler = Handler(Looper.getMainLooper())
    private var pending: Runnable? = null
    private var droppedSince = 0L
    private var lastReconnect = 0L
    private val poller = object : Runnable {
        override fun run() {
            poll()
            if (player != null) handler.postDelayed(this, 500)
        }
    }

    val isOpen: Boolean get() = url != null

    fun setVolume(v: Float) {
        volume = v
        player?.volume = v
    }

    /** Plays a stream in this tile. One already open is fully closed first, then the new one opens a moment later. */
    fun open(url: String, label: String) {
        val had = this.url != null || (player?.mediaItemCount ?: 0) > 0
        cancelPending()
        if (had) closeStream()
        this.url = url
        this.label = label
        everPicture = false
        hasPicture = false
        resolution = ""
        droppedSince = 0L
        freeze.reset()
        status = Playback.Status.OPENING
        ConnLog.add("Multiview: opened $name ($label)")
        later(if (had) 600L else 0L) { load(url) }
    }

    /** Stops the stream and releases the player completely. */
    fun close() {
        cancelPending()
        if (url != null) ConnLog.add("Multiview: closed $name")
        closeStream()
        url = null
        status = Playback.Status.IDLE
        hasPicture = false
        resolution = ""
        handler.removeCallbacks(poller)
        player?.release()
        player = null
    }

    private fun cancelPending() {
        pending?.let { handler.removeCallbacks(it) }
        pending = null
    }

    private fun later(delayMs: Long, action: () -> Unit) {
        cancelPending()
        val run = Runnable { pending = null; action() }
        pending = run
        if (delayMs <= 0) run.run() else handler.postDelayed(run, delayMs)
    }

    private fun closeStream() {
        player?.let { it.stop(); it.clearMediaItems() }
    }

    private fun load(url: String) {
        if (this.url != url) return
        val p = player ?: build().also {
            player = it
            handler.removeCallbacks(poller)
            handler.postDelayed(poller, 500)
        }
        p.volume = volume
        hasPicture = false
        p.setMediaSource(Playback.source(url))
        p.prepare()
        p.playWhenReady = true
    }

    /** Closes the stream, waits a moment so the provider sees it gone, and opens the same one again. */
    private fun reopen(delayMs: Long, why: String) {
        val u = url ?: return
        ConnLog.add("Multiview: $name $why, opening it again")
        closeStream()
        later(delayMs) { load(u) }
    }

    private fun build(): ExoPlayer {
        val bufferMs = Prefs.bufferMs(context)
        val load = DefaultLoadControl.Builder()
            .setBufferDurationsMs(maxOf(bufferMs, 2500), maxOf(bufferMs * 4, 15_000), bufferMs, bufferMs)
            .build()
        return ExoPlayer.Builder(context, FreshDecoderRenderers(context)).setLoadControl(load).build().apply {
            videoChangeFrameRateStrategy = C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_OFF
            addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(state: Int) = refreshStatus()
                override fun onIsPlayingChanged(isPlaying: Boolean) = refreshStatus()
                override fun onRenderedFirstFrame() {
                    hasPicture = true
                    everPicture = true
                }
                override fun onVideoSizeChanged(size: VideoSize) {
                    if (size.height > 0) resolution = Playback.label(size.height)
                }
                override fun onPlayerError(error: PlaybackException) {
                    ConnLog.add("Multiview: $name stream error: ${error.errorCodeName}")
                    status = if (reconnectAfterDrop()) Playback.Status.BUFFERING else Playback.Status.FAILED
                }
            })
        }
    }

    /** Like Playback: a stream that had shown a picture and dropped is opened again (every 3 s, up to 2 minutes). */
    private fun reconnectAfterDrop(): Boolean {
        if (!everPicture || url == null) return false
        val now = System.currentTimeMillis()
        if (droppedSince == 0L) droppedSince = now
        if (now - droppedSince >= 120_000) return false
        if (pending != null) return true
        val wait = maxOf(0L, 3000 - (now - lastReconnect))
        lastReconnect = now + wait
        reopen(wait, "dropped")
        return true
    }

    private fun refreshStatus() {
        val p = player ?: return
        status = when (p.playbackState) {
            Player.STATE_BUFFERING -> if (status == Playback.Status.OPENING) Playback.Status.OPENING else Playback.Status.BUFFERING
            Player.STATE_READY -> if (p.playWhenReady) { droppedSince = 0L; Playback.Status.PLAYING } else Playback.Status.PAUSED
            Player.STATE_ENDED -> if (reconnectAfterDrop()) Playback.Status.BUFFERING else Playback.Status.ENDED
            else -> if (url == null) Playback.Status.IDLE else status
        }
    }

    private fun poll() {
        val p = player ?: return
        if (url == null || pending != null) return
        val watching = hasPicture && p.playWhenReady &&
            (status == Playback.Status.PLAYING || status == Playback.Status.BUFFERING || status == Playback.Status.OPENING)
        if (freeze.check(p.currentPosition.toDouble(), watching) == FreezeWatch.Action.RESTART) reopen(400, "froze")
    }
}

// MARK: Screen

/**
 * Multiview (2.30): two tiles over everything. Left/Right moves focus (orange outline); Select moves the sound there
 * (and, with "Make big", makes it the big tile); hold Select opens the tile's panel (streams, another game, remove);
 * Back leaves, keeping the tile with sound as the normal full-screen stream. Tile 1's video is the shell's main
 * video view, placed at `model.tileBounds`; tile 2 has its own view here.
 */
@Composable
fun MultiviewScreen(model: AppModel) {
    val tiles = model.tiles
    if (tiles.size < 2) return
    var focused by remember { mutableIntStateOf(0) }
    var panelFor by remember { mutableStateOf<Int?>(null) }
    // Holding select asks for the panel; it opens once select is let go, so the tile sees the release (and the
    // panel's first row doesn't get the rest of the press).
    var panelWanted by remember { mutableStateOf<Int?>(null) }
    val tileFocus = remember { List(2) { FocusRequester() } }
    BackHandler(enabled = panelFor == null) { model.leaveMultiview() }
    LaunchedEffect(panelFor) {
        if (panelFor == null) { delay(50); runCatching { tileFocus[focused.coerceIn(0, 1)].requestFocus() } }
    }
    // Remember the quality tile 2 really plays at (tile 1 is recorded by the shell, like normal playback).
    val second = tiles[1].item.channel.id
    LaunchedEffect(model.tile2.resolution, second) { model.recordQuality(second, model.tile2.resolution) }

    Box(Modifier.fillMaxSize().onPreviewKeyEvent { e ->
        val k = e.nativeKeyEvent
        if (k.action == android.view.KeyEvent.ACTION_UP && k.keyCode in SELECT_KEYCODES) {
            panelWanted?.let { panelFor = it; panelWanted = null }
        }
        false
    }.focusProperties { exit = { FocusRequester.Cancel } }.focusGroup()) {
        Column(Modifier.fillMaxSize().padding(horizontal = 24.dp, vertical = 16.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Label("Multiview", size = 20.sp, weight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                val a = model.account
                val max = a?.maxConnections
                if (max != null) Row(Modifier.clip(RoundedCornerShape(14.dp)).background(Theme.raised)
                    .padding(horizontal = 12.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    val active = a?.activeConnections ?: 0
                    Icon(Icons.Filled.People, null, tint = if (active >= max) Theme.accent else Theme.muted, modifier = Modifier.size(14.dp))
                    Label("$active of $max connections", size = 12.sp, weight = FontWeight.SemiBold,
                        color = if (active >= max) Theme.accent else Theme.soft)
                }
            }
            BoxWithConstraints(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                val big = model.bigTile
                val gap = if (big == null) 16.dp else maxWidth * 0.02f
                var widths: List<Dp> = when (big) {
                    null -> List(2) { (maxWidth - gap) / 2 }
                    0 -> listOf(maxWidth * 0.68f, maxWidth * 0.30f)
                    else -> listOf(maxWidth * 0.30f, maxWidth * 0.68f)
                }
                // Each tile is 16:9 with a line under it: shrink both if the taller one doesn't fit.
                val caption = 30.dp
                val tallest = widths.maxOf { it } * 9f / 16f + caption
                if (tallest > maxHeight) {
                    val f = (maxHeight - caption) / (tallest - caption)
                    widths = widths.map { it * f }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(gap), verticalAlignment = Alignment.CenterVertically) {
                    tiles.forEachIndexed { i, tile ->
                        TileView(model, i, tile, widths[i], tileFocus[i], canFocus = panelFor == null,
                            left = tileFocus[0], right = tileFocus[1],
                            onFocus = { focused = i }, onClick = { model.tileSelected(i) },
                            onHold = { panelWanted = i })
                    }
                }
            }
            Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.Center) {
                Label(if (model.settings.multiviewMakeBig) "Select  make big / move sound  ·  Hold select  swap or remove  ·  Back  leave"
                      else "Select  move sound  ·  Hold select  swap or remove  ·  Back  leave", size = 12.sp, color = Theme.muted)
            }
        }
        panelFor?.let { i -> TilePanel(model, i) { panelFor = null } }
    }
}

private val SELECT_KEYCODES = setOf(android.view.KeyEvent.KEYCODE_DPAD_CENTER, android.view.KeyEvent.KEYCODE_ENTER,
    android.view.KeyEvent.KEYCODE_NUMPAD_ENTER, android.view.KeyEvent.KEYCODE_BUTTON_A)

@Composable
private fun TileView(model: AppModel, i: Int, tile: AppModel.Tile, width: Dp, focus: FocusRequester, canFocus: Boolean,
                     left: FocusRequester, right: FocusRequester,
                     onFocus: () -> Unit, onClick: () -> Unit, onHold: () -> Unit) {
    val shape = RoundedCornerShape(8.dp)
    val channel = tile.item.channel
    val status = if (i == 0) Playback.status else model.tile2.status
    val resolution = if (i == 0) Playback.resolution else model.tile2.resolution
    val sound = model.soundTile == i
    Column(Modifier.width(width), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        // See-through (focusedFill transparent): tile 1's video is drawn underneath by the shell.
        TvButton(onClick = onClick, onFocus = onFocus, onLongClick = onHold, focusedFill = Color.Transparent, shape = shape,
            modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f).focusRequester(focus)
                .focusProperties { this.canFocus = canFocus; this.left = left; this.right = right }) { focused ->
            Box(Modifier.fillMaxSize().border(if (focused) 3.dp else 1.dp, if (focused) Theme.accent else Theme.border, shape)
                .padding(3.dp)) {
                if (i == 0) Box(Modifier.fillMaxSize().onGloballyPositioned { model.tileBounds = it.boundsInRoot() })
                else TileVideo(model.tile2, Modifier.fillMaxSize())
                val message = when (status) {
                    Playback.Status.OPENING -> "Opening…"
                    Playback.Status.BUFFERING -> "Buffering…"
                    Playback.Status.FAILED -> "This stream couldn't be opened"
                    Playback.Status.ENDED -> "The stream stopped"
                    else -> null
                }
                if (message != null) Box(Modifier.align(Alignment.Center).clip(RoundedCornerShape(8.dp))
                    .background(Color.Black.copy(alpha = 0.6f)).padding(horizontal = 10.dp, vertical = 5.dp)) {
                    Label(message, size = 12.sp, color = Theme.soft)
                }
                ScoreChip(model, tile, Modifier.align(Alignment.TopStart).padding(8.dp))
                Box(Modifier.align(Alignment.TopEnd).padding(8.dp).clip(RoundedCornerShape(8.dp))
                    .background(Color.Black.copy(alpha = 0.7f)).padding(5.dp)) {
                    Icon(if (sound) Icons.Filled.VolumeUp else Icons.Filled.VolumeOff, if (sound) "Sound" else "Muted",
                        tint = if (sound) Theme.accent else Theme.muted, modifier = Modifier.size(16.dp))
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 2.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            ReliabilityDot(channel.id, bare = true)
            Label(channel.name, size = 12.sp, weight = FontWeight.SemiBold, color = Theme.soft, modifier = Modifier.weight(1f, fill = false))
            val quality = resolution.ifEmpty { model.measuredQuality[channel.id] ?: "" }
            if (quality.isNotEmpty()) Badge(quality)
        }
    }
}

/** Tile 2's video: its own view (a real video surface, like the main player). */
@Composable
private fun TileVideo(tile: TilePlayer, modifier: Modifier) {
    AndroidView(
        factory = { ctx ->
            (android.view.LayoutInflater.from(ctx).inflate(R.layout.player_surface, null) as PlayerView).apply {
                useController = false
                resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                setShutterBackgroundColor(android.graphics.Color.BLACK)
                isFocusable = false
                player = tile.player
            }
        },
        update = { view -> val p = tile.player; if (view.player !== p) view.player = p },
        onRelease = { view -> view.player = null },
        modifier = modifier.background(Color.Black)
    )
}

/** "BOS 54 – 61 NYK · Q3 4:12" (status in orange), the event's name, or the channel's name for a channel with no game. */
@Composable
private fun ScoreChip(model: AppModel, tile: AppModel.Tile, modifier: Modifier) {
    val game = tile.gameId?.let { id -> model.game(id) }
    Row(modifier.clip(RoundedCornerShape(8.dp)).background(Color.Black.copy(alpha = 0.7f))
        .padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        if (game == null || game.isChannel) {
            Label(tile.item.channel.name, size = 12.sp, weight = FontWeight.SemiBold)
        } else {
            Label(scoreLine(game), size = 12.sp, weight = FontWeight.Bold)
            Label(gameStatus(game), size = 11.sp, weight = FontWeight.SemiBold, color = Theme.accent)
        }
    }
}

private fun scoreLine(game: Game): String = when {
    game.isEvent && !game.hasSides -> game.eventTitle
    game.state == GameState.UPCOMING || Perf.noScores || game.away.score.isEmpty() -> "${game.away.abbr} at ${game.home.abbr}"
    else -> "${game.away.abbr} ${game.away.score} – ${game.home.score} ${game.home.abbr}"
}

private fun gameStatus(game: Game): String = when (game.state) {
    GameState.LIVE -> if (Perf.noScores) "LIVE" else game.statusText.ifEmpty { "LIVE" }
    GameState.UPCOMING -> startText(game)
    GameState.FINISHED -> cardHeader(game)
}

/**
 * Hold select on a tile: a left panel with the game and its score, its streams (4K left out; the one playing
 * marked), Pick another game… (live games by sport) and Remove tile. Back closes it (from the games list: back to
 * the panel first).
 */
@Composable
private fun TilePanel(model: AppModel, index: Int, close: () -> Unit) {
    val tile = model.tiles.getOrNull(index) ?: return
    var picking by remember { mutableStateOf(false) }
    BackHandler { if (picking) picking = false else close() }
    val first = remember { FocusRequester() }
    LaunchedEffect(picking) { delay(50); runCatching { first.requestFocus() } }
    val game = tile.gameId?.let { id -> model.game(id) }
    val playing = tile.item.channel.id
    Box(Modifier.fillMaxHeight().width(320.dp).background(Theme.sidebar)) {
        LazyColumn(Modifier.fillMaxSize().focusGroup(), contentPadding = PaddingValues(12.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp)) {
            item(key = "title") {
                Column(Modifier.padding(start = 10.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Label("TILE ${index + 1}", size = 10.sp, weight = FontWeight.Bold, color = Theme.muted)
                    Label(game?.takeIf { !it.isChannel }?.title ?: tile.item.channel.name, size = 15.sp, weight = FontWeight.Bold, maxLines = 2)
                    if (game != null && !game.isChannel) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Label(scoreLine(game), size = 12.sp, color = Theme.soft)
                        Label(gameStatus(game), size = 12.sp, weight = FontWeight.SemiBold, color = Theme.accent)
                    }
                }
            }
            if (picking) {
                val home = model.home
                var firstRow = true
                for (sport in home.scoreSports) {
                    val live = model.games(sport).filter { it.state == GameState.LIVE && !it.isChannel }
                    if (live.isEmpty()) continue
                    item(key = "h:${sport.name}") {
                        Label(sport.title.uppercase(), size = 10.sp, weight = FontWeight.Bold, color = Theme.muted,
                            modifier = Modifier.padding(start = 10.dp, top = 8.dp, bottom = 2.dp))
                    }
                    for (g in live) {
                        val isFirst = firstRow
                        firstRow = false
                        item(key = "g:${g.id}") {
                            PanelRow(if (isFirst) Modifier.focusRequester(first) else Modifier, g.title, gameStatus(g),
                                selected = g.id == tile.gameId) { model.swapTileToGame(index, g.id); close() }
                        }
                    }
                }
                if (firstRow) item(key = "none") {
                    PanelRow(Modifier.focusRequester(first), "No live games right now", null) { picking = false }
                }
            } else {
                val streams = tile.gameId?.let { model.tileStreams(it) } ?: emptyList()
                if (streams.isNotEmpty()) item(key = "sh") {
                    Label("STREAMS", size = 10.sp, weight = FontWeight.Bold, color = Theme.muted,
                        modifier = Modifier.padding(start = 10.dp, top = 4.dp, bottom = 2.dp))
                }
                streams.forEachIndexed { n, m ->
                    item(key = "s:${m.channel.id}") {
                        val quality = model.measuredQuality[m.channel.id] ?: m.quality
                        PanelRow(if (n == 0) Modifier.focusRequester(first) else Modifier, m.channel.name,
                            if (m.channel.id == playing) "playing" else null, selected = m.channel.id == playing,
                            dot = m.channel.id, badge = quality) {
                            if (m.channel.id != playing) tile.gameId?.let { model.swapTile(index, m, it) }
                            close()
                        }
                    }
                }
                item(key = "pick") {
                    PanelRow(if (streams.isEmpty()) Modifier.focusRequester(first) else Modifier, "Pick another game…", null,
                        icon = Icons.Filled.LiveTv) { picking = true }
                }
                item(key = "remove") {
                    PanelRow(Modifier, "Remove tile", null, icon = Icons.Filled.Close) { model.leaveMultiview(keep = 1 - index) }
                }
            }
        }
    }
}

@Composable
private fun PanelRow(modifier: Modifier, title: String, detail: String?, selected: Boolean = false, dot: Int? = null,
                     badge: String? = null, icon: androidx.compose.ui.graphics.vector.ImageVector? = null, onClick: () -> Unit) {
    TvButton(onClick = onClick, selected = selected, modifier = modifier.fillMaxWidth()) { focused ->
        val color = if (focused) Theme.bg else Theme.text
        Row(Modifier.padding(horizontal = 10.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (icon != null) Icon(icon, null, tint = if (focused) Theme.bg else Theme.accent, modifier = Modifier.size(15.dp))
            if (dot != null) ReliabilityDot(dot, bare = true)
            Label(title, size = 13.sp, weight = FontWeight.SemiBold, color = color, maxLines = 2, modifier = Modifier.weight(1f))
            if (detail != null) Label(detail, size = 11.sp, color = if (focused) Theme.bg else Theme.accent)
            if (!badge.isNullOrEmpty()) Badge(badge)
        }
    }
}
