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
    val selected: Entry? = run {
        val id = s.guideCategory
        if (id.startsWith("g:")) CategoryGrouping.find(id.drop(2), tree)?.let { return@run Entry(id, it.name, it.categories) }
        entries.firstOrNull { it.id == id } ?: entries.firstOrNull()
    }
    val channels = remember(selected?.id, model.channelsByCategory) {
        (selected?.categories ?: emptyList()).flatMap { model.channelsByCategory[it.id] ?: emptyList() }.distinctBy { it.id }
    }
    fun key(n: CategoryGrouping.Node) = if (n.isGroup) "g:${n.id}" else n.id
    // Coming in from the tabs or the channels: the selected category if it's showing, otherwise the first row.
    val categoryTarget: String? = when {
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
        LazyColumn(Modifier.width(CATEGORY_WIDTH).fillMaxHeight().padding(bottom = topInset(model)).enterAt { cats["cat:$categoryTarget"] },
            verticalArrangement = Arrangement.spacedBy(3.dp), contentPadding = PaddingValues(vertical = 8.dp)) {
            // One search for categories and channels; results show on the right.
            item(key = "filter") { Field("Filter", search, { search = it }, width = CATEGORY_WIDTH) }
            item(key = "group") {
                CategoryRow(cats, "cat:toggle", Icons.Filled.Layers, "Group", if (s.grouped) "On" else "Off", false) {
                    s.grouped = !s.grouped
                    model.guidePath = emptyList()
                }
            }
            if (s.grouped) {
                if (openNodes.isNotEmpty()) item(key = "up") {
                    CategoryRow(cats, "cat:up", Icons.Filled.ChevronLeft, openNodes.joinToString(" › ") { it.name }, null, false, bold = true) {
                        go(model.guidePath.dropLast(1))
                    }
                }
                items(level, key = { key(it) }) { node ->
                    val k = key(node)
                    if (node.isGroup) {
                        CategoryRow(cats, "cat:$k", Icons.Filled.Folder, node.name, "${node.categories.size}", selected?.id == k,
                            trailing = Icons.Filled.ChevronRight, onFocus = { if (s.guideCategory != k) s.guideCategory = k }) {
                            go(model.guidePath + node.id)
                        }
                    } else {
                        CategoryRow(cats, "cat:$k", null, node.name, "${count(model, node.categories)}", selected?.id == k,
                            onFocus = { if (s.guideCategory != k) s.guideCategory = k }) { s.guideCategory = k }
                    }
                }
            } else {
                items(entries, key = { it.id }) { e ->
                    CategoryRow(cats, "cat:${e.id}", null, e.name, "${count(model, e.categories)}", selected?.id == e.id,
                        onFocus = { if (s.guideCategory != e.id) s.guideCategory = e.id }) { s.guideCategory = e.id }
                }
            }
        }

        Column(Modifier.weight(1f).fillMaxHeight()) {
            InfoPanel(model, focusedChannel?.let { model.channelById[it] } ?: playing, playing)
            LazyColumn(Modifier.fillMaxSize().enterAt { rows[lastRow] }, verticalArrangement = Arrangement.spacedBy(2.dp),
                contentPadding = PaddingValues(vertical = 6.dp)) {
                item(key = "header") {
                    Row(Modifier.padding(horizontal = 10.dp, vertical = 4.dp)) {
                        Label(if (searching) "Results for “$hitsFor”" else (selected?.name ?: ""), size = 10.sp,
                            weight = FontWeight.Bold, color = Theme.muted, modifier = Modifier.width(NAME_WIDTH))
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
                            ChannelRow(model, ch, ch.id == playing?.id, Modifier.tracked(rows, k),
                                onFocus = { focusedChannel = ch.id; lastRow = k }) { click(ch, hit.channels) }
                        }
                    }
                } else {
                    items(channels, key = { "c:${it.id}" }) { ch ->
                        val k = "c:${ch.id}"
                        ChannelRow(model, ch, ch.id == playing?.id, Modifier.tracked(rows, k),
                            onFocus = { focusedChannel = ch.id; lastRow = k }) { click(ch, channels) }
                    }
                }
            }
        }
    }
}

