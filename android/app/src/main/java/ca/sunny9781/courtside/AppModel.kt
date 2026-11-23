package ca.sunny9781.courtside

import kotlinx.coroutines.asCoroutineDispatcher

import androidx.compose.runtime.derivedStateOf

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

enum class Tab(val title: String) { HOME("Home"), EPG("EPG"), SETTINGS("Settings") }

/** Home's left column: Live Now, or one sport (optionally narrowed to one league). */
sealed class HomeSelection {
    data object LiveNow : HomeSelection()
    data class OfSport(val sport: Sport) : HomeSelection()
    data class OfLeague(val leagueId: String) : HomeSelection()
    /** A sport's finished games (2.45): their own entry at the end of the league list, out of the other lists. */
    data class Finished(val sport: Sport) : HomeSelection()
}

class AppModel(app: Application) : AndroidViewModel(app) {
    private val context get() = getApplication<Application>()
    val settings = Settings(app)
    // Before anything here can reach the provider: the built-in VPN's switch decides whether that has to wait.
    private val vpnReady = Vpn.attach(app)
    val whatsNew = WhatsNew.load(app)
    /**
     * Multiview's second tile (2.30): its own ExoPlayer and video view, created only while it plays. Tile 1 is the
     * stream that was already playing, in Playback (same player, same connection).
     */
    val tile2 = TilePlayer(app, "tile 2")

    var credentials by mutableStateOf(Prefs.loadCredentials(app))
        private set
    var account by mutableStateOf<AccountInfo?>(null)
        private set
    var categories by mutableStateOf<List<ChannelCategory>>(emptyList())
        private set
    var channels by mutableStateOf<List<Channel>>(emptyList())
        private set
    /** The EPG's category groups (CategoryGrouping). */
    var categoryTree by mutableStateOf<List<CategoryGrouping.Node>>(emptyList())
        private set
    var channelsByCategory by mutableStateOf<Map<String, List<Channel>>>(emptyMap())
        private set
    var channelById by mutableStateOf<Map<Int, Channel>>(emptyMap())
        private set
    /** Games in the leagues switched on in Settings. */
    var games by mutableStateOf<List<Game>>(emptyList())
        private set

    /**
     * New games keep the old ones where nothing about them changed, so when one score ticks over only that game's
     * row is drawn again (not every row on Home).
     */
    private fun updateGames(list: List<Game>) {
        val old = games.associateBy { it.id }
        games = list.map { n -> old[n.id]?.takeIf { it == n } ?: n }
    }
    private var allGames: List<Game> = emptyList()
    /** Canadian, UK and European broadcasters from the official schedules and the rights table (BroadcastSources). */
    private var extraBroadcasts: Map<String, List<Broadcast>> = emptyMap()
    private var broadcastsJob: Job? = null
    private var rawCategories: List<ChannelCategory> = emptyList()
    private var rawChannels: List<Channel> = emptyList()
    /** Resolution and frame rate each channel really played at, which beat what its name says. */
    var measuredQuality by mutableStateOf<Map<Int, String>>(emptyMap())
        private set
    var measuredFrameRate by mutableStateOf<Map<Int, Float>>(emptyMap())
        private set
    /** The sound each channel played with ("Stereo", "5.1 Dolby"). */
    var measuredAudio by mutableStateOf<Map<Int, String>>(emptyMap())
        private set
    var leagueLogos by mutableStateOf<Map<String, String>>(emptyMap())
        private set
    var guide by mutableStateOf<Map<String, List<Programme>>>(emptyMap())
        private set
    var matches by mutableStateOf<Map<String, List<StreamMatch>>>(emptyMap())
        private set
    var loading by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
        private set
    var updatedAt by mutableStateOf<Long?>(null)
        private set
    /** The guide is downloading (the top bar shows "Refreshing EPG" and how far along it is). */
    var guideLoading by mutableStateOf(false)
        private set
    /** How much of the guide has come in, 0 to 1 (null when the provider doesn't say how big it is). */
    var guideProgress by mutableStateOf<Float?>(null)
        private set
    /** Megabytes of the guide downloaded so far, for when the size isn't known. */
    var guideMegabytes by mutableStateOf(0)
        private set
    /** A refresh is waiting for the stream to stop (so the app never uses two connections). */
    var refreshWaiting by mutableStateOf(false)
        private set

    private var guideJob: kotlinx.coroutines.Job? = null

    /** A stream is open (or about to be). Downloads wait until it's closed, so only one connection is ever in use. */
    private val streamOpen get() = Playback.currentUrl != null || Cast.hasMedia || tile2.isOpen

    private suspend fun waitForNoStream() {
        if (!streamOpen) return
        ConnLog.add("Waiting for the stream to stop before downloading")
        refreshWaiting = true
        try {
            while (streamOpen) kotlinx.coroutines.delay(3000)
            // A moment for the provider to see the stream closed.
            kotlinx.coroutines.delay(2000)
        } finally {
            refreshWaiting = false
        }
    }

    /** A stream is starting: a guide download in progress stops and starts again once nothing plays. */
    private fun pauseDownloads() {
        if (guideJob?.isActive != true) return
        ConnLog.add("Paused the guide download (a stream started)")
        guideJob?.cancel()
        val creds = credentials ?: return
        startGuide(XtreamClient(creds))
    }

    /**
     * When the downloads are due. The channel list is checked every hour (new event channels appear on game day);
     * the guide downloads again after Settings › Updates' interval, or sooner when the provider's guide runs out
     * (an hour before most channels' last programme ends).
     */
    private val channelsEvery = 3600_000L

    private fun guideEnd(g: Map<String, List<Programme>>): Long {
        val ends = g.values.mapNotNull { it.lastOrNull()?.end }.sorted()
        return if (ends.isEmpty()) 0L else ends[ends.size / 2]
    }

    private fun guideDue(now: Long = System.currentTimeMillis()): Boolean {
        val g = guide
        if (g.isEmpty()) return true
        if (now - Cache.guideSavedAt(context) >= settings.refreshHours * 3600_000L) return true
        return now >= guideEnd(g) - 3600_000L
    }

    /** The last download this check started, so one that fails is tried again in 15 minutes, not every minute. */
    private var lastAutoRefresh = 0L

    /** Checked every minute while the app is on screen and nothing plays: downloads what's due. */
    private fun refreshIfDue() {
        if (loading || guideLoading || guideJob?.isActive == true || streamOpen || credentials == null) return
        val now = System.currentTimeMillis()
        if (now - lastAutoRefresh < 15 * 60_000L) return
        val channelsAge = now - (updatedAt ?: 0L)
        if (channelsAge >= channelsEvery) { lastAutoRefresh = now; refresh() }
        else if (guideDue(now)) { lastAutoRefresh = now; credentials?.let { startGuide(XtreamClient(it)) } }
    }

    private fun startGuide(client: XtreamClient) {
        guideJob?.cancel()
        guideJob = viewModelScope.launch {
            waitForNoStream()
            loadGuide(client)
        }
    }

