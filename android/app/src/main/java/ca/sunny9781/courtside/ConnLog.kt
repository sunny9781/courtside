package ca.sunny9781.courtside

import androidx.compose.runtime.mutableStateListOf
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * What used a connection to the provider, newest first (Settings › General › Connection log): streams opened and
 * closed, downloads started and finished, and what the provider said was in use. Never holds an address (they
 * contain the login): streams are named by their channel number only.
 */
object ConnLog {
    val entries = mutableStateListOf<String>()
    private val time = SimpleDateFormat("h:mm:ss a", Locale.US)

    fun add(text: String) {
        val line = "${time.format(Date())}  $text"
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            entries.add(0, line)
            while (entries.size > 40) entries.removeAt(entries.size - 1)
        }
    }

    /** "stream 12345 (TS)" from a stream address, without the login in it. */
    fun stream(url: String): String {
        val file = url.substringAfterLast('/')
        val id = file.substringBefore('.')
        return "stream $id (${if (file.endsWith(".m3u8")) "HLS" else "TS"})"
    }
}
