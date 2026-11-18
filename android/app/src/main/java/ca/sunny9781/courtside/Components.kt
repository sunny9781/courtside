package ca.sunny9781.courtside

import androidx.compose.foundation.basicMarquee
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Tv
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.type
import androidx.compose.ui.composed
import kotlinx.coroutines.launch
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Text
import coil.compose.AsyncImage

/** The same colours as the Mac and Apple TV apps. */
object Theme {
    val bg = Color(0xFF0E1116)
    val sidebar = Color(0xFF131820)
    val card = Color(0xFF171B22)
    val raised = Color(0xFF232A35)
    val border = Color(0xFF2E3643)
    val text = Color(0xFFF2F4F7)
    val soft = Color(0xFFD5DAE2)
    val muted = Color(0xFF9AA3B2)
    val accent = Color(0xFFFF8A3D)
    val onAccent = Color(0xFF14100C)
    val winning = Color(0xFF4ADE80)
    val losing = Color(0xFFF87171)
    val champion = Color(0xFFFACC15)
    /** Left, right and top margin on every screen: small, to use the whole TV. */
    val margin = 12.dp
    /** Width of the player's video at the top (the left column on Home matches it). */
    val playerWidth = 240.dp
    /** Height the player in the top-right corner takes; pages leave this much room above their right-hand part. */
    /** The one-line now-playing bar along the very bottom of the screen. */
    val barHeight = 30.dp
    /** The player and its gaps, plus the bar under it: how far the left panels stop from the bottom. */
    val stripHeight = playerWidth * 9 / 16 + margin * 2 + barHeight
}

/**
 * Anything you can move to with the remote and click: it grows a little and turns white when it has focus,
 * like the Apple TV app. `content` gets whether it's focused, to switch its text to dark.
 */
private val PlainBringIntoView = androidx.compose.runtime.staticCompositionLocalOf<Any?> { null }

/**
 * A page that scrolls under the now-playing bar along the bottom: moving to a row keeps it above the bar (instead of
 * leaving it hidden behind), while the page itself still runs to the bottom of the screen. Give the list bottom
 * padding of barInset(model) so its last row can scroll clear of the bar.
 */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@androidx.compose.runtime.Composable
fun BehindPlayerBar(model: AppModel, content: @androidx.compose.runtime.Composable () -> Unit) {
    val inset = with(androidx.compose.ui.platform.LocalDensity.current) { barInset(model).toPx() }
    val original = androidx.compose.foundation.gestures.LocalBringIntoViewSpec.current
    if (inset <= 0f) { content(); return }
    val spec = remember(inset) {
        object : androidx.compose.foundation.gestures.BringIntoViewSpec {
            override fun calculateScrollDistance(offset: Float, size: Float, containerSize: Float): Float {
                val visible = containerSize - inset
                val end = offset + size
                return when {
                    offset < 0f -> offset
                    end > visible -> if (size > visible) offset else end - visible
                    else -> 0f
                }
            }
        }
    }
    androidx.compose.runtime.CompositionLocalProvider(
        androidx.compose.foundation.gestures.LocalBringIntoViewSpec provides spec,
        PlainBringIntoView provides original
    ) { content() }
}

/** Inside a BehindPlayerBar page, a sideways row (league chips) scrolls the usual way. */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@androidx.compose.runtime.Composable
fun SidewaysScroll(content: @androidx.compose.runtime.Composable () -> Unit) {
    val original = PlainBringIntoView.current as? androidx.compose.foundation.gestures.BringIntoViewSpec
    if (original == null) { content(); return }
    androidx.compose.runtime.CompositionLocalProvider(androidx.compose.foundation.gestures.LocalBringIntoViewSpec provides original) { content() }
}

private val SELECT_KEYS = setOf(android.view.KeyEvent.KEYCODE_DPAD_CENTER, android.view.KeyEvent.KEYCODE_ENTER,
    android.view.KeyEvent.KEYCODE_NUMPAD_ENTER, android.view.KeyEvent.KEYCODE_BUTTON_A)

