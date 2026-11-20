package ca.sunny9781.courtside

import android.content.Context

/**
 * Which kind of device this is: a TV (Android TV, Google TV, Fire TV) gets the remote-driven TV app, anything else
 * (a phone or tablet) gets the touch app, laid out like the iPhone app. One APK for both.
 */
object Device {
    private var known: Boolean? = null

    fun isTv(context: Context): Boolean = known ?: run {
        val ui = context.getSystemService(Context.UI_MODE_SERVICE) as? android.app.UiModeManager
        val pm = context.packageManager
        val tv = ui?.currentModeType == android.content.res.Configuration.UI_MODE_TYPE_TELEVISION ||
            pm.hasSystemFeature(android.content.pm.PackageManager.FEATURE_LEANBACK) ||
            pm.hasSystemFeature("amazon.hardware.fire_tv") ||
            !pm.hasSystemFeature(android.content.pm.PackageManager.FEATURE_TOUCHSCREEN)
        known = tv
        tv
    }

    /** Set once in MainActivity before anything is drawn. */
    var tv = true
        private set

    fun detect(context: Context) { tv = isTv(context) }
}
