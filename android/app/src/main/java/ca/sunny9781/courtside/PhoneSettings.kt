package ca.sunny9781.courtside

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Icon
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date

private enum class PhoneSection(val title: String, val icon: ImageVector) {
    ACCOUNT("Account", Icons.Filled.AccountCircle), VPN("VPN", Icons.Filled.VpnLock), PLAYBACK("Playback", Icons.Filled.Slideshow),
    GENERAL("General", Icons.Filled.Tune), HIDDEN("Hidden", Icons.Filled.VisibilityOff), CHANGELOG("Changelog", Icons.Filled.AutoAwesome)
}

/** Settings: the same sections as the TVs, switched with chips along the bottom so nothing needs long scrolling. */
@Composable
fun PhoneSettings(model: AppModel) {
    var section by remember { mutableStateOf(PhoneSection.entries.firstOrNull { it.name == model.settingsSection } ?: PhoneSection.ACCOUNT) }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            when (section) {
                PhoneSection.ACCOUNT -> AccountSection(model)
                PhoneSection.VPN -> VpnSettings(model)
                PhoneSection.PLAYBACK -> PlaybackSettings(model)
                PhoneSection.GENERAL -> GeneralSection(model)
                PhoneSection.HIDDEN -> HiddenSection(model)
                PhoneSection.CHANGELOG -> ChangelogSection(model)
            }
        }
        Column(Modifier.fillMaxWidth().background(Theme.sidebar.copy(alpha = 0.96f)).padding(vertical = 8.dp)) {
            TrailingRow {
                for (item in PhoneSection.entries.reversed()) {
                    TouchChip(section == item, onClick = { section = item; model.settingsSection = item.name }) { color ->
                        Icon(item.icon, item.title, tint = color, modifier = Modifier.size(20.dp))
                        if (section == item) Label(item.title, size = 14.sp, weight = FontWeight.SemiBold, color = color)
                    }
                }
            }
        }
    }
}

@Composable
private fun Group(title: String?, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().padding(bottom = 10.dp)) {
        if (title != null) Label(title.uppercase(), size = 12.sp, weight = FontWeight.SemiBold, color = Theme.muted,
            modifier = Modifier.padding(start = 14.dp, bottom = 6.dp))
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Theme.card)) { content() }
        if (footer != null) Label(footer, size = 12.sp, color = Theme.muted, maxLines = 5,
            modifier = Modifier.padding(start = 14.dp, end = 14.dp, top = 6.dp))
    }
}

@Composable
private fun Line(title: String, value: String? = null, detail: String? = null, color: Color = Theme.text,
                 valueColor: Color = Theme.muted, onClick: (() -> Unit)? = null, trailing: @Composable (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
        .padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(Modifier.weight(1f)) {
            Label(title, size = 15.sp, color = color, maxLines = 2)
            if (detail != null) Label(detail, size = 12.sp, color = Theme.muted, maxLines = 4)
        }
        if (value != null) Label(value, size = 15.sp, color = valueColor)
        trailing?.invoke()
    }
}

@Composable
private fun Divider() = Box(Modifier.padding(start = 14.dp).fillMaxWidth().height(1.dp).background(Theme.raised))

@Composable
private fun Toggle(title: String, on: Boolean, detail: String? = null, set: (Boolean) -> Unit) {
    Line(title, detail = detail, onClick = { set(!on) }) { TouchSwitch(on, set) }
}

@Composable
fun TouchSwitch(on: Boolean, set: (Boolean) -> Unit) {
    androidx.compose.material3.Switch(checked = on, onCheckedChange = set,
        colors = androidx.compose.material3.SwitchDefaults.colors(
            checkedThumbColor = Color.White, checkedTrackColor = Theme.accent, checkedBorderColor = Theme.accent,
            uncheckedThumbColor = Theme.muted, uncheckedTrackColor = Theme.raised, uncheckedBorderColor = Theme.border))
}

