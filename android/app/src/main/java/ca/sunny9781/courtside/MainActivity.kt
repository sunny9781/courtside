package ca.sunny9781.courtside

import android.os.Build
import android.os.Bundle
import android.view.Display
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.runtime.LaunchedEffect
import kotlin.math.abs
import kotlinx.coroutines.flow.first
import kotlin.math.roundToInt

class MainActivity : ComponentActivity() {
    private val model: AppModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // If the app closed because of an error, keep what happened (it's shown once on the next start and kept in
        // crash.txt), so slow-TV crashes can be tracked down. Nothing is sent anywhere.
        val crashFile = java.io.File(filesDir, "crash.txt")
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            runCatching {
                val free = Runtime.getRuntime().let { (it.maxMemory() - (it.totalMemory() - it.freeMemory())) / 1_000_000 }
                crashFile.writeText("${java.util.Date()} · v${BuildConfig.VERSION_NAME} · ${android.os.Build.MODEL} · " +
                    "${free} MB free\n${error.stackTraceToString().take(4000)}")
            }
            previous?.uncaughtException(thread, error)
        }
        if (crashFile.exists()) runCatching {
            val text = crashFile.readText()
            val first = text.lines().getOrNull(1)?.take(110) ?: ""
            model.notice = "Courtside closed unexpectedly last time: $first"
            crashFile.renameTo(java.io.File(filesDir, "crash-last.txt"))
        }
        Perf.settings = model.settings
        // Logos: a small memory cache and no fade-in animation (cheap on low-power TVs).
        coil.Coil.setImageLoader(coil.ImageLoader.Builder(this)
            .memoryCache { coil.memory.MemoryCache.Builder(this).maxSizePercent(0.08).build() }
            .crossfade(false)
            // Logos in 16-bit colour: half the memory, so less clearing up (pauses) on 2 GB TVs.
            .allowRgb565(true)
            .respectCacheHeaders(false)
            .build())
        setContent {
            CourtsideApp(model)
            // In full screen, switch the TV to a refresh rate that matches the stream (Settings › Player).
            val full = model.nowPlaying != null
            // While a stream is opening or playing (full screen or the player in the corner), keep the TV awake: without
            // this the screensaver comes on mid-game (Chromecast's is quick) and leaving the app stops the stream.
            val awake = (full || model.pinned != null) && Playback.status in
                setOf(Playback.Status.OPENING, Playback.Status.BUFFERING, Playback.Status.PLAYING)
            LaunchedEffect(awake) {
                if (awake) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
            LaunchedEffect(full, model.settings.matchFrameRate) { Playback.setFullScreen(full, model.settings.matchFrameRate) }
            // The TV's refresh rate changes only as a channel starts (switching it goes black for a moment), never a
            // few seconds into playback: a channel's frame rate from last time, or the stream's own if it says so
            // straight away. A rate counted while it plays (that takes about 4 seconds) is kept for next time.
            val channelId = model.nowPlaying?.channel?.id
            val target = androidx.compose.runtime.remember { androidx.compose.runtime.mutableFloatStateOf(0f) }
            LaunchedEffect(full, channelId, model.settings.matchFrameRate) {
                if (!full || !model.settings.matchFrameRate || channelId == null) { target.floatValue = 0f; return@LaunchedEffect }
                model.measuredFrameRate[channelId]?.takeIf { it > 0f }?.let { target.floatValue = it; return@LaunchedEffect }
                kotlinx.coroutines.withTimeoutOrNull(1500) {
                    androidx.compose.runtime.snapshotFlow { Playback.frameRate }.first { it > 0f }
                }?.let { target.floatValue = it }
            }
            LaunchedEffect(target.floatValue) { matchRefreshRate(target.floatValue) }
        }
    }

    /** Holding Back while something plays in the player at the top opens it full screen. */
    override fun onKeyLongPress(keyCode: Int, event: android.view.KeyEvent): Boolean {
        val item = model.pinned
        if (keyCode == android.view.KeyEvent.KEYCODE_BACK && model.nowPlaying == null && item != null) {
            model.play(item.channel, item.gameTitle, item.lineup, from = "strip")
            return true
        }
        return super.onKeyLongPress(keyCode, event)
    }

    override fun onResume() {
        super.onResume()
        Updater.afterInstall(this)
    }

    override fun onStart() {
        super.onStart()
        model.cameBack()
    }

    override fun onStop() {
        super.onStop()
        model.onScreen = false
        // Leaving the app (Home button) stops the stream, so it doesn't keep using a connection.
        Playback.stop()
        model.pinned = null
        if (model.nowPlaying != null) model.closePlayer()
        model.pinned = null
    }

    /** Picks the display mode at the current resolution whose refresh rate fits the frame rate (0 = back to default). */
    private fun matchRefreshRate(fps: Float) {
        val display: Display = (if (Build.VERSION.SDK_INT >= 30) display else null)
            ?: @Suppress("DEPRECATION") windowManager.defaultDisplay
        val params = window.attributes
        if (fps <= 0f) {
            if (params.preferredDisplayModeId != 0) {
                params.preferredDisplayModeId = 0
                window.attributes = params
            }
            return
        }
        val current = display.mode
        val candidates = display.supportedModes.filter {
            it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight
        }
        // A refresh rate that's a whole multiple of the frame rate shows every frame evenly (60 for 30, 50 for 25).
        val best = candidates.minByOrNull { mode ->
            val ratio = mode.refreshRate / fps
            val off = abs(ratio - ratio.roundToInt())
            off * 100 + (if (ratio.roundToInt() < 1) 1000f else 0f) + abs(mode.refreshRate - 60f) / 1000f
        } ?: return
        val ratio = best.refreshRate / fps
        if (abs(ratio - ratio.roundToInt()) > 0.02f) return
        if (params.preferredDisplayModeId != best.modeId) {
            params.preferredDisplayModeId = best.modeId
            window.attributes = params
        }
    }
}
