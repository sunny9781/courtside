package ca.sunny9781.courtside

import android.util.Xml
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import org.xmlpull.v1.XmlPullParser
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.zip.GZIPInputStream

class XtreamException(message: String) : Exception(message)

/** Talks to the provider (Xtream Codes). Live TV only. Stream addresses contain the login, so never log them. */
class XtreamClient(private val creds: Credentials) {

    private val base: String
        get() {
            var s = creds.server.trim()
            val lower = s.lowercase()
            if (!lower.startsWith("http://") && !lower.startsWith("https://")) s = "http://$s"
            return s.trimEnd('/')
        }

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")

    private fun apiUrl(action: String?): String {
        val sb = StringBuilder("$base/player_api.php?username=${enc(creds.username)}&password=${enc(creds.password)}")
        if (action != null) sb.append("&action=").append(action)
        return sb.toString()
    }

    private suspend fun get(url: String, timeoutMs: Int = 45_000, label: String? = null): String = withContext(Dispatchers.IO) {
        Vpn.require()
        label?.let { ConnLog.add("Downloading $it") }
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = timeoutMs
            setRequestProperty("User-Agent", "Courtside")
        }
        try {
            if (conn.responseCode != 200) {
                throw XtreamException("The server refused the request. Check the address, username and password.")
            }
            conn.inputStream.bufferedReader().use { it.readText() }.also { label?.let { l -> ConnLog.add("Finished $l") } }
        } finally {
            conn.disconnect()
        }
    }

    /** Checks the login and returns the account details. */
    suspend fun login(): AccountInfo {
        val text = get(apiUrl(null))
        val root = try { JSONObject(text) } catch (e: Exception) {
            throw XtreamException("The server replied with something that isn't an Xtream Codes response.")
        }
        val user = root.optJSONObject("user_info")
            ?: throw XtreamException("The server replied with something that isn't an Xtream Codes response.")
        if (user.flexInt("auth") != 1) throw XtreamException("Wrong username or password.")
        val status = user.optString("status", "Unknown")
        if (!status.equals("active", ignoreCase = true)) throw XtreamException("The account is not active (status: $status).")
        val exp = user.flexInt("exp_date")
        return AccountInfo(status, exp?.takeIf { it > 0 }?.toLong(), user.flexInt("max_connections"), user.flexInt("active_cons"))
    }

    /** Live categories and channels (the movie and series lists are never fetched). */
    suspend fun live(): Pair<List<ChannelCategory>, List<Channel>> = coroutineScope {
        // One after the other, never both at once: some providers count each open request as a connection.
        val catsText = get(apiUrl("get_live_categories"), label = "categories")
        val cats = JSONArray(catsText)
        val categories = (0 until cats.length()).mapNotNull { i ->
            val o = cats.optJSONObject(i) ?: return@mapNotNull null
            val id = o.flexString("category_id") ?: return@mapNotNull null
            ChannelCategory(id, o.optString("category_name"))
        }
        val names = categories.associate { it.id to it.name }
        // 2.51: the channel list (tens of thousands of channels on some providers) is read straight from the
        // download, one channel at a time. Reading it all as text and then as a JSON tree briefly took a lot of memory,
        // and since 2.49 that can happen while a stream plays: choppy video and Android closing the app on a Chromecast.
        val channels = channelList(apiUrl("get_live_streams"), names)
        categories to channels
    }

    private suspend fun channelList(url: String, names: Map<String, String>): List<Channel> = withContext(Dispatchers.IO) {
        Vpn.require()
        ConnLog.add("Downloading channels")
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 120_000
            setRequestProperty("User-Agent", "Courtside")
        }
        try {
            if (conn.responseCode != 200) {
                throw XtreamException("The server refused the request. Check the address, username and password.")
            }
            val out = ArrayList<Channel>()
            try {
                android.util.JsonReader(conn.inputStream.bufferedReader()).use { r ->
                    if (r.peek() != android.util.JsonToken.BEGIN_ARRAY) throw IllegalStateException("not a list")
                    r.beginArray()
                    while (r.hasNext()) {
                        if (r.peek() != android.util.JsonToken.BEGIN_OBJECT) { r.skipValue(); continue }
                        var id: Int? = null; var num: Int? = null; var name = ""; var catId = ""
                        var icon: String? = null; var epg = ""
                        r.beginObject()
                        while (r.hasNext()) {
                            when (r.nextName()) {
                                "stream_id" -> id = r.flex()?.toFlexInt()
                                "num" -> num = r.flex()?.toFlexInt()
                                "name" -> name = r.flex() ?: ""
                                "category_id" -> catId = r.flex()?.let { v -> v.toFlexInt()?.toString() ?: v } ?: ""
                                "stream_icon" -> icon = r.flex()?.takeIf { it.lowercase().startsWith("http") }
                                "epg_channel_id" -> epg = r.flex()?.trim()?.lowercase() ?: ""
                                else -> r.skipValue()
                            }
                        }
                        r.endObject()
                        if (id != null && name.isNotEmpty()) out.add(Channel(id, num, name, catId, names[catId] ?: "", epg, icon))
                    }
                    r.endArray()
                }
            } catch (e: java.io.IOException) {
                if (e is java.net.SocketTimeoutException) throw e
                throw XtreamException("The server replied with something that isn't an Xtream Codes response.")
            } catch (e: IllegalStateException) {
                throw XtreamException("The server replied with something that isn't an Xtream Codes response.")
            }
            ConnLog.add("Finished channels")
            out
        } finally {
            conn.disconnect()
        }
    }

    /**
     * Reads the provider's guide straight from the download, keeping only the wanted channels and the hours around
     * now, so even a huge guide file stays light on memory (the Chromecast with Google TV has little to spare).
     */
    suspend fun guide(wanted: Set<String>, from: Long, to: Long, progress: (read: Long, total: Long) -> Unit = { _, _ -> }):
        Map<String, List<Programme>> = withContext(Dispatchers.IO) {
        Vpn.require()
        ConnLog.add("Downloading the guide")
        val conn = (URL("$base/xmltv.php?username=${enc(creds.username)}&password=${enc(creds.password)}")
            .openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 300_000
            setRequestProperty("Accept-Encoding", "gzip")
        }
        try {
            if (conn.responseCode != 200) throw XtreamException("The provider's guide file couldn't be read.")
            // Counts what has come in so far, against the size the provider gives (when it gives one).
            val total = conn.contentLengthLong
            val raw: InputStream = object : java.io.FilterInputStream(conn.inputStream) {
                var read = 0L
                var told = 0L
                private fun count(n: Int) {
                    if (n <= 0) return
                    read += n
                    if (read - told > 256 * 1024) { told = read; progress(read, total) }
                }
                override fun read(): Int = super.read().also { if (it >= 0) count(1) }
                override fun read(b: ByteArray, off: Int, len: Int): Int = super.read(b, off, len).also { count(it) }
            }
            val input = if (conn.contentEncoding == "gzip") GZIPInputStream(raw) else raw
            input.use { parseGuide(it, wanted, from, to) }.also { ConnLog.add("Finished the guide") }
        } finally {
            conn.disconnect()
        }
    }

    fun streamUrl(channel: Channel, hls: Boolean): String =
        "$base/live/${enc(creds.username)}/${enc(creds.password)}/${channel.id}.${if (hls) "m3u8" else "ts"}"

    companion object {
        private val withZone = SimpleDateFormat("yyyyMMddHHmmss Z", Locale.US)
        private val plain = SimpleDateFormat("yyyyMMddHHmmss", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }

        private fun date(text: String?): Long? {
            if (text == null) return null
            return try { withZone.parse(text)?.time } catch (e: Exception) {
                try { plain.parse(text.take(14))?.time } catch (e: Exception) { null }
            }
        }

        fun parseGuide(input: InputStream, wanted: Set<String>, from: Long, to: Long): Map<String, List<Programme>> {
            val result = HashMap<String, MutableList<Programme>>()
            val parser = Xml.newPullParser()
            parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
            parser.setInput(input, null)
            var channel: String? = null
            var start = 0L
            var end = 0L
            var title: String? = null
            try {
                var event = parser.eventType
                while (event != XmlPullParser.END_DOCUMENT) {
                    when (event) {
                        XmlPullParser.START_TAG -> when (parser.name) {
                            "programme" -> {
                                channel = null
                                title = null
                                val ch = parser.getAttributeValue(null, "channel")?.lowercase()
                                if (ch != null && ch in wanted) {
                                    val s = date(parser.getAttributeValue(null, "start"))
                                    val e = date(parser.getAttributeValue(null, "stop"))
                                    if (s != null && e != null && s < to && e > from) {
                                        channel = ch; start = s; end = e
                                    }
                                }
                            }
                            "title" -> if (channel != null && title == null) title = parser.nextText().trim()
                        }
                        XmlPullParser.END_TAG -> if (parser.name == "programme") {
                            val ch = channel
                            if (ch != null) result.getOrPut(ch) { mutableListOf() }.add(Programme(title ?: "", start, end))
                            channel = null
                        }
                    }
                    event = parser.next()
                }
            } catch (e: Exception) {
                if (result.isEmpty()) throw XtreamException("The provider's guide file couldn't be read.")
            }
            return result.mapValues { (_, v) -> v.sortedBy { it.start } }
        }
    }
}

/** Providers are inconsistent about numbers vs strings in their JSON. */
/** One value as text whatever its JSON type (numbers and strings both; null and objects as null). */
private fun android.util.JsonReader.flex(): String? = when (peek()) {
    android.util.JsonToken.STRING, android.util.JsonToken.NUMBER -> nextString()
    android.util.JsonToken.BOOLEAN -> nextBoolean().toString()
    android.util.JsonToken.NULL -> { nextNull(); null }
    else -> { skipValue(); null }
}

/** "12", "12.0" or 12.0 as 12. */
private fun String.toFlexInt(): Int? = toIntOrNull() ?: toDoubleOrNull()?.toInt()

fun JSONObject.flexInt(key: String): Int? = when (val v = opt(key)) {
    is Int -> v
    is Long -> v.toInt()
    is Double -> v.toInt()
    is String -> v.toIntOrNull()
    else -> null
}

fun JSONObject.flexString(key: String): String? = when (val v = opt(key)) {
    is String -> v
    is Int, is Long -> v.toString()
    is Double -> v.toInt().toString()
    else -> null
}