    var tab by mutableStateOf(Tab.HOME)
    /** Focus is on Home / EPG / Settings: the player's video can't take focus then, so down lands on the page. */
    var tabsFocused by mutableStateOf(false)
    /**
     * You moved to a sport yourself. Until then Home keeps the top sport selected while things finish loading (the
     * order settles once the scores, channels and guide are in), so it doesn't stay on whichever sport loaded first.
     */
    var pickedSport = false
    /** The select button is still held after it stopped the corner player: ignore it until it's let go. */
    var swallowSelect = false
    val openedAt = System.currentTimeMillis()
    /** Focus is in a screen's left panel (sports, EPG categories, settings sections, game categories). */
    var sideFocused by mutableStateOf(false)
    /** Settings' section, kept while you visit other tabs (coming back lands where you were). */
    var settingsSection by mutableStateOf("ACCOUNT")
    /**
     * Back moves focus up one level: "side" (from a page to its left panel, onto the selected item) or "tabs" (from a
     * left panel to the tab you're on). Each screen listens and moves focus itself.
     */
    val focusMoves = kotlinx.coroutines.flow.MutableSharedFlow<String>(extraBufferCapacity = 1)
    /** The app is on screen (not behind the TV's home screen): nothing is fetched while it isn't. */
    var onScreen = true
    private var lastScores = 0L

    /** Back on screen: scores right away if they're more than a minute old. */
    fun cameBack() {
        onScreen = true
        refreshIfDue()
        if (System.currentTimeMillis() - lastScores > 60_000 && !settings.liteNoScores && allGames.isNotEmpty()) {
            lastScores = System.currentTimeMillis()
            viewModelScope.launch { runCatching { loadScores() } }
        }
    }
    /** Settings › Account › Edit account is open. */
    var editingAccount by mutableStateOf(false)
    /** The EPG groups you've opened, outermost first. */
    var guidePath by mutableStateOf<List<String>>(emptyList())
    /** Where full screen was opened from ("strip", "game", "epg"), so focus goes back there afterwards. */
    var fullScreenFrom by mutableStateOf("")
    var homeSelection by mutableStateOf<HomeSelection>(HomeSelection.LiveNow)
    /** The game screen that's open on Home, if any. */
    var openGameId by mutableStateOf<String?>(null)
    /** The game just closed, so Home puts focus back on its card. */
    var returnToGame: String? = null
    /** Home's games, kept here so the list is where you left it after a game screen. */
    val homeGrid = androidx.compose.foundation.lazy.grid.LazyGridState()
    val homeList = androidx.compose.foundation.lazy.LazyListState()
    /** The left panel of whichever page is showing: pressing up from the player goes there (not to the top bar). */
    val leftPanel = androidx.compose.ui.focus.FocusRequester()

    fun closeGame() {
        returnToGame = openGameId
        openGameId = null
    }

    /** In the player at the top. */
    /** Where the corner player sits on screen (the shell draws the one video view there). */
    var cornerBounds by mutableStateOf<androidx.compose.ui.geometry.Rect?>(null)
    var pinned by mutableStateOf<NowPlaying?>(null)
    /** Full screen. */
    var nowPlaying by mutableStateOf<NowPlaying?>(null)
        private set
    var lastPlayedChannelId by mutableStateOf<Int?>(null)
        private set
    var notice by mutableStateOf<String?>(null)

    // EPG favourites (listed first). Categories by id: a provider category, or a "__node:" group.
    val favoriteChannelIds: List<Int> get() = settings.favoriteChannels.split(",").mapNotNull { it.toIntOrNull() }
    val favoriteCategoryIds: List<String> get() = settings.favoriteCategories.split("\n").filter { it.isNotEmpty() }
    fun isFavoriteChannel(id: Int) = id in favoriteChannelIds
    fun isFavoriteCategory(id: String) = id in favoriteCategoryIds
    fun toggleFavoriteChannel(id: Int) {
        val list = favoriteChannelIds
        settings.favoriteChannels = (if (id in list) list - id else list + id).joinToString(",")
    }
    fun toggleFavoriteCategory(id: String) {
        val list = favoriteCategoryIds
        settings.favoriteCategories = (if (id in list) list - id else list + id).joinToString("\n")
    }
    /** Favourite channels that still exist, in the order added. */
    fun favoriteChannelList(): List<Channel> = favoriteChannelIds.mapNotNull { channelById[it] }
    /** Favourite categories and groups that still exist, in the order added. */
    fun favoriteCategoryNodes(): List<CategoryGrouping.Node> = favoriteCategoryIds.mapNotNull { id ->
        CategoryGrouping.find(id, categoryTree)
            ?: categories.firstOrNull { it.id == id }?.let { CategoryGrouping.Node(it.id, it.name, emptyList(), listOf(it)) }
    }
    // Hidden categories, groups and channels (Settings › Hidden turns them back on).
    val hiddenChannelIds: List<Int> get() = settings.hiddenChannels.split(",").mapNotNull { it.toIntOrNull() }
    val hiddenCategoryIds: List<String> get() = settings.hiddenCategories.split("\n").filter { it.isNotEmpty() }
    fun setChannelHidden(id: Int, hidden: Boolean) {
        val list = hiddenChannelIds - id
        settings.hiddenChannels = (if (hidden) list + id else list).joinToString(",")
        filtersChanged()
    }
    fun setCategoryHidden(id: String, hidden: Boolean) {
        val list = hiddenCategoryIds - id
        settings.hiddenCategories = (if (hidden) list + id else list).joinToString("\n")
        filtersChanged()
    }
    /** Hidden channels with their names, in the order hidden. */
    fun hiddenChannelNames(): List<Pair<Int, String>> {
        val byId = rawChannels.associateBy { it.id }
        return hiddenChannelIds.map { it to (byId[it]?.name ?: "Channel $it") }
    }
    /** Hidden categories and groups with their names ("Sports › 4K" for a group). */
    fun hiddenCategoryNames(): List<Pair<String, String>> {
        val byId = rawCategories.associateBy { it.id }
        return hiddenCategoryIds.map { id ->
            id to (byId[id]?.name ?: id.removePrefix(CategoryGrouping.NODE).replace("/", " › "))
        }
    }

    /** The same channels with favourites first. */
    fun favoritesFirst(channels: List<Channel>): List<Channel> {
        val fav = favoriteChannelIds.toSet()
        return if (fav.isEmpty()) channels else channels.filter { it.id in fav } + channels.filter { it.id !in fav }
    }

    private var indexed: List<Matcher.Indexed> = emptyList()
    private val recent = LinkedHashSet<Int>()
    private var scoresJob: Job? = null

    /**
     * Heavy work (matching streams to games, guide events) runs on one low-priority thread, so it never competes
     * with drawing the screen or moving focus.
     */
    private val background = java.util.concurrent.Executors.newSingleThreadExecutor { r ->
        Thread(r, "courtside-matching").apply { priority = Thread.MIN_PRIORITY; isDaemon = true }
    }.asCoroutineDispatcher()

