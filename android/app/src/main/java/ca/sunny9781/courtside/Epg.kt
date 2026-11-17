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
import androidx.compose.ui.focus.focusRequester
import androidx.compose.foundation.background
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
            Label(if (model.loading) "Downloading channels…" else (model.error ?: "No channels yet."), size = 15.sp, color = Theme.muted)
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
    fun go(path: List<String>) { model.guidePath = path; pathMoves++ }

    LaunchedEffect(pathMoves) {
        if (pathMoves == 0) return@LaunchedEffect
        delay(60)
        cats.focus("cat:${level.firstOrNull()?.let { key(it) }}")
    }
    BackHandler(enabled = model.guidePath.isNotEmpty() && model.nowPlaying == null) { go(model.guidePath.dropLast(1)) }
    // Back from full screen: focus goes back to the channel you were watching.
    AfterFullScreen(model, "epg") { if (!rows.focus(lastRow)) rows.focus("c:${model.lastPlayedChannelId}") }

    val playing = model.pinned?.channel
    fun click(ch: Channel, lineup: List<Channel>) {
        if (ch.id == playing?.id) model.play(ch, null, lineup, from = "epg") else model.pin(ch, null, lineup)
    }

    Row(Modifier.fillMaxSize().padding(horizontal = Theme.margin).enterAt { cats["cat:$categoryTarget"] },
        horizontalArrangement = Arrangement.spacedBy(18.dp)) {
        LazyColumn(Modifier.width(CATEGORY_WIDTH).fillMaxHeight().padding(bottom = topInset(model)).focusRequester(model.leftPanel)
            .enterAt { cats["cat:$categoryTarget"] },
            verticalArrangement = Arrangement.spacedBy(3.dp), contentPadding = PaddingValues(vertical = 8.dp)) {
            // One search for categories and channels; results show on the right.
            // Enter (or Search) on the keyboard closes it and goes to the first result.
            item(key = "filter") {
                Field("Filter", search, { search = it }, width = CATEGORY_WIDTH) {
                    hits.firstOrNull()?.let { h -> h.channels.firstOrNull()?.let { rows.focus("h:${h.id}:${it.id}") } }
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
                        selected?.id == FAVORITES, onFocus = { if (s.guideCategory != FAVORITES) s.guideCategory = FAVORITES }) {
                        s.guideCategory = FAVORITES
                    }
                }
                items(favEntries, key = { "fav:${it.id}" }) { e ->
                    CategoryRow(cats, "cat:${e.id}", null, e.name, "${count(model, e.categories)}", selected?.id == e.id,
                        favorite = true, onLongClick = { holdCategory(e.id, e.name) },
                        onFocus = { if (s.guideCategory != e.id) s.guideCategory = e.id }) { s.guideCategory = e.id }
                }
                if (favChannels.isNotEmpty() || favEntries.isNotEmpty()) item(key = "favline") {
                    Box(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 5.dp).height(1.dp)
                        .background(Theme.raised))
                }
            }
            if (s.grouped) {
                if (openNodes.isNotEmpty()) item(key = "up") {
                    CategoryRow(cats, "cat:up", Icons.Filled.ChevronLeft, openNodes.joinToString(" › ") { it.name }, null, false, bold = true) {
                        go(model.guidePath.dropLast(1))
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
                            onFocus = { if (s.guideCategory != k) s.guideCategory = k }) {
                            go(model.guidePath + node.id)
                        }
                    } else {
                        CategoryRow(cats, "cat:$k", null, node.name, "${count(model, node.categories)}", selected?.id == k,
                            favorite = fav, onLongClick = { holdCategory(k, node.name) },
                            onFocus = { if (s.guideCategory != k) s.guideCategory = k }) { s.guideCategory = k }
                    }
                }
            } else {
                items(entries.filter { !model.isFavoriteCategory(it.id) }, key = { it.id }) { e ->
                    CategoryRow(cats, "cat:${e.id}", null, e.name, "${count(model, e.categories)}", selected?.id == e.id,
                        onLongClick = { holdCategory(e.id, e.name) },
                        onFocus = { if (s.guideCategory != e.id) s.guideCategory = e.id }) { s.guideCategory = e.id }
                }
            }
        }


        val nameWidth = nameWidthFor(if (searching) hits.flatMap { it.channels } else channels)
        // The schedule runs to the bottom of the screen, under the now-playing bar beside the player.
        Column(Modifier.weight(1f).fillMaxHeight()) { BehindPlayerBar(model) {
            LazyColumn(Modifier.fillMaxSize().enterAt { rows[lastRow] }, verticalArrangement = Arrangement.spacedBy(2.dp),
                contentPadding = PaddingValues(top = 6.dp, bottom = 6.dp + topInset(model))) {
                item(key = "header") {
                    Row(Modifier.padding(horizontal = 10.dp, vertical = 4.dp)) {
                        Label(if (searching) "Results for “$hitsFor”" else (selected?.name ?: ""), size = 10.sp,
                            weight = FontWeight.Bold, color = Theme.muted, modifier = Modifier.width(nameWidth))
                        Label("NOW", size = 10.sp, weight = FontWeight.Bold, color = Theme.muted, modifier = Modifier.weight(1f))
                        Label("NEXT", size = 10.sp, weight = FontWeight.Bold, color = Theme.muted, modifier = Modifier.width(NEXT_WIDTH))
                    }
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
                        if (open) items(hit.channels, key = { "h:${hit.id}:${it.id}" }) { ch ->
                            val k = "h:${hit.id}:${ch.id}"
                            ChannelRow(model, ch, ch.id == playing?.id, Modifier.tracked(rows, k), onLongClick = { holdChannel(ch) },
                                nameWidth = nameWidth, onFocus = { focusedChannel = ch.id; lastRow = k }) { click(ch, hit.channels) }
                        }
                    }
                } else {
                    items(channels, key = { "c:${it.id}" }) { ch ->
                        val k = "c:${ch.id}"
                        ChannelRow(model, ch, ch.id == playing?.id, Modifier.tracked(rows, k), onLongClick = { holdChannel(ch) },
                            nameWidth = nameWidth, onFocus = { focusedChannel = ch.id; lastRow = k }) { click(ch, channels) }
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
    androidx.compose.ui.window.Dialog(onDismissRequest = dismiss) {
        Column(Modifier.width(320.dp).background(Theme.card, androidx.compose.foundation.shape.RoundedCornerShape(14.dp)).padding(16.dp),
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

private val NAME_WIDTH = 230.dp

/** A name column wide enough for the longest channel name on one line (within reason), the same for every row. */
internal fun nameWidthFor(channels: List<Channel>): androidx.compose.ui.unit.Dp =
    (60 + 7 * (channels.maxOfOrNull { it.name.length } ?: 0)).coerceIn(230, 520).dp
/** The category column: narrow, so the names sit close to their counts. */
private val CATEGORY_WIDTH = Theme.playerWidth
private val NEXT_WIDTH = 180.dp

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
                        nameWidth: androidx.compose.ui.unit.Dp? = null,
                        onLongClick: (() -> Unit)? = null, onFocus: () -> Unit, onClick: () -> Unit) {
    val now = model.currentProgramme(channel)
    val next = now?.let { n -> model.guide[channel.epgId]?.firstOrNull { it.start >= n.end } }
    TvButton(onClick = onClick, onFocus = onFocus, focusedScale = 1.02f, onLongClick = onLongClick,
        modifier = modifier.fillMaxWidth()) { focused ->
        val color = if (focused) Theme.bg else Theme.text
        Row(Modifier.padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            // A set name width (the game screen) keeps names on one line; otherwise they can wrap onto two.
            Row(Modifier.width(nameWidth ?: NAME_WIDTH), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ChannelIcon(channel.icon, 24.dp)
                Label(channel.name, size = 12.sp, weight = FontWeight.SemiBold, color = if (playing && !focused) Theme.accent else color,
                    maxLines = if (nameWidth != null) 1 else 2, modifier = Modifier.weight(1f, fill = false))
                if (playing) Icon(Icons.Filled.GraphicEq, null, tint = if (focused) Theme.bg else Theme.accent, modifier = Modifier.size(11.dp))
                if (model.isFavoriteChannel(channel.id))
                    Icon(Icons.Filled.Favorite, null, tint = if (focused) Theme.bg else Theme.accent, modifier = Modifier.size(10.dp))
            }
            Column(Modifier.weight(1f).padding(end = 8.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Label(now?.title ?: "–", size = 12.sp, color = color)
                if (now != null) {
                    val total = (now.end - now.start).toFloat()
                    ProgressLine(if (total > 0) (System.currentTimeMillis() - now.start) / total else 0f, focused)
                }
            }
            Label(next?.let { "${clockTime(it.start)}  ${it.title}" } ?: "", size = 11.sp, color = color.copy(alpha = 0.65f),
                modifier = Modifier.width(NEXT_WIDTH))
            if (!badge.isNullOrEmpty()) Badge(badge, fill = if (badge == "4K") Theme.accent else Theme.raised,
                color = if (badge == "4K") Theme.onAccent else Theme.soft)
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
