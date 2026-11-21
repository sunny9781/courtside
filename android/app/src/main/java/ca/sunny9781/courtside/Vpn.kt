package ca.sunny9781.courtside

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Built-in VPN (2.33, Settings › VPN): a WireGuard tunnel that carries only Courtside's own traffic (the rest of the
 * TV or phone stays on its normal connection). It comes up when the app comes on screen and goes down when you leave
 * it, so nothing runs in the background. While it's switched on, Courtside never talks to the provider without it:
 * no tunnel, no channels and no streams (`blocked`), so the provider never sees your real address by accident.
 */
object Vpn {
    enum class State { OFF, CONNECTING, ON, FAILED }

    var state by mutableStateOf(State.OFF)
        private set
    /** What went wrong (shown in Settings › VPN), or the server it's connected to. */
    var detail by mutableStateOf("")
        private set

    @Volatile private var prefs: android.content.SharedPreferences? = null
    private var backend: GoBackend? = null
    private val lock = Mutex()
    private var permission: CompletableDeferred<Boolean>? = null
    /** Asks Android for permission to run a VPN (MainActivity shows the system's dialog). */
    var askPermission: ((Intent) -> Unit)? = null

    private val tunnel = object : Tunnel {
        override fun getName() = "courtside"
        override fun onStateChange(newState: Tunnel.State) {
            // The tunnel went down by itself (another VPN app took over, say): stop talking to the provider.
            if (newState == Tunnel.State.DOWN && state == State.ON) {
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    state = State.FAILED
                    detail = "The VPN disconnected (another VPN app may have taken over)."
                    ConnLog.add("VPN disconnected")
                    Playback.stop()
                }
            }
        }
    }

    /** Reads the switch and config straight from the saved settings (the same ones Settings › VPN writes). */
    fun attach(context: android.content.Context) {
        if (prefs == null) prefs = context.applicationContext.getSharedPreferences("courtside", android.content.Context.MODE_PRIVATE)
    }
    private val savedConfig: String get() = prefs?.getString("vpnConfig", "") ?: ""

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    /** Coming on screen (or switched on): connect. Runs in order with [stop]. */
    fun start(activity: Activity) { scope.launch { connect(activity) } }
    /** Leaving the app (or switched off): disconnect. */
    fun stop() { scope.launch { disconnect() } }

    /** Switched on in Settings (with a config). */
    val wanted: Boolean get() = prefs?.let { it.getBoolean("vpnOn", false) && savedConfig.isNotBlank() } ?: false

    /** Switched on but not connected: the provider mustn't be reached. */
    val blocked: Boolean get() = wanted && state != State.ON

    /** Checks a WireGuard config (the .conf file's text). Null when it's fine, or what's wrong with it. */
    fun check(text: String): String? = runCatching { parse(text); null }
        .getOrElse { "That isn't a WireGuard config the app can use (${it.message ?: it.javaClass.simpleName})." }

    /** The config, changed so the tunnel carries only this app (any app list in the file is replaced). */
    private fun parse(text: String): Config {
        val out = StringBuilder()
        var inInterface = false
        var added = false
        for (raw in text.replace("\r", "").lines()) {
            val line = raw.trim()
            if (line.startsWith("[")) {
                if (inInterface && !added) { out.append("IncludedApplications = $PACKAGE\n"); added = true }
                inInterface = line.equals("[Interface]", ignoreCase = true)
            }
            val key = line.substringBefore('=').trim().lowercase()
            if (key == "includedapplications" || key == "excludedapplications") continue
            out.append(raw).append('\n')
        }
        if (inInterface && !added) out.append("IncludedApplications = $PACKAGE\n")
        val config = Config.parse(out.toString().byteInputStream())
        require(config.peers.isNotEmpty()) { "no [Peer]" }
        return config
    }

    /** The server's name, for Settings ("vpn.example.com"). */
    fun server(text: String): String = runCatching {
        parse(text).peers.firstOrNull()?.endpoint?.orElse(null)?.host ?: ""
    }.getOrDefault("")

    /** Called by MainActivity with the answer from Android's VPN permission dialog. */
    fun permissionAnswered(ok: Boolean) { permission?.complete(ok) }

    /** Brings the tunnel up (when it's switched on), asking for Android's permission the first time. */
    suspend fun connect(activity: Activity) {
        if (!wanted) { disconnect(); return }
        lock.withLock {
            if (state == State.ON) return
            state = State.CONNECTING
            detail = ""
            val config = runCatching { parse(savedConfig) }.getOrElse {
                fail("The saved WireGuard config couldn't be read. Send it again in Settings › VPN."); return
            }
            val intent = runCatching { VpnService.prepare(activity) }.getOrElse {
                fail("This device doesn't allow VPN apps."); return
            }
            if (intent != null) {
                val answer = CompletableDeferred<Boolean>().also { permission = it }
                val ask = askPermission
                if (ask == null || runCatching { ask(intent) }.isFailure) {
                    fail("This device can't show Android's VPN permission dialog."); return
                }
                if (!answer.await()) {
                    fail("Android's VPN permission was declined. Switch the VPN off, or on again to be asked again."); return
                }
            }
            val error = withContext(Dispatchers.IO) {
                runCatching {
                    val b = backend ?: GoBackend(activity.applicationContext).also { backend = it }
                    b.setState(tunnel, Tunnel.State.UP, config)
                    null
                }.getOrElse { it.message ?: it.javaClass.simpleName }
            }
            if (error != null) { fail("The VPN didn't connect: $error"); return }
            // WireGuard has no "connected" moment of its own: a short wait lets the first handshake happen before
            // the app starts loading through it.
            kotlinx.coroutines.delay(1500)
            state = State.ON
            detail = server(savedConfig)
            ConnLog.add("VPN connected")
        }
    }

    /** Takes the tunnel down (leaving the app, or switching it off). */
    suspend fun disconnect() {
        lock.withLock {
            val b = backend
            if (b != null && state != State.OFF) {
                withContext(Dispatchers.IO) { runCatching { b.setState(tunnel, Tunnel.State.DOWN, null) } }
                ConnLog.add("VPN off")
            }
            state = State.OFF
            detail = ""
        }
    }

    /** Waits (up to 20 s) for a tunnel that's still coming up. True when the provider may be reached now. */
    suspend fun ready(): Boolean {
        if (!wanted) return true
        withTimeoutOrNull(20_000) {
            while (state == State.CONNECTING || state == State.OFF) kotlinx.coroutines.delay(150)
        }
        return state == State.ON
    }

    /** For the provider requests: throws (with a message for the screen) while the VPN is on but not connected. */
    suspend fun require() {
        if (!ready()) throw XtreamException(
            "The VPN isn't connected, so Courtside won't contact your provider. Check Settings › VPN, or switch it off.")
    }

    private fun fail(message: String) {
        state = State.FAILED
        detail = message
        ConnLog.add("VPN failed")
    }

    private const val PACKAGE = "ca.sunny9781.courtside"
}
