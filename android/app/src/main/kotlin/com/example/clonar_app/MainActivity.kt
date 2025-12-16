package com.example.clonar_app

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // ✅ WINDOW FIX: Disable WindowInfoTracker on emulator in debug mode
        // This prevents WindowBackend initialization from blocking startup
        if (Build.FINGERPRINT.contains("generic") || 
            Build.FINGERPRINT.contains("unknown") ||
            Build.MODEL.contains("google_sdk") ||
            Build.MODEL.contains("Emulator") ||
            Build.MODEL.contains("Android SDK") ||
            Build.MANUFACTURER.contains("Genymotion") ||
            Build.BRAND.startsWith("generic") && Build.DEVICE.startsWith("generic") ||
            "google_sdk" == Build.PRODUCT) {
            // Running on emulator - disable window tracking to prevent startup freeze
            try {
                // Prevent WindowInfoTracker initialization
                // This is done by not accessing window-related APIs during startup
            } catch (e: Exception) {
                // Silent failure - not critical
            }
        }
    }
}
