package ca.sunny9781.courtside

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.foundation.focusable
import androidx.compose.foundation.background
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Icon
import kotlinx.coroutines.delay

/**
 * EPG, like the Apple TV app: categories down the left (grouped), what's on at the top, and the channels with what's
 * on now and next below. Moving onto a category shows its channels; clicking a group opens it (Back goes up a
 * level). Click a channel to play it in the player at the top, click it again for full screen, where up/down flips
 * through the category.
 */
@Composable
fun EpgScreen(model: AppModel) {
    val s = model.settings
    if (model.channels.isEmpty()) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Label(if (model.loading || model.guideLoading) "Refreshing EPG…" else (model.error ?: "No channels yet."), size = 15.sp, color = Theme.muted)
        }
        return
    }
    val cats = remember { FocusTargets() }
    val rows = remember { FocusTargets() }
    var search by remember { mutableStateOf("") }
    // Searched in the background a moment after you stop typing, so the keyboard never stutters.
    var hits by remember { mutableStateOf<List<EpgSearch.Hit>>(emptyList()) }
    var hitsFor by remember { mutableStateOf("") }
    val searching = hitsFor.length >= 2
    LaunchedEffect(search, s.grouped, model.channels, model.guide) {
        val q = search.trim()
        if (q.length < 2) { hits = emptyList(); hitsFor = ""; return@LaunchedEffect }
        delay(300)
        val grouped = s.grouped
        val found = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { EpgSearch.run(q, model, grouped) }
        hits = found
        hitsFor = q
    }
    var flipped by remember(hits) { mutableStateOf(setOf<String>()) }
    var focusedChannel by remember { mutableStateOf<Int?>(null) }
    // The guide's clock: moves the time line (and the guide's start) along every minute.
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) { delay(60_000 - System.currentTimeMillis() % 60_000 + 50); now = System.currentTimeMillis() }
    }
    val start = Guide.windowStart(now)
    // Left on the categories (the screen's left edge) goes to Home; not while typing in Filter.
    var filterFocused by remember { mutableStateOf(false) }
    var lastRow by remember { mutableStateOf<String?>(null) }
    var pathMoves by remember { mutableIntStateOf(0) }

    val tree = model.categoryTree
    val openNodes = remember(tree, model.guidePath) {
        val out = mutableListOf<CategoryGrouping.Node>()
        var level = tree
        for (id in model.guidePath) {
            val node = level.firstOrNull { it.id == id } ?: break
            out.add(node)
            level = node.children
        }
        out
    }
    val level = openNodes.lastOrNull()?.children ?: tree
    val entries = remember(tree, model.categories, s.grouped) {
        if (!s.grouped) model.categories.sortedWith { a, b -> NaturalOrder.compare(a.name, b.name) }.map { Entry(it.id, it.name, listOf(it)) }
        else {
            fun leaves(nodes: List<CategoryGrouping.Node>): List<Entry> =
                nodes.flatMap { if (it.isGroup) leaves(it.children) else listOf(Entry(it.id, it.name, it.categories)) }
            leaves(tree)
        }
    }
    val favChannels = model.favoriteChannelIds
    val favNodes = remember(tree, model.categories, s.favoriteCategories) { model.favoriteCategoryNodes() }
    val favEntries = favNodes.map { Entry(if (it.isGroup) "g:${it.id}" else it.id, it.name, it.categories) }
    val selected: Entry? = run {
        val id = s.guideCategory
        if (id == FAVORITES && favChannels.isNotEmpty()) return@run Entry(FAVORITES, "Favourites", emptyList())
        if (id.startsWith("g:")) CategoryGrouping.find(id.drop(2), tree)?.let { return@run Entry(id, it.name, it.categories) }
        entries.firstOrNull { it.id == id } ?: entries.firstOrNull()
    }
    val channels = remember(selected?.id, model.channelsByCategory, s.favoriteChannels) {
        if (selected?.id == FAVORITES) model.favoriteChannelList()
        else model.favoritesFirst((selected?.categories ?: emptyList()).flatMap { model.channelsByCategory[it.id] ?: emptyList() }.distinctBy { it.id })
    }
    // Hold the select button on a category or channel: add it to favourites, or take it off.
    var prompt by remember { mutableStateOf<HoldPrompt?>(null) }
    fun holdCategory(id: String, name: String) {
        val key = id.removePrefix("g:")
        val fav = model.isFavoriteCategory(key)
        prompt = HoldPrompt(name, listOf(
            HoldOption(if (fav) "Remove from Favourites" else "Add to Favourites",
                if (fav) Icons.Filled.HeartBroken else Icons.Filled.Favorite) { model.toggleFavoriteCategory(key) },
            HoldOption("Hide", Icons.Filled.VisibilityOff) {
                if (fav) model.toggleFavoriteCategory(key)
                model.setCategoryHidden(key, true)
                model.notice = "$name is hidden. Settings › Hidden brings it back."
            }))
    }
    fun holdChannel(ch: Channel) {
        val fav = model.isFavoriteChannel(ch.id)
        prompt = HoldPrompt(ch.name, listOf(
            HoldOption(if (fav) "Remove from Favourites" else "Add to Favourites",
                if (fav) Icons.Filled.HeartBroken else Icons.Filled.Favorite) { model.toggleFavoriteChannel(ch.id) },
            HoldOption("Hide", Icons.Filled.VisibilityOff) {
                if (fav) model.toggleFavoriteChannel(ch.id)
                model.setChannelHidden(ch.id, true)
                model.notice = "${ch.name} is hidden. Settings › Hidden brings it back."
            }))
    }
    fun key(n: CategoryGrouping.Node) = if (n.isGroup) "g:${n.id}" else n.id
    // Coming in from the tabs or the channels: the selected category if it's showing, otherwise the first row.
    val categoryTarget: String? = when {
        model.guidePath.isEmpty() && selected != null && (selected.id == FAVORITES || favEntries.any { it.id == selected.id }) -> selected.id
        !s.grouped -> selected?.id
        selected != null && level.any { key(it) == selected.id } -> selected.id
        else -> level.firstOrNull()?.let { key(it) }
    }
    // Opening or leaving a group swaps the rows, and the focused one disappears: Android would then hand focus to the
    // first thing on screen (the EPG time at the top) for a moment. An invisible spot in the category column holds it
    // instead until the new rows are there.
    val holder = remember { androidx.compose.ui.focus.FocusRequester() }
    val holding = remember { BooleanArray(1) }
    var focusAfterMove by remember { mutableStateOf<String?>(null) }
    // Moving through the categories shows a category's channels once you stop on it, so passing several doesn't
    // draw (and save) each one. Clicking, or pressing right into the channels, is instant.
    val settle = rememberSettle()
    fun pick(id: String) {
        if (s.guideCategory != id) settle.later { s.guideCategory = id } else settle.cancel()
    }
    fun go(path: List<String>, then: String? = null) {
        settle.cancel()
        holding[0] = true
        runCatching { holder.requestFocus() }
        focusAfterMove = then
        model.guidePath = path
        pathMoves++
    }
    fun up() {
        // Back out of a group lands on that group.
        val left = model.guidePath.lastOrNull()
        go(model.guidePath.dropLast(1), left?.let { "cat:g:$it" })
    }

    LaunchedEffect(pathMoves) {
        if (pathMoves == 0) return@LaunchedEffect
        // Wait (briefly) for the new rows to be on screen, then focus the right one.
        for (i in 0 until 30) {
            delay(20)
            val wanted = focusAfterMove?.takeIf { it in cats.live } ?: "cat:${level.firstOrNull()?.let { key(it) }}"
            if (cats.focus(wanted)) break
        }
        holding[0] = false
    }
    BackHandler(enabled = model.guidePath.isNotEmpty() && model.nowPlaying == null) { up() }

    // Back from full screen: focus goes back to the channel you were watching (the one you flipped to, if it's in
    // this list, otherwise the one you opened). For a moment after, anything that brings focus back onto this page
    // (Android does when the full-screen player goes away) lands there too, not on the category.
    fun returnRow(): String? {
        val id = model.lastPlayedChannelId
        return listOf("c:$id").firstOrNull { it in rows.live }
            ?: rows.live.firstOrNull { it is String && it.startsWith("h:") && it.endsWith(":$id") } as String?
            ?: lastRow?.takeIf { it in rows.live }
    }
    var backAt by remember { mutableLongStateOf(0L) }
    var wasFull by remember { mutableStateOf(model.nowPlaying != null) }
    LaunchedEffect(model.nowPlaying != null) {
        val full = model.nowPlaying != null
        if (wasFull && !full && model.fullScreenFrom == "epg") backAt = System.currentTimeMillis()
        wasFull = full
    }
    fun justBack() = System.currentTimeMillis() - backAt < 1500 && returnRow() != null
    AfterFullScreen(model, "epg") { rows.focus(returnRow()) }

    val playing = model.pinned?.channel
    fun click(ch: Channel, lineup: List<Channel>) {
        if (ch.id == playing?.id) model.play(ch, null, lineup, from = "epg") else model.pin(ch, null, lineup)
    }

    Row(Modifier.fillMaxSize().padding(horizontal = Theme.margin)
        .enterAt { if (justBack()) rows[returnRow()] else cats["cat:$categoryTarget"] },
        horizontalArrangement = Arrangement.spacedBy(18.dp)) {
        Box(Modifier.width(CATEGORY_WIDTH).fillMaxHeight()) {
        // Holds focus while the rows change (see go()); it can't be reached with the remote.
        Box(Modifier.size(1.dp).focusRequester(holder).focusProperties { canFocus = holding[0] }
            .focusable())
        LazyColumn(Modifier.width(CATEGORY_WIDTH).fillMaxHeight().padding(bottom = topInset(model)).focusRequester(model.leftPanel)
            .onEdgeKey(android.view.KeyEvent.KEYCODE_DPAD_LEFT, enabled = { !filterFocused }) { model.tab = Tab.HOME }
            .flushOn(settle, androidx.compose.ui.focus.FocusDirection.Right).enterAt { if (justBack()) rows[returnRow()] else cats["cat:$categoryTarget"] },
            verticalArrangement = Arrangement.spacedBy(3.dp), contentPadding = PaddingValues(vertical = 8.dp)) {
            // One search for categories and channels; results show on the right.
            // Enter (or Search) on the keyboard closes it and goes to the first result.
            item(key = "filter") {
                Box(Modifier.onFocusChanged { filterFocused = it.hasFocus }) {
                    Field("Filter", search, { search = it }, width = CATEGORY_WIDTH) {
                        hits.firstOrNull()?.let { h -> h.channels.firstOrNull()?.let { rows.focus("h:${h.id}:${it.id}") } }
                    }
                }
            }
            item(key = "group") {
                CategoryRow(cats, "cat:toggle", Icons.Filled.Layers, "Auto-Group", if (s.grouped) "On" else "Off", false) {
                    s.grouped = !s.grouped
                    model.guidePath = emptyList()
                }
            }
            // Favourites first: your favourite channels, then favourite categories and groups, then a line.
            if (model.guidePath.isEmpty()) {
                if (favChannels.isNotEmpty()) item(key = "fav") {
                    CategoryRow(cats, "cat:$FAVORITES", Icons.Filled.Favorite, "Favourites", "${model.favoriteChannelList().size}",
                        selected?.id == FAVORITES, onFocus = { pick(FAVORITES) }) {
                        settle.now { s.guideCategory = FAVORITES }
                    }
                }
                items(favEntries, key = { "fav:${it.id}" }) { e ->
                    CategoryRow(cats, "cat:${e.id}", null, e.name, "${count(model, e.categories)}", selected?.id == e.id,
                        favorite = true, onLongClick = { holdCategory(e.id, e.name) },
                        onFocus = { pick(e.id) }) { settle.now { s.guideCategory = e.id } }
                }
                if (favChannels.isNotEmpty() || favEntries.isNotEmpty()) item(key = "favline") {
                    Box(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 5.dp).height(1.dp)
                        .background(Theme.raised))
                }
            }
            if (s.grouped) {
                if (openNodes.isNotEmpty()) item(key = "up") {
                    CategoryRow(cats, "cat:up", Icons.Filled.ChevronLeft, openNodes.joinToString(" › ") { it.name }, null, false, bold = true) {
                        up()
                    }
                }
                // At the top, favourites are already listed above; inside a group they come first.
                val shown = if (model.guidePath.isEmpty()) level.filter { !model.isFavoriteCategory(it.id) }
                    else level.filter { model.isFavoriteCategory(it.id) } + level.filter { !model.isFavoriteCategory(it.id) }
                items(shown, key = { key(it) }) { node ->
                    val k = key(node)
                    val fav = model.isFavoriteCategory(node.id)
                    if (node.isGroup) {
                        CategoryRow(cats, "cat:$k", Icons.Filled.Folder, node.name, "${node.categories.size}", selected?.id == k,
                            trailing = Icons.Filled.ChevronRight, favorite = fav, onLongClick = { holdCategory(k, node.name) },
                            onFocus = { pick(k) }) {
                            go(model.guidePath + node.id)
                        }
                    } else {
                        CategoryRow(cats, "cat:$k", null, node.name, "${count(model, node.categories)}", selected?.id == k,
                            favorite = fav, onLongClick = { holdCategory(k, node.name) },
                            onFocus = { pick(k) }) { settle.now { s.guideCategory = k } }
                    }
                }
            } else {
                items(entries.filter { !model.isFavoriteCategory(it.id) }, key = { it.id }) { e ->
                    CategoryRow(cats, "cat:${e.id}", null, e.name, "${count(model, e.categories)}", selected?.id == e.id,
                        onLongClick = { holdCategory(e.id, e.name) },
                        onFocus = { pick(e.id) }) { settle.now { s.guideCategory = e.id } }
                }
            }
        }
        }

        // The schedule runs to the bottom of the screen, under the now-playing bar beside the player.
        Column(Modifier.weight(1f).fillMaxHeight()) { BehindPlayerBar(model) {
            LazyColumn(Modifier.fillMaxSize().enterAt { rows[lastRow] }, verticalArrangement = Arrangement.spacedBy(3.dp),
                contentPadding = PaddingValues(top = 6.dp, bottom = 6.dp + barInset(model))) {
                item(key = "header") {
                    GuideHeader(if (searching) "Results for “$hitsFor”" else (selected?.name ?: ""), start, now)
                }
                if (searching) {
                    if (hits.isEmpty()) item(key = "none") {
                        Label("Nothing matches \"$hitsFor\".", size = 14.sp, color = Theme.muted, modifier = Modifier.padding(10.dp))
                    }
                    for (hit in hits) {
                        val open = hit.startsOpen(hits.size) != (hit.id in flipped)
                        item(key = "hit:${hit.id}") {
                            HitHeader(hit, open) { flipped = if (hit.id in flipped) flipped - hit.id else flipped + hit.id }
                        }
                        if (open) items(hit.channels, key = { "h:${hit.id}:${it.id}" }, contentType = { "channel" }) { ch ->
                            val k = "h:${hit.id}:${ch.id}"
                            GuideRow(model, ch, ch.id == playing?.id, start, now, Modifier.tracked(rows, k), onLongClick = { holdChannel(ch) },
                                onFocus = { focusedChannel = ch.id; lastRow = k }) { click(ch, hit.channels) }
                        }
                    }
                } else {
                    items(channels, key = { "c:${it.id}" }, contentType = { "channel" }) { ch ->
                        val k = "c:${ch.id}"
                        GuideRow(model, ch, ch.id == playing?.id, start, now, Modifier.tracked(rows, k), onLongClick = { holdChannel(ch) },
                            onFocus = { focusedChannel = ch.id; lastRow = k }) { click(ch, channels) }
                    }
                }
            }
        } }
    }
    prompt?.let { p -> HoldMenu(p) { prompt = null } }
}