/** A few choices side by side ("1 s  2 s  3 s  5 s"), the chosen one in orange. */
@Composable
private fun <T> Choice(title: String, options: List<Pair<T, String>>, value: T, set: (T) -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 14.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Label(title, size = 15.sp, maxLines = 2, modifier = Modifier.weight(1f))
        for ((v, label) in options) {
            val on = v == value
            Box(Modifier.clip(RoundedCornerShape(8.dp)).background(if (on) Theme.accent else Theme.raised).clickable { set(v) }
                .padding(horizontal = 10.dp, vertical = 6.dp)) {
                Label(label, size = 13.sp, weight = FontWeight.SemiBold, color = if (on) Theme.onAccent else Theme.soft)
            }
        }
    }
}

@Composable
private fun AccountSection(model: AppModel) {
    LaunchedEffect(Unit) { model.refreshAccount() }
    val a = model.account
    var confirm by remember { mutableStateOf(false) }
    Group("Account") {
        Line("Username", model.credentials?.username ?: "")
        Divider()
        Line("Status", a?.status ?: "–")
        Divider()
        Line("Expires", a?.expires?.let { DateFormat.getDateInstance(DateFormat.LONG).format(Date(it * 1000)) } ?: "No expiry date")
        Divider()
        Line("Connections", a?.maxConnections?.let { "${a.activeConnections ?: 0} of $it in use" } ?: "–")
        Divider()
        Line("Edit account", color = Theme.accent, onClick = { model.editingAccount = true })
        Divider()
        Line("Sign out", color = Theme.losing, onClick = { confirm = true })
    }
    if (confirm) androidx.compose.material3.AlertDialog(
        onDismissRequest = { confirm = false },
        containerColor = Theme.card,
        title = { Label("Sign out of Courtside?", size = 18.sp, weight = FontWeight.SemiBold) },
        text = { Label("Your login is removed from this phone.", size = 14.sp, color = Theme.muted, maxLines = 3) },
        confirmButton = {
            Box(Modifier.clip(RoundedCornerShape(8.dp)).clickable { confirm = false; model.signOut() }.padding(12.dp)) {
                Label("Sign out", size = 15.sp, weight = FontWeight.Bold, color = Theme.losing)
            }
        },
        dismissButton = {
            Box(Modifier.clip(RoundedCornerShape(8.dp)).clickable { confirm = false }.padding(12.dp)) {
                Label("Cancel", size = 15.sp, color = Theme.soft)
            }
        })
}

