package ca.sunny9781.courtside

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * How reliable each stream has been on this device (2.17): startup time, buffering, freezes, drops and failed
 * starts, kept per stream ID (never the URL, which holds the login) in stream-stats.json in the app's files folder.
 * Each stream keeps running averages, so recent sessions count more and the file never grows, plus its last few
 * sessions. Streams not watched for 60 days are dropped. Only what's actually watched is measured: nothing is
 * tested in the background (one connection at a time).
 */
object StreamStats {
    enum class Rating { GOOD, OK, POOR }

    /** One viewing, from pressing the stream until it's stopped or another one starts. */
    data class Session(
        val at: Long, val watchMs: Long, val bufferMs: Long, val buffers: Int,
        val freezes: Int, val drops: Int, val startupMs: Long, val failed: Boolean
    )

    private class Summary(
        var rebuffer: Double = 0.0,      // share of time spent buffering, 0..1
        var eventsPerHour: Double = 0.0, // buffers + freezes + drops per hour watched
        var startupMs: Double = 0.0,
        var failRate: Double = 0.0,      // share of opens that never showed a picture
        var watchMs: Long = 0,
        var opens: Int = 0,
        var lastAt: Long = 0,
        val sessions: ArrayDeque<Session> = ArrayDeque()
    )

    /** Recent sessions count this much in the running averages. */
    private const val WEIGHT = 0.3
    /** No dot until a stream has been watched this long in total (one bad first open shouldn't mark it). */
    private const val MIN_WATCH_MS = 5 * 60_000L
    private const val KEEP_SESSIONS = 15
    private const val FORGET_AFTER_MS = 60L * 24 * 3600_000

    private val streams = HashMap<Int, Summary>()
    private var file: File? = null

    /** The dot for each stream with enough history (Compose reads this). */
    var ratings by mutableStateOf<Map<Int, Rating>>(emptyMap())
        private set

    // The session being watched.
    private var id: Int? = null
    private var startedAt = 0L
    private var startupMs = -1L
    private var watchMs = 0L
    private var bufferMs = 0L
    private var buffers = 0
    private var freezes = 0
    private var drops = 0
    private var wasBuffering = false
    private var lastTick = 0L

    fun load(context: Context) {
        val f = File(context.filesDir, "stream-stats.json")
        file = f
        runCatching {
            if (!f.exists()) return@runCatching
            val root = JSONObject(f.readText())
            val now = System.currentTimeMillis()
            for (key in root.keys()) {
                val o = root.getJSONObject(key)
                val s = Summary(
                    o.optDouble("rebuffer"), o.optDouble("eventsPerHour"), o.optDouble("startupMs"),
                    o.optDouble("failRate"), o.optLong("watchMs"), o.optInt("opens"), o.optLong("lastAt")
                )
                if (now - s.lastAt > FORGET_AFTER_MS) continue
                o.optJSONArray("sessions")?.let { a ->
                    for (i in 0 until a.length()) a.getJSONObject(i).let { j ->
                        s.sessions.add(Session(j.optLong("at"), j.optLong("watchMs"), j.optLong("bufferMs"), j.optInt("buffers"),
                            j.optInt("freezes"), j.optInt("drops"), j.optLong("startupMs"), j.optBoolean("failed")))
                    }
                }
                key.toIntOrNull()?.let { streams[it] = s }
            }
        }
        publish()
    }

    /** The stream ID from an Xtream address (".../live/user/pass/1234.ts" → 1234). */
    fun idOf(url: String): Int? = url.substringAfterLast('/').substringBefore('.').toIntOrNull()

    /** A stream was pressed: ends the last session and starts one for this stream. */
    fun begin(url: String) {
        end()
        id = idOf(url) ?: return
        startedAt = System.currentTimeMillis()
        lastTick = startedAt
        startupMs = -1L; watchMs = 0L; bufferMs = 0L; buffers = 0; freezes = 0; drops = 0; wasBuffering = false
    }

    fun firstPicture() {
        if (id != null && startupMs < 0) startupMs = System.currentTimeMillis() - startedAt
    }

