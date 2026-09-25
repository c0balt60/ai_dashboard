package io.github.c0balt60.ai_dashboard

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

/**
 * Creates the channel the PC server's push notifications are posted to. Its id
 * must match FcmSender.channelId on the server and the default channel in
 * AndroidManifest.xml.
 */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "agent_updates",
                "Agent updates",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Failures, finished tasks and replies from your agents"
            }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }
}