/** Built-in VPN (2.33): a WireGuard config from a .conf file or pasted, used by Courtside only. */
@Composable
private fun VpnSettings(model: AppModel) {
    val s = model.settings
    val activity = LocalContext.current as android.app.Activity
    var error by remember { mutableStateOf<String?>(null) }
    var pasting by remember { mutableStateOf(false) }
    var removing by remember { mutableStateOf(false) }
    val pick = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.GetContent()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val text = runCatching {
            activity.contentResolver.openInputStream(uri)?.use { it.readBytes().take(32768).toByteArray().decodeToString() }
        }.getOrNull()
        error = if (text == null) "That file couldn't be read." else model.saveVpnConfig(text, activity)
    }
    val has = s.vpnConfig.isNotBlank()
    Group("VPN", footer = error ?: (if (s.vpnOn && Vpn.state == Vpn.State.FAILED) Vpn.detail.ifEmpty { null } else null)
        ?: "Courtside's own WireGuard VPN: only this app goes through it, the rest of the phone stays on its normal " +
        "connection. While it's on, Courtside won't contact your provider without it. It connects when you open the " +
        "app and disconnects when you leave. Casting isn't covered: the Chromecast fetches the stream itself.") {
        if (has) {
            Toggle("Use the VPN", s.vpnOn) { error = null; model.vpnSwitched(it, activity) }
            Divider()
            Line("Status", vpnStatus(s.vpnOn), valueColor = if (s.vpnOn && Vpn.state == Vpn.State.ON) Theme.accent else Theme.muted)
            Divider()
            Line("Server", Vpn.server(s.vpnConfig).ifEmpty { "–" })
        } else {
            Line("Status", "No VPN set up")
        }
    }
    Group("WireGuard config", footer = "Use the .conf file from your VPN provider's WireGuard setup page (Proton VPN, " +
        "Mullvad, Surfshark, AirVPN and others offer one), or from your own WireGuard server.") {
        Line(if (has) "Choose a new .conf file" else "Choose a .conf file", color = Theme.accent, onClick = { pick.launch("*/*") })
        Divider()
        Line("Paste a config", color = Theme.accent, onClick = { pasting = true })
        if (has) {
            Divider()
            Line("Remove the VPN", color = Theme.losing, onClick = { removing = true })
        }
    }
    if (pasting) {
        var text by remember { mutableStateOf("") }
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { pasting = false },
            containerColor = Theme.card,
            title = { Label("Paste a WireGuard config", size = 18.sp, weight = FontWeight.SemiBold) },
            text = {
                androidx.compose.material3.OutlinedTextField(text, { text = it }, minLines = 6, maxLines = 12,
                    placeholder = { Label("[Interface]\nPrivateKey = …\n\n[Peer]\nEndpoint = …", size = 13.sp, color = Theme.muted, maxLines = 6) },
                    textStyle = androidx.compose.ui.text.TextStyle(color = Theme.text, fontSize = 13.sp,
                        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace),
                    modifier = Modifier.fillMaxWidth())
            },
            confirmButton = {
                Box(Modifier.clip(RoundedCornerShape(8.dp)).clickable {
                    pasting = false; error = model.saveVpnConfig(text, activity)
                }.padding(12.dp)) {
                    Label("Save and connect", size = 15.sp, weight = FontWeight.Bold, color = Theme.accent)
                }
            },
            dismissButton = {
                Box(Modifier.clip(RoundedCornerShape(8.dp)).clickable { pasting = false }.padding(12.dp)) {
                    Label("Cancel", size = 15.sp, color = Theme.soft)
                }
            })
    }
    if (removing) androidx.compose.material3.AlertDialog(
        onDismissRequest = { removing = false },
        containerColor = Theme.card,
        title = { Label("Remove the VPN?", size = 18.sp, weight = FontWeight.SemiBold) },
        text = { Label("Its config is deleted from this phone and Courtside goes back to your normal connection.", size = 14.sp, color = Theme.muted, maxLines = 3) },
        confirmButton = {
            Box(Modifier.clip(RoundedCornerShape(8.dp)).clickable { removing = false; error = null; model.removeVpnConfig() }.padding(12.dp)) {
                Label("Remove", size = 15.sp, weight = FontWeight.Bold, color = Theme.losing)
            }
        },
        dismissButton = {
            Box(Modifier.clip(RoundedCornerShape(8.dp)).clickable { removing = false }.padding(12.dp)) {
                Label("Cancel", size = 15.sp, color = Theme.soft)
            }
        })
}

