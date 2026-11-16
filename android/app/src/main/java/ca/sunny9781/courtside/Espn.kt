package ca.sunny9781.courtside

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Today's games from ESPN's public scoreboard feed, parsed defensively (the feed is unofficial). */
object Espn {
    private fun fetch(url: String): String {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 20_000
        }
        try {
            return conn.inputStream.bufferedReader().use { it.readText() }
        } finally {
            conn.disconnect()
        }
    }

    /** Every league at once; a league that fails is skipped. Also returns each league's logo. */
    suspend fun schedule(leagues: List<League>, now: Long = System.currentTimeMillis()): Pair<List<Game>, Map<String, String>> =
        coroutineScope {
            val results = leagues.map { league ->
                async(Dispatchers.IO) { runCatching { leagueSchedule(league, now) }.getOrNull()?.let { league.id to it } }
            }.awaitAll().filterNotNull()
            val games = results.flatMap { it.second.first }.sortedBy { it.start ?: Long.MAX_VALUE }
            val logos = results.mapNotNull { (id, r) -> r.second?.let { id to it } }.toMap()
            games to logos
        }

    private fun leagueSchedule(league: League, now: Long): Pair<List<Game>, String?> {
        if (league.path.isEmpty()) return emptyList<Game>() to null
        if (league.id == "cricket") return cricket(league, now)
        // The "sports day" ends at 5 AM Eastern, so late West Coast games still show after midnight.
        val day = SimpleDateFormat("yyyyMMdd", Locale.US).apply { timeZone = TimeZone.getTimeZone("America/New_York") }
            .format(Date(now - 5 * 3600_000L))
        val root = JSONObject(fetch("https://site.api.espn.com/apis/site/v2/sports/${league.path}/scoreboard?dates=$day"))
        val events = root.optJSONArray("events") ?: JSONArray()
        val logos = root.optJSONArray("leagues")?.optJSONObject(0)?.optJSONArray("logos")
        var logo: String? = null
        if (logos != null) {
            for (i in 0 until logos.length()) {
                val l = logos.optJSONObject(i) ?: continue
                val rel = l.optJSONArray("rel")?.toString() ?: ""
                if (logo == null || rel.contains("dark")) logo = l.optString("href").ifEmpty { null } ?: logo
                if (rel.contains("dark")) break
            }
        }
        val games = (0 until events.length()).mapNotNull { i ->
            val e = events.optJSONObject(i) ?: return@mapNotNull null
            runCatching { if (league.isEvent) parseEvent(e, league) else parse(e, league) }.getOrNull()
        }
        return games to logo
    }

    private val majorCricket = Regex(
        "tour of|world cup|champions trophy|premier league|big bash|super league|the hundred|sa20|caribbean|ilt20|major league cricket|test championship|asia cup|super smash",
        RegexOption.IGNORE_CASE
    )

    private fun cricket(league: League, now: Long): Pair<List<Game>, String?> {
        val root = JSONObject(fetch("https://site.api.espn.com/apis/personalized/v2/scoreboard/header?sport=cricket"))
        val sport = root.optJSONArray("sports")?.optJSONObject(0) ?: return emptyList<Game>() to null
        val logo = sport.optJSONArray("logos")?.optJSONObject(0)?.optString("href")
        val games = mutableListOf<Game>()
        val series = sport.optJSONArray("leagues") ?: JSONArray()
        for (s in 0 until series.length()) {
            val ser = series.optJSONObject(s) ?: continue
            val seriesName = ser.optString("name")
            if (!majorCricket.containsMatchIn(seriesName)) continue
            val events = ser.optJSONArray("events") ?: continue
            for (i in 0 until events.length()) {
                val ev = events.optJSONObject(i) ?: continue
                val comps = ev.optJSONArray("competitors") ?: continue
                fun side(which: String): Team? {
                    for (c in 0 until comps.length()) {
                        val o = comps.optJSONObject(c) ?: continue
                        if (o.optString("homeAway") != which) continue
                        val name = o.optString("displayName").ifEmpty { o.optString("name") }
                        if (name.isEmpty()) return null
                        return Team(name, name, name, o.optString("location"), o.optString("abbreviation"),
                            o.flexString("score") ?: "", o.optString("logo").ifEmpty { null })
                    }
                    return null
                }
                val home = side("home") ?: continue
                val away = side("away") ?: continue
                val type = ev.optJSONObject("fullStatus")?.optJSONObject("type")
                val raw = type?.optString("state") ?: "pre"
                val detail = type?.optString("shortDetail")?.ifEmpty { type.optString("description") } ?: ""
                val start = parseDate(ev.optString("date"))
                val state = when (raw) { "in" -> GameState.LIVE; "post" -> GameState.FINISHED; else -> GameState.UPCOMING }
                if (state == GameState.UPCOMING && start != null && start - now > 24 * 3600_000L) continue
                val end = parseDate(ev.optString("endDate")) ?: start
                if (state == GameState.FINISHED && end != null && now - end > 12 * 3600_000L) continue
                games += Game("cricket-${ev.flexString("id") ?: i}", league, start, state,
                    detail.ifEmpty { if (state == GameState.LIVE) "Live" else "" }, away, home, emptyList(), venue = seriesName)
            }
        }
        return games to logo
    }

    private fun timeText(ms: Long): String = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(ms))

    private fun broadcasters(comps: List<JSONObject>): List<String> {
        val names = mutableListOf<String>()
        for (comp in comps) {
            comp.optJSONArray("broadcasts")?.let { b ->
                for (i in 0 until b.length()) {
                    val n = b.optJSONObject(i)?.optJSONArray("names") ?: continue
                    for (j in 0 until n.length()) names += n.optString(j)
                }
            }
            comp.optJSONArray("geoBroadcasts")?.let { g ->
                for (i in 0 until g.length()) {
                    g.optJSONObject(i)?.optJSONObject("media")?.optString("shortName")?.let { if (it.isNotEmpty()) names += it }
                }
            }
        }
        val seen = HashSet<String>()
        return names.filter { it.isNotEmpty() && seen.add(it.lowercase()) }
    }

    private fun parse(e: JSONObject, league: League): Game? {
        val id = e.flexString("id") ?: return null
        val comp = e.optJSONArray("competitions")?.optJSONObject(0) ?: return null
        val competitors = comp.optJSONArray("competitors") ?: return null
        if (competitors.length() < 2) return null
        var homeRaw: JSONObject? = null
        var awayRaw: JSONObject? = null
        for (i in 0 until competitors.length()) {
            val c = competitors.optJSONObject(i) ?: continue
            if (c.optString("homeAway") == "home") homeRaw = c else if (c.optString("homeAway") == "away") awayRaw = c
        }
        val home = team(homeRaw ?: competitors.optJSONObject(0)) ?: return null
        val away = team(awayRaw ?: competitors.optJSONObject(1)) ?: return null
        val start = parseDate(e.optString("date"))
        val type = e.optJSONObject("status")?.optJSONObject("type")
        val detail = type?.optString("shortDetail") ?: ""
        val (state, status) = when (type?.optString("state") ?: "pre") {
            "in" -> GameState.LIVE to detail.ifEmpty { "Live" }
            "post" -> GameState.FINISHED to detail.ifEmpty { "Final" }
            else -> GameState.UPCOMING to (start?.let { timeText(it) } ?: detail)
        }
        var venue = ""
        comp.optJSONObject("venue")?.let { v ->
            val address = v.optJSONObject("address")
            val place = listOfNotNull(address?.optString("city")?.ifEmpty { null }, address?.optString("state")?.ifEmpty { null })
                .joinToString(", ")
            venue = listOf(v.optString("fullName"), place).filter { it.isNotEmpty() }.joinToString(" · ")
        }
        return Game("${league.id}-$id", league, start, state, status, away, home, broadcasters(listOf(comp)), venue = venue)
    }

    private fun athleteName(c: JSONObject): String {
        val a = c.optJSONObject("athlete")
        return a?.optString("displayName")?.ifEmpty { a.optString("shortName") }?.ifEmpty { null }
            ?: c.optJSONObject("team")?.optString("displayName") ?: ""
    }

    private fun athlete(c: JSONObject): Team? {
        val name = athleteName(c)
        if (name.isEmpty()) return null
        val parts = name.split(" ")
        val initials = parts.mapNotNull { it.firstOrNull()?.toString() }.joinToString("").take(3)
        val flag = c.optJSONObject("athlete")?.optJSONObject("flag")?.optString("href")?.ifEmpty { null }
        return Team(name, parts.last(), name, "", initials, c.flexString("score") ?: "", flag)
    }

    private fun stateOf(node: JSONObject?): Pair<GameState, String> {
        val type = node?.optJSONObject("status")?.optJSONObject("type")
        val detail = type?.optString("shortDetail") ?: ""
        return when (type?.optString("state") ?: "pre") {
            "in" -> GameState.LIVE to detail.ifEmpty { "Live" }
            "post" -> GameState.FINISHED to detail.ifEmpty { "Final" }
            else -> GameState.UPCOMING to detail
        }
    }

    private fun parseEvent(e: JSONObject, league: League): Game? {
        val id = e.flexString("id") ?: return null
        val name = e.optString("name").ifEmpty { e.optString("shortName") }.ifEmpty { league.name }
        val comps = mutableListOf<JSONObject>()
        e.optJSONArray("competitions")?.let { for (i in 0 until it.length()) it.optJSONObject(i)?.let(comps::add) }
        e.optJSONArray("groupings")?.let { g ->
            for (i in 0 until g.length()) g.optJSONObject(i)?.optJSONArray("competitions")?.let {
                for (j in 0 until it.length()) it.optJSONObject(j)?.let(comps::add)
            }
        }
        var start = parseDate(e.optString("date"))
        var (state, status) = stateOf(e)
        var detail = ""
        var away = Team.none
        var home = Team.none
        when (league.sport) {
            Sport.MOTORSPORT -> {
                val live = comps.firstOrNull { stateOf(it).first == GameState.LIVE }
                val next = comps.filter { stateOf(it).first == GameState.UPCOMING }
                    .minByOrNull { parseDate(it.optString("date")) ?: Long.MAX_VALUE }
                (live ?: next ?: comps.lastOrNull())?.let { s ->
                    val type = s.optJSONObject("type")
                    detail = type?.optString("text")?.ifEmpty { type.optString("abbreviation") } ?: ""
                    start = parseDate(s.optString("date")) ?: start
                    stateOf(s).let { state = it.first; status = it.second }
                }
            }
            Sport.FIGHTING -> {
                val sides = comps.lastOrNull()?.optJSONArray("competitors")
                if (sides != null && sides.length() >= 2) {
                    val a = sides.optJSONObject(0)?.let(::athlete)
                    val b = sides.optJSONObject(1)?.let(::athlete)
                    if (a != null && b != null) { away = a; home = b; detail = "Main event: ${a.name} vs ${b.name}" }
                }
            }
            Sport.TENNIS -> {
                val live = comps.filter { stateOf(it).first == GameState.LIVE }
                val sides = live.firstOrNull()?.optJSONArray("competitors")
                if (sides != null && sides.length() >= 2) {
                    detail = "${athleteName(sides.getJSONObject(0))} vs ${athleteName(sides.getJSONObject(1))}"
                    if (live.size > 1) detail += " + ${live.size - 1} more live"
                }
            }
            Sport.GOLF -> {
                val field = comps.firstOrNull()?.optJSONArray("competitors")
                if (field != null && field.length() > 0) {
                    val ordered = (0 until field.length()).mapNotNull { field.optJSONObject(it) }
                        .sortedBy { it.flexInt("order") ?: 999 }
                    ordered.firstOrNull()?.let { l ->
                        val score = l.flexString("score") ?: ""
                        detail = "Leader: ${athleteName(l)}" + if (score.isEmpty()) "" else " $score"
                    }
                }
            }
            else -> {}
        }
        if (state == GameState.UPCOMING) start?.let { status = timeText(it) }
        return Game("${league.id}-$id", league, start, state, status, away, home, broadcasters(comps.take(3)),
            isEvent = true, eventTitle = name, eventDetail = detail)
    }

    private fun team(c: JSONObject?): Team? {
        val t = c?.optJSONObject("team") ?: return null
        val display = t.optString("displayName").ifEmpty { t.optString("name") }
        if (display.isEmpty()) return null
        val nickname = t.optString("name").ifEmpty { t.optString("shortDisplayName") }.ifEmpty { display }
        val lines = c.optJSONArray("linescores")
        return Team(
            display, nickname, t.optString("shortDisplayName").ifEmpty { nickname }, t.optString("location"),
            t.optString("abbreviation"), c.flexString("score") ?: "", t.optString("logo").ifEmpty { null },
            record = c.optJSONArray("records")?.optJSONObject(0)?.optString("summary") ?: "",
            linescores = if (lines == null) emptyList() else (0 until lines.length()).mapNotNull {
                lines.optJSONObject(it)?.let { l -> l.optString("displayValue").ifEmpty { l.flexString("value") } }
            }
        )
    }

    private fun parseDate(text: String?): Long? {
        if (text.isNullOrEmpty()) return null
        for (f in listOf("yyyy-MM-dd'T'HH:mm'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'")) {
            try {
                return SimpleDateFormat(f, Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }.parse(text)?.time
            } catch (_: Exception) {}
        }
        return null
    }
}
