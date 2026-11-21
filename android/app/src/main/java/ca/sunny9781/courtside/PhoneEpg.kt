package ca.sunny9781.courtside

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Icon
import kotlinx.coroutines.delay

/**
 * EPG: groups → categories → channels, one level at a time (Back goes up a level), favourites first. Along the bottom:
 * your favourite categories and channels, then Auto-Group and the filter. Tap a channel to play it at the top, tap it
 * again for full screen (the arrows there flip through the category). The heart on a row adds it to favourites.
 * Sideways, a category shows as a timeline.
 */
@Composable
fun PhoneEpg(model: AppModel) {
    val s = model.settings
    var search by remember { mutableStateOf("") }
    var hits by remember { mutableStateOf<List<EpgSearch.Hit>>(emptyList()) }
    var flipped by remember(hits) { mutableStateOf(setOf<String>()) }
    val searching = search.trim().length >= 2
    LaunchedEffect(search, s.grouped, model.channels, model.guide) {
        val q = search.trim()
        if (q.length < 2) { hits = emptyList(); return@LaunchedEffect }
        // Searching covers every category, so it starts from the top.
        PhoneUi.epgPath = emptyList()
        delay(250)
        val grouped = s.grouped
        hits = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { EpgSearch.run(q, model, grouped) }
    }
    val path = PhoneUi.epgPath
    val id = path.lastOrNull()
    val playing = model.pinned?.channel?.id
    val landscape = isLandscape()

    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (model.channels.isEmpty()) {
                Label(if (model.loading) "Downloading channels…" else (model.error ?: "No channels yet."), size = 15.sp,
                    color = Theme.muted, maxLines = 3, modifier = Modifier.align(Alignment.Center).padding(24.dp))
            } else Column(Modifier.fillMaxSize()) {
                if (id != null && !searching) PageHeader(title(model, id)) { PhoneUi.epgPath = path.dropLast(1) }
                if (id != null && id.startsWith("cat:") && landscape && !searching) {
                    val list = channelsOf(model, id.removePrefix("cat:"))
                    PhoneTimeline(model, list, playing) { tapChannel(model, it, list) }
                } else LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 30.dp)) {
                    when {
                        searching -> searchResults(model, hits, flipped, search, playing) { hid ->
                            flipped = if (hid in flipped) flipped - hid else flipped + hid
                        }
                        id != null && id.startsWith("cat:") -> {
                            val list = channelsOf(model, id.removePrefix("cat:"))
                            if (list.isEmpty()) item { Label("No channels.", size = 14.sp, color = Theme.muted, modifier = Modifier.padding(24.dp)) }
                            items(list, key = { "ch:${it.id}" }, contentType = { "channel" }) { ch ->
                                PhoneChannelRow(model, ch, ch.id == playing, heart = true) { tapChannel(model, ch, list) }
                            }
                        }
                        id != null -> {
                            val group = CategoryGrouping.find(id, model.categoryTree)
                            if (group != null) {
                                item(key = "all") {
                                    CategoryLine(model, group.id, "All ${group.name} channels", count(model, group.categories), group = false,
                                        heart = false) { PhoneUi.epgPath = path + ("cat:" + group.id) }
                                }
                                nodeRows(model, group.children, path)
                            }
                        }
                        s.grouped -> nodeRows(model, model.categoryTree, path)
                        else -> nodeRows(model, model.categories.sortedWith { a, b -> NaturalOrder.compare(a.name, b.name) }
                            .map { CategoryGrouping.Node(it.id, it.name, emptyList(), listOf(it)) }, path)
                    }
                }
            }
        }
        EpgBottomBar(model, search, { search = it }, playing)
    }
}

private fun title(model: AppModel, id: String): String {
    val raw = id.removePrefix("cat:")
    CategoryGrouping.find(raw, model.categoryTree)?.let { return it.name }
    return model.categories.firstOrNull { it.id == raw }?.name ?: ""
}

/** The channels of a category, or of every category in a group, favourites first. */
private fun channelsOf(model: AppModel, id: String): List<Channel> {
    val cats = CategoryGrouping.find(id, model.categoryTree)?.categories ?: model.categories.filter { it.id == id }
    return model.favoritesFirst(cats.flatMap { model.channelsByCategory[it.id] ?: emptyList() }.distinctBy { it.id })
}

private fun count(model: AppModel, cats: List<ChannelCategory>) = cats.sumOf { model.channelsByCategory[it.id]?.size ?: 0 }

private fun LazyListScope.nodeRows(model: AppModel, nodes: List<CategoryGrouping.Node>, path: List<String>) {
    val favs = model.favoriteCategoryIds.toSet()
    val ordered = nodes.filter { it.id in favs } + nodes.filter { it.id !in favs }
    items(ordered, key = { "n:${it.id}" }, contentType = { "category" }) { node ->
        if (node.isGroup) CategoryLine(model, node.id, node.name, node.categories.size, group = true) { PhoneUi.epgPath = path + node.id }
        else CategoryLine(model, node.id, node.name, count(model, node.categories), group = false) { PhoneUi.epgPath = path + ("cat:" + node.id) }
    }
}

