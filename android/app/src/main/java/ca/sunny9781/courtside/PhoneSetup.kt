package ca.sunny9781.courtside

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.net.URLDecoder
import kotlin.concurrent.thread

/**
 * Set up from your phone: while the sign-in screen is showing, the TV serves a small web page on the home network.
 * The phone scans the QR code (or types the address), fills in the Xtream details and sends them straight to the TV.
 * Nothing goes through the internet, and the details are never logged. A PIN (in the QR code) stops anyone else on
 * the Wi-Fi from sending a login; five wrong PINs make a new one.
 */
class PhoneSetupServer(private val onLogin: suspend (Credentials) -> String?,
                       /** Settings › VPN (2.33): the page takes a WireGuard config instead of the Xtream login. */
                       private val onVpn: (suspend (String) -> String?)? = null) {
    @Volatile var pin: String = newPin(); private set
    @Volatile private var socket: ServerSocket? = null
    private var wrong = 0
    /** Tells the screen the PIN changed. */
    var onPinChange: (String) -> Unit = {}

    val port: Int get() = socket?.localPort ?: 0

    fun start(): Boolean {
        val s = runCatching { ServerSocket().apply { reuseAddress = true; bind(InetSocketAddress(PORT)) } }
            .recoverCatching { ServerSocket(0) }.getOrNull() ?: return false
        socket = s
        thread(name = "phone-setup", isDaemon = true) {
            while (!s.isClosed) {
                val client = runCatching { s.accept() }.getOrNull() ?: break
                thread(isDaemon = true) { runCatching { handle(client) }; runCatching { client.close() } }
            }
        }
        ConnLog.add("Phone setup page on")
        return true
    }

    fun stop() {
        runCatching { socket?.close() }
        socket = null
    }

    private fun handle(client: Socket) {
        client.soTimeout = 15_000
        val input = BufferedInputStream(client.getInputStream())
        val requestLine = readLine(input) ?: return
        var length = 0
        while (true) {
            val h = readLine(input) ?: break
            if (h.isEmpty()) break
            if (h.lowercase().startsWith("content-length:")) length = h.substringAfter(':').trim().toIntOrNull() ?: 0
        }
        val parts = requestLine.split(" ")
        val method = parts.getOrNull(0) ?: ""
        val target = parts.getOrNull(1) ?: "/"
        val path = target.substringBefore('?')
        val query = parse(target.substringAfter('?', ""))
        val out = client.getOutputStream()
        fun send(code: String, html: String) {
            val body = html.toByteArray()
            out.write(("HTTP/1.1 $code\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: ${body.size}\r\n" +
                "Cache-Control: no-store\r\nConnection: close\r\n\r\n").toByteArray())
            out.write(body)
            out.flush()
        }
        when {
            method == "GET" && path == "/" ->
                send("200 OK", if (onVpn != null) vpnPage(query["pin"].orEmpty(), null) else page(query["pin"].orEmpty(), null, null))
            method == "POST" && path == "/vpn" && onVpn != null -> {
                val bytes = ByteArray(length.coerceIn(0, 32768))
                var read = 0
                while (read < bytes.size) { val n = input.read(bytes, read, bytes.size - read); if (n < 0) break; read += n }
                val form = parse(String(bytes, 0, read))
                if (form["pin"]?.trim() != pin) {
                    synchronized(this) {
                        wrong++
                        if (wrong >= 5) { wrong = 0; pin = newPin(); onPinChange(pin) }
                    }
                    send("200 OK", vpnPage("", "That PIN doesn't match the one on the TV."))
                    return
                }
                val config = form["config"].orEmpty().trim()
                if (config.isEmpty()) { send("200 OK", vpnPage(pin, "Paste the WireGuard config first.")); return }
                ConnLog.add("Phone setup: VPN config received")
                val error = runBlocking(Dispatchers.Main) { onVpn.invoke(config) }
                if (error == null) send("200 OK", done("VPN config saved", "The TV is connecting to the VPN. You can close this page."))
                else send("200 OK", vpnPage(pin, error))
            }
            method == "POST" && path == "/login" -> {
                val bytes = ByteArray(length.coerceIn(0, 8192))
                var read = 0
                while (read < bytes.size) { val n = input.read(bytes, read, bytes.size - read); if (n < 0) break; read += n }
                val form = parse(String(bytes, 0, read))
                val creds = Credentials(form["server"].orEmpty().trim(), form["username"].orEmpty().trim(), form["password"].orEmpty())
                if (form["pin"]?.trim() != pin) {
                    synchronized(this) {
                        wrong++
                        if (wrong >= 5) { wrong = 0; pin = newPin(); onPinChange(pin) }
                    }
                    send("200 OK", page("", "That PIN doesn't match the one on the TV.", creds.copy(password = "")))
                    return
                }
                if (creds.server.isEmpty() || creds.username.isEmpty() || creds.password.isEmpty()) {
                    send("200 OK", page(pin, "Fill in the server, username and password.", creds.copy(password = "")))
                    return
                }
                ConnLog.add("Phone setup: details received")
                val server = if (creds.server.startsWith("http")) creds.server else "http://${creds.server}"
                val error = runBlocking(Dispatchers.Main) { onLogin(creds.copy(server = server)) }
                if (error == null) send("200 OK", done())
                else send("200 OK", page(pin, error, creds.copy(password = "")))
            }
            else -> send("404 Not Found", "<h1>Not found</h1>")
        }
    }

    private fun readLine(input: BufferedInputStream): String? {
        val buf = ByteArrayOutputStream()
        while (true) {
            val b = input.read()
            if (b < 0) return if (buf.size() == 0) null else buf.toString()
            if (b == '\n'.code) return buf.toString().trimEnd('\r')
            if (buf.size() > 8192) return null
            buf.write(b)
        }
    }

    private fun parse(s: String): Map<String, String> = s.split('&').filter { it.contains('=') }.associate {
        val k = it.substringBefore('='); val v = it.substringAfter('=')
        runCatching { URLDecoder.decode(k, "UTF-8") }.getOrDefault(k) to runCatching { URLDecoder.decode(v, "UTF-8") }.getOrDefault(v)
    }

    private fun esc(s: String) = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

    private val style = """
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body{margin:0;background:#0E1116;color:#F2F4F7;font:16px -apple-system,system-ui,sans-serif;padding:28px 20px}
          h1{font-size:24px;margin:0 0 4px} p{color:#9AA3B2;margin:0 0 20px}
          label{display:block;font-size:13px;color:#9AA3B2;margin:14px 0 6px}
          input{width:100%;box-sizing:border-box;background:#171B22;color:#F2F4F7;border:1.5px solid #2E3643;
                border-radius:10px;padding:12px;font-size:16px}
          input:focus{outline:none;border-color:#FF8A3D}
          button{width:100%;margin-top:24px;background:#FF8A3D;color:#14100C;border:0;border-radius:10px;padding:14px;
                 font-size:17px;font-weight:600}
          .err{background:#3a1d1d;color:#F87171;border-radius:10px;padding:12px;margin-bottom:8px}
          .ok{font-size:56px;color:#4ADE80;margin:30px 0 10px}
        </style>"""

    private fun page(pinValue: String, error: String?, prefill: Credentials?): String = """
        <!doctype html><html><head><title>Courtside setup</title>$style</head><body>
        <h1>Courtside</h1><p>Send your Xtream Codes details to the TV.</p>
        ${error?.let { "<div class=\"err\">${esc(it)}</div>" } ?: ""}
        <form method="post" action="/login" onsubmit="this.querySelector('button').textContent='Signing in…'">
          <label>Server</label><input name="server" type="url" inputmode="url" autocapitalize="off" autocorrect="off"
            placeholder="http://example.com:8080" value="${esc(prefill?.server ?: "")}" required>
          <label>Username</label><input name="username" autocapitalize="off" autocorrect="off" autocomplete="username"
            value="${esc(prefill?.username ?: "")}" required>
          <label>Password</label><input name="password" type="password" autocomplete="current-password" required>
          <label>PIN on the TV</label><input name="pin" inputmode="numeric" pattern="[0-9]*" maxlength="4"
            value="${esc(pinValue)}" required>
          <button type="submit">Send to TV</button>
        </form></body></html>"""

    private fun done(title: String = "Signed in", detail: String = "The TV is loading your channels. You can close this page."): String = """
        <!doctype html><html><head><title>Courtside setup</title>$style</head><body style="text-align:center">
        <div class="ok">✓</div><h1>${esc(title)}</h1><p>${esc(detail)}</p>
        </body></html>"""

    /** Settings › VPN: paste the WireGuard config (or pick the .conf file) and send it to the TV. */
    private fun vpnPage(pinValue: String, error: String?): String = """
        <!doctype html><html><head><title>Courtside VPN</title>$style
        <style>textarea{width:100%;box-sizing:border-box;min-height:220px;background:#171B22;color:#F2F4F7;
          border:1.5px solid #2E3643;border-radius:10px;padding:12px;font:13px ui-monospace,Menlo,monospace}
          input[type=file]{padding:10px}</style></head><body>
        <h1>Courtside VPN</h1><p>Send a WireGuard config to the TV. Only Courtside will use it.</p>
        ${error?.let { "<div class=\"err\">${esc(it)}</div>" } ?: ""}
        <form method="post" action="/vpn" onsubmit="this.querySelector('button').textContent='Sending…'">
          <label>WireGuard config (.conf file)</label>
          <input type="file" accept=".conf,text/plain" onchange="var f=this.files[0];if(f){var r=new FileReader();
            r.onload=function(){document.getElementById('c').value=r.result};r.readAsText(f)}">
          <textarea id="c" name="config" autocapitalize="off" autocorrect="off" spellcheck="false"
            placeholder="[Interface]&#10;PrivateKey = …&#10;Address = …&#10;&#10;[Peer]&#10;PublicKey = …&#10;Endpoint = …" required></textarea>
          <label>PIN on the TV</label><input name="pin" inputmode="numeric" pattern="[0-9]*" maxlength="4"
            value="${esc(pinValue)}" required>
          <button type="submit">Send to TV</button>
        </form></body></html>"""

    companion object {
        const val PORT = 8642
        private fun newPin() = (1000..9999).random().toString()

        /** The TV's address on the home network (Wi-Fi or Ethernet), or null when it isn't on one. */
        fun localAddress(): String? = runCatching {
            NetworkInterface.getNetworkInterfaces().toList()
                .filter { it.isUp && !it.isLoopback && !it.isVirtual }
                .sortedBy { if (it.name.startsWith("eth")) 0 else if (it.name.startsWith("wlan")) 1 else 2 }
                .flatMap { it.inetAddresses.toList() }
                .filterIsInstance<Inet4Address>()
                .firstOrNull { it.isSiteLocalAddress }?.hostAddress
        }.getOrNull()

        fun qr(text: String, size: Int = 360): ImageBitmap? = runCatching {
            val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size, mapOf(EncodeHintType.MARGIN to 1))
            val pixels = IntArray(size * size) { i -> if (matrix[i % size, i / size]) 0xFF000000.toInt() else 0xFFFFFFFF.toInt() }
            Bitmap.createBitmap(pixels, size, size, Bitmap.Config.ARGB_8888).asImageBitmap()
        }.getOrNull()
    }
}

