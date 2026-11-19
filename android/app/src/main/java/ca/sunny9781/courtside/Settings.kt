package ca.sunny9781.courtside

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import kotlin.properties.ReadWriteProperty
import kotlin.reflect.KProperty

/** The same settings as the Apple TV app, saved on the device. Screens redraw when one changes. */
class Settings(context: Context) {
    private val p = context.getSharedPreferences("courtside", Context.MODE_PRIVATE)

    private inner class Flag(val key: String, def: Boolean) : ReadWriteProperty<Any?, Boolean> {
        private var state by mutableStateOf(p.getBoolean(key, def))
        override fun getValue(thisRef: Any?, property: KProperty<*>) = state
        override fun setValue(thisRef: Any?, property: KProperty<*>, value: Boolean) {
            state = value; p.edit().putBoolean(key, value).apply()
        }
    }

    private inner class Number(val key: String, def: Int) : ReadWriteProperty<Any?, Int> {
        private var state by mutableStateOf(p.getInt(key, def))
        override fun getValue(thisRef: Any?, property: KProperty<*>) = state
        override fun setValue(thisRef: Any?, property: KProperty<*>, value: Int) {
            state = value; p.edit().putInt(key, value).apply()
        }
    }

    private inner class Words(val key: String) : ReadWriteProperty<Any?, String> {
        private var state by mutableStateOf(p.getString(key, "") ?: "")
        override fun getValue(thisRef: Any?, property: KProperty<*>) = state
        override fun setValue(thisRef: Any?, property: KProperty<*>, value: String) {
            state = value; p.edit().putString(key, value).apply()
        }
    }

    var autoSwitch by Flag("autoSwitch", true)
    var matchFrameRate by Flag("matchFrameRate", true)
    /** A less powerful TV (anything but an Nvidia Shield): Settings shows the Lite mode section only here. */
    val slowDevice = !android.os.Build.MANUFACTURER.equals("NVIDIA", ignoreCase = true)
    /** Before 1.94 Lite mode was one switch ("lite"); each option starts where that switch was. */
    private val liteDefault = p.getBoolean("lite", slowDevice)
    // Lite mode's options, from the least to the most effect on speed (the order Settings › Lite mode lists them).
    /** Wait a little longer (350 ms instead of 250) before showing a page as you move through lists. */
    var liteSettle by Flag("liteSettle", liteDefault)
    /** Finished games stay folded on Home. */
    var liteFoldFinished by Flag("liteFoldFinished", liteDefault)
    /** No team or channel logos. */
    var liteNoLogos by Flag("liteNoLogos", liteDefault)
    /** No live scores: today's games load once when the app opens, and Home shows no scores. */
    var liteNoScores by Flag("liteNoScores", liteDefault)
    /** Opening a game doesn't start one of its streams by itself. */
    var liteNoAutoplay by Flag("liteNoAutoplay", liteDefault)
    /** No player in the corner: channels open full screen, and leaving full screen stops the stream. */
    var liteNoCorner by Flag("liteNoCorner", liteDefault)
    /** Every Lite option on (the one switch at the top of the section turns them all on or off). */
    var lite: Boolean
        get() = liteSettle && liteFoldFinished && liteNoLogos && liteNoScores && liteNoAutoplay && liteNoCorner
        set(v) { liteSettle = v; liteFoldFinished = v; liteNoLogos = v; liteNoScores = v; liteNoAutoplay = v; liteNoCorner = v }
    val anyLite get() = liteSettle || liteFoldFinished || liteNoLogos || liteNoScores || liteNoAutoplay || liteNoCorner
    var bufferMs by Number("bufferMs", 2000)
    /** Opening the app reuses the saved channels and guide until they're this old. */
    var refreshHours by Number("refreshHours", 6)

    init {
        // The refresh default went back to 6 hours: move anyone on the 12-hour default over, once.
        if (!p.getBoolean("refreshHours6", false)) {
            if (p.getInt("refreshHours", 6) == 12) refreshHours = 6
            p.edit().putBoolean("refreshHours6", true).apply()
        }
    }
    /**
     * Open streams as HLS first, with TS as the fallback; off (the default) is TS first. TS is one connection that
     * closes the moment you switch away. HLS has no connection to close, so the provider keeps counting each HLS
     * stream you flipped past for a while, and flipping channels showed (and used) 2 connections.
     */
    var preferHls by Flag("preferHls", false)

