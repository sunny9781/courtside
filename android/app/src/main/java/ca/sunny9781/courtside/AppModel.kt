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
    private var allGames: List<Game> = emptyList()
    private var rawCategories: List<ChannelCategory> = emptyList()
    private var rawChannels: List<Channel> = emptyList()
    /** Resolution and frame rate each channel really played at, which beat what its name says. */
    var measuredQuality by mutableStateOf<Map<Int, String>>(emptyMap())
        private set
    var measuredFrameRate by mutableStateOf<Map<Int, Float>>(emptyMap())
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

    fun closeGame() {
        returnToGame = openGameId
        openGameId = null
    }

    /** In the player at the top. */
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
        viewModelScope.launch { runCatching { account = XtreamClient(creds).login() } }
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
                    if (g.isNotEmpty()) guide = g
                    loadScores()    // matches today's games with the guide already in place
                    if (g.isEmpty()) loadGuide(client)
                    return@launch
                }
                runCatching { account = client.login() }
                val (cats, chans) = client.live()
                rawCategories = cats
                rawChannels = chans
                applyFilters()
                loadScores()
                updatedAt = System.currentTimeMillis()
                withContext(Dispatchers.IO) { Cache.saveLive(context, owner, cats, chans) }
                loadGuide(client)
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
                runCatching { loadScores() }
                // While something plays, the connection count is checked each minute too.
                if (pinned != null || nowPlaying != null) refreshAccount()
            }
        }
    }

    private suspend fun loadScores() {
        val (list, logos) = Espn.schedule(League.all)
        allGames = list
        leagueLogos = logos
        // Nothing changed since last minute (same games, same states, only scores ticking): just update the cards.
        val signature = list.joinToString("|") { it.id + it.state.name }
        val unchanged = signature == scheduleSignature && matches.isNotEmpty()
        scheduleSignature = signature
        // Guide-built events (pickleball) stay put until rematch rebuilds them, so their cards don't blink.
        games = visible(list) + games.filter { it.id.startsWith("guide-") }
        if (!unchanged) rematch()
    }

    private suspend fun loadGuide(client: XtreamClient) {
        val wanted = channels.mapNotNull { it.epgId.ifEmpty { null } }.toSet()
        if (wanted.isEmpty()) return
        val now = System.currentTimeMillis()
        runCatching {
            // Last hour to the next 8: plenty for now/next and today's games, and light on a 2 GB TV.
            val g = client.guide(wanted, now - 3600_000L, now + 8 * 3600_000L)
            guide = g
            withContext(Dispatchers.IO) { Cache.saveGuide(context, g) }
        }
        rematch()
    }

    private suspend fun rematch() {
        val g = games
        val ch = indexed
        val gd = guide
        val rec = recent.toSet()
        val measured = measuredQuality
        val now = System.currentTimeMillis()
        val hidden = settings.hiddenLeagueSet
        val (found, guideGames) = withContext(background) {
            val m = Matcher.matchAll(g.filter { !it.id.startsWith("guide-") }, ch, gd, measured, rec, now).toMutableMap()
            // Sports with no schedule feed (pickleball): events and channels from the guide.
            val extra = mutableListOf<Game>()
            for (league in League.all) {
                if (league.path.isNotEmpty() || league.id in hidden) continue
                val (gs, ms) = Matcher.guideEvents(league, ch, gd, measured, now)
                extra += gs
                m.putAll(ms)
            }
            m to extra
        }
        if (guideGames.isNotEmpty() || games.any { it.id.startsWith("guide-") }) {
            games = visible(allGames) + guideGames
        }
        matches = found
        withContext(Dispatchers.IO) { Cache.saveMatches(context, found) }
    }

    private fun isAdult(name: String) = name.contains("adult", ignoreCase = true)

    /** Hides adult categories and their channels everywhere when that setting is on (called again when it changes). */
    suspend fun applyFilters() {
        val hide = settings.hideAdult
        val cats = if (hide) rawCategories.filter { !isAdult(it.name) } else rawCategories
        val kept = cats.map { it.id }.toSet()
        val list = if (hide) rawChannels.filter { it.categoryId in kept && !isAdult(it.categoryName) } else rawChannels
        val tree = withContext(Dispatchers.Default) { CategoryGrouping.build(cats) }
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
        games = visible(allGames)
        viewModelScope.launch { rematch() }
    }

    fun recordQuality(channelId: Int, label: String) {
        if (label.isEmpty() || measuredQuality[channelId] == label) return
        measuredQuality = measuredQuality + (channelId to label)
        // Shown on the stream straight away; the order catches up at the next rematch.
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

    fun pinnedIsFrom(gameId: String): Boolean {
        val id = pinned?.channel?.id ?: return false
        return (matches[gameId] ?: emptyList()).any { it.channel.id == id }
    }

    /** The streams shown on a game's card: local stations and guesses left out, unless that's all there is. */
    fun mainStreams(gameId: String): List<StreamMatch> = home.main[gameId] ?: run {
        val all = matches[gameId] ?: emptyList()
        all.filter { !it.hidden }.ifEmpty { all }
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
        recent.add(channel.id)
        pinned = NowPlaying(channel, gameTitle, lineup.ifEmpty { listOf(channel) })
        val (ts, hls) = urls(channel) ?: return
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
        Playback.play(ts, hls)
        checkAccountSoon()
    }

    /** Leaving full screen: the stream carries on in the player at the top. */
    fun closePlayer() {
        val closing = nowPlaying ?: return
        lastPlayedChannelId = closing.channel.id
        nowPlaying = null
        pinned = closing
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