    /** Home's lists, worked out once when the games, streams or sport settings change (not on every redraw). */
    class HomeIndex(
        val sports: List<Sport>,
        /** Sports with games from a live-score feed today. */
        val scoreSports: List<Sport>,
        /** Sports with no scores today but channels or shows in the guide (pickleball). */
        val channelSports: List<Sport>,
        /** Sports with nothing today. */
        val emptySports: List<Sport>,
        val bySport: Map<Sport, List<Game>>,
        val byLeague: Map<String, List<Game>>,
        val main: Map<String, List<StreamMatch>>
    )

    val home: HomeIndex by derivedStateOf {
        val list = games
        val m = matches
        val hidden = settings.hiddenSportSet
        val favs = settings.favoriteSet
        val bySport = list.groupBy { it.league.sport }
        val byLeague = list.groupBy { it.league.id }
        fun rank(s: Sport): Int {
            if (s in favs) return 0
            val g = bySport[s] ?: emptyList()
            return when {
                g.any { it.state == GameState.LIVE } -> 1
                g.any { it.state == GameState.UPCOMING } -> 2
                g.isEmpty() -> 4
                else -> 3
            }
        }
        val main = list.associate { g ->
            val all = m[g.id] ?: emptyList()
            g.id to all.filter { !it.hidden }.ifEmpty { all }
        }
        val ordered = Sport.entries.filter { it !in hidden }.sortedBy { rank(it) }
        val scored = ordered.filter { s -> bySport[s].orEmpty().any { !it.id.startsWith("guide-") } }
        val channelOnly = ordered.filter { s -> s !in scored && bySport[s].orEmpty().isNotEmpty() }
        HomeIndex(ordered, scored, channelOnly, ordered.filter { it !in scored && it !in channelOnly }, bySport, byLeague, main)
    }

    /** Signature of the schedule (games and their states), so an unchanged minute doesn't rematch everything. */
    private var scheduleSignature = ""

    init {
        Playback.init(app)
        Playback.onRepeatedFreezing = { skipFrozenStream() }
        if (credentials != null) refresh()
        // Checks for a new version now and every 30 minutes, so "Install update" appears on its own.
        viewModelScope.launch {
            while (true) {
                Updater.check(app, download = !Device.tv)
                kotlinx.coroutines.delay(30 * 60_000L)
            }
        }
    }

    private var accountJob: kotlinx.coroutines.Job? = null

    /** The provider's own connection count, fetched again (it's only right once the provider has noticed a change). */
    fun refreshAccount() {
        val creds = credentials ?: return
        viewModelScope.launch {
            runCatching { account = XtreamClient(creds).login() }
            account?.let { ConnLog.add("Provider says ${it.activeConnections ?: "?"}/${it.maxConnections ?: "?"} in use") }
        }
    }

    /**
     * A stream started, switched or stopped: check the connection count once things settle. Providers take a while
     * to notice a closed stream, so checking right after flipping channels counts the old one too (2/2 while only
     * one plays). Each switch restarts the 20-second wait, so flipping through channels only checks at the end.
     */
    private fun checkAccountSoon() {
        accountJob?.cancel()
        accountJob = viewModelScope.launch {
            kotlinx.coroutines.delay(20_000)
            refreshAccount()
        }
    }

    /**
     * Settings › Account › Edit account. The new details are checked first (nothing changes if they don't work);
     * a different server or username starts fresh with that account's channels.
     */
    suspend fun updateAccount(creds: Credentials): String? {
        val info = try {
            XtreamClient(creds).login()
        } catch (e: Exception) {
            return e.message ?: "Couldn't sign in with those details."
        }
        val same = creds.server == credentials?.server && creds.username == credentials?.username
        if (!same) signOut()
        credentials = creds
        account = info
        Prefs.saveCredentials(context, creds)
        if (!same) refresh(force = true)
        return null
    }

    // MARK: VPN (2.33)

    /** Settings › VPN switch. Whatever plays stops (it was on the other route), then channels load through the new one. */
    fun vpnSwitched(on: Boolean, activity: android.app.Activity) {
        stopMultiview()
        Playback.stop()
        pinned = null
        if (nowPlaying != null) closePlayer()
        pinned = null
        settings.vpnOn = on
        if (on) Vpn.start(activity) else Vpn.stop()
        viewModelScope.launch {
            if (!Vpn.ready() || credentials == null) return@launch
            if (channels.isEmpty()) refresh() else refreshAccount()
        }
    }

    /** A WireGuard config pasted or sent from the phone: checked, saved, and connected straight away. Null when fine. */
    fun saveVpnConfig(text: String, activity: android.app.Activity): String? {
        Vpn.check(text)?.let { return it }
        settings.vpnConfig = text.trim()
        Vpn.stop()
        vpnSwitched(true, activity)
        return null
    }

    fun removeVpnConfig() {
        settings.vpnOn = false
        settings.vpnConfig = ""
        Vpn.stop()
    }

    // MARK: Login

    suspend fun signIn(creds: Credentials): String? = try {
        val info = XtreamClient(creds).login()
        account = info
        credentials = creds
        Prefs.saveCredentials(context, creds)
        refresh()
        null
    } catch (e: Exception) {
        e.message ?: "Couldn't sign in."
    }

    fun signOut() {
        stopMultiview()
        Playback.stop()
        Cast.stopMedia()
        Cache.clear(context)
        rawCategories = emptyList(); rawChannels = emptyList(); categoryTree = emptyList()
        channelsByCategory = emptyMap(); channelById = emptyMap()
        pinned = null
        nowPlaying = null
        credentials = null
        Prefs.saveCredentials(context, null)
        channels = emptyList(); categories = emptyList(); matches = emptyMap(); guide = emptyMap(); account = null
        extraBroadcasts = emptyMap()
    }

    // MARK: Loading

