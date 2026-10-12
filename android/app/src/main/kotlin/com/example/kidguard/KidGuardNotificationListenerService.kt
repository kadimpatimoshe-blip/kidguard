package com.example.kidguard

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.database.FirebaseDatabase
import java.security.MessageDigest

class KidGuardNotificationListenerService : NotificationListenerService() {
    companion object {
        const val PREFERENCES = "kidguard_monitoring"
        private const val TAG = "KidGuardNotifications"
        private const val DATABASE_URL =
            "https://kidguard-3b499-default-rtdb.asia-southeast1.firebasedatabase.app"
    }

    override fun onNotificationPosted(notification: StatusBarNotification) {
        if (notification.packageName == packageName) return

        val extras = notification.notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = (
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: extras.getCharSequence(Notification.EXTRA_TEXT)
            )?.toString()
        if (title.isNullOrBlank() && text.isNullOrBlank()) return

        val preferences = getSharedPreferences(PREFERENCES, MODE_PRIVATE)
        val deviceId = preferences.getString("deviceId", null) ?: return
        val parentUid = preferences.getString("parentUid", null) ?: return
        val childId = preferences.getString("childId", null) ?: return

        try {
            val app = getOrInitializeFirebaseApp()
            val childUserId = FirebaseAuth.getInstance(app).currentUser?.uid ?: return
            val childReference = FirebaseDatabase.getInstance(app, DATABASE_URL)
                .reference
                .child("parents")
                .child(parentUid)
                .child("children")
                .child(childId)

            childReference.get()
                .addOnSuccessListener { snapshot ->
                    if (snapshot.child("status").getValue(String::class.java) != "paired" ||
                        snapshot.child("childUid").getValue(String::class.java) != childUserId ||
                        snapshot.child("deviceId").getValue(String::class.java) != deviceId
                    ) {
                        return@addOnSuccessListener
                    }

                    val notificationKey = MessageDigest.getInstance("SHA-256")
                        .digest(notification.key.toByteArray())
                        .joinToString("") { byte -> "%02x".format(byte) }
                    val event =
                        childReference.child("notifications").child(notificationKey)
                    event.setValue(
                        mapOf(
                            "packageName" to notification.packageName,
                            "title" to title?.take(512),
                            "text" to text?.take(2000),
                            "postedAt" to notification.postTime,
                            "syncedAt" to System.currentTimeMillis(),
                        ),
                    ).addOnFailureListener { error ->
                        Log.e(TAG, "Could not upload a device notification.", error)
                    }
                }
                .addOnFailureListener { error ->
                    Log.e(TAG, "Could not verify the paired child device.", error)
                }
        } catch (error: Exception) {
            Log.e(TAG, "Could not initialize notification syncing.", error)
        }
    }

    private fun getOrInitializeFirebaseApp(): FirebaseApp {
        FirebaseApp.getApps(this).firstOrNull()?.let { return it }
        val options = FirebaseOptions.Builder()
            .setApplicationId("1:897177192961:android:205829551a9fac30938e00")
            .setApiKey("AIzaSyCn_0mbkQNSlOIvUA3Tv9QKFn8skyZL0vg")
            .setProjectId("kidguard-3b499")
            .setGcmSenderId("897177192961")
            .setDatabaseUrl(DATABASE_URL)
            .setStorageBucket("kidguard-3b499.firebasestorage.app")
            .build()
        return FirebaseApp.initializeApp(this, options)
            ?: error("Firebase could not initialize notification syncing.")
    }
}