/** The right-hand side of the TV sign-in screen: QR code, address and PIN, while the setup page is on. */
@Composable
fun PhoneSetupPanel(title: String = "Or set up from your phone", onVpn: (suspend (String) -> String?)? = null,
                    onLogin: suspend (Credentials) -> String?) {
    val latest by rememberUpdatedState(onLogin)
    val latestVpn by rememberUpdatedState(onVpn)
    val server = remember { PhoneSetupServer({ latest(it) }, if (onVpn != null) { c -> latestVpn?.invoke(c) } else null) }
    var pin by remember { mutableStateOf(server.pin) }
    var started by remember { mutableStateOf(false) }
    val address = remember { PhoneSetupServer.localAddress() }
    DisposableEffect(Unit) {
        server.onPinChange = { p -> android.os.Handler(android.os.Looper.getMainLooper()).post { pin = p } }
        started = address != null && server.start()
        onDispose { server.stop() }
    }
    val base = if (started && address != null) {
        val port = server.port
        if (port == 80) "http://$address" else "http://$address:$port"
    } else null
    val code = remember(base, pin) { base?.let { PhoneSetupServer.qr("$it/?pin=$pin") } }
    Column(Modifier.width(300.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Label(title, size = 17.sp, weight = FontWeight.SemiBold)
        Spacer(Modifier.height(4.dp))
        if (base == null || code == null) {
            Label("Connect the TV to your home network to use your phone.", size = 13.sp, color = Theme.muted, maxLines = 3)
            return@Column
        }
        Label("Scan with your phone's camera", size = 13.sp, color = Theme.muted)
        Spacer(Modifier.height(14.dp))
        Box(Modifier.size(200.dp).clip(RoundedCornerShape(12.dp)).background(androidx.compose.ui.graphics.Color.White).padding(8.dp)) {
            Image(code, contentDescription = "QR code", filterQuality = FilterQuality.None, modifier = Modifier.fillMaxSize())
        }
        Spacer(Modifier.height(14.dp))
        Label("or go to", size = 12.sp, color = Theme.muted)
        Label(base.removePrefix("http://"), size = 15.sp, weight = FontWeight.SemiBold)
        Spacer(Modifier.height(8.dp))
        Label("PIN  $pin", size = 20.sp, weight = FontWeight.Bold, color = Theme.accent)
        Spacer(Modifier.height(6.dp))
        Label("Phone and TV need to be on the same Wi-Fi.", size = 12.sp, color = Theme.muted, maxLines = 2)
    }
}
