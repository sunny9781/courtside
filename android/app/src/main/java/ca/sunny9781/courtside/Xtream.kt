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

    private suspend fun get(url: String, timeoutMs: Int = 45_000): String = withContext(Dispatchers.IO) {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = timeoutMs
            setRequestProperty("User-Agent", "Courtside")
        }
        try {
            if (conn.responseCode != 200) {
                throw XtreamException("The server refused the request. Check the address, username and password.")
            }
            conn.inputStream.bufferedReader().use { it.readText() }
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
        val catsText = async { get(apiUrl("get_live_categories")) }
        val streamsText = async { get(apiUrl("get_live_streams"), timeoutMs = 120_000) }
        val cats = JSONArray(catsText.await())
        val categories = (0 until cats.length()).mapNotNull { i ->
            val o = cats.optJSONObject(i) ?: return@mapNotNull null
            val id = o.flexString("category_id") ?: return@mapNotNull null
            ChannelCategory(id, o.optString("category_name"))
        }
        val names = categories.associate { it.id to it.name }
        val list = try { JSONArray(streamsText.await()) } catch (e: Exception) {
            throw XtreamException("The server replied with something that isn't an Xtream Codes response.")
        }
        val channels = (0 until list.length()).mapNotNull { i ->
            val o = list.optJSONObject(i) ?: return@mapNotNull null
            val id = o.flexInt("stream_id") ?: return@mapNotNull null
            val name = o.optString("name").takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            val catId = o.flexString("category_id") ?: ""
            val icon = o.optString("stream_icon").takeIf { it.lowercase().startsWith("http") }
            Channel(id, o.flexInt("num"), name, catId, names[catId] ?: "",
                o.optString("epg_channel_id").trim().lowercase(), icon)
        }
        categories to channels
    }

    /**
     * Reads the provider's guide straight from the download, keeping only the wanted channels and the hours around
     * now, so even a huge guide file stays light on memory (the Chromecast with Google TV has little to spare).
     */
    suspend fun guide(wanted: Set<String>, from: Long, to: Long): Map<String, List<Programme>> = withContext(Dispatchers.IO) {
        val conn = (URL("$base/xmltv.php?username=${enc(creds.username)}&password=${enc(creds.password)}")
            .openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 300_000
            setRequestProperty("Accept-Encoding", "gzip")
        }
        try {
            if (conn.responseCode != 200) throw XtreamException("The provider's guide file couldn't be read.")
            val raw: InputStream = conn.inputStream
            val input = if (conn.contentEncoding == "gzip") GZIPInputStream(raw) else raw
            input.use { parseGuide(it, wanted, from, to) }
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
