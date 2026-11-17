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
    /** Let full screen switch the TV into HDR for HDR streams (off: always shown as standard range). */
    var hdr by Flag("hdr", false)
    /**
     * Lite mode: cheaper drawing for less powerful TVs (no zoom on focus, no team logos on Home, the fast video
     * path). On by default everywhere except an Nvidia Shield.
     */
    var lite by Flag("lite", !android.os.Build.MANUFACTURER.equals("NVIDIA", ignoreCase = true))
    var bufferMs by Number("bufferMs", 2000)
    /** Opening the app reuses the saved channels and guide until they're this old. */
    var refreshHours by Number("refreshHours", 12)

    init {
        // The refresh default went from 6 to 12 hours: move anyone still on the old default over, once.
        if (!p.getBoolean("refreshHours12", false)) {
            if (p.getInt("refreshHours", 12) == 6) refreshHours = 12
            p.edit().putBoolean("refreshHours12", true).apply()
        }
    }
    /** Open streams as HLS first (what the iPhone app uses), with TS as the fallback; off is the other way round. */
    var preferHls by Flag("preferHls", true)
    var hideSD by Flag("hideSD", true)
    var showForeign by Flag("showForeign", false)
    var hideAdult by Flag("hideAdult", true)
    var grouped by Flag("guideGrouped", true)
    var guideCategory by Words("guideCategory")
    var hiddenSports by Words("hiddenSports")
    var hiddenLeagues by Words("hiddenLeagues")
    var favoriteSports by Words("favoriteSports")

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
