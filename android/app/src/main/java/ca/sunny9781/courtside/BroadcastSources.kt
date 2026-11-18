package ca.sunny9781.courtside

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/**
 * A network carrying a game, with the country it airs in when known.
 * Confirmed = from an official league schedule; otherwise it's a "usually on" guess from the rights table.
 */
data class Broadcast(val name: String, val country: String?, val confirmed: Boolean)

/**
 * Second source of broadcasters beyond ESPN's (mostly US) list: official NHL, NBA and MLB schedules, plus a table
 * of who holds the rights in Canada, the UK and Europe. Same as the Apple apps' BroadcastSources.swift.
 */
object BroadcastSources {
    suspend fun fetch(context: Context, games: List<Game>, now: Long = System.currentTimeMillis()): Map<String, List<Broadcast>> =
        withContext(Dispatchers.IO) {
            val out = HashMap<String, List<Broadcast>>()
            for (game in games) {
                val likely = RightsTable.likely(game)
                if (likely.isNotEmpty()) out[game.id] = likely
            }
            val confirmed = coroutineScope {
                val nhl = async { runCatching { nhl(games.filter { it.league.id == "nhl" }, now) }.getOrDefault(emptyMap()) }
                val nba = async { runCatching { nba(context, games.filter { it.league.id == "nba" }) }.getOrDefault(emptyMap()) }
                val mlb = async { runCatching { mlb(games.filter { it.league.id == "mlb" }, now) }.getOrDefault(emptyMap()) }
                val all = HashMap<String, MutableList<Broadcast>>()
                for (part in listOf(nhl.await(), nba.await(), mlb.await())) {
                    for ((id, list) in part) all.getOrPut(id) { mutableListOf() }.addAll(list)
                }
                all
            }
            // Confirmed entries replace a "usually on" guess for the same network.
            for ((id, list) in confirmed) {
                val names = list.map { it.name.lowercase() }.toSet()
                out[id] = list + (out[id] ?: emptyList()).filter { it.name.lowercase() !in names }
            }
            out
        }

    // NHL (api-web.nhle.com)

    private val nhlNames = mapOf(
        "SN" to "Sportsnet", "SN1" to "Sportsnet One", "SNE" to "Sportsnet East", "SNO" to "Sportsnet Ontario",
        "SNP" to "Sportsnet Pacific", "SNW" to "Sportsnet West", "SN+" to "Sportsnet+", "SN360" to "Sportsnet 360",
        "TVAS" to "TVA Sports", "TVAS2" to "TVA Sports 2", "Prime" to "Prime Video", "NHLN" to "NHL Network"
    )

    private fun nhl(games: List<Game>, now: Long): Map<String, List<Broadcast>> {
        if (games.isEmpty()) return emptyMap()
        val json = getJson("https://api-web.nhle.com/v1/schedule/${sportsDay(now)}") ?: return emptyMap()
        val out = HashMap<String, MutableList<Broadcast>>()
        for (item in collect(json) { it.has("tvBroadcasts") }) {
            val home = item.optJSONObject("homeTeam")?.optJSONObject("commonName")?.optString("default").orEmpty()
            val away = item.optJSONObject("awayTeam")?.optJSONObject("commonName")?.optString("default").orEmpty()
            val game = find(games, home, away, date(item.opt("startTimeUTC"))) ?: continue
            val tvs = item.optJSONArray("tvBroadcasts") ?: continue
            for (i in 0 until tvs.length()) {
                val tv = tvs.optJSONObject(i) ?: continue
                val code = tv.optString("network").trim()
                if (code.isEmpty()) continue
                val country = tv.optString("countryCode").takeIf { it.isNotEmpty() }
                    ?.let { if (it == "CA") "Canada" else if (it == "US") "USA" else it }
                out.getOrPut(game.id) { mutableListOf() } += Broadcast(nhlNames[code] ?: code, country, true)
            }
        }
        return out
    }

    // NBA (cdn.nba.com season schedule, kept for 12 hours because it's large)

    private val nbaKeys = listOf(
        "nationalTvBroadcasters", "nationalBroadcasters", "homeTvBroadcasters", "awayTvBroadcasters",
        "intlTvBroadcasters", "nationalOttBroadcasters", "homeOttBroadcasters", "awayOttBroadcasters",
        "intlOttBroadcasters"
    )

