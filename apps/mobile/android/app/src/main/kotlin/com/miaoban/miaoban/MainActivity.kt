package com.miaoban.miaoban

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import com.google.android.gms.common.GoogleApiAvailabilityLight
import com.google.android.gms.common.ConnectionResult
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object { var pushChannel: MethodChannel? = null }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (Build.VERSION.SDK_INT >= 26) getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel("partner_events", "TA 的动态", NotificationManager.IMPORTANCE_DEFAULT))
        pushChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.miaoban/push")
        pushChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialNotification" -> { result.success(tapPayload(intent)); clearTap(intent) }
                "register" -> {
                    if (BuildConfig.FCM_APP_ID.isEmpty()) {
                        result.error("PUSH_NOT_CONFIGURED", "远程通知尚未配置；本地提醒和收件箱可正常使用", null)
                    } else if (GoogleApiAvailabilityLight.getInstance().isGooglePlayServicesAvailable(this) != ConnectionResult.SUCCESS) {
                        result.error("GMS_UNAVAILABLE", "此设备需要配置适用的厂商推送通道", null)
                    } else {
                        if (FirebaseApp.getApps(this).isEmpty()) FirebaseApp.initializeApp(this,
                            FirebaseOptions.Builder().setProjectId(BuildConfig.FCM_PROJECT_ID)
                                .setApplicationId(BuildConfig.FCM_APP_ID).setApiKey(BuildConfig.FCM_API_KEY)
                                .setGcmSenderId(BuildConfig.FCM_SENDER_ID).build())
                        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                            if (task.isSuccessful) result.success(task.result)
                            else result.error("PUSH_REGISTRATION_FAILED", "远程通知注册未完成，请稍后重试", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun tapPayload(intent: Intent): Map<String, String>? {
        val data = listOf("space_id", "entity_id", "notification_id").mapNotNull { key ->
            intent.getStringExtra(key)?.let { key to it }
        }.toMap()
        return if (data.isEmpty()) null else data
    }
    private fun clearTap(intent: Intent) { listOf("space_id", "entity_id", "notification_id").forEach { intent.removeExtra(it) } }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        tapPayload(intent)?.let { pushChannel?.invokeMethod("notificationTap", it) }
        clearTap(intent)
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pushChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
