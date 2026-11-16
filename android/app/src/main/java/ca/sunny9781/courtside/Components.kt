package ca.sunny9781.courtside

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
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
            .scale(if (focused) focusedScale else 1f)
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
    modifier: Modifier = Modifier
) {
    Text(text, modifier = modifier, color = color, fontSize = size, fontWeight = weight, maxLines = maxLines,
        overflow = TextOverflow.Ellipsis)
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