    /**
     * Channels and guide come from the saved copy while it's newer than Settings › Updates says (12 hours by default);
     * scores are always fetched. `force` downloads everything now.
     */
    fun refresh(force: Boolean = false) {
        if (loading) return
        val creds = credentials ?: return
        val owner = creds.server + "|" + creds.username
        viewModelScope.launch {
            loading = true
            error = null
            try {
                val client = XtreamClient(creds)
                val maxAge = channelsEvery
                val stored = withContext(Dispatchers.IO) { Cache.loadLive(context) }
                    ?.takeIf { it.server == owner && it.channels.isNotEmpty() }
                val saved = if (force) null else stored?.takeIf { System.currentTimeMillis() - it.savedAt < maxAge }
                if (saved != null) {
                    // The saved guide is read alongside the channels and shown before today's scores come in (which
                    // can take a while on a slower TV), so the EPG is there straight away after an update or reopen.
                    val savedGuide = async(Dispatchers.IO) { Cache.loadGuide(context) }
                    rawCategories = saved.categories
                    rawChannels = saved.channels
                    applyFilters()
                    // Last time's streams, shown straight away while today's scores load and matching runs again.
                    val lastMatches = withContext(Dispatchers.IO) { Cache.loadMatches(context, channelById) }
                    if (matches.isEmpty() && lastMatches.isNotEmpty()) matches = lastMatches
                    updatedAt = saved.savedAt
                    loading = false
                    launch { runCatching { account = client.login() } }
                    val g = savedGuide.await()
                    if (g.isNotEmpty()) { guide = g; matchGuideSports() }
                    loadScores()    // matches today's games with the guide already in place
                    loadBroadcasts()
                    if (force || g.isEmpty() || guideDue()) startGuide(client)
                    return@launch
                }
                // Channels are due again (or you asked): until the new list is in, show the saved channels and guide
                // (when there are any), so the EPG isn't empty while the provider's list downloads.
                if (stored != null && rawChannels.isEmpty()) {
                    val savedGuide = async(Dispatchers.IO) { Cache.loadGuide(context) }
                    rawCategories = stored.categories
                    rawChannels = stored.channels
                    applyFilters()
                    val g = savedGuide.await()
                    if (g.isNotEmpty() && guide.isEmpty()) { guide = g; matchGuideSports() }
                }
                runCatching { account = client.login() }
                waitForNoStream()
                val (cats, chans) = client.live()
                // The hourly check usually finds the same list: then nothing on screen is rebuilt.
                val changed = cats != rawCategories || chans != rawChannels
                if (changed) {
                    rawCategories = cats
                    rawChannels = chans
                    applyFilters()
                }
                if (guide.isEmpty()) {
                    val g = withContext(Dispatchers.IO) { Cache.loadGuide(context) }
                    if (g.isNotEmpty() && guide.isEmpty()) guide = g
                }
                loadScores()
                loadBroadcasts()
                updatedAt = System.currentTimeMillis()
                withContext(Dispatchers.IO) { Cache.saveLive(context, owner, cats, chans) }
                loading = false
                ConnLog.add(if (changed) "Channel list changed: ${chans.size} channels" else "Channel list unchanged")
                if (force || guideDue()) startGuide(client)
                // New channels (an event channel added today) are matched straight away, without waiting for the guide.
                else if (changed) rematch(timed = true)
            } catch (e: Exception) {
                error = e.message ?: "Couldn't load your channels."
            } finally {
                loading = false
            }
        }
        // Scores every minute while a game is live or starts within 15 minutes, otherwise every 5 minutes; nothing
        // while the app isn't on screen (it catches up as soon as it's back).
        // Started once: the loop also starts the hourly refreshes, so a refresh mustn't cancel it.
        if (scoresJob?.isActive == true) return
        scoresJob = viewModelScope.launch {
            while (true) {
                delay(60_000)
                if (!onScreen) continue
                refreshIfDue()
                val soon = System.currentTimeMillis() + 15 * 60_000L
                val busy = allGames.any { it.state == GameState.LIVE || (it.state == GameState.UPCOMING && (it.start ?: Long.MAX_VALUE) < soon) }
                if (!busy && System.currentTimeMillis() - lastScores < 290_000) continue
                // Lite mode: no live scores. Today's games are fetched when the app opens, and not again.
                if (!settings.liteNoScores) { lastScores = System.currentTimeMillis(); runCatching { loadScores() } }
                // While something plays, the connection count is checked each minute too.
                if (pinned != null || nowPlaying != null) refreshAccount()
            }
        }
    }

    /**
     * The second source of broadcasters (official NHL, NBA and MLB schedules and the rights table), so a game also
     * lists its Sportsnet, TSN, Sky… channels and their 4K feeds, like the Apple apps. Fetched once per refresh,
     * in the background; the games are matched again when it's in.
     */
    private fun loadBroadcasts() {
        val todays = games.filter { !it.id.startsWith("guide-") }
        if (todays.isEmpty()) return
        broadcastsJob?.cancel()
        broadcastsJob = viewModelScope.launch {
            val found = runCatching { BroadcastSources.fetch(context, todays) }.getOrNull() ?: return@launch
            extraBroadcasts = found
            rematch()
        }
    }

    private suspend fun loadScores() {
        // Hidden sports and leagues are switched off: no scores fetched, nothing matched.
        val (list, logos) = Espn.schedule(activeLeagues())
        allGames = list
        leagueLogos = logos
        // Nothing changed since last minute (same games, same states, only scores ticking): just update the cards.
        val signature = list.joinToString("|") { it.id + it.state.name }
        val unchanged = signature == scheduleSignature && matches.isNotEmpty()
        scheduleSignature = signature
        // Guide-built events (pickleball) stay put until rematch rebuilds them, so their cards don't blink.
        updateGames(visible(list) + games.filter { it.id.startsWith("guide-") })
        if (!unchanged) rematch()
    }

    /**
     * Channel sports (Fighting, pickleball…) come from the guide only, so they don't need today's scores: on reopen
     * they're matched from the saved guide straight away instead of waiting for the scores to download.
     */
    private suspend fun matchGuideSports() {
        val ch = indexed
        val gd = guide
        val measured = measuredQuality
        val now = System.currentTimeMillis()
        val active = activeLeagues().map { it.id }.toSet()
        val (gs, ms) = withContext(background) {
            val extra = mutableListOf<Game>()
            val m = HashMap<String, List<StreamMatch>>()
            for (league in League.all) {
                if (league.path.isNotEmpty() || league.id !in active) continue
                val (g, found) = Matcher.guideEvents(league, ch, gd, measured, now)
                extra += g
                m.putAll(found)
            }
            extra to m
        }
        if (gs.isEmpty()) return
        updateGames(games.filter { !it.id.startsWith("guide-") } + gs)
        matches = matches + ms
    }

    private suspend fun loadGuide(client: XtreamClient) {
        val wanted = channels.mapNotNull { it.epgId.ifEmpty { null } }.toSet()
        if (wanted.isEmpty()) return
        val now = System.currentTimeMillis()
        val job = kotlin.coroutines.coroutineContext[kotlinx.coroutines.Job]
        guideLoading = true
        guideProgress = null
        guideMegabytes = 0
        try {
            runCatching {
                // Last hour to the refresh interval ahead (at least 3 hours, for the guide's two and a half hours on
                // screen) plus 3 hours: only what's needed, light on a 2 GB TV.
                // Three hours past the next download, so the EPG never runs out before it.
                val ahead = (maxOf(settings.refreshHours, 3) + 3) * 3600_000L
                val g = client.guide(wanted, now - 3600_000L, now + ahead) { read, total ->
                    // A stream started: stop reading (the download starts again once it's closed).
                    if (job?.isActive == false) throw java.io.InterruptedIOException("paused")
                    viewModelScope.launch {
                        guideMegabytes = (read / 1_048_576).toInt()
                        guideProgress = if (total > 0) (read.toFloat() / total).coerceIn(0f, 1f) else null
                    }
                }
                guide = g
                updatedAt = System.currentTimeMillis()
                withContext(Dispatchers.IO) { Cache.saveGuide(context, g) }
            }
        } finally {
            guideLoading = false
        }
        if (job?.isActive == false) return
        rematch(timed = true)
    }

