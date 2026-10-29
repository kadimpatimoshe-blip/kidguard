# ProGuard & R8 Optimization and Keep Rules for KidGuard Child App
# Android 14 (API 34) & Flutter Native Plugins

# Flutter Framework Keep Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flutter Embedder v2
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keep class * implements io.flutter.embedding.engine.plugins.activity.ActivityAware { *; }
-keep class * implements io.flutter.embedding.engine.plugins.service.ServiceAware { *; }

# Native Foreground Services
-keep class com.kidguard.child.services.** { *; }
-keep class com.kidguard.child.MainActivity { *; }

# Battery Plus Plugin
-keep class dev.fluttercommunity.plus.battery.** { *; }

# Geolocator Android Plugin
-keep class com.baseflow.geolocator.** { *; }
-keep class com.google.android.gms.location.** { *; }
-keep class com.google.android.gms.tasks.** { *; }

# Google & Firebase Services
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# WebRTC & MediaProjection Streaming
-keep class org.webrtc.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }
-dontwarn org.webrtc.**
-dontwarn com.cloudwebrtc.webrtc.**
-keep class android.media.projection.** { *; }

# Flutter Foreground Task & Wakelock
-keep class com.pravera.flutter_foreground_task.** { *; }
-keep class dev.fluttercommunity.plus.wakelock.** { *; }

# Kotlin Coroutines & Serialization
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-keepnames class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# Keep Native Methods & JNI
-keepclasseswithmembernames class * {
    native <methods>;
}