@Composable
fun TvButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    selected: Boolean = false,
    shape: Shape = RoundedCornerShape(10.dp),
    focusedScale: Float = 1.04f,
    onFocus: (() -> Unit)? = null,
    background: Color = Color.Transparent,
    /** Holding the select button down (instead of clicking). */
    onLongClick: (() -> Unit)? = null,
    content: @Composable BoxScope.(focused: Boolean) -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    var held by remember { mutableStateOf(false) }
    Box(
        modifier
            .onFocusChanged {
                focused = it.isFocused
                if (it.isFocused) onFocus?.invoke()
            }
            .onPreviewKeyEvent { e ->
                val k = e.nativeKeyEvent
                if (onLongClick == null || k.keyCode !in SELECT_KEYS) return@onPreviewKeyEvent false
                when (k.action) {
                    // The remote repeats the key while it's held: that's a long press (once), and no click after.
                    android.view.KeyEvent.ACTION_DOWN -> if (k.repeatCount > 0) {
                        if (!held) { held = true; onLongClick() }
                        true
                    } else false
                    android.view.KeyEvent.ACTION_UP -> if (held) { held = false; true } else false
                    else -> false
                }
            }
            .scale(if (focused && !Perf.lite) focusedScale else 1f)
            .clip(shape)
            .background(
                when {
                    focused -> Theme.text
                    selected -> Theme.raised
                    else -> background
                }
            )
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClick)
    ) { content(focused) }
}

