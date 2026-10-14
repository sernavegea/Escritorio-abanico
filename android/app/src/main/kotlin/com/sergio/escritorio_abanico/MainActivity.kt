package com.sergio.escritorio_abanico

import android.Manifest
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newFixedThreadPool(3)
    private val ui = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url") ?: ""))
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) { result.success(false) }
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
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.hasCategory(Intent.CATEGORY_HOME)) channel?.invokeMethod("home", null)
    }

    private fun hasAllFiles(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Environment.isExternalStorageManager()
        else checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == android.content.pm.PackageManager.PERMISSION_GRANTED
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