    /** `timed`: after a channel or guide download, the time it took goes in the connection log. */
    private suspend fun rematch(timed: Boolean = false) {
        val started = System.nanoTime()
        val g = games
        val ch = indexed
        val gd = guide
        val rec = recent.toSet()
        val extras = extraBroadcasts
        val measured = measuredQuality
        val now = System.currentTimeMillis()
        val active = activeLeagues().map { it.id }.toSet()
        val (found, guideGames) = withContext(background) {
            val m = Matcher.matchAll(g.filter { !it.id.startsWith("guide-") }, ch, gd, measured, rec, now, extras).toMutableMap()
            // Sports with no schedule feed (pickleball): events and channels from the guide.
            val extra = mutableListOf<Game>()
            for (league in League.all) {
                if (league.path.isNotEmpty() || league.id !in active) continue
                val (gs, ms) = Matcher.guideEvents(league, ch, gd, measured, now)
                extra += gs
                m.putAll(ms)
            }
            m to extra
        }
        if (guideGames.isNotEmpty() || games.any { it.id.startsWith("guide-") }) {
            updateGames(visible(allGames) + guideGames)
        }
        matches = found
        if (timed) ConnLog.add("Matched streams to ${g.size} games in ${(System.nanoTime() - started) / 1_000_000} ms")
        withContext(Dispatchers.IO) { Cache.saveMatches(context, found) }
    }

    private fun isAdult(name: String) = name.contains("adult", ignoreCase = true)

    /**
     * A category with "adult" in its name goes into Settings › Hidden the first time it's seen, like one you hid
     * yourself: showing it again there sticks. (Someone who had the old "Adult categories" switch on keeps them.)
     */
    private fun hideNewAdultCategories() {
        val handled = settings.adultHandled.split("\n").filter { it.isNotEmpty() }.toSet()
        val fresh = rawCategories.filter { isAdult(it.name) && it.id !in handled }.map { it.id }
        if (fresh.isEmpty()) return
        if (settings.hideAdult) {
            val hidden = hiddenCategoryIds
            settings.hiddenCategories = (hidden + fresh.filter { it !in hidden }).joinToString("\n")
        }
        settings.adultHandled = (handled + fresh).joinToString("\n")
    }

    /** Hides what's in Settings › Hidden everywhere (called again when it changes). */
    suspend fun applyFilters() {
        hideNewAdultCategories()
        val hiddenCats = hiddenCategoryIds.toSet()
        val hiddenChans = hiddenChannelIds.toSet()
        val cats = rawCategories.filter { it.id !in hiddenCats }
        val kept = cats.map { it.id }.toSet()
        val list = rawChannels.filter { it.categoryId in kept && it.id !in hiddenChans }
        // Hidden groups ("__node:" ids) leave the tree; their categories stay wherever else they're listed.
        fun prune(nodes: List<CategoryGrouping.Node>): List<CategoryGrouping.Node> =
            nodes.filter { it.id !in hiddenCats }.map { if (it.isGroup) it.copy(children = prune(it.children)) else it }
        val tree = withContext(Dispatchers.Default) { prune(CategoryGrouping.build(cats)) }
        categories = cats
        categoryTree = tree
        channels = list
        channelsByCategory = list.groupBy { it.categoryId }
        channelById = list.associateBy { it.id }
        indexed = withContext(Dispatchers.Default) { list.map { Matcher.Indexed(it) } }
    }

    fun filtersChanged() {
        viewModelScope.launch { applyFilters(); rematch() }
    }

    private fun visible(list: List<Game>): List<Game> {
        val hidden = settings.hiddenLeagueSet
        return list.filter { it.league.id !in hidden }
    }

    fun leagueFilterChanged() {
        updateGames(visible(allGames))
        viewModelScope.launch { rematch() }
    }

    fun recordQuality(channelId: Int, label: String) {
        if (label.isEmpty() || measuredQuality[channelId] == label) return
        measuredQuality = measuredQuality + (channelId to label)
        // Shown on the stream straight away; the order catches up at the next rematch.
    }

    /** Each channel's HDR kind ("HDR10", "HLG", "Dolby Vision"), once it has played; shown with its other tags. */
    var measuredHdr by mutableStateOf<Map<Int, String>>(emptyMap())

    fun recordHdr(channelId: Int, label: String) {
        if (label.isEmpty() || measuredHdr[channelId] == label) return
        measuredHdr = measuredHdr + (channelId to label)
    }

    fun recordAudio(channelId: Int, label: String) {
        if (label.isEmpty() || measuredAudio[channelId] == label) return
        measuredAudio = measuredAudio + (channelId to label)
    }

    fun recordFrameRate(channelId: Int, fps: Float) {
        if (fps <= 0f || measuredFrameRate[channelId] == fps) return
        measuredFrameRate = measuredFrameRate + (channelId to fps)
    }

    // MARK: Lists

    fun games(sport: Sport): List<Game> = home.bySport[sport] ?: emptyList()

    fun gamesIn(leagueId: String): List<Game> = home.byLeague[leagueId] ?: emptyList()

    /** A sport's leagues that are switched on. */
    fun leagues(sport: Sport): List<League> {
        val hidden = settings.hiddenLeagueSet
        return sport.leagues.filter { it.id !in hidden }
    }

    /** Favourites first, then sports with live games, then upcoming, then finished-only, then none; no hidden ones. */
    fun orderedSports(): List<Sport> = home.sports

    /** The leagues that are switched on (not hidden, and their sport not hidden). */
    fun activeLeagues(): List<League> {
        val sports = settings.hiddenSportSet
        val leagues = settings.hiddenLeagueSet
        return League.all.filter { it.sport !in sports && it.id !in leagues }
    }

    /** Hide (switch off) or show a sport: nothing is fetched or matched for it while hidden. */
    fun setSportHidden(sport: Sport, hidden: Boolean) {
        settings.setHidden(sport, hidden)
        scheduleSignature = ""
        viewModelScope.launch { runCatching { loadScores() } }
    }

    fun setLeagueHidden(id: String, hidden: Boolean) {
        settings.setLeagueHidden(id, hidden)
        scheduleSignature = ""
        viewModelScope.launch { runCatching { loadScores() } }
    }

    fun pinnedIsFrom(gameId: String): Boolean {
        val id = pinned?.channel?.id ?: return false
        return streams(gameId).any { it.channel.id == id }
    }

    /** The streams shown on a game's card: local stations and guesses left out, unless that's all there is. */
    private var redZoneFor: List<Channel>? = null
    private var redZoneList: List<Channel> = emptyList()

    /** NFL RedZone channels (their name says RedZone or Red Zone), worked out once per channel list. */
    fun redZoneChannels(): List<Channel> {
        val all = channels
        if (redZoneFor !== all) {
            redZoneFor = all
            redZoneList = all.filter { val n = it.name.lowercase(); "redzone" in n || "red zone" in n }
        }
        return redZoneList
    }