@Composable
private fun PlaybackSettings(model: AppModel) {
    val s = model.settings
    val context = LocalContext.current
    var castNote by remember { mutableStateOf<String?>(null) }
    Group("Chromecast", footer = castNote ?: when {
        Cast.disabled -> "Chromecast was turned off because it made Courtside close while starting."
        !Cast.ready -> "Chromecast needs Google Play services on this phone."
        else -> "Tap the Cast button on the player to play on a TV. The TV plays the provider's HLS version of the channel, and the phone's own player stops, so only one connection is used."
    }) {
        when {
            Cast.disabled -> Line("Turn Chromecast back on", color = Theme.accent, onClick = {
                Cast.enableAgain(context); castNote = "Chromecast comes back the next time Courtside opens."
            })
            Cast.connected -> Line("Casting to ${Cast.deviceName}", "Stop", valueColor = Theme.accent, onClick = { Cast.disconnect() })
            else -> Line(if (Cast.routes.isEmpty()) "No Chromecasts found on this Wi-Fi" else "${Cast.routes.size} found on this Wi-Fi",
                if (Cast.ready && Cast.routes.isNotEmpty()) "Connect" else null, valueColor = Theme.accent,
                onClick = if (Cast.ready && Cast.routes.isNotEmpty()) ({ PhoneUi.castPicker = true }) else null)
        }
    }
    Group("Playback", footer = "USA and Canada streams are tried first when switching. More buffer means fewer stalls but a longer delay behind live (takes effect the next time the app opens).") {
        Toggle("Switch to the next stream when one stalls", s.autoSwitch) { s.autoSwitch = it }
        Divider()
        Choice("Buffer", listOf(1000 to "1 s", 2000 to "2 s", 3000 to "3 s", 5000 to "5 s"), s.bufferMs) { s.bufferMs = it }
        Divider()
        Choice("Stream format", listOf(false to "TS", true to "HLS"), s.preferHls) { s.preferHls = it }
    }
    Group("Games") {
        Toggle("Hide SD streams", s.hideSD) { s.hideSD = it }
    }
}

