package com.sergio.escritorio_abanico

import android.Manifest
import android.app.ActivityOptions
import android.app.Notification
import android.app.PendingIntent
import android.app.RemoteInput
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.AlarmClock
import android.provider.Settings
import android.service.notification.StatusBarNotification
import android.view.Gravity
import android.view.View
import android.widget.TextView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newFixedThreadPool(3)
    private val ui = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null

    // Widgets de Android alojados en el escritorio
    private val hostId = 4711
    private val reqBind = 9001
    private val reqConfig = 9002
    private var widgetHost: AppWidgetHost? = null
    private var widgetManager: AppWidgetManager? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingWidgetId = -1

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        widgetManager = AppWidgetManager.getInstance(this)
        widgetHost = AppWidgetHost(applicationContext, hostId).also { h -> try { h.startListening() } catch (e: Exception) {} }
        flutterEngine.platformViewsController.registry.registerViewFactory("abanico/widget", WidgetFactory())
        NotiBridge.onChange = { ui.post { pushNotifs() } }
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "abanico/native")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "apps" -> worker.execute {
                    try {
                        val pm = packageManager
                        val query = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                        val list = pm.queryIntentActivities(query, 0)
                            .filter { it.activityInfo.packageName != packageName }
                            .map { mapOf("label" to it.loadLabel(pm).toString(), "pkg" to it.activityInfo.packageName) }
                            .distinctBy { it["pkg"] }
                            .sortedBy { (it["label"] ?: "").lowercase() }
                        ui.post { result.success(list) }
                    } catch (e: Exception) {
                        ui.post { result.error("apps", e.message, null) }
                    }
                }
                "icon" -> {
                    val pkg = call.argument<String>("pkg") ?: ""
                    worker.execute {
                        val bytes = try { toPng(packageManager.getApplicationIcon(pkg), 160) } catch (e: Exception) { null }
                        ui.post { result.success(bytes) }
                    }
                }
                "launch" -> {
                    val pkg = call.argument<String>("pkg") ?: ""
                    val intent = packageManager.getLaunchIntentForPackage(pkg)
                    if (intent != null) {
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } else result.success(false)
                }
                "openUrl" -> {
                    val uri = Uri.parse(call.argument<String>("url") ?: "")
                    val pkg = call.argument<String>("pkg") ?: ""
                    var ok = false
                    if (pkg.isNotEmpty()) {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, uri).setPackage(pkg)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            ok = true
                        } catch (e: Exception) { ok = false }
                    }
                    if (!ok) {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, uri)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            ok = true
                        } catch (e: Exception) { ok = false }
                    }
                    result.success(ok)
                }
                "browsers" -> worker.execute {
                    try {
                        val pm = packageManager
                        val query = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.google.com")).addCategory(Intent.CATEGORY_BROWSABLE)
                        val list = pm.queryIntentActivities(query, PackageManager.MATCH_ALL)
                            .filter { it.activityInfo.packageName != packageName }
                            .map { mapOf("label" to it.loadLabel(pm).toString(), "pkg" to it.activityInfo.packageName) }
                            .distinctBy { it["pkg"] }
                            .sortedBy { (it["label"] ?: "").lowercase() }
                        ui.post { result.success(list) }
                    } catch (e: Exception) {
                        ui.post { result.success(listOf<Map<String, String>>()) }
                    }
                }
                "appInfo" -> {
                    try {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + (call.argument<String>("pkg") ?: "")))
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                    } catch (e: Exception) {}
                    result.success(true)
                }
                "homeSettings" -> {
                    try { startActivity(Intent(Settings.ACTION_HOME_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                    catch (e: Exception) { startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                    result.success(true)
                }
                "hasAllFiles" -> result.success(hasAllFiles())
                "requestAllFiles" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        try {
                            startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:$packageName")))
                        } catch (e: Exception) {
                            startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                        }
                    } else {
                        requestPermissions(arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE, Manifest.permission.WRITE_EXTERNAL_STORAGE), 7)
                    }
                    result.success(true)
                }
                "alarms" -> result.success(openAlarms())
                "calendar" -> {
                    var ok = false
                    try {
                        startActivity(Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_CALENDAR).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        ok = true
                    } catch (e: Exception) { ok = false }
                    result.success(ok)
                }
                "widgetProviders" -> worker.execute {
                    try {
                        val pm = packageManager
                        val density = resources.displayMetrics.density
                        val list = (widgetManager?.installedProviders ?: listOf())
                            .filter { it.provider.packageName != packageName }
                            .map {
                                val appLabel = try { pm.getApplicationLabel(pm.getApplicationInfo(it.provider.packageName, 0)).toString() } catch (e: Exception) { it.provider.packageName }
                                mapOf(
                                    "label" to it.loadLabel(pm).toString(),
                                    "app" to appLabel,
                                    "pkg" to it.provider.packageName,
                                    "cls" to it.provider.className,
                                    "minW" to (it.minWidth / density).toDouble(),
                                    "minH" to (it.minHeight / density).toDouble()
                                )
                            }
                            .sortedWith(compareBy<Map<String, Any>>({ (it["app"] as String).lowercase() }, { (it["label"] as String).lowercase() }))
                        ui.post { result.success(list) }
                    } catch (e: Exception) {
                        ui.post { result.success(listOf<Map<String, Any>>()) }
                    }
                }
                "addWidget" -> {
                    val host = widgetHost
                    val mgr = widgetManager
                    if (host == null || mgr == null) { result.success(-1) } else {
                        val cn = ComponentName(call.argument<String>("pkg") ?: "", call.argument<String>("cls") ?: "")
                        val id = host.allocateAppWidgetId()
                        val bound = try { mgr.bindAppWidgetIdIfAllowed(id, cn) } catch (e: Exception) { false }
                        if (bound) {
                            configureOrFinish(id, result)
                        } else {
                            pendingResult = result
                            pendingWidgetId = id
                            val intent = Intent(AppWidgetManager.ACTION_APPWIDGET_BIND)
                            intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                            intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER, cn)
                            try { startActivityForResult(intent, reqBind) } catch (e: Exception) {
                                host.deleteAppWidgetId(id)
                                pendingResult = null
                                result.success(-1)
                            }
                        }
                    }
                }
                "removeWidget" -> {
                    val id = call.argument<Int>("id") ?: -1
                    try { if (id >= 0) widgetHost?.deleteAppWidgetId(id) } catch (e: Exception) {}
                    result.success(true)
                }
                "widgetExists" -> {
                    val id = call.argument<Int>("id") ?: -1
                    result.success(id >= 0 && widgetManager?.getAppWidgetInfo(id) != null)
                }
                "notifs" -> {
                    ensureListener()
                    result.success(notifList())
                }
                "notifAccess" -> result.success(hasNotifAccess())
                "notifStatus" -> {
                    ensureListener()
                    result.success(mapOf(
                        "access" to hasNotifAccess(),
                        "connected" to (NotiBridge.service != null),
                        "count" to NotiBridge.items.size,
                        "seen" to NotiBridge.seen
                    ))
                }
                "requestNotifAccess" -> {
                    try { startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                    catch (e: Exception) { startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                    result.success(true)
                }
                "openNotif" -> {
                    val sbn = NotiBridge.items[call.argument<String>("key") ?: ""]
                    var ok = false
                    if (sbn != null) {
                        val pi = sbn.notification.contentIntent
                        if (pi != null) ok = sendPending(pi, null)
                        if (!ok) {
                            val launch = packageManager.getLaunchIntentForPackage(sbn.packageName)
                            if (launch != null) {
                                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(launch)
                                ok = true
                            }
                        }
                        if (ok && (sbn.notification.flags and Notification.FLAG_AUTO_CANCEL) != 0) {
                            try { NotiBridge.service?.cancelNotification(sbn.key) } catch (e: Exception) {}
                        }
                    }
                    result.success(ok)
                }
                "dismissNotif" -> {
                    val key = call.argument<String>("key") ?: ""
                    try { NotiBridge.service?.cancelNotification(key) } catch (e: Exception) {}
                    if (NotiBridge.items.remove(key) != null) pushNotifs()
                    result.success(true)
                }
                "replyNotif" -> {
                    val sbn = NotiBridge.items[call.argument<String>("key") ?: ""]
                    val text = call.argument<String>("text") ?: ""
                    val action = if (sbn != null) replyAction(sbn) else null
                    val inputs = action?.remoteInputs
                    if (action == null || inputs == null || text.isBlank()) {
                        result.success(false)
                    } else {
                        try {
                            val intent = Intent()
                            val bundle = Bundle()
                            for (ri in inputs) bundle.putCharSequence(ri.resultKey, text)
                            RemoteInput.addResultsToIntent(inputs, intent, bundle)
                            result.success(sendPending(action.actionIntent, intent))
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.hasCategory(Intent.CATEGORY_HOME)) channel?.invokeMethod("home", null)
    }

    override fun onStart() {
        super.onStart()
        try { widgetHost?.startListening() } catch (e: Exception) {}
    }

    override fun onStop() {
        super.onStop()
        try { widgetHost?.stopListening() } catch (e: Exception) {}
    }

    override fun onDestroy() {
        NotiBridge.onChange = null
        super.onDestroy()
    }

    private fun hasNotifAccess(): Boolean {
        if (Build.VERSION.SDK_INT >= 27) {
            try {
                val nm = getSystemService(android.app.NotificationManager::class.java)
                if (nm != null) return nm.isNotificationListenerAccessGranted(ComponentName(this, NotiService::class.java))
            } catch (e: Exception) {}
        }
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        return flat.split(":").any { it.startsWith("$packageName/") }
    }

    /** Si hay permiso pero Android no ha conectado el servicio (pasa tras actualizar la app), se lo pedimos. */
    private fun ensureListener() {
        if (NotiBridge.service == null && hasNotifAccess() && Build.VERSION.SDK_INT >= 24) {
            try {
                android.service.notification.NotificationListenerService.requestRebind(ComponentName(this, NotiService::class.java))
            } catch (e: Exception) {}
        }
    }

    private fun pushNotifs() {
        try { channel?.invokeMethod("notifs", notifList()) } catch (e: Exception) {}
    }

    private fun replyAction(sbn: StatusBarNotification): Notification.Action? =
        sbn.notification.actions?.firstOrNull { a -> a.remoteInputs?.any { it.allowFreeFormInput } == true }

    private fun notifList(): List<Map<String, Any>> {
        val pm = packageManager
        return NotiBridge.items.values.sortedByDescending { it.postTime }.take(15).map { sbn ->
            val ex = sbn.notification.extras
            val title = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
            val text = (ex.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: ex.getCharSequence(Notification.EXTRA_TEXT))?.toString() ?: ""
            val label = try { pm.getApplicationLabel(pm.getApplicationInfo(sbn.packageName, 0)).toString() } catch (e: Exception) { sbn.packageName }
            mapOf(
                "key" to sbn.key,
                "pkg" to sbn.packageName,
                "app" to label,
                "title" to title,
                "text" to text,
                "time" to sbn.postTime,
                "reply" to (replyAction(sbn) != null)
            )
        }
    }

    private fun sendPending(pi: PendingIntent, fill: Intent?): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= 34) {
                val opts = ActivityOptions.makeBasic()
                    .setPendingIntentBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
                    .toBundle()
                pi.send(this, 0, fill, null, null, null, opts)
            } else {
                pi.send(this, 0, fill)
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun configureOrFinish(id: Int, result: MethodChannel.Result?) {
        val info = widgetManager?.getAppWidgetInfo(id)
        if (info?.configure != null) {
            pendingResult = result
            pendingWidgetId = id
            try {
                widgetHost?.startAppWidgetConfigureActivityForResult(this, id, 0, reqConfig, null)
            } catch (e: Exception) {
                pendingResult = null
                result?.success(id)
            }
        } else {
            result?.success(id)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != reqBind && requestCode != reqConfig) return
        val r = pendingResult
        val id = pendingWidgetId
        pendingResult = null
        if (resultCode == android.app.Activity.RESULT_OK) {
            if (requestCode == reqBind) configureOrFinish(id, r) else r?.success(id)
        } else {
            try { widgetHost?.deleteAppWidgetId(id) } catch (e: Exception) {}
            r?.success(-1)
        }
    }

    private fun openAlarms(): Boolean {
        try {
            startActivity(Intent(AlarmClock.ACTION_SHOW_ALARMS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return true
        } catch (e: Exception) {}
        val clocks = listOf("com.hihonor.deskclock", "com.huawei.deskclock", "com.google.android.deskclock", "com.android.deskclock", "com.sec.android.app.clockpackage")
        for (p in clocks) {
            val i = packageManager.getLaunchIntentForPackage(p)
            if (i != null) {
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(i)
                return true
            }
        }
        return false
    }

    inner class WidgetFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
        override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
            val params = args as? Map<*, *>
            val id = (params?.get("id") as? Number)?.toInt() ?: -1
            val w = (params?.get("w") as? Number)?.toInt() ?: 0
            val h = (params?.get("h") as? Number)?.toInt() ?: 0
            return WidgetPlatformView(id, w, h)
        }
    }

    inner class WidgetPlatformView(id: Int, w: Int, h: Int) : PlatformView {
        private val view: View

        init {
            val info = if (id >= 0) widgetManager?.getAppWidgetInfo(id) else null
            val host = widgetHost
            view = if (info != null && host != null) {
                val hv = host.createView(this@MainActivity, id, info)
                if (w > 0 && h > 0) {
                    try {
                        @Suppress("DEPRECATION")
                        hv.updateAppWidgetSize(Bundle(), w, h, w, h)
                    } catch (e: Exception) {}
                }
                hv
            } else {
                TextView(this@MainActivity).apply {
                    text = "Este widget ya no está disponible. Quítalo en modo edición."
                    setTextColor(Color.WHITE)
                    gravity = Gravity.CENTER
                }
            }
        }

        override fun getView(): View = view
        override fun dispose() {}
    }

    private fun hasAllFiles(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Environment.isExternalStorageManager()
        else checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
    }

    private fun toPng(d: Drawable, size: Int): ByteArray {
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        d.setBounds(0, 0, size, size)
        d.draw(canvas)
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
        return out.toByteArray()
    }
}
