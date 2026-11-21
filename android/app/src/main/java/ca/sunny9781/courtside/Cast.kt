package ca.sunny9781.courtside

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.mediarouter.media.MediaRouteSelector
import androidx.mediarouter.media.MediaRouter
import com.google.android.gms.cast.CastMediaControlIntent
import com.google.android.gms.cast.HlsSegmentFormat
import com.google.android.gms.cast.HlsVideoSegmentFormat
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.MediaStatus
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.cast.framework.SessionProvider
import com.google.android.gms.cast.framework.media.CastMediaOptions
import com.google.android.gms.cast.framework.media.NotificationOptions
import com.google.android.gms.cast.framework.media.RemoteMediaClient
import com.google.android.gms.common.images.WebImage

/**
 * Chromecast on the phone app, like the iPhone app: Google's Cast framework and its standard media receiver. While a
 * Chromecast (or a TV with Chromecast built in) is connected, streams play there instead of on the phone, using the
 * provider's HLS version of the channel (the receiver can't play plain TS). The phone's own player stops, so only
 * one provider connection is ever in use, and downloads wait while the TV plays.
 *
 * TVs never start any of this (no Cast on Fire TV, and a TV doesn't cast to itself).
 */
object Cast {
    /** The Chromecast's name while connected. */
    var deviceName by mutableStateOf<String?>(null)
        private set
    /** What the Chromecast is doing: "Loading…", "Playing", "Buffering…", "Paused", "Stopped", or an error. */
    var status by mutableStateOf("")
        private set
    /** Chromecasts on the network (while the app is open). */
    var routes by mutableStateOf<List<MediaRouter.RouteInfo>>(emptyList())
        private set
    /** Cast started this time (not on TVs, not without Google Play services, not after it crashed the app). */
    var ready by mutableStateOf(false)
        private set
    /** Turned off because starting it crashed the app last time (Settings › Playback can turn it back on). */
    var disabled by mutableStateOf(false)
        private set

    val connected get() = deviceName != null
    /** Something is loaded on the Chromecast (it's using a provider connection). */
    val hasMedia get() = connected && loaded
    private var loaded = false

    /** The connection changed (connected or disconnected): the model moves the stream there or back here. */
    var onChange: (() -> Unit)? = null
    /** A message for the user (a stream the Chromecast couldn't play). */
    var onMessage: ((String) -> Unit)? = null

    private var castContext: CastContext? = null
    private var router: MediaRouter? = null
    private var selector: MediaRouteSelector? = null

    private const val PREFS = "cast"

