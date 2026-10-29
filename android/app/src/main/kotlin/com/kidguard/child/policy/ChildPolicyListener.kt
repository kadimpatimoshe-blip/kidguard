package com.kidguard.child.policy

import android.util.Log
import com.google.firebase.database.*
import com.google.gson.Gson

class ChildPolicyListener {
    private val db = FirebaseDatabase.getInstance().reference
    private val gson = Gson()
    private var activeListener: ValueEventListener? = null
    private var currentDeviceCode: String? = null

    companion object {
        private const val TAG = "ChildPolicyListener"
    }

    fun listen(deviceCode: String, onPolicyUpdated: (Policy) -> Unit) {
        stop()
        currentDeviceCode = deviceCode

        activeListener = object : ValueEventListener {
            override fun onDataChange(snapshot: DataSnapshot) {
                if (!snapshot.exists()) return
                try {
                    val json = gson.toJson(snapshot.value)
                    val policy = gson.fromJson(json, Policy::class.java)
                    if (policy != null) {
                        Log.d(TAG, "Child policy updated successfully for device $deviceCode")
                        onPolicyUpdated(policy)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error deserializing policy for device $deviceCode: ${e.message}", e)
                }
            }

            override fun onCancelled(error: DatabaseError) {
                Log.w(TAG, "Policy listener cancelled: ${error.message}")
            }
        }

        db.child("devices")
            .child(deviceCode)
            .child("policy")
            .addValueEventListener(activeListener!!)
    }

    fun stop() {
        activeListener?.let { listener ->
            currentDeviceCode?.let { code ->
                db.child("devices").child(code).child("policy").removeEventListener(listener)
            }
        }
        activeListener = null
        currentDeviceCode = null
    }
}
