package ca.sunny9781.courtside

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.hls.DefaultHlsExtractorFactory
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory

/**
 * The one player in the app (Media3). The player at the top and full screen both show it; only one view is
 * attached at a time. Plays the provider's MPEG-TS stream, and falls back to HLS if that fails.
 */
@OptIn(UnstableApi::class)
object Playback {
    enum class Status { IDLE, OPENING, BUFFERING, PLAYING, PAUSED, FAILED, ENDED }

    lateinit var player: ExoPlayer
        private set

    var status by mutableStateOf(Status.IDLE)
        private set
    /** "1080p", "4K"… (empty until the first picture). */
    var resolution by mutableStateOf("")
        private set
    var frameRate by mutableStateOf(0f)
        private set

    /** Called when a stream keeps freezing even after restarting it, so the app can move to the next stream. */
    var onRepeatedFreezing: (() -> Unit)? = null

    var currentUrl: String? = null
        private set
    /** Goes up every time a stream (or its other format) is opened. */
    var attempt by mutableStateOf(0)
        private set
    private var firstFrame = false
    private var openedAt = 0L
    private lateinit var http: DefaultHttpDataSource.Factory

    /**
     * IPTV streams often start between keyframes and don't mark them: without these flags the picture can stay black
     * while the player waits for one that never comes.
     */
    private const val TS_FLAGS = DefaultTsPayloadReaderFactory.FLAG_ALLOW_NON_IDR_KEYFRAMES or
        DefaultTsPayloadReaderFactory.FLAG_DETECT_ACCESS_UNITS
    private var fallbackUrl: String? = null
    private val freeze = FreezeWatch()
    private val handler = Handler(Looper.getMainLooper())