    /**
     * NFL RedZone as a game (2.41): while an NFL game is live, Home shows it as a card that opens a game screen with
     * its channels grouped like any game's streams (4K, USA, Canada…). It isn't in `games`; [game] finds it.
     */
    fun redZoneGame(): Game? {
        val n = redZoneChannels().size
        if (n == 0) return null
        val nfl = League.all.firstOrNull { it.id == "nfl" } ?: return null
        return Game(REDZONE_ID, nfl, null, GameState.LIVE, "Live", Team.none, Team.none, emptyList(), isEvent = true,
            eventTitle = "NFL RedZone", eventDetail = if (n == 1) "1 channel" else "$n channels")
    }

    /** A game by id: today's games, or RedZone. */
    fun game(id: String): Game? = games.firstOrNull { it.id == id } ?: if (id == REDZONE_ID) redZoneGame() else null

    private var redZoneMatchesFor: List<Channel>? = null
    private var redZoneMatchList: List<StreamMatch> = emptyList()

    /** The RedZone channels as streams (quality from the name, or as measured). */
    private fun redZoneMatches(): List<StreamMatch> {
        val rz = redZoneChannels()
        if (redZoneMatchesFor !== rz) {
            redZoneMatchesFor = rz
            redZoneMatchList = rz.map { ch ->
                val q = measuredQuality[ch.id]?.let { it to when (it) { "4K" -> 4; "1080p" -> 3; "720p", "HD" -> 2; else -> 1 } }
                    ?: Matcher.quality(Matcher.Indexed(ch).tokenSet)
                StreamMatch(ch, "RedZone channel", 3, q.first, q.second, false, false, false, Matcher.country(ch))
            }.sortedByDescending { it.qualityRank }
        }
        return redZoneMatchList
    }

    fun mainStreams(gameId: String): List<StreamMatch> = if (gameId == REDZONE_ID) redZoneMatches() else home.main[gameId] ?: run {
        val all = matches[gameId] ?: emptyList()
        all.filter { !it.hidden }.ifEmpty { all }
    }

    /** What's on a channel now and next. */
    class NowNext(val now: Programme?, val next: Programme?, internal val list: List<Programme>?, internal val from: Long, internal val until: Long)

    private val nowNextCache = HashMap<String, NowNext>()

    /**
     * What's on now and next, for the EPG rows: worked out once per programme and kept until it ends (or the guide
     * is downloaded again), instead of searching the channel's whole guide for every row each time it's drawn.
     */
    fun nowNext(channel: Channel): NowNext {
        val list = guide[channel.epgId]
        val t = System.currentTimeMillis()
        nowNextCache[channel.epgId]?.let { if (it.list === list && t >= it.from && t < it.until) return it }
        val now = list?.on(t)
        val next = now?.let { n -> list.getOrNull(list.firstStartingAtOrAfter(n.end)) }
        val until = now?.end ?: list?.let { it.getOrNull(it.firstStartingAtOrAfter(t + 1))?.start } ?: Long.MAX_VALUE
        return NowNext(now, next, list, now?.start ?: t, until).also { nowNextCache[channel.epgId] = it }
    }

    fun currentProgramme(channel: Channel, at: Long = System.currentTimeMillis()): Programme? =
        guide[channel.epgId]?.on(at)

    fun playerTitle(item: NowPlaying): String =
        item.gameTitle ?: currentProgramme(item.channel)?.title?.ifEmpty { null } ?: item.channel.name

    /** The streams for a game screen, with SD left out when better ones exist. */
    fun streams(gameId: String): List<StreamMatch> = if (gameId == REDZONE_ID) redZoneMatches() else matches[gameId] ?: emptyList()

    // MARK: Playing

    private fun urls(channel: Channel): Pair<String, String>? {
        val c = XtreamClient(credentials ?: return null)
        val ts = c.streamUrl(channel, hls = false)
        val hls = c.streamUrl(channel, hls = true)
        return if (settings.preferHls) hls to ts else ts to hls
    }

    /**
     * Streams watched before the current one, most recent first (2.4): full screen shows them along the bottom so you
     * can flip back. A stream only counts once it has played for 5 seconds (flipping past one doesn't).
     */
    val watched = androidx.compose.runtime.mutableStateListOf<NowPlaying>()
    private var watching: NowPlaying? = null
    private var watchingSince = 0L

    private fun noteWatching(item: NowPlaying) {
        val now = System.currentTimeMillis()
        val previous = watching
        watching = item
        if (previous?.channel?.id == item.channel.id) return
        if (previous != null && now - watchingSince >= 5000) {
            watched.removeAll { it.channel.id == previous.channel.id }
            watched.add(0, previous)
            while (watched.size > 8) watched.removeAt(watched.size - 1)
        }
        watchingSince = now
    }

    fun clearWatched() { watched.clear() }

    /** The streams to offer while watching [item]: the ones watched before it, most recent first. */
    fun recentStreams(item: NowPlaying, limit: Int = 6): List<NowPlaying> =
        watched.filter { it.channel.id != item.channel.id }.take(limit)

    /** Opens a stream here, or on the Chromecast while one is connected (phone app; the phone's player then stops). */
    private fun startStream(item: NowPlaying) {
        val (ts, hls) = urls(item.channel) ?: return
        // Built-in VPN switched on but not connected: the provider isn't contacted (it would see your own address).
        if (Vpn.blocked) {
            Playback.stop()
            notice = "The VPN isn't connected, so the stream didn't start. Check Settings › VPN."
            return
        }
        pauseDownloads()
        if (Cast.connected) {
            Playback.stop()
            Cast.load(XtreamClient(credentials ?: return).streamUrl(item.channel, hls = true), playerTitle(item),
                item.channel.name, item.channel.icon)
        } else Playback.play(ts, hls)
        checkAccountSoon()
    }

    /** A Chromecast connected or disconnected: move what's playing there, or back to the phone. */
    fun castChanged() {
        val current = nowPlaying ?: pinned ?: return
        when {
            Cast.connected -> startStream(current)
            onScreen -> startStream(current)
            else -> { Playback.stop(); nowPlaying = null; pinned = null }
        }
    }

    /** Plays in the player at the top. */
    fun pin(channel: Channel, gameTitle: String? = null, lineup: List<Channel> = emptyList()) {
        // Lite mode has no player in the corner: a channel goes straight to full screen.
        if (settings.liteNoCorner) {
            play(channel, gameTitle, lineup, from = when {
                tab == Tab.EPG -> "epg"
                tab == Tab.HOME && openGameId != null -> "game"
                else -> "home"
            })
            return
        }
        recent.add(channel.id)
        pinned = NowPlaying(channel, gameTitle, lineup.ifEmpty { listOf(channel) })
        noteWatching(pinned!!)
        startStream(pinned!!)
    }

    /** Full screen. */
    fun play(channel: Channel, gameTitle: String? = null, lineup: List<Channel> = emptyList(), from: String = fullScreenFrom) {
        recent.add(channel.id)
        fullScreenFrom = from
        val item = NowPlaying(channel, gameTitle, lineup.ifEmpty { listOf(channel) })
        nowPlaying = item
        noteWatching(item)
        startStream(item)
    }