@Composable
fun Label(
    text: String,
    size: TextUnit = 13.sp,
    color: Color = Theme.text,
    weight: FontWeight = FontWeight.Normal,
    maxLines: Int = 1,
    modifier: Modifier = Modifier,
    align: androidx.compose.ui.text.style.TextAlign? = null,
    scroll: Boolean = false
) {
    // scroll: text too long for its space slides along inside it (used on the row you're on, in fixed columns).
    if (scroll) ScrollingLabel(text, size, color, weight, modifier)
    else Text(text, modifier = modifier, color = color, fontSize = size, fontWeight = weight, maxLines = maxLines,
        overflow = TextOverflow.Ellipsis, textAlign = align)
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
private fun ScrollingLabel(text: String, size: TextUnit, color: Color, weight: FontWeight, modifier: Modifier) {
    Text(text, modifier = modifier.basicMarquee(iterations = Int.MAX_VALUE), color = color, fontSize = size,
        fontWeight = weight, maxLines = 1, overflow = TextOverflow.Clip)
}

@Composable
fun Badge(text: String, fill: Color = Theme.raised, color: Color = Theme.soft) {
    Box(Modifier.clip(RoundedCornerShape(6.dp)).background(fill).padding(horizontal = 6.dp, vertical = 2.dp)) {
        Label(text, size = 10.sp, color = color, weight = FontWeight.Bold)
    }
}

@Composable
fun Logo(url: String?, size: Dp, fallback: String = "") {
    Box(Modifier.size(size).clip(CircleShape).background(Theme.raised), contentAlignment = Alignment.Center) {
        if (url != null) {
            SmallLogo(url, size, Modifier.size(size * 0.8f))
        } else if (fallback.isNotEmpty()) {
            Label(fallback.take(3), size = (size.value / 3).sp, color = Theme.soft, weight = FontWeight.Bold)
        }
    }
}

/** Live leader green, trailing red; final winner gold, loser grey; tied stays white; not started is grey. */
fun scoreColor(game: Game, side: Team): Color {
    val other = if (side == game.away) game.home else game.away
    val mine = side.score.toDoubleOrNull() ?: return Theme.text
    val theirs = other.score.toDoubleOrNull() ?: return Theme.text
    return when (game.state) {
        GameState.UPCOMING -> Theme.muted
        GameState.LIVE -> if (mine >= theirs) Theme.winning else Theme.losing
        GameState.FINISHED -> if (mine == theirs) Theme.text else if (mine > theirs) Theme.champion else Theme.muted
    }
}

fun Modifier.outline(on: Boolean, color: Color = Theme.accent, shape: Shape = RoundedCornerShape(10.dp)) =
    if (on) this.border(1.5.dp, color, shape) else this

/**
 * Remembers a FocusRequester per item, and which items are on screen right now, so a list can send focus back to
 * the item you came from (the selected sport, the stream you watched) the way the Apple TV app does.
 */
class FocusTargets {
    private val requesters = HashMap<Any, FocusRequester>()
    internal val live = HashSet<Any>()

    fun requester(key: Any): FocusRequester = requesters.getOrPut(key) { FocusRequester() }

    /** The item's requester if it's on screen, otherwise the normal "nearest item" behaviour. */
    operator fun get(key: Any?): FocusRequester =
        if (key != null && key in live) requester(key) else FocusRequester.Default

    fun focus(key: Any?): Boolean {
        if (key == null || key !in live) return false
        return runCatching { requester(key).requestFocus() }.isSuccess
    }
}

/** Tags an item so FocusTargets can find it. */
@Composable
fun Modifier.tracked(targets: FocusTargets, key: Any): Modifier {
    DisposableEffect(targets, key) {
        targets.live.add(key)
        onDispose { targets.live.remove(key) }
    }
    return this.focusRequester(targets.requester(key))
}

/** A group that focus enters at `target()` (moving in from another part of the screen), or never while `blocked`. */
@OptIn(ExperimentalComposeUiApi::class)
fun Modifier.enterAt(blocked: () -> Boolean = { false }, target: () -> FocusRequester): Modifier =
    this.focusProperties { enter = { if (blocked()) FocusRequester.Cancel else target() } }.focusGroup()

@Composable
fun ChannelIcon(url: String?, size: Dp) {
    Box(Modifier.size(size).clip(RoundedCornerShape(6.dp)).background(Theme.raised), contentAlignment = Alignment.Center) {
        if (!url.isNullOrEmpty()) {
            AsyncImage(model = url, contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.size(size * 0.85f))
        } else {
            androidx.tv.material3.Icon(Icons.Filled.Tv, contentDescription = null, tint = Theme.muted, modifier = Modifier.size(size * 0.5f))
        }
    }
}

/** The league's logo from the schedule feed, or its sport's icon. */
@Composable
fun LeagueLogo(model: AppModel, league: League, size: Dp) {
    val url = model.leagueLogos[league.id]
    if (url != null) {
        SmallLogo(url, size, Modifier.size(size))
    } else {
        androidx.tv.material3.Icon(league.sport.icon, contentDescription = null, tint = Theme.accent, modifier = Modifier.size(size * 0.8f))
    }
}

/** "LIVE · Q3 4:12", "STARTS 7:30 PM" or "FINAL", like the Apple TV cards. */
fun cardHeader(game: Game): String = if (game.isChannel) "CHANNEL" else when (game.state) {
    GameState.LIVE -> "LIVE · ${game.statusText}"
    GameState.UPCOMING -> "STARTS ${startText(game)}"
    GameState.FINISHED -> game.statusText.ifEmpty { "Final" }.uppercase()
}

fun startText(game: Game): String {
    val start = game.start ?: return game.statusText
    val today = android.text.format.DateUtils.isToday(start)
    val fmt = if (today) java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT)
              else java.text.SimpleDateFormat("EEE h:mm a", java.util.Locale.getDefault())
    return fmt.format(java.util.Date(start))
}

fun clockTime(ms: Long): String = java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT).format(java.util.Date(ms))

@Composable
fun ProgressLine(fraction: Float, focused: Boolean, width: Dp = 160.dp) {
    Box(Modifier.width(width).height(3.dp).clip(RoundedCornerShape(2.dp)).background(if (focused) Theme.muted else Theme.raised)) {
        Box(Modifier.fillMaxWidth(fraction.coerceIn(0f, 1f)).fillMaxHeight().background(if (focused) Theme.bg else Theme.accent))
    }
}

