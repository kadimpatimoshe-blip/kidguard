package com.kidguard.child.ui

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.kidguard.child.MainActivity

/**
 * SettingsActivity
 * Launched when the user taps "Settings" in the Android System Accessibility settings for KidGuard.
 * Directs the user back to the primary KidGuard Child companion dashboard.
 */
class SettingsActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        startActivity(intent)
        finish()
    }
}
