package com.miaoban.miaoban
import android.os.Handler
import android.os.Looper
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class MiaobanMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        // Ask the authenticated Flutter client to register. Never persist auth tokens natively.
        Handler(Looper.getMainLooper()).post { MainActivity.pushChannel?.invokeMethod("tokenChanged", null) }
    }
    override fun onMessageReceived(message: RemoteMessage) {
        Handler(Looper.getMainLooper()).post { MainActivity.pushChannel?.invokeMethod("foregroundNotification", message.data) }
    }
}