private const val FAVORITES = "fav"

/** One choice in the menu that holding the select button on a row opens. */
internal class HoldOption(val label: String, val icon: androidx.compose.ui.graphics.vector.ImageVector, val action: () -> Unit)

/** What holding the select button on a row asks about: its name and the choices. */
internal class HoldPrompt(val name: String, val options: List<HoldOption>)

/** The menu for the row you held the select button on (Add to Favourites, Hide…), then Cancel. */
@Composable
internal fun HoldMenu(p: HoldPrompt, dismiss: () -> Unit) {
    val first = remember { androidx.compose.ui.focus.FocusRequester() }
    // The menu opens while the select button is still held: letting go of it mustn't pick the first choice. Clicks
    // count only after that release (or after a moment, in case the release came before the menu opened).
    var armed by remember { mutableStateOf(false) }
    var lastHeld by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (!armed) { delay(200); if (System.currentTimeMillis() - lastHeld > 800) armed = true }
    }
    androidx.compose.ui.window.Dialog(onDismissRequest = dismiss) {
        Column(Modifier.onPreviewKeyEvent { e ->
            val k = e.nativeKeyEvent
            val select = k.keyCode == android.view.KeyEvent.KEYCODE_DPAD_CENTER || k.keyCode == android.view.KeyEvent.KEYCODE_ENTER ||
                k.keyCode == android.view.KeyEvent.KEYCODE_NUMPAD_ENTER || k.keyCode == android.view.KeyEvent.KEYCODE_BUTTON_A
            if (armed || !select) false
            else {
                lastHeld = System.currentTimeMillis()
                if (k.action == android.view.KeyEvent.ACTION_UP) armed = true
                true
            }
        }.width(320.dp).background(Theme.card, androidx.compose.foundation.shape.RoundedCornerShape(14.dp)).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Label(p.name, size = 15.sp, weight = FontWeight.Bold, maxLines = 2)
            p.options.forEachIndexed { i, option ->
                TvButton(onClick = { option.action(); dismiss() }, focusedScale = 1f,
                    modifier = Modifier.fillMaxWidth().then(if (i == 0) Modifier.focusRequester(first) else Modifier)) { focused ->
                    val color = if (focused) Theme.bg else Theme.text
                    Row(Modifier.padding(horizontal = 10.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(option.icon, null, tint = if (focused) Theme.bg else Theme.accent, modifier = Modifier.size(15.dp))
                        Label(option.label, size = 14.sp, weight = FontWeight.SemiBold, color = color)
                    }
                }
            }
            TvButton(onClick = dismiss, focusedScale = 1f, modifier = Modifier.fillMaxWidth()) { focused ->
                Label("Cancel", size = 14.sp, color = if (focused) Theme.bg else Theme.soft,
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp))
            }
        }
    }
    LaunchedEffect(Unit) { delay(50); runCatching { first.requestFocus() } }
}