private data class Entry(val id: String, val name: String, val categories: List<ChannelCategory>)

private val NAME_WIDTH = 230.dp
/** The category column: narrow, so the names sit close to their counts. */
private val CATEGORY_WIDTH = Theme.playerWidth
private val NEXT_WIDTH = 180.dp

private fun count(model: AppModel, cats: List<ChannelCategory>) = cats.sumOf { model.channelsByCategory[it.id]?.size ?: 0 }

@Composable
internal fun CategoryRow(
    targets: FocusTargets, key: String, icon: androidx.compose.ui.graphics.vector.ImageVector?, name: String, value: String?,
    selected: Boolean, bold: Boolean = false, trailing: androidx.compose.ui.graphics.vector.ImageVector? = null,
    onFocus: (() -> Unit)? = null, onClick: () -> Unit
) {
    TvButton(onClick = onClick, selected = selected, onFocus = onFocus, modifier = Modifier.fillMaxWidth().tracked(targets, key)) { focused ->
        val color = if (focused) Theme.bg else Theme.text
        Row(Modifier.padding(horizontal = 10.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (icon != null) Icon(icon, null, tint = color.copy(alpha = 0.75f), modifier = Modifier.size(14.dp))
            Label(name, size = 14.sp, weight = if (bold) FontWeight.Bold else FontWeight.SemiBold, color = color, modifier = Modifier.weight(1f))
            if (value != null) Label(value, size = 11.sp, color = color.copy(alpha = 0.6f))
            if (trailing != null) Icon(trailing, null, tint = color.copy(alpha = 0.6f), modifier = Modifier.size(13.dp))
        }
    }
}

/** Two lines about the channel you're on: what's on now (and until when), then what's next. */
@Composable
private fun InfoPanel(model: AppModel, channel: Channel?, playing: Channel?) {
    Column(Modifier.fillMaxWidth().height(46.dp).padding(top = 6.dp, start = 10.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        if (channel == null) {
            Label("Click a channel to play it in the player at the top. Click it again for full screen.", size = 12.sp, color = Theme.muted)
            return@Column
        }
        val now = model.currentProgramme(channel)
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Label(now?.title?.ifEmpty { null } ?: channel.name, size = 15.sp, weight = FontWeight.Bold, modifier = Modifier.weight(1f, fill = false))
            if (now != null) Label("${clockTime(now.start)} – ${clockTime(now.end)}", size = 11.sp, color = Theme.muted)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Label(channel.name, size = 11.sp, color = Theme.soft)
            val next = now?.let { n -> model.guide[channel.epgId]?.firstOrNull { it.start >= n.end } }
            if (next != null) Label("Next: ${next.title} at ${clockTime(next.start)}", size = 11.sp, color = Theme.muted, modifier = Modifier.weight(1f, fill = false))
            Spacer(Modifier.weight(1f))
            Label(if (channel.id == playing?.id) "Click again for full screen" else "Click to play", size = 11.sp, color = Theme.muted.copy(alpha = 0.8f))
        }
    }
}

/** A channel: logo and name, what's on now (with progress), and what's next. */
@Composable
internal fun ChannelRow(model: AppModel, channel: Channel, playing: Boolean, modifier: Modifier, badge: String? = null,
                        onFocus: () -> Unit, onClick: () -> Unit) {
    val now = model.currentProgramme(channel)
    val next = now?.let { n -> model.guide[channel.epgId]?.firstOrNull { it.start >= n.end } }
    TvButton(onClick = onClick, onFocus = onFocus, focusedScale = 1.02f, modifier = modifier.fillMaxWidth()) { focused ->
        val color = if (focused) Theme.bg else Theme.text
        Row(Modifier.padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.width(NAME_WIDTH), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ChannelIcon(channel.icon, 24.dp)
                Label(channel.name, size = 12.sp, weight = FontWeight.SemiBold, color = if (playing && !focused) Theme.accent else color,
                    modifier = Modifier.weight(1f, fill = false))
                if (playing) Icon(Icons.Filled.GraphicEq, null, tint = if (focused) Theme.bg else Theme.accent, modifier = Modifier.size(11.dp))
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
