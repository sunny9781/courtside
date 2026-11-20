package ca.sunny9781.courtside

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Keeps the app up to date from the courtside repo on GitHub: every build publishes Courtside.apk and android.json
 * on the "android" release. When a newer build exists it downloads in the background, then Android asks you to
 * confirm the install (one click).
 */
object Updater {
    private const val FEED = "https://github.com/sunny9781/courtside/releases/download/android/android.json"

    /** The version that's downloaded and ready to install, if any. */
    var readyVersion by mutableStateOf<String?>(null)
        private set
    var checking by mutableStateOf(false)
        private set
    var message by mutableStateOf<String?>(null)
    /** The new version being downloaded right now, and how far it's got (0..1, null if the size isn't known). */
    var downloading by mutableStateOf<String?>(null)
        private set
    var downloadProgress by mutableStateOf<Float?>(null)
        private set
    private var readyFile: File? = null
    private var readyBuild = 0

    /** One check at a time; a press while the app is already checking (or downloading) waits for it, then carries on. */
    private val lock = kotlinx.coroutines.sync.Mutex()

    suspend fun check(context: Context, userInitiated: Boolean = false) = withContext(Dispatchers.IO) {
        lock.lock()
        checking = true
        try {
            val text = get("$FEED?t=${System.currentTimeMillis() / 1000}")
            val json = JSONObject(text)
            val build = json.optInt("build")
            val version = json.optString("version")
            val url = json.optString("url")
            if (build <= maxOf(BuildConfig.VERSION_CODE, readyBuild) || url.isEmpty()) {
                if (userInitiated && readyVersion == null) message = "You're up to date."
                return@withContext
            }
            val dir = File(context.cacheDir, "updates").apply { mkdirs() }
            val file = File(dir, "Courtside.apk")
            downloading = version
            downloadProgress = null
            try { download(url, file) } finally { downloading = null; downloadProgress = null }
            readyFile = file
            readyBuild = build
            readyVersion = version
            message = null
        } catch (e: Exception) {
            if (userInitiated) message = "Couldn't check for updates."
        } finally {
            checking = false
            lock.unlock()
        }
    }

    /** Waiting for "Install unknown apps" to be switched on: the install carries on by itself once you're back. */
    private var waitingForPermission = false

    /** Opens Android's installer for the downloaded update. */
    /**
     * "Install update": checks once more first, so if an even newer version came out since the last download, that
     * one is fetched and installed instead (no installing 1.42 only to be offered 1.43 straight after).
     */
    suspend fun installLatest(context: Context) {
        installing = true
        try {
            check(context)
        } finally {
            installing = false
        }
        withContext(Dispatchers.Main) { install(context) }
    }

    /** "Install update" was pressed and the latest version is being fetched. */
    var installing by mutableStateOf(false)
        private set