    private fun nba(context: Context, games: List<Game>): Map<String, List<Broadcast>> {
        if (games.isEmpty()) return emptyMap()
        val json = nbaSchedule(context, games) ?: return emptyMap()
        val out = HashMap<String, MutableList<Broadcast>>()
        for (item in collect(json) { it.has("gameId") && it.has("broadcasters") }) {
            val home = item.optJSONObject("homeTeam")?.optString("teamName").orEmpty()
            val away = item.optJSONObject("awayTeam")?.optString("teamName").orEmpty()
            val game = find(games, home, away, date(item.opt("gameDateTimeUTC"))) ?: continue
            val b = item.optJSONObject("broadcasters") ?: continue
            val seen = HashSet<String>()
            for (key in nbaKeys) {
                val list = b.optJSONArray(key) ?: continue
                for (i in 0 until list.length()) {
                    val entry = list.optJSONObject(i) ?: continue
                    val name = entry.optString("broadcasterDisplay").ifEmpty { entry.optString("broadcasterAbbreviation") }
                    if (name.isNotEmpty() && seen.add(name.lowercase())) {
                        out.getOrPut(game.id) { mutableListOf() } += Broadcast(name, null, true)
                    }
                }
            }
        }
        return out
    }

    /**
     * The whole season's schedule is several MB, too much to keep parsed on a 2 GB TV: it's saved to a file and only
     * today's games are kept from it (the parsed tree is let go straight after).
     */
    private fun nbaSchedule(context: Context, games: List<Game>): Any? {
        val file = File(context.cacheDir, "nba-schedule.json")
        val fresh = file.exists() && System.currentTimeMillis() - file.lastModified() < 12 * 3600_000L
        if (!fresh) runCatching {
            val text = get("https://cdn.nba.com/static/json/staticData/scheduleLeagueV2.json")
            if (text != null) {
                val tmp = File(context.cacheDir, "nba-schedule.json.tmp")
                tmp.writeText(text)
                tmp.renameTo(file)
            }
        }
        if (!file.exists()) return null
        // Only the days of today's games: the schedule is split into gameDates, each with its games.
        val days = games.mapNotNull { it.start }.flatMap { listOf(it - 12 * 3600_000L, it, it + 12 * 3600_000L) }
            .map { dayFormat("MM/dd/yyyy", "UTC").format(java.util.Date(it)) }.toSet()
        return runCatching {
            val root = JSONObject(file.readText())
            val dates = root.optJSONObject("leagueSchedule")?.optJSONArray("gameDates") ?: return@runCatching root
            val kept = JSONArray()
            for (i in 0 until dates.length()) {
                val d = dates.optJSONObject(i) ?: continue
                if (days.any { d.optString("gameDate").startsWith(it) }) kept.put(d)
            }
            if (kept.length() == 0) root else kept
        }.getOrNull()
    }

    // MLB (statsapi.mlb.com)

    private fun mlb(games: List<Game>, now: Long): Map<String, List<Broadcast>> {
        if (games.isEmpty()) return emptyMap()
        val json = getJson("https://statsapi.mlb.com/api/v1/schedule?sportId=1&date=${sportsDay(now)}&hydrate=broadcasts(all)")
            ?: return emptyMap()
        val out = HashMap<String, MutableList<Broadcast>>()
        for (item in collect(json) { it.has("gamePk") && it.has("teams") }) {
            val teams = item.optJSONObject("teams")
            val home = teams?.optJSONObject("home")?.optJSONObject("team")?.optString("name").orEmpty()
            val away = teams?.optJSONObject("away")?.optJSONObject("team")?.optString("name").orEmpty()
            val game = find(games, home, away, date(item.opt("gameDate"))) ?: continue
            val list = item.optJSONArray("broadcasts") ?: continue
            val seen = HashSet<String>()
            for (i in 0 until list.length()) {
                val b = list.optJSONObject(i) ?: continue
                if (!b.optString("type").equals("TV", ignoreCase = true)) continue
                val name = b.optString("name")
                if (name.isNotEmpty() && seen.add(name.lowercase())) {
                    out.getOrPut(game.id) { mutableListOf() } += Broadcast(name, null, true)
                }
            }
        }
        return out
    }

    // Helpers