    /** Leaving full screen: the stream carries on in the player at the top. */
    fun closePlayer() {
        val closing = nowPlaying ?: return
        lastPlayedChannelId = closing.channel.id
        nowPlaying = null
        if (settings.liteNoCorner) {
            // Lite mode: no player in the corner, so leaving full screen stops the stream (and frees the connection).
            Playback.stop()
            Cast.stopMedia()
            pinned = null
            checkAccountSoon()
        } else pinned = closing
    }

    fun stopPinned() {
        Playback.stop()
        Cast.stopMedia()
        pinned = null
        checkAccountSoon()
    }

    fun step(delta: Int) {
        val current = nowPlaying ?: return
        if (current.lineup.size < 2) return
        val i = current.lineup.indexOfFirst { it.id == current.channel.id }.coerceAtLeast(0)
        val n = current.lineup.size
        val next = current.lineup[((i + delta) % n + n) % n]
        play(next, current.gameTitle, current.lineup)
    }

    fun stepPinned(delta: Int) {
        val current = pinned ?: return
        if (current.lineup.size < 2) return
        val i = current.lineup.indexOfFirst { it.id == current.channel.id }.coerceAtLeast(0)
        val n = current.lineup.size
        pin(current.lineup[((i + delta) % n + n) % n], current.gameTitle, current.lineup)
    }

    /** The stream kept freezing even after restarting it: say so and move on to the next one. */
    fun skipFrozenStream() {
        val current = nowPlaying ?: pinned ?: return
        if (current.lineup.size < 2) {
            notice = "${current.channel.name} keeps freezing. Try another channel."
            return
        }
        if (nowPlaying != null) step(1) else stepPinned(1)
        notice = "${current.channel.name} kept freezing, so this is the next stream"
    }

    // MARK: Multiview (2.30, Android TV)

    /** A multiview tile: what it plays, and the game it's for (null for a channel with no game). */
    class Tile(val item: NowPlaying, val gameId: String?)

    var multiview by mutableStateOf(false)
        private set
    var tiles by mutableStateOf<List<Tile>>(emptyList())
        private set
    /** The tile you hear; the other is muted. */
    var soundTile by mutableStateOf(0)
        private set
    /** The big tile (layout `big`), or null for two the same size side by side (`equal`). */
    var bigTile by mutableStateOf<Int?>(null)
        private set
    /** Where tile 1's video sits on screen (the shell draws the one main video view there). */
    var tileBounds by mutableStateOf<androidx.compose.ui.geometry.Rect?>(null)
    private var multiviewChecking = false
    /** Streams you picked by hand for a game: they come first for that game for the rest of the session. */
    private val pickedForGame = HashMap<String, Int>()
    private val tileFallback = arrayOfNulls<Job>(2)

    /** "Watch alongside" is offered: a stream plays, multiview is on in Settings, and this is a TV. */
    val canWatchAlongside: Boolean
        get() = Device.tv && settings.multiview && !multiview && !Cast.connected && (pinned != null || nowPlaying != null)

    /**
     * A game's streams for multiview, best first: no 4K, no local stations or guesses, nothing the other tile plays;
     * then reliability (green, amber, no rating, red), quality (1080p, 720p, SD), favourites, English before Foreign,
     * and the game screen's order. A stream you picked by hand for this game comes first.
     */
    fun multiviewCandidates(gameId: String, avoid: Int?): List<StreamMatch> {
        val game = game(gameId) ?: return emptyList()
        val all = streams(gameId).let { l -> if (settings.hideSD) l.filter { it.quality != "SD" } else l }
        val listing = StreamSections.build(all, game.league, measured = measuredQuality, fps = measuredFrameRate,
            hdr = measuredHdr, audio = measuredAudio)
        val english = listing.sections.flatMap { it.streams }
        val foreignIds = listing.foreign.flatMap { it.streams }.map { it.channel.id }.toSet()
        val ordered = (english + listing.foreign.flatMap { it.streams }).distinctBy { it.channel.id }
        val favs = favoriteChannelIds.toSet()
        val picked = pickedForGame[gameId]
        fun rel(m: StreamMatch) = when (StreamStats.ratings[m.channel.id]) {
            StreamStats.Rating.GOOD -> 0; StreamStats.Rating.OK -> 1; null -> 2; StreamStats.Rating.POOR -> 3
        }
        // Lite devices (Chromecast, Google TV sets) struggle to decode two 1080p streams: 720p first, then SD, then 1080p.
        fun light(rank: Int) = if (!settings.slowDevice) rank else when (rank) { 2 -> 3; 1 -> 2; 3 -> 1; else -> rank }
        return ordered.withIndex()
            .filter { (_, m) -> !isUhd(m) && !m.hidden && m.channel.id != avoid }
            .sortedWith(compareBy<IndexedValue<StreamMatch>> { if (it.value.channel.id == picked) 0 else 1 }
                .thenBy { rel(it.value) }
                .thenByDescending { light(StreamSections.qualityRank(it.value, measuredQuality)) }
                .thenBy { if (it.value.channel.id in favs) 0 else 1 }
                .thenBy { if (it.value.channel.id in foreignIds) 1 else 0 }
                .thenBy { it.index })
            .map { it.value }
    }

    /** The streams a tile's panel lists for its game (the game screen's order, 4K left out). */
    fun tileStreams(gameId: String): List<StreamMatch> {
        val game = game(gameId) ?: return emptyList()
        val all = streams(gameId).let { l -> if (settings.hideSD) l.filter { it.quality != "SD" } else l }
        val listing = StreamSections.build(all, game.league, measured = measuredQuality, fps = measuredFrameRate,
            hdr = measuredHdr, audio = measuredAudio)
        return (listing.sections.flatMap { it.streams } + listing.foreign.flatMap { it.streams } + listing.extras)
            .distinctBy { it.channel.id }.filter { !isUhd(it) }
    }

    private fun isUhd(m: StreamMatch) = m.is4K || m.quality == "4K" || measuredQuality[m.channel.id] == "4K" ||
        Categories.isUHD(m.channel.name) || Categories.isUHD(m.channel.categoryName)

    /** The game a playing stream belongs to: the open game screen's, else a game listing that channel. */
    private fun gameIdFor(item: NowPlaying): String? {
        val id = item.channel.id
        openGameId?.takeIf { g -> streams(g).any { it.channel.id == id } }?.let { return it }
        return games.filter { g -> matches[g.id].orEmpty().any { it.channel.id == id } }
            .sortedBy { if (it.title == item.gameTitle) 0 else if (it.state == GameState.LIVE) 1 else 2 }
            .firstOrNull()?.id
    }

    /**
     * Hold select › Watch alongside: multiview with the stream playing now as tile 1 and this game's stream as tile 2
     * (`pick`, or the best one for it). The provider's count is checked first: there must be a free connection.
     */
    /** Hold select on an EPG channel (2.41): this channel beside the stream playing (no game). */
    fun watchChannelAlongside(ch: Channel) {
        if (!canWatchAlongside) { notice = "Start a stream first, then hold a channel to watch it alongside"; return }
        if (ch.id == pinned?.channel?.id) { notice = "${ch.name} is already playing"; return }
        watchAlongside(null, StreamMatch(ch, "EPG", 0, "", 0, false, false, false, null))
    }

