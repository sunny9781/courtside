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
}

class AppModel(app: Application) : AndroidViewModel(app) {
    private val context get() = getApplication<Application>()
    val settings = Settings(app)
    val whatsNew = WhatsNew.load(app)

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
    private val streamOpen get() = Playback.currentUrl != null

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
                Updater.check(app)
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
        Playback.stop()
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
                val maxAge = settings.refreshHours * 3600_000L
                val saved = if (force) null else withContext(Dispatchers.IO) { Cache.loadLive(context) }
                    ?.takeIf { it.server == owner && it.channels.isNotEmpty() && System.currentTimeMillis() - it.savedAt < maxAge }
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
                    if (g.isEmpty()) startGuide(client)
                    return@launch
                }
                runCatching { account = client.login() }
                waitForNoStream()
                val (cats, chans) = client.live()
                rawCategories = cats
                rawChannels = chans
                applyFilters()
                loadScores()
                loadBroadcasts()
                updatedAt = System.currentTimeMillis()
                withContext(Dispatchers.IO) { Cache.saveLive(context, owner, cats, chans) }
                loading = false
                startGuide(client)
            } catch (e: Exception) {
                error = e.message ?: "Couldn't load your channels."
            } finally {
                loading = false
            }
        }
        // Scores every minute.
        scoresJob?.cancel()
        scoresJob = viewModelScope.launch {
            while (true) {
                delay(60_000)
                // Lite mode: no live scores. Today's games are fetched when the app opens, and not again.
                if (!settings.lite) runCatching { loadScores() }
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
                // Last hour to the next 8: plenty for now/next and today's games, and light on a 2 GB TV.
                val g = client.guide(wanted, now - 3600_000L, now + 8 * 3600_000L) { read, total ->
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
        rematch()
    }

    private suspend fun rematch() {
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
        return (matches[gameId] ?: emptyList()).any { it.channel.id == id }
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

    fun mainStreams(gameId: String): List<StreamMatch> = home.main[gameId] ?: run {
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
        val now = list?.firstOrNull { it.start <= t && it.end > t }
        val next = now?.let { n -> list.firstOrNull { it.start >= n.end } }
        val until = now?.end ?: list?.firstOrNull { it.start > t }?.start ?: Long.MAX_VALUE
        return NowNext(now, next, list, now?.start ?: t, until).also { nowNextCache[channel.epgId] = it }
    }

    fun currentProgramme(channel: Channel, at: Long = System.currentTimeMillis()): Programme? =
        guide[channel.epgId]?.firstOrNull { it.start <= at && it.end > at }

    fun playerTitle(item: NowPlaying): String =
        item.gameTitle ?: currentProgramme(item.channel)?.title?.ifEmpty { null } ?: item.channel.name

    /** The streams for a game screen, with SD left out when better ones exist. */
    fun streams(gameId: String): List<StreamMatch> = matches[gameId] ?: emptyList()

    // MARK: Playing

    private fun urls(channel: Channel): Pair<String, String>? {
        val c = XtreamClient(credentials ?: return null)
        val ts = c.streamUrl(channel, hls = false)
        val hls = c.streamUrl(channel, hls = true)
        return if (settings.preferHls) hls to ts else ts to hls
    }

    /** Plays in the player at the top. */
    fun pin(channel: Channel, gameTitle: String? = null, lineup: List<Channel> = emptyList()) {
        // Lite mode has no player in the corner: a channel goes straight to full screen.
        if (settings.lite) {
            play(channel, gameTitle, lineup, from = when {
                tab == Tab.EPG -> "epg"
                tab == Tab.HOME && openGameId != null -> "game"
                else -> "home"
            })
            return
        }
        recent.add(channel.id)
        pinned = NowPlaying(channel, gameTitle, lineup.ifEmpty { listOf(channel) })
        val (ts, hls) = urls(channel) ?: return
        pauseDownloads()
        Playback.play(ts, hls)
        checkAccountSoon()
    }

    /** Full screen. */
    fun play(channel: Channel, gameTitle: String? = null, lineup: List<Channel> = emptyList(), from: String = fullScreenFrom) {
        recent.add(channel.id)
        fullScreenFrom = from
        val item = NowPlaying(channel, gameTitle, lineup.ifEmpty { listOf(channel) })
        nowPlaying = item
        val (ts, hls) = urls(channel) ?: return
        pauseDownloads()
        Playback.play(ts, hls)
        checkAccountSoon()
    }

    /** Leaving full screen: the stream carries on in the player at the top. */
    fun closePlayer() {
        val closing = nowPlaying ?: return
        lastPlayedChannelId = closing.channel.id
        nowPlaying = null
        if (settings.lite) {
            // Lite mode: no player in the corner, so leaving full screen stops the stream (and frees the connection).
            Playback.stop()
            pinned = null
            checkAccountSoon()
        } else pinned = closing
    }

    fun stopPinned() {
        Playback.stop()
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

    private fun stepPinned(delta: Int) {
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
}
