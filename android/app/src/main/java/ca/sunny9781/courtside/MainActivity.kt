package ca.sunny9781.courtside

import android.os.Build
import android.os.Bundle
import android.view.Display
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
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
        Device.detect(this)
        if (Device.tv) {
            requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        } else {
            // Phones: drawn edge to edge (the app pads for the bars itself), light icons on the dark app, and free to
            // turn sideways (sideways on a game goes full screen, like the iPhone app).
            enableEdgeToEdge(
                statusBarStyle = androidx.activity.SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
                navigationBarStyle = androidx.activity.SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))
        }
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
        // Built-in VPN (Settings › VPN): Android's permission dialog opens from here.
        Vpn.askPermission = { vpnPermission.launch(it) }
        // Logos: a small memory cache and no fade-in animation (cheap on low-power TVs).
        coil.Coil.setImageLoader(coil.ImageLoader.Builder(this)
            .memoryCache { coil.memory.MemoryCache.Builder(this).maxSizePercent(0.08).build() }
            .crossfade(false)
            // Logos in 16-bit colour: half the memory, so less clearing up (pauses) on 2 GB TVs.
            .allowRgb565(true)
            .respectCacheHeaders(false)
            .build())
        if (!Device.tv) {
            // Chromecast (phone app only).
            Cast.setUp(this)
            Cast.onChange = { model.castChanged() }
            Cast.onMessage = { model.notice = it }
        }
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
            // Phones: leaving the app while something plays carries on in a small floating window (picture in picture).
            LaunchedEffect(awake, Cast.connected) { if (!Device.tv) updatePip(awake && !Cast.connected) }
            // Refresh-rate matching is for TVs only.
            val match = model.settings.matchFrameRate && Device.tv
            LaunchedEffect(full, match) { Playback.setFullScreen(full, match) }
            // The TV's refresh rate changes only as a channel starts (switching it goes black for a moment), never a
            // few seconds into playback: a channel's frame rate from last time, or the stream's own if it says so
            // straight away. A rate counted while it plays (that takes about 4 seconds) is kept for next time.
            val channelId = model.nowPlaying?.channel?.id
            val target = androidx.compose.runtime.remember { androidx.compose.runtime.mutableFloatStateOf(0f) }
            LaunchedEffect(full, channelId, match) {
                if (!full || !match || channelId == null) { target.floatValue = 0f; return@LaunchedEffect }
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
        if (keyCode == android.view.KeyEvent.KEYCODE_BACK && model.nowPlaying == null && !model.multiview && item != null) {
            model.play(item.channel, item.gameTitle, item.lineup, from = "strip")
            return true
        }
        return super.onKeyLongPress(keyCode, event)
    }

    private val vpnPermission = registerForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.StartActivityForResult()) {
        Vpn.permissionAnswered(it.resultCode == RESULT_OK)
    }

    private var pipReady = false

    private fun pipParams(auto: Boolean): android.app.PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < 26) return null
        val b = android.app.PictureInPictureParams.Builder().setAspectRatio(android.util.Rational(16, 9))
        if (Build.VERSION.SDK_INT >= 31) b.setAutoEnterEnabled(auto).setSeamlessResizeEnabled(false)
        return b.build()
    }

    /** Android 12 and up: swiping home while something plays goes into picture in picture by itself. */
    private fun updatePip(playing: Boolean) {
        pipReady = playing
        if (Build.VERSION.SDK_INT >= 31) runCatching { pipParams(playing)?.let { setPictureInPictureParams(it) } }
    }

    /** The full-screen player's picture-in-picture button, and leaving the app on Android 8 to 11. */
    fun enterPip(): Boolean {
        if (Device.tv || Build.VERSION.SDK_INT < 26) return false
        if (!packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)) return false
        return runCatching { enterPictureInPictureMode(pipParams(pipReady)!!) }.getOrDefault(false)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (!Device.tv && pipReady && Build.VERSION.SDK_INT in 26..30) enterPip()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: android.content.res.Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        PhoneUi.inPip = isInPictureInPictureMode
    }

    override fun onResume() {
        super.onResume()
        Updater.inFront = true
        Updater.afterInstall(this)
        Cast.discover(true)
    }

    override fun onPause() {
        super.onPause()
        Updater.inFront = false
        Cast.discover(false)
    }

    /** While casting, the phone's volume buttons change the TV's volume. */
    override fun dispatchKeyEvent(event: android.view.KeyEvent): Boolean {
        if (!Device.tv && Cast.connected &&
            (event.keyCode == android.view.KeyEvent.KEYCODE_VOLUME_UP || event.keyCode == android.view.KeyEvent.KEYCODE_VOLUME_DOWN)) {
            if (event.action == android.view.KeyEvent.ACTION_DOWN) Cast.volumeStep(event.keyCode == android.view.KeyEvent.KEYCODE_VOLUME_UP)
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onStart() {
        super.onStart()
        // The built-in VPN comes up while the app is on screen only (provider requests wait for it).
        if (Vpn.wanted) Vpn.start(this)
        model.cameBack()
    }

    override fun onStop() {
        super.onStop()
        model.onScreen = false
        // Multiview's second tile stops too (2.30).
        model.stopMultiview()
        // Casting: the TV carries on playing (the phone isn't using a connection).
        if (Cast.connected) { Playback.stop(); Vpn.stop(); return }
        // Leaving the app (Home button) stops the stream, so it doesn't keep using a connection.
        Playback.stop()
        model.pinned = null
        if (model.nowPlaying != null) model.closePlayer()
        model.pinned = null
        Vpn.stop()
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