/** Lite mode (Settings › General), read by every button and card; kept in step with the setting. */
object Perf {
    var lite by androidx.compose.runtime.mutableStateOf(false)
}

/**
 * Moving through a list (sports on Home, the tabs, EPG and game-screen categories) only draws what's beside it once
 * you stop on an item, so passing several doesn't draw a whole page for each one (slow on a Chromecast, Sony or Fire
 * TV). Clicking is instant, and so is moving on (right from a list, down from the tabs): what's waiting is shown
 * first, then the move happens.
 */
class Settle(private val scope: kotlinx.coroutines.CoroutineScope) {
    private var job: kotlinx.coroutines.Job? = null
    private var waiting: (() -> Unit)? = null

    /** Do it once you've stayed on the item for a moment. */
    fun later(action: () -> Unit) {
        job?.cancel()
        waiting = action
        job = scope.launch {
            kotlinx.coroutines.delay(if (Perf.lite) 350L else 250L)
            waiting = null
            action()
        }
    }

    /** Do it straight away (a click), dropping anything waiting. */
    fun now(action: () -> Unit) { cancel(); action() }

    fun cancel() { job?.cancel(); job = null; waiting = null }

    /** Does what's waiting straight away; false when nothing was. */
    fun flush(): Boolean {
        val action = waiting ?: return false
        cancel()
        action()
        return true
    }
}

@Composable
fun rememberSettle(): Settle {
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    return remember { Settle(scope) }
}

/**
 * Pressing [direction] while something is waiting in [settle]: show it first, then move once it's drawn (otherwise
 * focus would land on the old page, which then disappears).
 */
fun Modifier.flushOn(settle: Settle, direction: androidx.compose.ui.focus.FocusDirection): Modifier = composed {
    val focus = androidx.compose.ui.platform.LocalFocusManager.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val key = when (direction) {
        androidx.compose.ui.focus.FocusDirection.Right -> androidx.compose.ui.input.key.Key.DirectionRight
        androidx.compose.ui.focus.FocusDirection.Down -> androidx.compose.ui.input.key.Key.DirectionDown
        androidx.compose.ui.focus.FocusDirection.Left -> androidx.compose.ui.input.key.Key.DirectionLeft
        else -> androidx.compose.ui.input.key.Key.DirectionUp
    }
    onPreviewKeyEvent { e ->
        if (e.type == androidx.compose.ui.input.key.KeyEventType.KeyDown && e.key == key && settle.flush()) {
            scope.launch {
                androidx.compose.runtime.withFrameNanos { }
                androidx.compose.runtime.withFrameNanos { }
                focus.moveFocus(direction)
            }
            true
        } else false
    }
}

/**
 * ESPN's logos are 500-pixel images; a row shows them at about 30. ESPN's image server sends them at the size
 * they're shown (sharp on a 4K TV too), so there's much less to download and shrink on the TV. Other addresses
 * are left as they are.
 */
fun smallLogo(url: String, size: Dp): String {
    val prefix = "https://a.espncdn.com/i/"
    if (!url.startsWith(prefix) || url.contains('?')) return url
    val px = (size.value * 4).toInt().coerceIn(48, 160)
    return "https://a.espncdn.com/combiner/i?img=/i/${url.removePrefix(prefix)}&w=$px&h=$px"
}

/** A logo at the size it's shown; if the small version won't load, the full-size one. */
@Composable
private fun SmallLogo(url: String, size: Dp, modifier: Modifier) {
    var failed by remember(url) { mutableStateOf(false) }
    AsyncImage(model = if (failed) url else smallLogo(url, size), contentDescription = null, contentScale = ContentScale.Fit,
        modifier = modifier, onError = { if (!failed) failed = true })
}