    fun froze() { if (id != null) freezes++ }
    fun dropped() { if (id != null) drops++ }

    /**
     * Every half second from the player: [playing] = picture moving, [buffering] = stalled after it had shown a
     * picture. Paused or still opening counts as neither.
     */
    fun tick(playing: Boolean, buffering: Boolean) {
        val now = System.currentTimeMillis()
        val dt = (now - lastTick).coerceIn(0, 2000)
        lastTick = now
        if (id == null) return
        if (playing) watchMs += dt
        if (buffering) {
            bufferMs += dt
            if (!wasBuffering) buffers++
        }
        wasBuffering = buffering
    }

    /** The stream was stopped (or another one started): folds this session into the stream's history and saves. */
    fun end() {
        val sid = id ?: return
        id = null
        val failed = startupMs < 0
        // Opened and closed again straight away (flipping through streams): not a real try, nothing learned.
        if (!failed && watchMs + bufferMs < 10_000) return
        if (failed && System.currentTimeMillis() - startedAt < 8_000) return
        val session = Session(startedAt, watchMs, bufferMs, buffers, freezes, drops, startupMs.coerceAtLeast(0), failed)
        val s = streams.getOrPut(sid) { Summary() }
        val first = s.opens == 0
        fun mix(old: Double, new: Double) = if (first) new else old * (1 - WEIGHT) + new * WEIGHT
        s.failRate = mix(s.failRate, if (failed) 1.0 else 0.0)
        if (!failed) {
            val total = (watchMs + bufferMs).toDouble()
            val events = (buffers + freezes + drops).toDouble()
            val hasWatch = s.watchMs > 0
            fun mixWatch(old: Double, new: Double) = if (!hasWatch) new else old * (1 - WEIGHT) + new * WEIGHT
            s.rebuffer = mixWatch(s.rebuffer, bufferMs / total)
            s.eventsPerHour = mixWatch(s.eventsPerHour, events / (total / 3_600_000.0))
            s.startupMs = mixWatch(s.startupMs, startupMs.toDouble())
        }
        s.watchMs += watchMs
        s.opens++
        s.lastAt = session.at
        s.sessions.addFirst(session)
        while (s.sessions.size > KEEP_SESSIONS) s.sessions.removeLast()
        publish()
        save()
    }

    fun reset() {
        id = null
        streams.clear()
        publish()
        save()
    }

    private fun rate(s: Summary): Rating? {
        // Never shows a picture: red even without watch time.
        if (s.opens >= 2 && s.failRate > 0.5) return Rating.POOR
        if (s.watchMs < MIN_WATCH_MS) return null
        return when {
            s.rebuffer > 0.05 || s.eventsPerHour > 20 || s.failRate > 0.4 -> Rating.POOR
            s.rebuffer > 0.01 || s.eventsPerHour > 6 || s.failRate > 0.15 || s.startupMs > 8_000 -> Rating.OK
            else -> Rating.GOOD
        }
    }

    private fun publish() {
        ratings = streams.mapNotNull { (k, s) -> rate(s)?.let { k to it } }.toMap()
    }

    private fun save() {
        val f = file ?: return
        val root = JSONObject()
        for ((k, s) in streams) {
            root.put(k.toString(), JSONObject().apply {
                put("rebuffer", s.rebuffer); put("eventsPerHour", s.eventsPerHour); put("startupMs", s.startupMs)
                put("failRate", s.failRate); put("watchMs", s.watchMs); put("opens", s.opens); put("lastAt", s.lastAt)
                put("sessions", JSONArray().apply {
                    s.sessions.forEach { x ->
                        put(JSONObject().apply {
                            put("at", x.at); put("watchMs", x.watchMs); put("bufferMs", x.bufferMs); put("buffers", x.buffers)
                            put("freezes", x.freezes); put("drops", x.drops); put("startupMs", x.startupMs); put("failed", x.failed)
                        })
                    }
                })
            })
        }
        val text = root.toString()
        Thread {
            runCatching {
                val tmp = File(f.parentFile, "stream-stats.tmp")
                tmp.writeText(text)
                tmp.renameTo(f)
            }
        }.start()
    }
}