private data class Entry(val id: String, val name: String, val categories: List<ChannelCategory>)


/** A name column wide enough for the longest channel name on one line (within reason), the same for every row. */
internal fun nameWidthFor(channels: List<Channel>): androidx.compose.ui.unit.Dp =
    CHANNEL_WIDTH
/** The category column: narrow, so the names sit close to their counts. */
private val CATEGORY_WIDTH = Theme.playerWidth
private val NEXT_WIDTH = 210.dp
/** The same column widths on every screen: channel (with its logo), what's on now, what's next. */
internal val CHANNEL_WIDTH = 210.dp
private val NOW_WIDTH = 290.dp
private val COLUMN_GAP = 12.dp

private fun count(model: AppModel, cats: List<ChannelCategory>) = cats.sumOf { model.channelsByCategory[it.id]?.size ?: 0 }

@Composable
internal fun CategoryRow(
    targets: FocusTargets, key: String, icon: androidx.compose.ui.graphics.vector.ImageVector?, name: String, value: String?,
    selected: Boolean, bold: Boolean = false, trailing: androidx.compose.ui.graphics.vector.ImageVector? = null,
    favorite: Boolean = false, onLongClick: (() -> Unit)? = null,
    onFocus: (() -> Unit)? = null, onClick: () -> Unit
) {
    TvButton(onClick = onClick, selected = selected, onFocus = onFocus, onLongClick = onLongClick,
        modifier = Modifier.fillMaxWidth().tracked(targets, key)) { focused ->
        val color = if (focused) Theme.bg else Theme.text
        Row(Modifier.padding(horizontal = 10.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (icon != null) Icon(icon, null, tint = color.copy(alpha = 0.75f), modifier = Modifier.size(14.dp))
            Label(name, size = 14.sp, weight = if (bold) FontWeight.Bold else FontWeight.SemiBold, color = color, modifier = Modifier.weight(1f))
            if (favorite) Icon(Icons.Filled.Favorite, null, tint = if (focused) Theme.bg else Theme.accent, modifier = Modifier.size(12.dp))
            if (value != null) Label(value, size = 11.sp, color = color.copy(alpha = 0.6f))
            if (trailing != null) Icon(trailing, null, tint = color.copy(alpha = 0.6f), modifier = Modifier.size(13.dp))
        }
    }
}

/** A channel: logo and name, what's on now (with progress), and what's next. */
@Composable
internal fun ChannelRow(model: AppModel, channel: Channel, playing: Boolean, modifier: Modifier, badge: String? = null,
                        nameWidth: androidx.compose.ui.unit.Dp? = null, showNext: Boolean = true,
                        onLongClick: (() -> Unit)? = null, onFocus: () -> Unit, onClick: () -> Unit) {
    val nowNext = model.nowNext(channel)
    val now = nowNext.now
    val next = nowNext.next
    TvButton(onClick = onClick, onFocus = onFocus, focusedScale = 1.02f, onLongClick = onLongClick,
        modifier = modifier.fillMaxWidth()) { focused ->
        val color = if (focused) Theme.bg else Theme.text
        Row(Modifier.padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            // Fixed columns on every screen (channel, now, next): one line each; on the row you're on, text that
            // doesn't fit scrolls inside its column.
            Row(Modifier.width(CHANNEL_WIDTH), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ChannelIcon(channel.icon, 24.dp)
                Label(channel.name, size = 12.sp, weight = FontWeight.SemiBold, color = if (playing && !focused) Theme.accent else color,
                    scroll = focused, modifier = Modifier.weight(1f, fill = false))
                if (playing) Icon(Icons.Filled.GraphicEq, null, tint = if (focused) Theme.bg else Theme.accent, modifier = Modifier.size(11.dp))
                if (model.isFavoriteChannel(channel.id))
                    Icon(Icons.Filled.Favorite, null, tint = if (focused) Theme.bg else Theme.accent, modifier = Modifier.size(10.dp))
            }
            Column(Modifier.width(NOW_WIDTH).padding(start = COLUMN_GAP, end = COLUMN_GAP), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Label(now?.title ?: "–", size = 12.sp, color = color, scroll = focused)
                if (now != null) {
                    val total = (now.end - now.start).toFloat()
                    ProgressLine(if (total > 0) (System.currentTimeMillis() - now.start) / total else 0f, focused)
                }
            }
            // The game screen shows the stream's tags where the EPG shows what's next.
            if (showNext) Label(next?.let { "${clockTime(it.start)}  ${it.title}" } ?: "", size = 11.sp,
                color = color.copy(alpha = 0.65f), scroll = focused, modifier = Modifier.width(NEXT_WIDTH).padding(end = COLUMN_GAP))
            // What it really played at, once it has (resolution, frame rate, sound), on the EPG and the game screen.
            val quality = badge?.takeIf { it.isNotEmpty() } ?: model.measuredQuality[channel.id]
            val fps = model.measuredFrameRate[channel.id]
            val sound = model.measuredAudio[channel.id]
            Row(Modifier.then(if (showNext) Modifier else Modifier.width(NEXT_WIDTH)),
                horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                if (!quality.isNullOrEmpty()) Badge(quality, fill = if (quality == "4K") Theme.accent else Theme.raised,
                    color = if (quality == "4K") Theme.onAccent else Theme.soft)
                if (fps != null && fps > 0) Badge(Playback.fpsLabel(fps), fill = Theme.raised, color = Theme.soft)
                if (!sound.isNullOrEmpty()) Badge(sound, fill = Theme.raised, color = Theme.soft)
            }
        }
    }
}

@Composable
private fun HitHeader(hit: EpgSearch.Hit, open: Boolean, onClick: () -> Unit) {
    TvButton(onClick = onClick, modifier = Modifier.fillMaxWidth()) { focused ->
        val color = if (focused) Theme.bg else Theme.text
        Row(Modifier.padding(horizontal = 10.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(if (open) Icons.Filled.ExpandMore else Icons.Filled.ChevronRight, null, tint = color, modifier = Modifier.size(15.dp))
            Column(Modifier.weight(1f)) {
                Label(hit.category.name, size = 13.sp, weight = FontWeight.Bold, color = color)
                if (hit.path.isNotEmpty()) Label(hit.path, size = 10.sp, color = color.copy(alpha = 0.6f))
            }
            Label("${hit.channels.size}", size = 11.sp, color = color.copy(alpha = 0.6f))
        }
    }
}

// MARK: Timeline guide (like the Apple TV app since 1.81)

/**
 * The EPG's timeline: a channel column, then two and a half hours of programmes laid out by time, coloured by sport
 * (or the channel's own colour), with a line at the current time and what's already been on a shade darker.
 */
internal object Guide {
    const val SPAN = 150 * 60_000L
    val channelWidth = 110.dp
    val rowHeight = 46.dp

    /** The guide starts at the last half hour, so up to 30 minutes of what's on is behind the line. */
    fun windowStart(now: Long): Long = now - now % (30 * 60_000L)

    fun fill(sport: Sport): androidx.compose.ui.graphics.Color = androidx.compose.ui.graphics.Color(when (sport) {
        Sport.BASKETBALL -> 0xFF8A4214; Sport.HOCKEY -> 0xFF22508F; Sport.FOOTBALL -> 0xFF267040
        Sport.SOCCER -> 0xFF177375; Sport.MOTORSPORT -> 0xFF8A2532; Sport.CRICKET -> 0xFF75600F
        Sport.BASEBALL -> 0xFF76305A; Sport.FIGHTING -> 0xFF6A4A2E; Sport.TENNIS -> 0xFF557018
        Sport.GOLF -> 0xFF3A6430; Sport.RUGBY -> 0xFF52408A; Sport.AUSSIE_RULES -> 0xFF7A5016
        Sport.LACROSSE -> 0xFF2E5F7A; Sport.PICKLEBALL -> 0xFF687A16
    })

    /** Channels whose sport can't be told still get a colour of their own (the same one every time), like UHF. */
    private val channelFills = longArrayOf(0xFF5B3A8C, 0xFF2C5D8A, 0xFF7A3B5E, 0xFF2F6F6A, 0xFF6E5320, 0xFF3E5C2E, 0xFF803A2A, 0xFF46508A)

    fun fill(title: String, channel: Channel, games: List<Game>): androidx.compose.ui.graphics.Color {
        sport(title, channel, games)?.let { return fill(it) }
        var h = 5381L
        for (b in channel.name.toByteArray()) h = (h * 33 + (b.toLong() and 0xFF)) and 0xFFFFFFFFL
        return androidx.compose.ui.graphics.Color(channelFills[(h % channelFills.size).toInt()])
    }

    private val words: List<Pair<Sport, List<String>>> = listOf(
        Sport.BASKETBALL to listOf("nba", "wnba", "basketball", "ncaab", "euroleague", "march madness"),
        Sport.HOCKEY to listOf("nhl", "hockey", "hockey night", "ahl", "ohl", "whl", "khl", "stanley cup"),
        Sport.FOOTBALL to listOf("nfl", "cfl", "ncaaf", "college football", "super bowl", "redzone", "red zone", "grey cup"),
        Sport.BASEBALL to listOf("mlb", "baseball", "world series"),
        Sport.SOCCER to listOf("soccer", "epl", "premier league", "champions league", "europa league", "conference league", "la liga",
            "laliga", "serie a", "bundesliga", "ligue 1", "mls", "uefa", "fifa", "fa cup", "world cup", "eredivisie"),
        Sport.FIGHTING to listOf("ufc", "boxing", "mma", "wwe", "aew", "pfl", "fight night"),
        Sport.TENNIS to listOf("tennis", "atp", "wta", "wimbledon"),
        Sport.MOTORSPORT to listOf("f1", "formula 1", "formula one", "nascar", "indycar", "motogp", "grand prix", "motorsport"),
        Sport.GOLF to listOf("golf", "pga", "lpga"),
        Sport.RUGBY to listOf("rugby", "six nations", "urc"),
        Sport.AUSSIE_RULES to listOf("afl"),
        Sport.LACROSSE to listOf("lacrosse", "nll", "pll"),
        Sport.CRICKET to listOf("cricket", "ipl", "bbl", "t20", "odi", "test match", "psl"),
        Sport.PICKLEBALL to listOf("pickleball", "ppa"),
    )
    private val cache = HashMap<String, Sport?>()
    private val teamCache = HashMap<String, Sport?>()
    private var teams: Map<String, Sport> = emptyMap()
    private var teamsFrom: List<Game>? = null

    /** Lower case, letters and digits only, single spaces, a space at each end (so whole words match). */
    private fun normalized(text: String): String =
        " " + text.lowercase().map { if (it.isLetterOrDigit()) it else ' ' }.joinToString("").split(' ').filter { it.isNotEmpty() }.joinToString(" ") + " "

    private fun guess(text: String): Sport? {
        if (cache.containsKey(text)) return cache[text]
        val clean = normalized(text)
        val found = words.firstOrNull { (_, list) -> list.any { clean.contains(" $it ") } }?.first
        if (cache.size > 4000) cache.clear()
        cache[text] = found
        return found
    }

    /** Team names from today's scoreboard ("raptors", "toronto raptors"); a nickname two sports share is left out. */
    private fun team(title: String, games: List<Game>): Sport? {
        if (teamsFrom !== games) {
            val map = HashMap<String, Sport>()
            val clash = HashSet<String>()
            for (g in games) {
                if (g.league.isEvent) continue
                for (t in listOf(g.away, g.home)) for (n in listOf(t.name, t.nickname, t.shortName)) {
                    val key = normalized(n).trim()
                    if (key.length < 4) continue
                    val had = map[key]
                    if (had != null && had != g.league.sport) clash.add(key)
                    map[key] = g.league.sport
                }
            }
            clash.forEach { map.remove(it) }
            teams = map
            teamsFrom = games
            teamCache.clear()
        }
        if (teamCache.containsKey(title)) return teamCache[title]
        val clean = normalized(title)
        val found = teams.entries.firstOrNull { clean.contains(" ${it.key} ") }?.value
        if (teamCache.size > 4000) teamCache.clear()
        teamCache[title] = found
        return found
    }

    /** From the title, else a team playing today, else the channel's name ("NBA TV"), else its category. */
    fun sport(title: String, channel: Channel, games: List<Game>): Sport? =
        guess(title) ?: team(title, games) ?: guess(channel.name) ?: guess(channel.categoryName)

    fun left(ms: Long): String {
        val m = (ms / 60_000).coerceAtLeast(0)
        return if (m >= 60) "${m / 60}h ${m % 60}m left" else "${m}m left"
    }
}

/** Times along the top of the guide, with the current time in a pill over the line. */
@Composable
private fun GuideHeader(title: String, start: Long, now: Long) {
    Row(Modifier.fillMaxWidth().height(18.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Label(title, size = 10.sp, weight = FontWeight.Bold, color = Theme.muted, modifier = Modifier.width(Guide.channelWidth))
        androidx.compose.foundation.layout.BoxWithConstraints(Modifier.weight(1f).fillMaxHeight()) {
            val perMs = maxWidth.value / Guide.SPAN
            for (i in 0 until 5) {
                Label(clockTime(start + i * 30 * 60_000L), size = 10.sp, color = Theme.muted,
                    modifier = Modifier.offset(x = (i * 30 * 60_000L * perMs).dp))
            }
            Box(Modifier.offset(x = ((now - start) * perMs).dp - 14.dp)
                .background(Theme.accent, androidx.compose.foundation.shape.RoundedCornerShape(8.dp)).padding(horizontal = 5.dp, vertical = 1.dp)) {
                Label(clockTime(now).replace(" AM", "").replace(" PM", "").replace(" am", "").replace(" pm", ""),
                    size = 9.sp, weight = FontWeight.Bold, color = Theme.onAccent)
            }
        }
    }
}

/**
 * One channel in the timeline guide: the channel (logo, name over up to three lines, its tags), then its programmes
 * by time. Every row is the same height; the one you're on turns its channel and what's on now white.
 */
@Composable
internal fun GuideRow(model: AppModel, channel: Channel, playing: Boolean, start: Long, now: Long, modifier: Modifier,
                      onLongClick: (() -> Unit)? = null, onFocus: () -> Unit, onClick: () -> Unit) {
    val end = start + Guide.SPAN
    val programmes = model.guide[channel.epgId].orEmpty().filter { it.end > start && it.start < end }
    val shape = androidx.compose.foundation.shape.RoundedCornerShape(6.dp)
    TvButton(onClick = onClick, onFocus = onFocus, onLongClick = onLongClick, focusedFill = androidx.compose.ui.graphics.Color.Transparent,
        modifier = modifier.fillMaxWidth().height(Guide.rowHeight)) { focused ->
        Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            // The channel.
            val color = if (focused) Theme.bg else if (playing) Theme.accent else Theme.text
            Row(Modifier.width(Guide.channelWidth).fillMaxHeight().background(if (focused) Theme.text else Theme.card, shape)
                .padding(horizontal = 5.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                if (!Perf.lite) ChannelIcon(channel.icon, 20.dp)
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        Label(channel.name, size = 10.sp, weight = FontWeight.SemiBold, color = color, maxLines = 3,
                            modifier = Modifier.weight(1f, fill = false))
                        if (playing) Icon(Icons.Filled.GraphicEq, null, tint = if (focused) Theme.bg else Theme.accent, modifier = Modifier.size(9.dp))
                        if (model.isFavoriteChannel(channel.id))
                            Icon(Icons.Filled.Favorite, null, tint = if (focused) Theme.bg else Theme.accent, modifier = Modifier.size(8.dp))
                    }
                    // Always shown, so nothing moves as you go up and down.
                    val quality = model.measuredQuality[channel.id]
                    val fps = model.measuredFrameRate[channel.id]
                    val sound = model.measuredAudio[channel.id]
                    if (!quality.isNullOrEmpty() || (fps != null && fps > 0) || !sound.isNullOrEmpty())
                        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                            if (!quality.isNullOrEmpty()) Badge(quality, fill = if (quality == "4K") Theme.accent else Theme.raised,
                                color = if (quality == "4K") Theme.onAccent else Theme.soft)
                            if (fps != null && fps > 0) Badge(Playback.fpsLabel(fps), fill = Theme.raised, color = Theme.soft)
                            if (!sound.isNullOrEmpty()) Badge(sound, fill = Theme.raised, color = Theme.soft)
                        }
                }
            }
            // The programmes, by time.
            androidx.compose.foundation.layout.BoxWithConstraints(Modifier.weight(1f).fillMaxHeight()) {
                val perMs = maxWidth.value / Guide.SPAN
                if (programmes.isEmpty()) {
                    Box(Modifier.fillMaxSize().background(Theme.card, shape).padding(horizontal = 8.dp), contentAlignment = Alignment.CenterStart) {
                        Label("No guide information", size = 10.sp, color = Theme.muted)
                    }
                }
                for (p in programmes) {
                    val s = maxOf(p.start, start)
                    val e = minOf(p.end, end)
                    val width = ((e - s) * perMs - 2f).coerceAtLeast(0f)
                    val isNow = p.start <= now && p.end > now
                    val lit = focused && isNow
                    val elapsed = ((now - s) * perMs).coerceIn(0f, width)
                    val sub = if (lit) androidx.compose.ui.graphics.Color(0xFF4A4F5C) else androidx.compose.ui.graphics.Color.White.copy(alpha = 0.78f)
                    Box(Modifier.offset(x = ((s - start) * perMs).dp).width(width.dp).fillMaxHeight().clip(shape)
                        .background(if (lit) Theme.text else Guide.fill(p.title, channel, model.games))
                        .then(if (lit) Modifier.outline(true, Theme.accent, shape) else Modifier)) {
                        // What's already been on is a shade darker.
                        Box(Modifier.width(elapsed.dp).fillMaxHeight()
                            .background(androidx.compose.ui.graphics.Color.Black.copy(alpha = if (lit) 0.07f else 0.28f)))
                        Column(Modifier.fillMaxHeight().padding(horizontal = 6.dp), verticalArrangement = Arrangement.Center) {
                            Label(if (lit) "${clockTime(p.start)} – ${clockTime(p.end)}   ${Guide.left(p.end - now)}" else clockTime(p.start),
                                size = 8.sp, color = sub)
                            Label(p.title, size = 10.sp, weight = if (lit) FontWeight.Bold else FontWeight.SemiBold,
                                color = if (lit) Theme.bg else Theme.text, maxLines = 2)
                        }
                    }
                }
                Box(Modifier.offset(x = ((now - start) * perMs).dp - 1.dp).width(2.dp).fillMaxHeight().background(Theme.accent))
            }
        }
    }
}