    /**
     * Installs the downloaded update with Android's installer screen. Courtside itself needs "Install unknown apps"
     * for this; if it's off (common on Google TV, and why updates failed on a Sony), the switch for it opens first.
     */
    fun install(context: Context) {
        val file = readyFile ?: return
        val pm = context.packageManager
        // Installing needs room for the new version beside the old one (about three times the download).
        val free = minOf(context.filesDir.usableSpace, context.cacheDir.usableSpace)
        val needed = file.length() * 3
        if (free < needed) {
            message = "Not enough space on this TV to update (needs about ${needed / 1_000_000 + 1} MB free, " +
                "has ${free / 1_000_000} MB). Free some up in Settings › System › Storage, then try again."
            return
        }
        // Remembered (with the download), so if Android's installer says "App not installed", or this app was closed
        // to make room while it installed, the app can try again or explain when you're back.
        context.getSharedPreferences("courtside", Context.MODE_PRIVATE).edit()
            .putInt("installAttempt", readyBuild).putLong("installAttemptAt", System.currentTimeMillis())
            .putString("installAttemptVersion", readyVersion).apply()
        if (android.os.Build.VERSION.SDK_INT >= 26 && !pm.canRequestPackageInstalls()) {
            waitingForPermission = true
            message = "Turn on Courtside here so it can install its own updates; the update carries on when you come back."
            runCatching {
                context.startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    android.net.Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }.onFailure { message = "Allow Courtside to install apps: Settings › Apps › Security & restrictions › Unknown sources." }
            return
        }
        // Less powerful TVs (Chromecast) can close this app to make room for the installer while it's still reading the
        // update from it, and the install then fails. Free what we can first: the stream and the image cache.
        runCatching { Playback.stop() }
        runCatching { coil.Coil.imageLoader(context).memoryCache?.clear() }
        System.gc()
        // Android's installer screen: asks to confirm, then says "App installed" with Done / Open.
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", file)
        context.startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        })
    }

    /**
     * Back in the app after the installer screen: if the update we tried didn't take (Android only says "App not
     * installed"), say what usually causes it. Also tidies away a downloaded update that's already installed.
     */
    fun afterInstall(context: Context) {
        // Back from switching on "Install unknown apps": install straight away, no second press.
        if (waitingForPermission && readyFile != null && (android.os.Build.VERSION.SDK_INT < 26 ||
                context.packageManager.canRequestPackageInstalls())) {
            waitingForPermission = false
            message = null
            install(context)
            return
        }
        val prefs = context.getSharedPreferences("courtside", Context.MODE_PRIVATE)
        val attempt = prefs.getInt("installAttempt", 0)
        val at = prefs.getLong("installAttemptAt", 0)
        if (attempt == 0) return
        val since = System.currentTimeMillis() - at
        // Some installers pass back through the app on their way to the confirm screen: not a result yet.
        if (since < 3_000) return
        if (attempt > BuildConfig.VERSION_CODE) {
            // The app may have been closed while installing: pick the download back up.
            val file = File(File(context.cacheDir, "updates"), "Courtside.apk")
            if (readyFile == null && file.exists()) {
                readyFile = file
                readyBuild = attempt
                readyVersion = prefs.getString("installAttemptVersion", null)
            }
            val retried = prefs.getInt("installRetried", 0) == attempt
            prefs.edit().remove("installAttempt").remove("installAttemptAt").apply()
            if (since < 30 * 60_000L) {
                if (!retried && readyFile != null) {
                    // The first try often fails on less powerful TVs while the second works: try again by itself.
                    prefs.edit().putInt("installRetried", attempt).apply()
                    message = null
                    install(context)
                } else {
                    message = "The update didn't finish installing. Try Install update again. If it keeps failing, " +
                        "it's usually storage: free up some space in Settings › System › Storage, or reinstall with " +
                        "Downloader (is.gd/courtsidetv); your login and settings stay."
                }
            }
        } else {
            File(context.cacheDir, "updates").deleteRecursively()
            prefs.edit().remove("installAttempt").remove("installAttemptAt").remove("installRetried").apply()
        }
    }

    private fun get(url: String): String {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply { connectTimeout = 15_000; readTimeout = 20_000 }
        try { return conn.inputStream.bufferedReader().use { it.readText() } } finally { conn.disconnect() }
    }

    private fun download(url: String, to: File) {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply { connectTimeout = 15_000; readTimeout = 120_000 }
        try {
            val tmp = File(to.parentFile, "download.tmp")
            val total = conn.contentLengthLong
            conn.inputStream.use { input ->
                tmp.outputStream().use { out ->
                    val buf = ByteArray(64 * 1024)
                    var read = 0L
                    var shown = -1
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                        read += n
                        if (total > 0) {
                            val pct = (read * 100 / total).toInt()
                            if (pct != shown) { shown = pct; downloadProgress = read.toFloat() / total }
                        }
                    }
                }
            }
            // A cut-off download would fail to install ("App not installed"), so it's checked first.
            val expected = conn.contentLengthLong
            if (expected > 0 && tmp.length() != expected) { tmp.delete(); error("The download was incomplete.") }
            to.delete()
            tmp.renameTo(to)
        } finally {
            conn.disconnect()
        }
    }
}

/** Saved settings and the login (in the app's private storage). */
object Prefs {
    private fun prefs(context: Context) = context.getSharedPreferences("courtside", Context.MODE_PRIVATE)

    fun loadCredentials(context: Context): Credentials? {
        val p = prefs(context)
        val server = p.getString("server", null) ?: return null
        return Credentials(server, p.getString("username", "") ?: "", p.getString("password", "") ?: "")
    }

    fun saveCredentials(context: Context, creds: Credentials?) {
        prefs(context).edit().apply {
            if (creds == null) {
                remove("server"); remove("username"); remove("password")
            } else {
                putString("server", creds.server); putString("username", creds.username); putString("password", creds.password)
            }
        }.apply()
    }

    fun bufferMs(context: Context) = prefs(context).getInt("bufferMs", 2000)
    fun matchFrameRate(context: Context) = prefs(context).getBoolean("matchFrameRate", true)
    fun setMatchFrameRate(context: Context, on: Boolean) = prefs(context).edit().putBoolean("matchFrameRate", on).apply()
    fun showForeign(context: Context) = prefs(context).getBoolean("showForeign", false)
    fun setShowForeign(context: Context, on: Boolean) = prefs(context).edit().putBoolean("showForeign", on).apply()
}