    private fun get(url: String): String? {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 20_000
        }
        return try {
            if (conn.responseCode != 200) null else conn.inputStream.bufferedReader().use { it.readText() }
        } finally {
            conn.disconnect()
        }
    }

    private fun getJson(url: String): Any? = get(url)?.let { text ->
        runCatching { if (text.trimStart().startsWith("[")) JSONArray(text) else JSONObject(text) }.getOrNull()
    }

    /** Every object in the JSON that passes the test, wherever it sits, so small format changes don't break it. */
    private fun collect(json: Any, test: (JSONObject) -> Boolean): List<JSONObject> {
        val out = mutableListOf<JSONObject>()
        fun walk(node: Any?) {
            when (node) {
                is JSONObject -> {
                    if (test(node)) { out += node; return }
                    for (k in node.keys()) walk(node.opt(k))
                }
                is JSONArray -> for (i in 0 until node.length()) walk(node.opt(i))
            }
        }
        walk(json)
        return out
    }

    /** The ESPN game with these two teams, starting within six hours of the other source's time. */
    private fun find(games: List<Game>, home: String, away: String, start: Long?): Game? {
        val h = home.lowercase()
        val a = away.lowercase()
        if (h.isEmpty() || a.isEmpty()) return null
        fun same(team: Team, other: String) = listOf(team.nickname, team.name, team.shortName).map { it.lowercase() }
            .filter { it.isNotEmpty() }.any { it.contains(other) || other.contains(it) }
        return games.firstOrNull { g ->
            if (!same(g.home, h) || !same(g.away, a)) return@firstOrNull false
            val gs = g.start
            if (start != null && gs != null) Math.abs(start - gs) < 6 * 3600_000L else true
        }
    }

    private fun date(value: Any?): Long? {
        val text = value as? String ?: return null
        for (pattern in listOf("yyyy-MM-dd'T'HH:mm:ssX", "yyyy-MM-dd'T'HH:mm:ss.SSSX", "yyyy-MM-dd'T'HH:mmX")) {
            runCatching { return dayFormat(pattern, "UTC").parse(text)?.time }
        }
        return null
    }

    private fun dayFormat(pattern: String, zone: String) =
        SimpleDateFormat(pattern, Locale.US).apply { timeZone = TimeZone.getTimeZone(zone) }

    /** The sports day in Eastern time, ending at 5 AM, same as the ESPN schedule. */
    private fun sportsDay(now: Long): String =
        dayFormat("yyyy-MM-dd", "America/New_York").format(java.util.Date(now - 5 * 3600_000L))
}

/**
 * Who usually carries each league outside the US, for the 2026–27 season. These are guesses ("usually on"), ranked
 * below confirmed broadcasters, and rights change between seasons. Same table as the Apple apps.
 */
object RightsTable {
    private val byLeague: Map<String, List<Pair<String, List<String>>>> = mapOf(
        "nfl" to listOf("Canada" to listOf("TSN", "CTV", "RDS", "DAZN")),
        "epl" to listOf("Canada" to listOf("Fubo"), "UK" to listOf("Sky Sports", "TNT Sports")),
        "ucl" to listOf("Canada" to listOf("DAZN"), "UK" to listOf("TNT Sports", "Amazon Prime")),
        "laliga" to listOf("UK" to listOf("Premier Sports", "LaLiga TV", "Disney+"), "Spain" to listOf("Movistar", "DAZN")),
        "seriea" to listOf("UK" to listOf("TNT Sports", "DAZN"), "Italy" to listOf("DAZN", "Sky Sport")),
        "bundesliga" to listOf("Canada" to listOf("DAZN"), "UK" to listOf("Sky Sports"), "Germany" to listOf("Sky Sport", "DAZN")),
        "ligue1" to listOf("France" to listOf("Ligue 1+", "beIN Sports")),
        "mls" to listOf("Canada" to listOf("TSN"), "All" to listOf("Apple TV", "MLS Season Pass")),
        "f1" to listOf("Canada" to listOf("TSN", "RDS"), "UK" to listOf("Sky Sports F1"), "All" to listOf("F1 TV")),
        "ufc" to listOf("UK" to listOf("TNT Sports"), "All" to listOf("UFC Fight Pass")),
        "atp" to listOf("Canada" to listOf("TSN"), "UK" to listOf("Sky Sports Tennis")),
        "wta" to listOf("Canada" to listOf("TSN"), "UK" to listOf("Sky Sports Tennis")),
        "pga" to listOf("Canada" to listOf("TSN"), "UK" to listOf("Sky Sports Golf")),
        "sixnations" to listOf("UK" to listOf("BBC", "ITV")),
        "premrugby" to listOf("UK" to listOf("TNT Sports"))
    )

    /** Canadian teams whose games are on Canadian networks. */
    private data class TeamRule(val league: String, val team: String, val country: String, val names: List<String>)
    private val teamRights = listOf(
        TeamRule("nba", "raptors", "Canada", listOf("TSN", "Sportsnet")),
        TeamRule("mlb", "blue jays", "Canada", listOf("Sportsnet"))
    )

    fun likely(game: Game): List<Broadcast> {
        val out = mutableListOf<Broadcast>()
        for ((country, names) in byLeague[game.league.id] ?: emptyList()) {
            out += names.map { Broadcast(it, if (country == "All") null else country, false) }
        }
        for (rule in teamRights) {
            if (rule.league != game.league.id) continue
            if (listOf(game.home, game.away).any { it.name.lowercase().contains(rule.team) }) {
                out += rule.names.map { Broadcast(it, rule.country, false) }
            }
        }
        return out
    }
}
