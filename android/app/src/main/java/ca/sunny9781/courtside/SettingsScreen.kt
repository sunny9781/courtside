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
    SPORTS("Sports", Icons.Filled.Sports),
    /** Playback, games, EPG and updates together. */
    GENERAL("General", Icons.Filled.Tune),
    CHANGELOG("Changelog", Icons.Filled.AutoAwesome)
}

/** Settings, like the Apple TV app: sections down the left (moving onto one shows it), the section on the right. */
@Composable
fun SettingsScreen(model: AppModel) {
    var section by remember { mutableStateOf(Section.ACCOUNT) }
    val side = remember { FocusTargets() }
    Row(Modifier.fillMaxSize().padding(horizontal = Theme.margin).enterAt { side[section] },
        horizontalArrangement = Arrangement.spacedBy(24.dp)) {
        Column(Modifier.width(150.dp).padding(vertical = 8.dp).enterAt { side[section] },
            verticalArrangement = Arrangement.spacedBy(3.dp)) {
            for (item in Section.entries) {
                TvButton(onClick = { section = item }, selected = section == item, onFocus = { section = item },
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
        Column(Modifier.weight(1f).widthIn(max = 560.dp).fillMaxHeight().padding(top = topInset(model)).verticalScroll(rememberScrollState())
            .padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            when (section) {
                Section.ACCOUNT -> Account(model)
                Section.SPORTS -> Sports(model)
                Section.GENERAL -> {
                    PlaybackSection(model)
                    Toggle("Hide SD streams", "Most providers have HD versions of the same channels.", model.settings.hideSD) {
                    model.settings.hideSD = it
                }
                    Toggle("Hide adult categories", "Any category with \"adult\" in its name, and its channels.", model.settings.hideAdult) {
                        model.settings.hideAdult = it
                        model.filtersChanged()
                    }
                    Toggle("Group similar categories", "Sports, Country, 24/7 and so on, opened one level at a time.", model.settings.grouped) {
                        model.settings.grouped = it
                        model.guidePath = emptyList()
                    }
                    Updates(model)
                }
                Section.CHANGELOG -> Changelog(model)
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
    Action("Stream format", "Which version of each stream to open first. If it shows no picture within 8 seconds, the other one is tried.",
        value = if (s.preferHls) "HLS first" else "TS first") { s.preferHls = !s.preferHls }
    Action("Buffer", "More buffer means fewer stalls but a longer delay behind live. Takes effect the next time the app opens.",
        value = "${s.bufferMs / 1000} s") {
        val list = listOf(1000, 2000, 3000, 5000)
        s.bufferMs = list[(list.indexOf(s.bufferMs) + 1) % list.size]
    }
}

@Composable
private fun Sports(model: AppModel) {
    val s = model.settings
    var open by remember { mutableStateOf<Sport?>(null) }
    Label("Click a sport to show or hide it, or the heart to keep it first on Home. Open a sport to switch its leagues on or off.",
        size = 11.sp, color = Theme.muted, maxLines = 3, modifier = Modifier.padding(bottom = 6.dp))
    val hidden = s.hiddenSportSet
    val favs = s.favoriteSet
    for (sport in Sport.entries) {
        val isHidden = sport in hidden
        Row(Modifier.alpha(if (isHidden) 0.7f else 1f), horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically) {
            TvButton(onClick = { s.setHidden(sport, !isHidden) }, modifier = Modifier.weight(1f)) { focused ->
                val color = if (focused) Theme.bg else Theme.text
                Row(Modifier.padding(horizontal = 10.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(sport.icon, null, tint = color, modifier = Modifier.size(16.dp))
                    Label(sport.title, size = 13.sp, weight = FontWeight.Medium, color = color, modifier = Modifier.weight(1f))
                    Label(if (isHidden) "Hidden" else "Shown", size = 12.sp, weight = FontWeight.SemiBold,
                        color = color.copy(alpha = if (isHidden) 0.5f else 0.8f))
                }
            }
            TvButton(onClick = { s.toggleFavorite(sport) }, background = Theme.raised) { focused ->
                Icon(if (sport in favs) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder, null,
                    tint = if (focused) Theme.bg else if (sport in favs) Theme.accent else Theme.muted,
                    modifier = Modifier.padding(8.dp).size(15.dp))
            }
            if (sport.leagues.size > 1) {
                TvButton(onClick = { open = if (open == sport) null else sport }, background = Theme.raised) { focused ->
                    Icon(if (open == sport) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, null,
                        tint = if (focused) Theme.bg else Theme.text, modifier = Modifier.padding(8.dp).size(15.dp))
                }
            } else Spacer(Modifier.width(31.dp))
        }
        if (open == sport) for (league in sport.leagues) {
            val off = league.id in s.hiddenLeagueSet
            TvButton(onClick = { s.setLeagueHidden(league.id, !off); model.leagueFilterChanged() },
                modifier = Modifier.fillMaxWidth().padding(start = 28.dp, end = 78.dp)) { focused ->
                val color = if (focused) Theme.bg else Theme.text
                Row(Modifier.padding(horizontal = 10.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    LeagueLogo(model, league, 18.dp)
                    Label(league.name, size = 12.sp, color = color, modifier = Modifier.weight(1f))
                    Label(if (off) "Hidden" else "Shown", size = 11.sp, weight = FontWeight.SemiBold, color = color.copy(alpha = if (off) 0.5f else 0.8f))
                }
            }
        }
    }
}

@Composable
private fun Updates(model: AppModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val s = model.settings
    Action("Download fresh channels and guide after",
        "Opening the app reuses the saved channels and guide until they're this old. Scores always update every minute.",
        value = "${s.refreshHours} h") {
        val list = listOf(1, 3, 6, 12, 24)
        s.refreshHours = list[(list.indexOf(s.refreshHours) + 1) % list.size]
    }
    Action("Refresh now", model.updatedAt?.let { "Last downloaded ${DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(it))}" },
        value = if (model.loading) "Downloading…" else null) { model.refresh(force = true) }
    val ready = Updater.readyVersion
    if (ready != null) {
        Action("Install version $ready", "Downloaded and ready. Android asks you to confirm the install.") { scope.launch { Updater.installLatest(context) } }
    } else {
        Action("Check for updates", Updater.message ?: "Courtside checks by itself every time it opens.",
            value = if (Updater.checking) "Checking…" else null) { scope.launch { Updater.check(context, userInitiated = true) } }
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
                    Label(r.title, size = 13.sp, weight = FontWeight.SemiBold, color = color, modifier = Modifier.weight(1f))
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

@Composable
private fun Info(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp).heightIn(min = 30.dp), verticalAlignment = Alignment.CenterVertically) {
        Label(label, size = 13.sp, color = Theme.muted, modifier = Modifier.weight(1f))
        Label(value, size = 13.sp)
    }
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
                Label(title, size = 13.sp, weight = FontWeight.Medium,
                    color = if (focused) Theme.bg else if (destructive) Theme.losing else Theme.text)
                if (detail != null) Label(detail, size = 10.sp, color = (if (focused) Theme.bg else Theme.text).copy(alpha = 0.6f), maxLines = 3)
            }
            if (value != null) Label(value, size = 12.sp, weight = FontWeight.SemiBold, color = (if (focused) Theme.bg else Theme.text).copy(alpha = 0.8f))
        }
    }
}
