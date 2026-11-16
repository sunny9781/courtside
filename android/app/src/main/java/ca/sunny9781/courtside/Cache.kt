package ca.sunny9781.courtside

import android.content.Context
import android.util.JsonReader
import android.util.JsonToken
import android.util.JsonWriter
import java.io.File

/**
 * The channels and guide saved on the device, so opening the app (or installing an update) reuses them until
 * they're older than Settings › Updates says, like the Apple apps. Scores are always fetched fresh.
 */
object Cache {
    data class Live(val savedAt: Long, val server: String, val categories: List<ChannelCategory>, val channels: List<Channel>)

    private fun liveFile(context: Context) = File(context.filesDir, "live.json")
    private fun guideFile(context: Context) = File(context.filesDir, "guide.json")

    fun saveLive(context: Context, server: String, categories: List<ChannelCategory>, channels: List<Channel>) = runCatching {
        val tmp = File(context.filesDir, "live.tmp")
        JsonWriter(tmp.bufferedWriter()).use { w ->
            w.beginObject()
            w.name("savedAt").value(System.currentTimeMillis())
            w.name("server").value(server)
            w.name("categories").beginArray()
            for (c in categories) w.beginArray().value(c.id).value(c.name).endArray()
            w.endArray()
            w.name("channels").beginArray()
            for (c in channels) {
                w.beginArray().value(c.id.toLong()).value(c.number?.toLong() ?: -1L).value(c.name).value(c.categoryId)
                    .value(c.categoryName).value(c.epgId).value(c.icon ?: "").endArray()
            }
            w.endArray()
            w.endObject()
        }
        tmp.renameTo(liveFile(context))
    }

    fun loadLive(context: Context): Live? = runCatching {
        val file = liveFile(context)
        if (!file.exists()) return null
        JsonReader(file.bufferedReader()).use { r ->
            var savedAt = 0L
            var server = ""
            val cats = mutableListOf<ChannelCategory>()
            val chans = mutableListOf<Channel>()
            r.beginObject()
            while (r.hasNext()) {
                when (r.nextName()) {
                    "savedAt" -> savedAt = r.nextLong()
                    "server" -> server = r.nextString()
                    "categories" -> {
                        r.beginArray()
                        while (r.hasNext()) { r.beginArray(); cats.add(ChannelCategory(r.nextString(), r.nextString())); r.endArray() }
                        r.endArray()
                    }
                    "channels" -> {
                        r.beginArray()
                        while (r.hasNext()) {
                            r.beginArray()
                            val id = r.nextLong().toInt()
                            val number = r.nextLong().toInt().takeIf { it >= 0 }
                            chans.add(Channel(id, number, r.nextString(), r.nextString(), r.nextString(), r.nextString(),
                                r.nextString().ifEmpty { null }))
                            r.endArray()
                        }
                        r.endArray()
                    }
                    else -> r.skipValue()
                }
            }
            r.endObject()
            Live(savedAt, server, cats, chans)
        }
    }.getOrNull()

    fun saveGuide(context: Context, guide: Map<String, List<Programme>>) = runCatching {
        val tmp = File(context.filesDir, "guide.tmp")
        JsonWriter(tmp.bufferedWriter()).use { w ->
            w.beginObject()
            for ((id, list) in guide) {
                w.name(id).beginArray()
                for (p in list) w.beginArray().value(p.title).value(p.start).value(p.end).endArray()
                w.endArray()
            }
            w.endObject()
        }
        tmp.renameTo(guideFile(context))
    }

    fun loadGuide(context: Context): Map<String, List<Programme>> = runCatching {
        val file = guideFile(context)
        if (!file.exists()) return emptyMap()
        val now = System.currentTimeMillis()
        val out = HashMap<String, List<Programme>>()
        JsonReader(file.bufferedReader()).use { r ->
            r.beginObject()
            while (r.hasNext()) {
                val id = r.nextName()
                val list = ArrayList<Programme>()
                r.beginArray()
                while (r.hasNext()) {
                    r.beginArray()
                    val p = Programme(if (r.peek() == JsonToken.NULL) { r.nextNull(); "" } else r.nextString(), r.nextLong(), r.nextLong())
                    r.endArray()
                    if (p.end > now) list.add(p)    // what's already over isn't needed
                }
                r.endArray()
                if (list.isNotEmpty()) out[id] = list
            }
            r.endObject()
        }
        out
    }.getOrDefault(emptyMap())

    fun clear(context: Context) {
        liveFile(context).delete()
        guideFile(context).delete()
    }
}