private fun LazyListScope.searchResults(model: AppModel, hits: List<EpgSearch.Hit>, flipped: Set<String>, search: String,
                                        playing: Int?, flip: (String) -> Unit) {
    if (hits.isEmpty()) item { Label("Nothing matches \"$search\".", size = 14.sp, color = Theme.muted, modifier = Modifier.padding(24.dp)) }
    for (hit in hits) {
        val open = hit.startsOpen(hits.size) != (hit.id in flipped)
        item(key = "hit:${hit.id}") {
            Row(Modifier.fillMaxWidth().background(Theme.card.copy(alpha = 0.6f)).clickable { flip(hit.id) }
                .padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(Icons.Filled.ChevronRight, null, tint = Theme.muted, modifier = Modifier.size(16.dp).rotate(if (open) 90f else 0f))
                Column(Modifier.weight(1f)) {
                    Label(hit.category.name, size = 14.sp, weight = FontWeight.SemiBold)
                    if (hit.path.isNotEmpty()) Label(hit.path, size = 11.sp, color = Theme.muted)
                }
                Label("${hit.channels.size}", size = 12.sp, color = Theme.muted)
            }
        }
        if (open) items(hit.channels, key = { "hit:${hit.id}:${it.id}" }, contentType = { "channel" }) { ch ->
            PhoneChannelRow(model, ch, ch.id == playing, heart = true) { tapChannel(model, ch, hit.channels) }
        }
    }
}

@Composable
private fun PageHeader(title: String, back: () -> Unit) {
    Row(Modifier.fillMaxWidth().height(46.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(44.dp).clip(CircleShape).clickable(onClick = back), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.ArrowBackIosNew, "Back", tint = Theme.accent, modifier = Modifier.size(18.dp))
        }
        Label(title, size = 16.sp, weight = FontWeight.SemiBold, modifier = Modifier.weight(1f),
            align = androidx.compose.ui.text.style.TextAlign.Center)
        Spacer(Modifier.width(44.dp))
    }
}

@Composable
private fun CategoryLine(model: AppModel, id: String, name: String, count: Int, group: Boolean, heart: Boolean = true, open: () -> Unit) {
    Column {
        Row(Modifier.fillMaxWidth().height(50.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f).fillMaxHeight().clickable(onClick = open).padding(start = 16.dp, end = if (heart) 4.dp else 16.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(if (group) Icons.Filled.Folder else Icons.Filled.List, null, tint = if (group) Theme.accent else Theme.muted,
                    modifier = Modifier.size(20.dp))
                Label(name, size = 15.sp, modifier = Modifier.weight(1f))
                Label("$count", size = 13.sp, color = Theme.muted)
                Icon(Icons.Filled.ChevronRight, null, tint = Theme.muted, modifier = Modifier.size(16.dp))
            }
            if (heart) Heart(model.isFavoriteCategory(id)) { model.toggleFavoriteCategory(id) }
        }
        Box(Modifier.padding(start = 52.dp).fillMaxWidth().height(1.dp).background(Theme.raised))
    }
}

@Composable
private fun Heart(on: Boolean, toggle: () -> Unit) {
    Box(Modifier.padding(end = 6.dp).size(44.dp).clip(CircleShape).clickable(onClick = toggle), contentAlignment = Alignment.Center) {
        Icon(if (on) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder, if (on) "Remove from favourites" else "Add to favourites",
            tint = if (on) Theme.accent else Theme.muted.copy(alpha = 0.6f), modifier = Modifier.size(20.dp))
    }
}

/**
 * A channel: a strip in the colour of what's on (its sport, like the TV guide), the logo and name, what's on now with
 * its progress, and what's next. Game streams and channel sports also show the quality tags.
 */
