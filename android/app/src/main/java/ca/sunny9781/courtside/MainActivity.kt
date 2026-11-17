package ca.sunny9781.courtside

import android.os.Build
import android.os.Bundle
import android.view.Display
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.runtime.LaunchedEffect
import kotlin.math.abs
import kotlin.math.roundToInt

class MainActivity : ComponentActivity() {
    private val model: AppModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            CourtsideApp(model)
            // In full screen, switch the TV to a refresh rate that matches the stream (Settings › Player).
            val fps = Playback.frameRate
            val full = model.nowPlaying != null
            LaunchedEffect(full, model.settings.matchFrameRate) { Playback.setFullScreen(full, model.settings.matchFrameRate) }
            LaunchedEffect(fps, full) {
                matchRefreshRate(if (full && model.settings.matchFrameRate) fps else 0f)
            }
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

    override fun onStop() {
        super.onStop()
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
