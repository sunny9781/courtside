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
    private var readyFile: File? = null
    private var readyBuild = 0

    suspend fun check(context: Context, userInitiated: Boolean = false) = withContext(Dispatchers.IO) {
        if (checking) return@withContext
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
            download(url, file)
            readyFile = file
            readyBuild = build
            readyVersion = version
            message = null
        } catch (e: Exception) {
            if (userInitiated) message = "Couldn't check for updates."
        } finally {
            checking = false
        }
    }

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
     * Installs the downloaded update through Android's package installer (more reliable on Google TV sets than
     * opening the file). Courtside itself needs "Install unknown apps" for this; if it's off (common on Google TV),
     * the switch for it opens first.
     */
    fun install(context: Context) {
        val file = readyFile ?: return
        val pm = context.packageManager
        if (android.os.Build.VERSION.SDK_INT >= 26 && !pm.canRequestPackageInstalls()) {
            message = "Turn on Courtside here so it can install its own updates, then choose Install update again."
            runCatching {
                context.startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    android.net.Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }.onFailure { message = "Allow Courtside to install apps: Settings › Apps › Security & restrictions › Unknown sources." }
            return
        }
        try {
            val installer = pm.packageInstaller
            val params = android.content.pm.PackageInstaller.SessionParams(android.content.pm.PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            params.setAppPackageName(context.packageName)
            val id = installer.createSession(params)
            installer.openSession(id).use { session ->
                file.inputStream().use { input ->
                    session.openWrite("Courtside.apk", 0, file.length()).use { out ->
                        input.copyTo(out)
                        session.fsync(out)
                    }
                }
                val flags = android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                    (if (android.os.Build.VERSION.SDK_INT >= 31) android.app.PendingIntent.FLAG_MUTABLE else 0)
                val pending = android.app.PendingIntent.getBroadcast(context, id, Intent(context, InstallReceiver::class.java), flags)
                session.commit(pending.intentSender)
            }
        } catch (e: Exception) {
            // Fall back to opening the file with Android's installer.
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", file)
            context.startActivity(Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            })
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
            conn.inputStream.use { input -> tmp.outputStream().use { input.copyTo(it) } }
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

/** Hears back from Android's package installer: asks you to confirm, or says why the update didn't install. */
class InstallReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.getIntExtra(android.content.pm.PackageInstaller.EXTRA_STATUS, -999)) {
            android.content.pm.PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirm: Intent? = if (android.os.Build.VERSION.SDK_INT >= 33)
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java) else intent.getParcelableExtra(Intent.EXTRA_INTENT)
                confirm?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                runCatching { context.startActivity(confirm) }
            }
            android.content.pm.PackageInstaller.STATUS_SUCCESS -> {}
            else -> Updater.message = "The update didn't install (" +
                (intent.getStringExtra(android.content.pm.PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "no reason given") + ")."
        }
    }
}