@Composable
fun PhoneChannelRow(model: AppModel, channel: Channel, playing: Boolean, heart: Boolean = false, showTags: Boolean = false,
                    onClick: () -> Unit) {
    val nn = model.nowNext(channel)
    val now = nn.now
    Column {
        // What's playing: an orange outline around the row (like the iPhone and the TVs; no speaker icon).
        Row(Modifier.fillMaxWidth().padding(horizontal = 6.dp)
            .border(2.dp, if (playing) Theme.accent else androidx.compose.ui.graphics.Color.Transparent, RoundedCornerShape(10.dp))
            .clip(RoundedCornerShape(10.dp)), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f).clickable(onClick = onClick).padding(start = 10.dp, end = if (heart) 0.dp else 10.dp, top = 10.dp, bottom = 10.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.width(4.dp).height(44.dp).clip(RoundedCornerShape(2.dp))
                    .background(Guide.fill(now?.title ?: "", channel, model.games)))
                ChannelIcon(channel.icon, 38.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Label(channel.name, size = 14.sp, weight = FontWeight.SemiBold, color = if (playing) Theme.accent else Theme.text,
                            modifier = Modifier.weight(1f, fill = false))
                    }
                    if (now != null) {
                        Label(now.title, size = 13.sp, color = Theme.soft)
                        val total = (now.end - now.start).toFloat()
                        ThinProgress(if (total > 0) (System.currentTimeMillis() - now.start) / total else 0f)
                    }
                    nn.next?.let { Label("Next: ${clockTime(it.start)} ${it.title}", size = 11.sp, color = Theme.muted) }
                }
                if (showTags) {
                    val quality = model.measuredQuality[channel.id]
                    val fps = model.measuredFrameRate[channel.id]
                    val sound = model.measuredAudio[channel.id]
                    val hdr = model.measuredHdr[channel.id]
                    Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        if (!quality.isNullOrEmpty()) Badge(quality, fill = if (quality == "4K") Theme.accent else Theme.raised,
                            color = if (quality == "4K") Theme.onAccent else Theme.soft)
                        if (fps != null && fps > 0) Badge(Playback.fpsLabel(fps))
                        if (!sound.isNullOrEmpty()) Badge(sound)
                        if (!hdr.isNullOrEmpty()) Badge(hdr)
                    }
                }
            }
            if (heart) Heart(model.isFavoriteChannel(channel.id)) { model.toggleFavoriteChannel(channel.id) }
        }
        Box(Modifier.padding(start = 82.dp).fillMaxWidth().height(1.dp).background(Theme.raised))
    }
}

/** Favourites (categories, a line, then channels), then Auto-Group and the filter, in reach of the thumb. */
@Composable
private fun EpgBottomBar(model: AppModel, search: String, setSearch: (String) -> Unit, playing: Int?) {
    val cats = model.favoriteCategoryNodes()
    val chans = model.favoriteChannelList()
    Column(Modifier.fillMaxWidth().background(Theme.sidebar.copy(alpha = 0.96f)).padding(vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (cats.isNotEmpty() || chans.isNotEmpty()) {
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Filled.Favorite, null, tint = Theme.accent, modifier = Modifier.size(14.dp))
                for (node in cats) {
                    val target = if (node.isGroup) node.id else "cat:" + node.id
                    TouchChip(PhoneUi.epgPath.lastOrNull() == target, onClick = { setSearch(""); PhoneUi.epgPath = listOf(target) }) { color ->
                        Icon(if (node.isGroup) Icons.Filled.Folder else Icons.Filled.List, null, tint = color, modifier = Modifier.size(16.dp))
                        Label(node.name, size = 14.sp, weight = FontWeight.SemiBold, color = color)
                    }
                }
                if (cats.isNotEmpty() && chans.isNotEmpty()) Box(Modifier.padding(horizontal = 4.dp).width(1.dp).height(24.dp).background(Theme.border))
                for (ch in chans) {
                    TouchChip(ch.id == playing, onClick = { tapChannel(model, ch, chans) }) { color ->
                        ChannelIcon(ch.icon, 20.dp)
                        Label(ch.name, size = 14.sp, weight = FontWeight.SemiBold, color = color)
                    }
                }
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(Theme.raised))
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            TouchChip(model.settings.grouped, onClick = { model.settings.grouped = !model.settings.grouped; PhoneUi.epgPath = emptyList() }) { color ->
                Icon(Icons.Filled.Layers, null, tint = color, modifier = Modifier.size(16.dp))
                Label("Auto-Group", size = 14.sp, weight = FontWeight.SemiBold, color = color)
            }
            TouchField("Filter", search, setSearch, height = 40.dp, leading = Icons.Filled.Search, modifier = Modifier.weight(1f))
        }
    }
}

/**
 * Sideways on a category: the guide as a timeline (two and a half hours from the last half hour), coloured by sport,
 * with an orange line at the current time. Tap a row to play it (again for full screen).
 */
@Composable
private fun PhoneTimeline(model: AppModel, channels: List<Channel>, playing: Int?, onTap: (Channel) -> Unit) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(30_000); now = System.currentTimeMillis() } }
    val start = Guide.windowStart(now)
    Column(Modifier.fillMaxSize().padding(horizontal = 12.dp)) {
        Row(Modifier.fillMaxWidth().height(22.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Spacer(Modifier.width(Guide.channelWidth))
            BoxWithConstraints(Modifier.weight(1f).fillMaxHeight()) {
                val perMs = maxWidth.value / Guide.SPAN
                for (i in 0 until 5) Label(clockTime(start + i * 30 * 60_000L), size = 11.sp, weight = FontWeight.SemiBold, color = Theme.muted,
                    modifier = Modifier.offset(x = (i * 30 * 60_000L * perMs).dp))
            }
        }
        LazyColumn(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp), contentPadding = PaddingValues(bottom = 20.dp)) {
            items(channels, key = { it.id }) { ch ->
                GuideRow(model, ch, ch.id == playing, start, now, Modifier, onFocus = {}) { onTap(ch) }
            }
        }
    }
}