@Composable
private fun GeneralSection(model: AppModel) {
    val s = model.settings
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    Group("Updates", footer = model.updatedAt?.let {
        "Channels last checked ${DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(it))} (every hour). The guide downloads again after the time above, or sooner if your provider's guide runs out. Scores update every minute."
    }) {
        Choice("Download a fresh guide after", listOf(1 to "1 h", 3 to "3 h", 6 to "6 h", 12 to "12 h", 24 to "24 h"), s.refreshHours) { s.refreshHours = it }
        Divider()
        Line(when {
            model.refreshWaiting -> "Refreshes after this stream"
            model.loading || model.guideLoading -> "Refreshing…"
            else -> "Refresh now"
        }, color = Theme.accent, onClick = { model.refresh(force = true) })
        Divider()
        val ready = Updater.readyVersion
        val downloading = Updater.downloading
        when {
            downloading != null -> Line("Downloading $downloading", Updater.downloadProgress?.let { "${(it * 100).toInt()}%" })
            ready != null -> Line("Install version $ready", detail = "Android's own screen asks you to confirm the install.",
                color = Theme.accent, onClick = { Updater.installNow(context) })
            else -> Line(if (Updater.checking) "Checking…" else "Check for updates", detail = Updater.status ?: Updater.message ?: "Courtside checks by itself every time it opens.",
                color = Theme.accent, onClick = { scope.launch { Updater.check(context, userInitiated = true) } })
        }
        Divider()
        Line("Version", "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
    }
    var logOpen by remember { mutableStateOf(false) }
    Group(null, footer = "Streams opened and closed, downloads, and what the provider said was in use.") {
        Line("Connection log", onClick = { logOpen = !logOpen }) {
            Icon(Icons.Filled.ChevronRight, null, tint = Theme.muted, modifier = Modifier.size(16.dp).rotate(if (logOpen) 90f else 0f))
        }
        if (logOpen) Column(Modifier.padding(horizontal = 14.dp, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            if (ConnLog.entries.isEmpty()) Label("Nothing yet.", size = 12.sp, color = Theme.muted)
            for (line in ConnLog.entries) Label(line, size = 12.sp, color = Theme.soft, maxLines = 3)
        }
    }
    val crash = remember { runCatching { java.io.File(context.filesDir, "crash-last.txt").readText() }.getOrNull() }
    if (crash != null) Group("Last crash") {
        Label(crash.lines().take(6).joinToString("\n"), size = 11.sp, color = Theme.muted, maxLines = 6, modifier = Modifier.padding(14.dp))
    }
}

/** Every sport (heart = first on Home, switch = shown), its leagues, then the hidden EPG categories and channels. */
@Composable
private fun HiddenSection(model: AppModel) {
    val s = model.settings
    var openSport by remember { mutableStateOf<Sport?>(null) }
    Group("Sports", footer = "Tap a sport for its leagues. Switch one off to hide it; the heart keeps it first on Home.") {
        Sport.entries.forEachIndexed { i, sport ->
            if (i > 0) Divider()
            val hidden = sport in s.hiddenSportSet
            val fav = sport in s.favoriteSet
            val leagues = sport.leagues
            Row(Modifier.fillMaxWidth().heightIn(min = 50.dp).padding(end = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(48.dp).clickable { s.toggleFavorite(sport) }, contentAlignment = Alignment.Center) {
                    Icon(if (fav) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder, if (fav) "Unfavourite" else "Favourite",
                        tint = if (fav) Theme.accent else Theme.muted, modifier = Modifier.size(20.dp))
                }
                Row(Modifier.weight(1f).heightIn(min = 50.dp).then(if (leagues.size > 1) Modifier.clickable {
                    openSport = if (openSport == sport) null else sport } else Modifier),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(sport.icon, null, tint = Theme.accent, modifier = Modifier.size(20.dp))
                    Label(sport.title, size = 15.sp, modifier = Modifier.weight(1f, fill = false))
                    if (leagues.size > 1) Icon(Icons.Filled.ChevronRight, null, tint = Theme.muted,
                        modifier = Modifier.size(16.dp).rotate(if (openSport == sport) 90f else 0f))
                }
                TouchSwitch(!hidden) { model.setSportHidden(sport, !it) }
            }
            if (openSport == sport) for (league in leagues) {
                Row(Modifier.fillMaxWidth().heightIn(min = 46.dp).padding(start = 58.dp, end = 14.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    LeagueLogo(model, league, 22.dp)
                    Label(league.name, size = 14.sp, color = Theme.soft, modifier = Modifier.weight(1f))
                    TouchSwitch(league.id !in s.hiddenLeagueSet) { model.setLeagueHidden(league.id, !it) }
                }
            }
        }
    }
    val cats = model.hiddenCategoryNames()
    val chans = model.hiddenChannelNames()
    Group("Categories and channels", footer = "Categories with \"adult\" in the name start out here. Tap one to show it again.") {
        if (cats.isEmpty() && chans.isEmpty()) Line("Nothing hidden.", color = Theme.muted)
        var first = true
        for ((id, name) in cats) {
            if (!first) Divider(); first = false
            Line(name, "Show", valueColor = Theme.accent, onClick = { model.setCategoryHidden(id, false) })
        }
        for ((id, name) in chans) {
            if (!first) Divider(); first = false
            Line(name, "Show", valueColor = Theme.accent, onClick = { model.setChannelHidden(id, false) })
        }
    }
}

@Composable
private fun ChangelogSection(model: AppModel) {
    var openIds by remember { mutableStateOf(model.whatsNew.take(1).map { it.version + it.time }.toSet()) }
    Group("Changelog") {
        model.whatsNew.forEachIndexed { i, r ->
            if (i > 0) Divider()
            val key = r.version + r.time
            val open = key in openIds
            Column(Modifier.fillMaxWidth().clickable { openIds = if (open) openIds - key else openIds + key }
                .padding(horizontal = 14.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Column(Modifier.weight(1f)) {
                        Label(r.title.ifEmpty { if (r.changes.size == 1) "1 change" else "${r.changes.size} changes" }, size = 15.sp,
                            weight = FontWeight.SemiBold, maxLines = 2)
                        Label(if (i == 0) "Latest · ${r.label}" else r.label, size = 12.sp, color = Theme.muted)
                    }
                    Icon(Icons.Filled.ChevronRight, null, tint = Theme.muted, modifier = Modifier.size(16.dp).rotate(if (open) 90f else 0f))
                }
                if (open) for (c in r.changes) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.padding(top = 6.dp).size(6.dp).clip(RoundedCornerShape(3.dp)).background(Theme.accent))
                    Label(c, size = 13.sp, color = Theme.soft, maxLines = 10)
                }
            }
        }
    }
}
