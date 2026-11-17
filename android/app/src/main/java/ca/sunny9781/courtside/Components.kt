package ca.sunny9781.courtside

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
    val stripHeight = playerWidth * 9 / 16 + 10.dp
}

/**
 * Anything you can move to with the remote and click: it grows a little and turns white when it has focus,
 * like the Apple TV app. `content` gets whether it's focused, to switch its text to dark.
 */
@Composable
fun TvButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    selected: Boolean = false,
    shape: Shape = RoundedCornerShape(10.dp),
    focusedScale: Float = 1.04f,
    onFocus: (() -> Unit)? = null,
    background: Color = Color.Transparent,
    content: @Composable BoxScope.(focused: Boolean) -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    Box(
        modifier
            .onFocusChanged {
                focused = it.isFocused
                if (it.isFocused) onFocus?.invoke()
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
    align: androidx.compose.ui.text.style.TextAlign? = null
) {
    Text(text, modifier = modifier, color = color, fontSize = size, fontWeight = weight, maxLines = maxLines,
        overflow = TextOverflow.Ellipsis, textAlign = align)
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
            AsyncImage(model = url, contentDescription = null, contentScale = ContentScale.Fit,
                modifier = Modifier.size(size * 0.8f))
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
        AsyncImage(model = url, contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.size(size))
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
