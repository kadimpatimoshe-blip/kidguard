package com.kidguard.child.service

import android.app.Notification
import android.content.Context
import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * ChildNotificationListenerService
 * Listens for real system notifications on the child device and synchronizes alerts.
 * Zero mock lists: strictly processes real StatusBarNotifications.
 */
class ChildNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "KidGuardNotifListener"
        const val ACTION_NEW_NOTIFICATION = "com.kidguard.child.ACTION_NEW_NOTIFICATION"
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val packageName = sbn.packageName ?: return
        // Ignore own notifications
        if (packageName == applicationContext.packageName) return

        val extras = sbn.notification?.extras
        val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

        if (title.isEmpty() && text.isEmpty()) return

        Log.i(TAG, "Real notification intercepted from $packageName: $title")

        val intent = Intent(ACTION_NEW_NOTIFICATION).apply {
            putExtra("package_name", packageName)
            putExtra("title", title)
            putExtra("text", text)
            putExtra("timestamp", sbn.postTime)
        }
        sendBroadcast(intent)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
    }
}
