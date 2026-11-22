package ca.sunny9781.courtside

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Icon
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date

private enum class Section(val title: String, val icon: ImageVector) {
    ACCOUNT("Account", Icons.Filled.AccountCircle),
    /** How streams play: switching, frame rate, Lite mode, format, buffer. */
    PLAYBACK("Playback", Icons.Filled.PlayCircle),
    /** Channels and guide, updates. */
    GENERAL("General", Icons.Filled.Tune),
    /** Lite mode's options, one switch each (only on less powerful TVs, not the Shield). */
    LITE("Lite mode", Icons.Filled.Speed),
    /** Hidden sports, categories, groups and channels (hold the select button on one to hide it). */
    HIDDEN("Hidden", Icons.Filled.VisibilityOff),
    CHANGELOG("Changelog", Icons.Filled.AutoAwesome)
}

/** Settings, like the Apple TV app: sections down the left (moving onto one shows it), the section on the right. */
@Composable
fun SettingsScreen(model: AppModel) {
    // Kept in the model: coming back from another tab lands on the section you were in.
    val section = Section.entries.firstOrNull { it.name == model.settingsSection } ?: Section.ACCOUNT
    val side = remember { FocusTargets() }
    // Back from a setting: its section on the left.
    LaunchedEffect(Unit) {
        model.focusMoves.collect { m -> if (m == "side") side.focus(Section.entries.firstOrNull { it.name == model.settingsSection }) }
    }
    Row(Modifier.fillMaxSize().padding(end = Theme.margin).enterAt { side[section] },
        horizontalArrangement = Arrangement.spacedBy(24.dp)) {
        Column(Modifier.width(Theme.playerWidth).padding(bottom = topInset(model)).padding(vertical = 8.dp)
            .focusRequester(model.leftPanel).onFocusChanged { model.sideFocused = it.hasFocus }.enterAt { side[section] },
            verticalArrangement = Arrangement.spacedBy(3.dp)) {
            for (item in Section.entries.filter { it != Section.LITE || model.settings.slowDevice }) {
                TvButton(onClick = { model.settingsSection = item.name }, selected = section == item,
                    onFocus = { model.settingsSection = item.name },
                    modifier = Modifier.fillMaxWidth().tracked(side, item)) { focused ->
                    val color = if (focused) Theme.bg else Theme.text
                    Row(Modifier.padding(horizontal = 10.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(item.icon, null, tint = color, modifier = Modifier.size(17.dp))
                        Label(item.title, size = 14.sp, weight = FontWeight.SemiBold, color = color)
                    }
                }
            }
        }
        // Runs to the bottom of the screen, under the now-playing bar beside the player.
        val pane = Modifier.weight(1f).widthIn(max = 560.dp).fillMaxHeight()
        BehindPlayerBar(model) {
        Column(pane.verticalScroll(rememberScrollState())
            .padding(top = 8.dp, bottom = 8.dp + barInset(model)), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            when (section) {
                Section.ACCOUNT -> Account(model)
                Section.PLAYBACK -> PlaybackSection(model)
                Section.GENERAL -> {
                    Toggle("Hide SD streams", "Most providers have HD versions of the same channels.", model.settings.hideSD) {
                    model.settings.hideSD = it
                }
                    Updates(model)
                    ConnectionLog()
                    LastCrash()
                }
                Section.LITE -> LiteSection(model)
                Section.HIDDEN -> Hidden(model)
                Section.CHANGELOG -> Changelog(model)
            }
        }
        }
    }
}

@Composable
private fun Account(model: AppModel) {
    // The connection count is fetched fresh each time you open Account.
    LaunchedEffect(Unit) { model.refreshAccount() }
    val a = model.account
    Info("Username", model.credentials?.username ?: "")
    Info("Status", a?.status ?: "–")
    Info("Expires", a?.expires?.let { DateFormat.getDateInstance(DateFormat.LONG).format(Date(it * 1000)) } ?: "No expiry date")
    Info("Connections", a?.maxConnections?.let { "${a.activeConnections ?: 0} of $it in use" } ?: "–")
    Spacer(Modifier.height(10.dp))
    Action("Edit account", "Change the server, username or password.") { model.editingAccount = true }
    var confirm by remember { mutableStateOf(false) }
    Action(if (confirm) "Click again to sign out" else "Sign out", if (confirm) "Press Back or move away to cancel." else null,
        destructive = true, modifier = Modifier.onFocusChanged { if (!it.isFocused) confirm = false }) {
        if (confirm) model.signOut() else confirm = true
    }
}

@Composable
private fun PlaybackSection(model: AppModel) {
    val s = model.settings
    Toggle("Switch to the next stream when one stalls", "USA and Canada streams are tried first.", s.autoSwitch) { s.autoSwitch = it }
    Toggle("Match frame rate", "Switches your TV to each stream's frame rate (50 or 60 fps) in full screen, for smoother motion.",
        s.matchFrameRate) { s.matchFrameRate = it }
    Toggle("Multiview", "Hold select on a stream or a score card and choose Watch alongside to watch two at once. Needs a second free connection.",
        s.multiview) { s.multiview = it }
    if (s.multiview) Action("Select in multiview", "What pressing select on a tile does. Either way, only one tile plays sound.",
        value = if (s.multiviewMakeBig) "Make big" else "Move sound only") { s.multiviewMakeBig = !s.multiviewMakeBig }
    Action("Stream format", "Which version of each stream to open first. If it shows no picture within 8 seconds, the other one is tried.",
        value = if (s.preferHls) "HLS first" else "TS first") { s.preferHls = !s.preferHls }
    Action("Buffer", "More buffer means fewer stalls but a longer delay behind live. Takes effect the next time the app opens.",
        value = "${s.bufferMs / 1000} s") {
        val list = listOf(1000, 2000, 3000, 5000)
        s.bufferMs = list[(list.indexOf(s.bufferMs) + 1) % list.size]
    }
}

/** What used a connection to the provider, newest first: to see what caused 2/2 when only one thing plays. */
@Composable
private fun ConnectionLog() {
    var open by remember { mutableStateOf(false) }
    Action("Connection log", "Streams opened and closed, downloads, and what the provider said was in use.",
        value = if (open) "Hide" else "Show") { open = !open }
    if (open) {
        if (ConnLog.entries.isEmpty()) Label("Nothing yet.", size = 11.sp, color = Theme.muted, modifier = Modifier.padding(horizontal = 10.dp))
        ConnLog.entries.forEach { line ->
            Label(line, size = 11.sp, color = Theme.soft, maxLines = 2, modifier = Modifier.padding(horizontal = 10.dp, vertical = 2.dp))
        }
    }
}

@Composable
private fun Updates(model: AppModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val s = model.settings
    Action("Download a fresh guide after",
        "The channel list is checked every hour. The guide downloads again after this long, or sooner if your provider's guide runs out. Scores update every minute.",
        value = "${s.refreshHours} h") {
        val list = listOf(1, 3, 6, 12, 24)
        s.refreshHours = list[(list.indexOf(s.refreshHours) + 1) % list.size]
    }
    Action("Refresh now", model.updatedAt?.let { "Last downloaded ${DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(it))}" },
        value = if (model.refreshWaiting) "After this stream" else if (model.loading || model.guideLoading) "Refreshing…" else null) { model.refresh(force = true) }
    val ready = Updater.readyVersion
    if (ready != null) {
        Action("Install version $ready", "Already downloaded. Android's own screen asks you to confirm the install.") { Updater.installNow(context) }
    } else if (Updater.downloading != null) {
        Action("Downloading version ${Updater.downloading}", null,
            value = Updater.downloadProgress?.let { "${(it * 100).toInt()}%" } ?: "…") { }
    } else if (Updater.availableVersion != null) {
        Action("Download version ${Updater.availableVersion}", "Then Install update installs it.") {
            scope.launch { Updater.check(context, userInitiated = true, download = true) }
        }
    } else {
        Action("Check for updates", Updater.status ?: Updater.message ?: "Courtside checks by itself every time it opens.",
            value = if (Updater.checking) "Checking…" else null) { scope.launch { Updater.check(context, userInitiated = true, download = false) } }
    }
    Info("Version", "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
}

@Composable
private fun Changelog(model: AppModel) {
    // The newest update starts open; click one to open or close it.
    var openIds by remember { mutableStateOf(model.whatsNew.take(1).map { it.version }.toSet()) }
    model.whatsNew.forEachIndexed { i, r ->
        val open = r.version in openIds
        TvButton(onClick = { openIds = if (open) openIds - r.version else openIds + r.version }, modifier = Modifier.fillMaxWidth()) { focused ->
            val color = if (focused) Theme.bg else Theme.text
            Column(Modifier.padding(horizontal = 10.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(if (open) Icons.Filled.ExpandMore else Icons.Filled.ChevronRight, null, tint = color, modifier = Modifier.size(14.dp))
                    Label(r.title.ifEmpty { if (r.changes.size == 1) "1 change" else "${r.changes.size} changes" }, size = 13.sp, weight = FontWeight.SemiBold, color = color, modifier = Modifier.weight(1f))
                    Label(if (i == 0) "Latest · ${r.label}" else r.label, size = 10.sp, color = color.copy(alpha = 0.6f))
                }
                if (open) for (c in r.changes) {
                    Row(Modifier.padding(start = 22.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Label("•", size = 11.sp, color = color.copy(alpha = 0.85f))
                        Label(c, size = 11.sp, color = color.copy(alpha = 0.85f), maxLines = 8)
                    }
                }
            }
        }
    }
}

/** What happened the last time the app closed unexpectedly, to read out when reporting it. */
@Composable
private fun LastCrash() {
    val context = androidx.compose.ui.platform.LocalContext.current
    val text = remember { runCatching { java.io.File(context.filesDir, "crash-last.txt").readText() }.getOrNull() } ?: return
    Label("LAST CRASH", size = 10.sp, weight = FontWeight.Bold, color = Theme.muted, modifier = Modifier.padding(start = 10.dp, top = 10.dp))
    Label(text.lines().take(6).joinToString("\n"), size = 10.sp, color = Theme.muted, maxLines = 6,
        modifier = Modifier.padding(horizontal = 10.dp))
}

/** Everything hidden (switched off): click one to show it again. */
@Composable
private fun Hidden(model: AppModel) {
    val s = model.settings
    val sports = Sport.entries.filter { it in s.hiddenSportSet }
    val leagues = League.all.filter { it.id in s.hiddenLeagueSet && it.sport !in s.hiddenSportSet }
    val cats = model.hiddenCategoryNames()
    val chans = model.hiddenChannelNames()
    if (sports.isEmpty() && leagues.isEmpty() && cats.isEmpty() && chans.isEmpty()) {
        Label("Nothing is hidden. Hold the select button on a sport on Home, or a category or channel in the EPG, and choose Hide.",
            size = 13.sp, color = Theme.muted, maxLines = 3, modifier = Modifier.padding(10.dp))
        return
    }
    Label("Click one to show it again. A hidden sport is switched off: no scores are fetched and nothing is matched for it. Categories with \"adult\" in the name start out here.", size = 11.sp, maxLines = 3, color = Theme.muted, modifier = Modifier.padding(horizontal = 10.dp))
    if (sports.isNotEmpty() || leagues.isNotEmpty()) {
        Label("SPORTS", size = 10.sp, weight = FontWeight.Bold, color = Theme.muted, modifier = Modifier.padding(start = 10.dp, top = 8.dp))
        for (sport in sports) Action(sport.title, null, value = "Show") { model.setSportHidden(sport, false) }
        for (league in leagues) Action(league.name, sport(league), value = "Show") { model.setLeagueHidden(league.id, false) }
    }
    if (cats.isNotEmpty()) {
        Label("CATEGORIES", size = 10.sp, weight = FontWeight.Bold, color = Theme.muted, modifier = Modifier.padding(start = 10.dp, top = 8.dp))
        for ((id, name) in cats) Action(name, null, value = "Show") { model.setCategoryHidden(id, false) }
    }
    if (chans.isNotEmpty()) {
        Label("CHANNELS", size = 10.sp, weight = FontWeight.Bold, color = Theme.muted, modifier = Modifier.padding(start = 10.dp, top = 8.dp))
        for ((id, name) in chans) Action(name, null, value = "Show") { model.setChannelHidden(id, false) }
    }
}

private fun sport(league: League) = league.sport.title

@Composable
private fun Info(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp).heightIn(min = 30.dp), verticalAlignment = Alignment.CenterVertically) {
        Label(label, size = 13.sp, color = Theme.muted, modifier = Modifier.weight(1f))
        Label(value, size = 13.sp, weight = FontWeight.SemiBold, color = Theme.text)
    }
}

/**
 * Lite mode, for less powerful TVs: one switch for everything, then each option on its own, from the one that
 * makes the least difference to speed to the one that makes the most.
 */
@Composable
private fun LiteSection(model: AppModel) {
    val s = model.settings
    Action("Lite mode", "Turns everything below off at once. Or turn them off one at a time, from the bottom up, if this TV feels slow.",
        value = when { s.lite -> "On"; s.anyLite -> "Custom"; else -> "Off" }) {
        val on = !s.lite
        s.lite = on
        if (on) model.stopPinned()
    }
    Spacer(Modifier.height(6.dp))
    // Each option says what you get when it's on (Logos: On), not what Lite mode takes away.
    Label("TURNING ONE OFF MAKES THIS TV FASTER (MOST AT THE BOTTOM)", size = 10.sp, weight = FontWeight.Bold, color = Theme.muted,
        modifier = Modifier.padding(start = 10.dp))
    Toggle("Quick page switching", "Moving through sports, tabs and categories shows a page after a short pause (250 ms; off: 350 ms).",
        !s.liteSettle) { s.liteSettle = !it }
    Toggle("Finished games", "Home shows finished games (off: they fold into one row at the bottom, Finished · 6).",
        !s.liteFoldFinished) { s.liteFoldFinished = !it }
    Toggle("Later games", "Home shows games starting more than 2 hours away (off: they fold into one row, Later today · 18).",
        !s.liteFoldLater) { s.liteFoldLater = !it }
    Toggle("Logos", "Team logos on Home and the game screen, channel logos in the EPG and the now-playing bar.",
        !s.liteNoLogos) { s.liteNoLogos = !it }
    Toggle("Live scores", "Scores and clocks update every minute (off: today's games load once when the app opens; LIVE instead of the clock).",
        !s.liteNoScores) { s.liteNoScores = !it }
    Toggle("Start a stream on the game screen", "Opening a game plays its first stream (off: it waits for you to pick one).",
        !s.liteNoAutoplay) { s.liteNoAutoplay = !it }
    Toggle("Player in the corner", "Channels play in the corner first (off: they open straight in full screen, and leaving full screen stops the stream).",
        !s.liteNoCorner) { s.liteNoCorner = !it; if (!it) model.stopPinned() }
}

@Composable
private fun Toggle(title: String, detail: String?, on: Boolean, set: (Boolean) -> Unit) {
    Action(title, detail, value = if (on) "On" else "Off") { set(!on) }
}

@Composable
private fun Action(title: String, detail: String?, value: String? = null, destructive: Boolean = false,
                   modifier: Modifier = Modifier, perform: () -> Unit) {
    TvButton(onClick = perform, modifier = modifier.fillMaxWidth()) { focused ->
        Row(Modifier.padding(horizontal = 10.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                // Bright title, dim grey detail, and the value in orange ("Off" grey), so each setting reads at a glance.
                Label(title, size = 14.sp, weight = FontWeight.SemiBold,
                    color = if (focused) Theme.bg else if (destructive) Theme.losing else Theme.text)
                if (detail != null) Label(detail, size = 10.sp, color = if (focused) Theme.bg.copy(alpha = 0.75f) else Theme.muted, maxLines = 3)
            }
            if (value != null) Label(value, size = 13.sp, weight = FontWeight.Bold,
                color = if (focused) Theme.bg else if (value == "Off") Theme.muted else Theme.accent)
        }
    }
}
