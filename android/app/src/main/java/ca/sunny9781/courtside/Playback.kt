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
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.video.MediaCodecVideoRenderer
import androidx.media3.exoplayer.video.VideoRendererEventListener
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
    /** The sound, like TiviMate shows it: "Stereo", "5.1 Dolby", "5.1 Atmos". */
    var audio by mutableStateOf("")
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
    /**
     * Low-power players (the Chromecast with Google TV has 2 GB): full screen always uses the fast video surface,
     * since drawing 4K the other way is too much for them.
     */
    var lowPower = false
        private set
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
        lowPower = (context.getSystemService(android.content.Context.ACTIVITY_SERVICE) as android.app.ActivityManager).let { am ->
            val info = android.app.ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
            am.isLowRamDevice || info.totalMem < 3L * 1024 * 1024 * 1024
        }
        // Some providers only answer players they know and send streams on through redirects (even to https).
        http = DefaultHttpDataSource.Factory()
            .setUserAgent("VLC/3.0.21 LibVLC/3.0.21")
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(10_000)
            .setReadTimeoutMs(15_000)
        player = ExoPlayer.Builder(context, FreshDecoderRenderers(context)).setLoadControl(load).build().apply {
            videoChangeFrameRateStrategy = C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_OFF
            addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(state: Int) = refreshStatus()
                override fun onIsPlayingChanged(isPlaying: Boolean) = refreshStatus()
                override fun onRenderedFirstFrame() {
                    firstFrame = true
                    fallbackUrl = null   // this format works: a later drop reopens it, never the other format
                }
                override fun onVideoSizeChanged(size: VideoSize) {
                    if (size.height > 0) resolution = label(size.height)
                    videoFormat?.frameRate?.takeIf { it > 0 }?.let { frameRate = if (it > 61) it / 2 else it }
                }
                override fun onPlayerError(error: PlaybackException) {
                    ConnLog.add("Stream error: ${error.errorCodeName}")
                    // It had been playing: the connection dropped, so open it again instead of stopping.
                    if (reconnectAfterDrop()) { status = Status.BUFFERING; return }
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
        // The player reconnecting by itself (a dropped or stalled download) shows in the connection log: that can
        // briefly count as two connections while the provider still sees the old one.
        player.addAnalyticsListener(object : androidx.media3.exoplayer.analytics.AnalyticsListener {
            override fun onLoadError(
                eventTime: androidx.media3.exoplayer.analytics.AnalyticsListener.EventTime,
                loadEventInfo: androidx.media3.exoplayer.source.LoadEventInfo,
                mediaLoadData: androidx.media3.exoplayer.source.MediaLoadData,
                error: java.io.IOException,
                wasCanceled: Boolean
            ) {
                if (!wasCanceled) ConnLog.add("Stream dropped, player reconnecting (${error.javaClass.simpleName})")
            }
        })
        // Headphones or a speaker connected or disconnected (Bluetooth, HDMI): a Dolby stream was set up for the old
        // output (sent to the TV as is, or decoded here), so it's reopened for the new one, otherwise it goes silent.
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
        audio.registerAudioDeviceCallback(object : android.media.AudioDeviceCallback() {
            private var ready = false
            override fun onAudioDevicesAdded(added: Array<out android.media.AudioDeviceInfo>) {
                // The first call lists what's already connected.
                if (ready) outputChanged() else ready = true
            }
            override fun onAudioDevicesRemoved(removed: Array<out android.media.AudioDeviceInfo>) = outputChanged()
        }, handler)
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
        droppedSince = 0L
        resolution = ""
        frameRate = 0f
        audio = ""
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

    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var pendingOpen: Runnable? = null

    private fun open(url: String) {
        status = Status.OPENING
        firstFrame = false
        openedAt = System.currentTimeMillis()
        attempt++
        // One connection at a time: close the old stream first and give the provider a moment to see it gone
        // before opening the next, so switching (or flipping quickly through channels) never counts as two.
        // Flipping fast only opens the channel you stop on.
        pendingOpen?.let { mainHandler.removeCallbacks(it) }
        val hadStream = player.mediaItemCount > 0
        if (hadStream) ConnLog.add("Closed ${player.currentMediaItem?.localConfiguration?.uri?.toString()?.let(ConnLog::stream) ?: "stream"}")
        player.stop()
        player.clearMediaItems()
        val run = Runnable {
            pendingOpen = null
            openedAt = System.currentTimeMillis()
            ConnLog.add("Opened ${ConnLog.stream(url)}")
            player.setMediaSource(source(url))
            player.prepare()
            player.playWhenReady = true
        }
        pendingOpen = run
        if (hadStream) mainHandler.postDelayed(run, 400) else run.run()
    }

    private var countFrom = 0L
    private var countFrames = 0

    /**
     * Many streams (most 4K ones) don't say their frame rate, so it's counted from the frames actually shown over
     * a few seconds and rounded to the usual rates (25, 29.97, 50, 59.94...).
     */
    private fun measureFrameRate() {
        if (frameRate > 0f || !firstFrame || !player.isPlaying) { countFrom = 0L; return }
        val counters = player.videoDecoderCounters ?: return
        counters.ensureUpdated()
        val frames = counters.renderedOutputBufferCount
        val now = System.currentTimeMillis()
        if (countFrom == 0L || frames < countFrames) { countFrom = now; countFrames = frames; return }
        val elapsed = now - countFrom
        if (elapsed < 4000) return
        val fps = (frames - countFrames) * 1000f / elapsed
        val rates = floatArrayOf(23.976f, 24f, 25f, 29.97f, 30f, 50f, 59.94f, 60f)
        val nearest = rates.minByOrNull { kotlin.math.abs(it - fps) } ?: return
        // Only when it's clearly one of them: a stuttering stream gives an in-between number, so it counts again.
        if (kotlin.math.abs(nearest - fps) <= nearest * 0.06f) frameRate = nearest else { countFrom = now; countFrames = frames }
    }

    fun stop() {
        pendingOpen?.let { mainHandler.removeCallbacks(it) }
        pendingOpen = null
        currentUrl?.let { ConnLog.add("Stopped ${ConnLog.stream(it)}") }
        player.stop()
        player.clearMediaItems()
        currentUrl = null
        fallbackUrl = null
        status = Status.IDLE
        resolution = ""
        frameRate = 0f
        audio = ""
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

    /**
     * The picture moved between full screen and the player at the top (two different kinds of video view). Some
     * TVs' decoders flicker green when a running stream is handed to a new view, so the stream is reopened there.
     */
    fun viewChanged() {
        if (!::player.isInitialized || currentUrl == null || !firstFrame) return
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            firstFrame = false
            openedAt = System.currentTimeMillis()
            player.stop()
            player.prepare()
            player.playWhenReady = true
        }
    }

    private val passthroughSound = setOf(
        androidx.media3.common.MimeTypes.AUDIO_AC3, androidx.media3.common.MimeTypes.AUDIO_E_AC3,
        androidx.media3.common.MimeTypes.AUDIO_E_AC3_JOC, androidx.media3.common.MimeTypes.AUDIO_AC4,
        androidx.media3.common.MimeTypes.AUDIO_DTS, androidx.media3.common.MimeTypes.AUDIO_DTS_HD,
        androidx.media3.common.MimeTypes.AUDIO_TRUEHD
    )

    private fun outputChanged() {
        if (!::player.isInitialized || currentUrl == null) return
        if (player.audioFormat?.sampleMimeType !in passthroughSound) return
        ConnLog.add("Sound output changed: reopening the stream")
        val url = player.currentMediaItem?.localConfiguration?.uri?.toString() ?: return
        // A moment for the new output to settle, then reopen (closing first, so it never counts as two connections).
        pendingOpen?.let { mainHandler.removeCallbacks(it) }
        val reopen = Runnable {
            pendingOpen = null
            player.setMediaSource(source(url)); player.prepare(); player.play()
        }
        val close = Runnable {
            player.stop()
            player.clearMediaItems()
            pendingOpen = reopen
            mainHandler.postDelayed(reopen, 400)
        }
        pendingOpen = close
        mainHandler.postDelayed(close, 800)
    }

    fun togglePause() {
        if (player.playWhenReady) player.pause() else player.play()
    }

    private var droppedSince = 0L
    private var lastReconnect = 0L

    /**
     * The stream dropped after it had shown a picture (the provider closed it, or the network went): open the same
     * stream again instead of stopping, every 3 seconds for up to 2 minutes. The old connection is already gone, so
     * this never makes two. False for a stream that never showed a picture (it fails as before) or after 2 minutes.
     */
    private fun reconnectAfterDrop(): Boolean {
        if (resolution.isEmpty() || currentUrl == null) return false
        val url = player.currentMediaItem?.localConfiguration?.uri?.toString() ?: currentUrl ?: return false
        val now = System.currentTimeMillis()
        if (droppedSince == 0L) droppedSince = now
        if (now - droppedSince >= 120_000) return false
        if (pendingOpen != null) return true   // already reopening
        val run = Runnable {
            pendingOpen = null
            lastReconnect = System.currentTimeMillis()
            ConnLog.add("Stream dropped: opening ${ConnLog.stream(url)} again")
            open(url)
        }
        pendingOpen = run
        mainHandler.postDelayed(run, maxOf(0L, 3000 - (now - lastReconnect)))
        return true
    }

    private fun refreshStatus() {
        status = when (player.playbackState) {
            Player.STATE_BUFFERING -> if (status == Status.OPENING) Status.OPENING else Status.BUFFERING
            Player.STATE_READY -> if (player.playWhenReady) { droppedSince = 0L; Status.PLAYING } else Status.PAUSED
            // A live stream never ends by itself: the provider closed the connection, so open it again.
            Player.STATE_ENDED -> if (reconnectAfterDrop()) Status.BUFFERING else Status.ENDED
            else -> if (currentUrl == null) Status.IDLE else status
        }
    }

    /**
     * No picture 8 seconds after opening: try the stream's other format (HLS or TS) once. After that, hiccups are
     * waited out with the connection open (like other IPTV apps); only a whole minute without progress reopens it.
     */
    private fun poll() {
        if (!::player.isInitialized || currentUrl == null) return
        measureFrameRate()
        soundLabel(player.audioFormat).let { if (it.isNotEmpty() && it != audio) audio = it }
        val fallback = fallbackUrl
        if (!firstFrame && fallback != null && player.playWhenReady && System.currentTimeMillis() - openedAt > 8000) {
            ConnLog.add("No picture after 8 s: trying the other format")
            fallbackUrl = null
            open(fallback)
            return
        }
        val watching = firstFrame && player.playWhenReady &&
            (status == Status.PLAYING || status == Status.BUFFERING || status == Status.OPENING)
        when (freeze.check(player.currentPosition.toDouble(), watching)) {
            FreezeWatch.Action.RESTART -> player.currentMediaItem?.localConfiguration?.uri?.toString()?.let { url ->
                // Close the frozen stream first and give the provider a moment, like switching channels: opening
                // the new one straight away counted as two connections (2/2) for a while.
                ConnLog.add("Picture froze: reopening ${ConnLog.stream(url)}")
                pendingOpen?.let { mainHandler.removeCallbacks(it) }
                player.stop()
                player.clearMediaItems()
                val run = Runnable {
                    pendingOpen = null
                    player.setMediaSource(source(url)); player.prepare(); player.play()
                }
                pendingOpen = run
                mainHandler.postDelayed(run, 400)
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

    fun soundLabel(f: androidx.media3.common.Format?): String {
        if (f == null) return ""
        val layout = when (val ch = f.channelCount) {
            Format_NO_VALUE, 0 -> ""
            1 -> "Mono"
            2 -> "Stereo"
            6 -> "5.1"
            8 -> "7.1"
            else -> "$ch ch"
        }
        val codec = when (f.sampleMimeType) {
            androidx.media3.common.MimeTypes.AUDIO_AC3 -> "Dolby"
            androidx.media3.common.MimeTypes.AUDIO_E_AC3 -> "Dolby+"
            androidx.media3.common.MimeTypes.AUDIO_E_AC3_JOC -> "Atmos"
            androidx.media3.common.MimeTypes.AUDIO_AC4 -> "AC-4"
            androidx.media3.common.MimeTypes.AUDIO_DTS, androidx.media3.common.MimeTypes.AUDIO_DTS_HD -> "DTS"
            androidx.media3.common.MimeTypes.AUDIO_TRUEHD -> "TrueHD"
            else -> ""
        }
        return listOf(layout, codec).filter { it.isNotEmpty() }.joinToString(" ")
    }

    private const val Format_NO_VALUE = androidx.media3.common.Format.NO_VALUE

    fun fpsLabel(fps: Float): String {
        val rounded = Math.round(fps * 100) / 100f
        return if (rounded % 1f == 0f) "${rounded.toInt()} fps" else "$rounded fps"
    }
}

/**
 * Notices a stream that has stopped moving. Hiccups are waited out with the connection open; only after a whole minute
 * without progress (a connection that died without saying so) does it ask for a quiet restart. Never SKIP any more.
 */
class FreezeWatch {
    enum class Action { NONE, RESTART, SKIP }

    private var lastProgress = -1.0
    private var lastChange = System.currentTimeMillis()

    fun reset() {
        lastProgress = -1.0
        lastChange = System.currentTimeMillis()
    }

    fun check(progress: Double, watching: Boolean): Action {
        val now = System.currentTimeMillis()
        if (!watching) { lastChange = now; return Action.NONE }
        if (progress != lastProgress) {
            lastProgress = progress
            if (lastChange < now) lastChange = now
            return Action.NONE
        }
        if (now - lastChange < 60_000) return Action.NONE
        lastProgress = -1.0
        lastChange = now + 6000      // a restart takes a few seconds to show a picture
        return Action.RESTART
    }
}

/**
 * When the picture moves between the player at the top and full screen (two kinds of video view), the video
 * decoder is started fresh on the new view instead of being handed over while it runs. Handing a running 4K
 * stream over left the picture fuzzy and unwatchable on the Chromecast with Google TV.
 */
@OptIn(UnstableApi::class)
private class FreshDecoderRenderers(context: Context) : DefaultRenderersFactory(context) {
    init {
        // Sound the TV box can't play itself (Dolby over Bluetooth headphones) is decoded by the app's own decoder,
        // used only when the box's own can't; over HDMI, Dolby still goes straight to the TV.
        setExtensionRendererMode(EXTENSION_RENDERER_MODE_ON)
    }

    override fun buildVideoRenderers(
        context: Context,
        extensionRendererMode: Int,
        mediaCodecSelector: MediaCodecSelector,
        enableDecoderFallback: Boolean,
        eventHandler: Handler,
        eventListener: VideoRendererEventListener,
        allowedVideoJoiningTimeMs: Long,
        out: ArrayList<Renderer>
    ) {
        out.add(object : MediaCodecVideoRenderer(
            context, mediaCodecSelector, allowedVideoJoiningTimeMs, enableDecoderFallback,
            eventHandler, eventListener, 50
        ) {
            override fun codecNeedsSetOutputSurfaceWorkaround(name: String) = true
        })
    }
}