    fun setUp(context: Context) {
        if (ready) return
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val build = BuildConfig.VERSION_CODE
        if (p.getBoolean("starting", false)) {
            p.edit().putBoolean("starting", false).putBoolean("disabled", true).putInt("disabledBuild", build).apply()
        } else if (p.getBoolean("disabled", false) && p.getInt("disabledBuild", 0) != build) {
            // A new version may have fixed what crashed: try once more.
            p.edit().putBoolean("disabled", false).apply()
        }
        disabled = p.getBoolean("disabled", false)
        if (disabled) return
        p.edit().putBoolean("starting", true).commit()
        val ctx = runCatching { CastContext.getSharedInstance(context.applicationContext) }.getOrNull()
        if (ctx == null) { p.edit().putBoolean("starting", false).apply(); return }
        castContext = ctx
        ctx.sessionManager.addSessionManagerListener(listener, CastSession::class.java)
        ctx.sessionManager.currentCastSession?.let { if (it.isConnected) attach(it) }
        selector = MediaRouteSelector.Builder()
            .addControlCategory(CastMediaControlIntent.categoryForCast(CastMediaControlIntent.DEFAULT_MEDIA_RECEIVER_APPLICATION_ID))
            .build()
        router = runCatching { MediaRouter.getInstance(context.applicationContext) }.getOrNull()
        ready = true
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ p.edit().putBoolean("starting", false).apply() }, 10_000)
    }

    /** Settings › Playback: turn Cast back on (takes effect the next time the app opens). */
    fun enableAgain(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("disabled", false).apply()
    }

    private val routerCallback = object : MediaRouter.Callback() {
        override fun onRouteAdded(router: MediaRouter, route: MediaRouter.RouteInfo) = updateRoutes()
        override fun onRouteRemoved(router: MediaRouter, route: MediaRouter.RouteInfo) = updateRoutes()
        override fun onRouteChanged(router: MediaRouter, route: MediaRouter.RouteInfo) = updateRoutes()
    }

    private fun updateRoutes() {
        val r = router ?: return
        val s = selector ?: return
        routes = r.routes.filter { !it.isDefault && it.isEnabled && it.matchesSelector(s) }
    }

    /** Looks for Chromecasts while the app is on screen (Google's advice: not in the background). */
    fun discover(on: Boolean) {
        val r = router ?: return
        val s = selector ?: return
        runCatching {
            if (on) { r.addCallback(s, routerCallback, MediaRouter.CALLBACK_FLAG_REQUEST_DISCOVERY); updateRoutes() }
            else r.removeCallback(routerCallback)
        }
    }

    /** Connects to a Chromecast; once connected, whatever plays moves there. */
    fun connect(route: MediaRouter.RouteInfo) {
        status = "Connecting…"
        runCatching { router?.selectRoute(route) }
    }

    fun disconnect() {
        runCatching { castContext?.sessionManager?.endCurrentSession(true) }
    }

    private val client: RemoteMediaClient? get() = castContext?.sessionManager?.currentCastSession?.remoteMediaClient

    /** Plays a channel's HLS stream on the Chromecast. (The URL holds the login: never logged.) */
    fun load(url: String, title: String, subtitle: String, icon: String?) {
        val c = client ?: return
        val meta = MediaMetadata(MediaMetadata.MEDIA_TYPE_GENERIC).apply {
            putString(MediaMetadata.KEY_TITLE, title)
            putString(MediaMetadata.KEY_SUBTITLE, subtitle)
            if (!icon.isNullOrBlank()) runCatching { addImage(WebImage(Uri.parse(icon))) }
        }
        val info = MediaInfo.Builder(url)
            .setContentUrl(url)
            .setStreamType(MediaInfo.STREAM_TYPE_LIVE)
            .setContentType("application/x-mpegURL")
            .setHlsSegmentFormat(HlsSegmentFormat.TS)
            .setHlsVideoSegmentFormat(HlsVideoSegmentFormat.MPEG2_TS)
            .setMetadata(meta)
            .build()
        loaded = true
        status = "Loading…"
        ConnLog.add("Chromecast: opening a stream")
        runCatching {
            c.load(MediaLoadRequestData.Builder().setMediaInfo(info).setAutoplay(true).build()).setResultCallback { r ->
                if (!r.status.isSuccess) {
                    status = "Couldn't play this stream"
                    onMessage?.invoke("The Chromecast couldn't play this stream. Try another one.")
                }
            }
        }
    }

    /** Stops what's playing on the Chromecast (it stays connected). */
    fun stopMedia() {
        if (!loaded) return
        loaded = false
        status = "Stopped"
        ConnLog.add("Chromecast: stream stopped")
        runCatching { client?.stop() }
    }

    fun togglePause() { runCatching { client?.togglePlayback() } }

    val paused get() = client?.mediaStatus?.playerState == MediaStatus.PLAYER_STATE_PAUSED

    /** The phone's volume buttons (and the + / − buttons) change the TV's volume while casting. */
    fun volumeStep(up: Boolean) {
        val session = castContext?.sessionManager?.currentCastSession ?: return
        runCatching { session.volume = (session.volume + if (up) 0.05 else -0.05).coerceIn(0.0, 1.0) }
    }

    private val mediaCallback = object : RemoteMediaClient.Callback() {
        override fun onStatusUpdated() {
            val s = client?.mediaStatus ?: return
            status = when (s.playerState) {
                MediaStatus.PLAYER_STATE_PLAYING -> "Playing"
                MediaStatus.PLAYER_STATE_BUFFERING, MediaStatus.PLAYER_STATE_LOADING -> "Buffering…"
                MediaStatus.PLAYER_STATE_PAUSED -> "Paused"
                MediaStatus.PLAYER_STATE_IDLE -> when (s.idleReason) {
                    MediaStatus.IDLE_REASON_ERROR -> {
                        loaded = false
                        onMessage?.invoke("The Chromecast couldn't play this stream. Try another one.")
                        "Couldn't play this stream"
                    }
                    MediaStatus.IDLE_REASON_FINISHED, MediaStatus.IDLE_REASON_CANCELED -> { loaded = false; "Stopped" }
                    else -> status
                }
                else -> status
            }
        }
    }

    private var attachedClient: RemoteMediaClient? = null

    private fun attach(session: CastSession) {
        deviceName = session.castDevice?.friendlyName ?: "Chromecast"
        attachedClient?.unregisterCallback(mediaCallback)
        attachedClient = session.remoteMediaClient?.also { it.registerCallback(mediaCallback) }
        loaded = session.remoteMediaClient?.mediaStatus?.playerState.let { it != null && it != MediaStatus.PLAYER_STATE_IDLE }
        ConnLog.add("Chromecast: connected to ${deviceName}")
    }

    private fun detach() {
        attachedClient?.unregisterCallback(mediaCallback)
        attachedClient = null
        val was = deviceName
        deviceName = null
        loaded = false
        status = ""
        if (was != null) ConnLog.add("Chromecast: disconnected")
    }

    private val listener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarted(session: CastSession, sessionId: String) { attach(session); onChange?.invoke() }
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            val was = connected
            attach(session)
            if (!was) onChange?.invoke()
        }
        override fun onSessionEnded(session: CastSession, error: Int) { detach(); onChange?.invoke() }
        override fun onSessionStartFailed(session: CastSession, error: Int) {
            status = ""
            onMessage?.invoke("Couldn't connect to the Chromecast.")
        }
        override fun onSessionStarting(session: CastSession) { status = "Connecting…" }
        override fun onSessionEnding(session: CastSession) {}
        override fun onSessionResuming(session: CastSession, sessionId: String) {}
        override fun onSessionResumeFailed(session: CastSession, error: Int) {}
        override fun onSessionSuspended(session: CastSession, reason: Int) {}
    }
}

/** Tells Google's Cast framework to use its standard media receiver (named in the manifest). */
class CastOptionsProvider : OptionsProvider {
    override fun getCastOptions(context: Context): CastOptions =
        CastOptions.Builder()
            .setReceiverApplicationId(CastMediaControlIntent.DEFAULT_MEDIA_RECEIVER_APPLICATION_ID)
            .setStopReceiverApplicationWhenEndingSession(true)
            .setCastMediaOptions(CastMediaOptions.Builder()
                .setNotificationOptions(NotificationOptions.Builder()
                    .setTargetActivityClassName(MainActivity::class.java.name).build())
                .build())
            .build()

    override fun getAdditionalSessionProviders(context: Context): List<SessionProvider>? = null
}