    fun init(context: Context) {
        if (::player.isInitialized) return
        val bufferMs = Prefs.bufferMs(context)
        val load = DefaultLoadControl.Builder()
            .setBufferDurationsMs(maxOf(bufferMs, 2500), maxOf(bufferMs * 4, 15_000), bufferMs, bufferMs)
            .build()
        // Some providers only answer players they know and send streams on through redirects (even to https).
        http = DefaultHttpDataSource.Factory()
            .setUserAgent("VLC/3.0.21 LibVLC/3.0.21")
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(10_000)
            .setReadTimeoutMs(15_000)
        player = ExoPlayer.Builder(context).setLoadControl(load).build().apply {
            videoChangeFrameRateStrategy = C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_OFF
            addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(state: Int) = refreshStatus()
                override fun onIsPlayingChanged(isPlaying: Boolean) = refreshStatus()
                override fun onRenderedFirstFrame() { firstFrame = true }
                override fun onVideoSizeChanged(size: VideoSize) {
                    if (size.height > 0) resolution = label(size.height)
                    videoFormat?.frameRate?.takeIf { it > 0 }?.let { frameRate = if (it > 61) it / 2 else it }
                }
                override fun onPlayerError(error: PlaybackException) {
                    // TS didn't work: try the HLS version once before giving up.
                    val hls = fallbackUrl
                    if (hls != null) {
                        fallbackUrl = null
                        open(hls)
                    } else {
                        status = Status.FAILED
                    }
                }
            })
        }
        handler.post(object : Runnable {
            override fun run() {
                poll()
                handler.postDelayed(this, 500)
            }
        })
    }

    /** Plays a stream (the TS address, with the HLS address as a fallback). Already playing it: carries on. */
    fun play(url: String, hlsFallback: String?) {
        if (url == currentUrl && status != Status.IDLE && status != Status.ENDED && status != Status.FAILED) {
            if (!player.playWhenReady) player.play()
            return
        }
        freeze.reset()
        resolution = ""
        frameRate = 0f
        fallbackUrl = hlsFallback
        currentUrl = url
        open(url)
    }

    private fun source(url: String): MediaSource {
        val item = MediaItem.fromUri(url)
        return if (url.endsWith(".m3u8")) {
            HlsMediaSource.Factory(http)
                .setExtractorFactory(DefaultHlsExtractorFactory(TS_FLAGS, true))
                .setAllowChunklessPreparation(true)
                .createMediaSource(item)
        } else {
            ProgressiveMediaSource.Factory(http, DefaultExtractorsFactory().setTsExtractorFlags(TS_FLAGS)).createMediaSource(item)
        }
    }

    private fun open(url: String) {
        status = Status.OPENING
        firstFrame = false
        openedAt = System.currentTimeMillis()
        attempt++
        player.setMediaSource(source(url))
        player.prepare()
        player.playWhenReady = true
    }

    fun stop() {
        player.stop()
        player.clearMediaItems()
        currentUrl = null
        fallbackUrl = null
        status = Status.IDLE
        resolution = ""
        frameRate = 0f
    }

    /**
     * Only full screen may switch the TV's refresh rate to the stream's: the player at the top never does, so
     * opening a game doesn't make the TV change modes.
     */
    fun setFullScreen(full: Boolean, matchFrameRate: Boolean) {
        if (!::player.isInitialized) return
        player.videoChangeFrameRateStrategy =
            if (full && matchFrameRate) C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_ONLY_IF_SEAMLESS else C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_OFF
    }

    fun togglePause() {
        if (player.playWhenReady) player.pause() else player.play()
    }

    private fun refreshStatus() {
        status = when (player.playbackState) {
            Player.STATE_BUFFERING -> if (status == Status.OPENING) Status.OPENING else Status.BUFFERING
            Player.STATE_READY -> if (player.playWhenReady) Status.PLAYING else Status.PAUSED
            Player.STATE_ENDED -> Status.ENDED
            else -> if (currentUrl == null) Status.IDLE else status
        }
    }

    /**
     * No picture 8 seconds after opening: try the stream's other format (HLS or TS) once. Frozen for 4 seconds after
     * that: restart quietly (the resolution and frame rate stay shown); if it keeps happening, move on.
     */
    private fun poll() {
        if (!::player.isInitialized || currentUrl == null) return
        val fallback = fallbackUrl
        if (!firstFrame && fallback != null && player.playWhenReady && System.currentTimeMillis() - openedAt > 8000) {
            fallbackUrl = null
            open(fallback)
            return
        }
        val watching = firstFrame && player.playWhenReady &&
            (status == Status.PLAYING || status == Status.BUFFERING || status == Status.OPENING)
        when (freeze.check(player.currentPosition.toDouble(), watching)) {
            FreezeWatch.Action.RESTART -> player.currentMediaItem?.localConfiguration?.uri?.toString()?.let {
                player.setMediaSource(source(it)); player.prepare(); player.play()
            }
            FreezeWatch.Action.SKIP -> onRepeatedFreezing?.invoke()
            FreezeWatch.Action.NONE -> {}
        }
    }

    fun label(height: Int): String = when {
        height >= 2000 -> "4K"
        height >= 1000 -> "1080p"
        height >= 700 -> "720p"
        else -> "${height}p"
    }

    fun fpsLabel(fps: Float): String {
        val rounded = Math.round(fps * 100) / 100f
        return if (rounded % 1f == 0f) "${rounded.toInt()} fps" else "$rounded fps"
    }
}

/** Notices a stream that has stopped moving for 4 seconds: restart quietly, and after 3 times in 2 minutes, move on. */
class FreezeWatch {
    enum class Action { NONE, RESTART, SKIP }

    private var lastProgress = -1.0
    private var lastChange = System.currentTimeMillis()
    private val restarts = ArrayDeque<Long>()

    fun reset() {
        lastProgress = -1.0
        lastChange = System.currentTimeMillis()
        restarts.clear()
    }

    fun check(progress: Double, watching: Boolean): Action {
        val now = System.currentTimeMillis()
        if (!watching) { lastChange = now; return Action.NONE }
        if (progress != lastProgress) {
            lastProgress = progress
            if (lastChange < now) lastChange = now
            return Action.NONE
        }
        if (now - lastChange < 4000) return Action.NONE
        while (restarts.isNotEmpty() && now - restarts.first() > 120_000) restarts.removeFirst()
        restarts.addLast(now)
        lastProgress = -1.0
        lastChange = now + 6000      // a restart takes a few seconds to show a picture
        if (restarts.size >= 3) {
            restarts.clear()
            return Action.SKIP
        }
        return Action.RESTART
    }
}