    init {
        // TS first is the new default (one connection while flipping): move everyone over, once.
        if (!p.getBoolean("tsFirst", false)) {
            preferHls = false
            p.edit().putBoolean("tsFirst", true).apply()
        }
    }
    var hideSD by Flag("hideSD", true)
    var showForeign by Flag("showForeign", false)
    /** Old switch for adult categories; now only read once, to carry over someone who had turned them on. */
    var hideAdult by Flag("hideAdult", true)
    /** Adult categories already put in Settings › Hidden once (so showing one again sticks). */
    var adultHandled by Words("adultHandled")
    var grouped by Flag("guideGrouped", true)
    var guideCategory by Words("guideCategory")
    var hiddenSports by Words("hiddenSports")
    var hiddenLeagues by Words("hiddenLeagues")
    var favoriteSports by Words("favoriteSports")
    /** EPG favourites, in the order added: channel ids (comma-separated) and category or group ids (one per line). */
    var favoriteChannels by Words("favoriteChannels")
    var favoriteCategories by Words("favoriteCategories")
    /** Hidden from the EPG (and game screens): channel ids (comma-separated) and category or group ids (one per line). */
    var hiddenChannels by Words("hiddenChannels")
    var hiddenCategories by Words("hiddenCategories")

    val hiddenSportSet: Set<Sport> get() = sports(hiddenSports)
    val favoriteSet: Set<Sport> get() = sports(favoriteSports)
    val hiddenLeagueSet: Set<String> get() = hiddenLeagues.split(",").filter { it.isNotEmpty() }.toSet()

    private fun sports(saved: String) = saved.split(",").mapNotNull { s -> Sport.entries.firstOrNull { it.name == s } }.toSet()

    fun setHidden(sport: Sport, hide: Boolean) {
        val set = hiddenSportSet.toMutableSet().apply { if (hide) add(sport) else remove(sport) }
        hiddenSports = Sport.entries.filter { it in set }.joinToString(",") { it.name }
    }

    fun toggleFavorite(sport: Sport) {
        val set = favoriteSet.toMutableSet().apply { if (sport in this) remove(sport) else add(sport) }
        favoriteSports = Sport.entries.filter { it in set }.joinToString(",") { it.name }
    }

    fun setLeagueHidden(id: String, hide: Boolean) {
        val set = hiddenLeagueSet.toMutableSet().apply { if (hide) add(id) else remove(id) }
        hiddenLeagues = League.all.filter { it.id in set }.joinToString(",") { it.id }
    }
}

/** What's new: the Android changes from Shared/Changelog.swift, put into the app when it's built. */
object WhatsNew {
    data class Release(val version: String, val date: String, val time: String, val title: String, val changes: List<String>) {
        /** "v1.33 · Sun, Nov 15 · 9:30 PM" (written in Eastern time, shown in the TV's own time zone). */
        val label: String
            get() = runCatching {
                val parse = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).apply { timeZone = TimeZone.getTimeZone("America/New_York") }
                val d = parse.parse("$date $time")!!
                "v$version · " + SimpleDateFormat("EEE, MMM d · h:mm a", Locale.getDefault()).format(d)
            }.getOrDefault("v$version · $date")
    }

    fun load(context: Context): List<Release> = runCatching {
        val text = context.assets.open("changelog.json").bufferedReader().use { it.readText() }
        val arr = JSONArray(text)
        (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            val ch = o.getJSONArray("changes")
            Release(o.getString("version"), o.getString("date"), o.getString("time"), o.getString("title"),
                (0 until ch.length()).map { ch.getString(it) })
        }
    }.getOrDefault(emptyList())
}

/** Finder-style order: numbers before letters, and "2" before "10". */
object NaturalOrder : Comparator<String> {
    override fun compare(a: String, b: String): Int {
        var i = 0
        var j = 0
        while (i < a.length && j < b.length) {
            val ca = a[i]
            val cb = b[j]
            if (ca.isDigit() && cb.isDigit()) {
                var ei = i
                while (ei < a.length && a[ei].isDigit()) ei++
                var ej = j
                while (ej < b.length && b[ej].isDigit()) ej++
                val na = a.substring(i, ei).trimStart('0')
                val nb = b.substring(j, ej).trimStart('0')
                if (na.length != nb.length) return na.length - nb.length
                val c = na.compareTo(nb)
                if (c != 0) return c
                i = ei
                j = ej
            } else {
                val c = ca.lowercaseChar().compareTo(cb.lowercaseChar())
                if (c != 0) return c
                i++
                j++
            }
        }
        return (a.length - i) - (b.length - j)
    }
}