    fun watchAlongside(gameId: String?, pick: StreamMatch? = null) {
        if (multiview || multiviewChecking || nowPlaying == null && pinned == null) return
        val creds = credentials ?: return
        if (Vpn.blocked) { notice = "The VPN isn't connected. Check Settings › VPN."; return }
        multiviewChecking = true
        viewModelScope.launch {
            try {
                val info = runCatching { XtreamClient(creds).login() }.getOrNull()
                if (info != null) account = info
                val max = info?.maxConnections ?: 0
                val active = info?.activeConnections ?: max
                ConnLog.add("Multiview: provider says $active/$max in use")
                // Our own stream is already counted in active.
                if (max < 2 || max - active < 1) { notice = "No free connection for multiview"; return@launch }
                val first = nowPlaying ?: pinned ?: return@launch
                val candidates = if (pick != null) listOf(pick) else multiviewCandidates(gameId ?: return@launch, avoid = first.channel.id)
                val second = candidates.firstOrNull() ?: run { notice = "No other stream for this game"; return@launch }
                if (nowPlaying != null) { lastPlayedChannelId = first.channel.id; nowPlaying = null }
                pinned = first
                tiles = listOf(Tile(first, gameIdFor(first)), Tile(NowPlaying(second.channel, null, emptyList()), gameId))
                soundTile = 0
                bigTile = null
                multiview = true
                Playback.player.volume = 1f
                tile2.setVolume(0f)
                setTile(1, second, gameId, auto = pick == null, rest = candidates.drop(1))
                // Lite devices: a 1080p tile 1 moves to a 720p stream of the same game, if there is one (closed first).
                if (settings.slowDevice) gameIdFor(first)?.let { g ->
                    val current = streams(g).firstOrNull { it.channel.id == first.channel.id } ?: return@let
                    if (StreamSections.qualityRank(current, measuredQuality) < 3) return@let
                    val lighter = multiviewCandidates(g, avoid = second.channel.id)
                        .firstOrNull { StreamSections.qualityRank(it, measuredQuality) == 2 } ?: return@let
                    ConnLog.add("Multiview: tile 1 to a 720p stream (${lighter.channel.name}) on this device")
                    Playback.stop()
                    delay(1000)
                    if (multiview) setTile(0, lighter, g, auto = false, rest = emptyList())
                }
            } finally {
                multiviewChecking = false
            }
        }
    }

    private fun lineupFor(gameId: String?, channel: Channel): List<Channel> =
        gameId?.let { g -> tileStreams(g).map { it.channel } }?.takeIf { l -> l.any { it.id == channel.id } } ?: listOf(channel)

    /**
     * Puts a stream in a tile: the old one is closed first, then the new one opened (never more than two at once).
     * `auto`: picked by the app, so if it shows no picture within 7 s (or fails first) the next of `rest` is tried, once.
     */
    private fun setTile(i: Int, m: StreamMatch, gameId: String?, auto: Boolean, rest: List<StreamMatch>) {
        val creds = credentials ?: return
        val game = gameId?.let { g -> game(g) }
        val item = NowPlaying(m.channel, game?.title, lineupFor(gameId, m.channel))
        tiles = tiles.mapIndexed { j, t -> if (j == i) Tile(item, gameId) else t }
        recent.add(m.channel.id)
        tileFallback[i]?.cancel()
        pauseDownloads()
        if (i == 0) {
            pinned = item
            noteWatching(item)
            // TS only in multiview: the HLS fallback could overlap with the other tile's connection.
            Playback.play(XtreamClient(creds).streamUrl(m.channel, hls = false), null)
        } else {
            tile2.open(XtreamClient(creds).streamUrl(m.channel, hls = false), m.channel.name)
        }
        checkAccountSoon()
        val next = rest.firstOrNull() ?: return
        if (!auto) return
        tileFallback[i] = viewModelScope.launch {
            val started = System.currentTimeMillis()
            while (true) {
                delay(500)
                val picture = if (i == 0) Playback.hasPicture else tile2.hasPicture
                if (picture) return@launch
                val failed = (if (i == 0) Playback.status else tile2.status) == Playback.Status.FAILED
                if (failed || System.currentTimeMillis() - started >= 7000) break
            }
            if (!multiview) return@launch
            ConnLog.add("Multiview: no picture on tile ${i + 1}, trying the next stream")
            if (i == 0) Playback.stop() else tile2.close()
            delay(1000)
            if (multiview) setTile(i, next, gameId, auto = false, rest = emptyList())
        }
    }

    /** Streams list in a tile's panel: the stream you picked, which then comes first for this game this session. */
    fun swapTile(i: Int, m: StreamMatch, gameId: String) {
        if (!multiview || tiles.getOrNull(i)?.item?.channel?.id == m.channel.id) return
        if (tiles.getOrNull(1 - i)?.item?.channel?.id == m.channel.id) { notice = "The other tile is playing that stream"; return }
        pickedForGame[gameId] = m.channel.id
        setTile(i, m, gameId, auto = false, rest = emptyList())
    }

    /** Pick another game… in a tile's panel: its best stream (with the same one-time fallback). */
    fun swapTileToGame(i: Int, gameId: String) {
        if (!multiview) return
        val candidates = multiviewCandidates(gameId, avoid = tiles.getOrNull(1 - i)?.item?.channel?.id)
        val first = candidates.firstOrNull() ?: run { notice = "No stream found for that game"; return }
        setTile(i, first, gameId, auto = true, rest = candidates.drop(1))
    }

    /** Select on a tile: the sound moves there; with "Make big", it also becomes the big tile (again: back to equal). */
    fun tileSelected(i: Int) {
        if (settings.multiviewMakeBig) bigTile = if (soundTile == i && bigTile == i) null else i
        soundTile = i
        Playback.player.volume = if (i == 0) 1f else 0f
        tile2.setVolume(if (i == 1) 1f else 0f)
    }

    /**
     * Back (or Remove tile on the other one): the tile `keep` carries on as the normal single stream in full screen,
     * and the other tile's stream is stopped. Tile 2 kept: its stream is closed and reopened in the main player
     * (closing first, so it never counts as more than two).
     */
    fun leaveMultiview(keep: Int = soundTile) {
        if (!multiview) return
        val kept = tiles.getOrNull(keep)?.item
        tileFallback.forEach { it?.cancel() }
        multiview = false
        tiles = emptyList()
        bigTile = null
        soundTile = 0
        tileBounds = null
        Playback.player.volume = 1f
        tile2.close()
        val item = kept ?: pinned ?: return
        if (keep != 0) Playback.stop()
        pinned = item
        play(item.channel, item.gameTitle, item.lineup, from = "strip")
        checkAccountSoon()
    }

    /** Leaving the app or signing out: tile 2 stops (the main player is stopped by the caller). */
    fun stopMultiview() {
        tileFallback.forEach { it?.cancel() }
        tile2.close()
        multiview = false
        tiles = emptyList()
        bigTile = null
        soundTile = 0
        tileBounds = null
        Playback.player.volume = 1f
    }
}
