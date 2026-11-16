package ca.sunny9781.courtside

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
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

    var credentials by mutableStateOf(Prefs.loadCredentials(app))
        private set
    var account by mutableStateOf<AccountInfo?>(null)
        private set
    var categories by mutableStateOf<List<ChannelCategory>>(emptyList())
        private set
    var channels by mutableStateOf<List<Channel>>(emptyList())
        private set
    var games by mutableStateOf<List<Game>>(emptyList())
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
    var homeSelection by mutableStateOf<HomeSelection>(HomeSelection.LiveNow)
    /** The game screen that's open on Home, if any. */
    var openGameId by mutableStateOf<String?>(null)

    /** In the player at the top. */
    var pinned by mutableStateOf<NowPlaying?>(null)
    /** Full screen. */
    var nowPlaying by mutableStateOf<NowPlaying?>(null)
        private set
    var lastPlayedChannelId by mutableStateOf<Int?>(null)
        private set
    var notice by mutableStateOf<String?>(null)

    private var indexed: List<Matcher.Indexed> = emptyList()
    private val recent = LinkedHashSet<Int>()
    private var scoresJob: Job? = null

    init {
        Playback.init(app)
        Playback.onRepeatedFreezing = { skipFrozenStream() }
        if (credentials != null) refresh()
        viewModelScope.launch { Updater.check(app) }
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
        pinned = null
        nowPlaying = null
        credentials = null
        Prefs.saveCredentials(context, null)
        channels = emptyList(); categories = emptyList(); matches = emptyMap(); guide = emptyMap(); account = null
    }

    // MARK: Loading

    fun refresh() {
        val creds = credentials ?: return
        viewModelScope.launch {
            loading = true
            error = null
            try {
                val client = XtreamClient(creds)
                runCatching { account = client.login() }
                val (cats, chans) = client.live()
                categories = cats
                channels = chans
                indexed = withContext(Dispatchers.Default) { chans.map { Matcher.Indexed(it) } }
                loadScores()
                updatedAt = System.currentTimeMillis()
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
            }
        }
    }

    private suspend fun loadScores() {
        val (list, logos) = Espn.schedule(League.all)
        games = list
        leagueLogos = logos
        rematch()
    }

    private suspend fun loadGuide(client: XtreamClient) {
        val wanted = channels.mapNotNull { it.epgId.ifEmpty { null } }.toSet()
        if (wanted.isEmpty()) return
        val now = System.currentTimeMillis()
        runCatching { guide = client.guide(wanted, now - 3 * 3600_000L, now + 12 * 3600_000L) }
        rematch()
    }

    private suspend fun rematch() {
        val g = games
        val ch = indexed
        val gd = guide
        val rec = recent.toSet()
        matches = withContext(Dispatchers.Default) {
            Matcher.matchAll(g, ch, gd, emptyMap(), rec, System.currentTimeMillis())
        }
    }

    // MARK: Lists

    fun games(sport: Sport) = games.filter { it.league.sport == sport }

    fun currentProgramme(channel: Channel, at: Long = System.currentTimeMillis()): Programme? =
        guide[channel.epgId]?.firstOrNull { it.start <= at && it.end > at }

    fun playerTitle(item: NowPlaying): String =
        item.gameTitle ?: currentProgramme(item.channel)?.title?.ifEmpty { null } ?: item.channel.name

    /** The streams for a game screen, with SD left out when better ones exist. */
    fun streams(gameId: String): List<StreamMatch> = matches[gameId] ?: emptyList()

    // MARK: Playing

    private fun urls(channel: Channel): Pair<String, String>? {
        val c = XtreamClient(credentials ?: return null)
        return c.streamUrl(channel, hls = false) to c.streamUrl(channel, hls = true)
    }

    /** Plays in the player at the top. */
    fun pin(channel: Channel, gameTitle: String? = null, lineup: List<Channel> = emptyList()) {
        recent.add(channel.id)
        pinned = NowPlaying(channel, gameTitle, lineup.ifEmpty { listOf(channel) })
        val (ts, hls) = urls(channel) ?: return
        Playback.play(ts, hls)
    }

    /** Full screen. */
    fun play(channel: Channel, gameTitle: String? = null, lineup: List<Channel> = emptyList()) {
        recent.add(channel.id)
        val item = NowPlaying(channel, gameTitle, lineup.ifEmpty { listOf(channel) })
        nowPlaying = item
        val (ts, hls) = urls(channel) ?: return
        Playback.play(ts, hls)
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
