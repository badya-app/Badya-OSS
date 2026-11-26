package com.badya.app

import android.app.AlarmManager
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.badya.app/notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestExactAlarmPermission" -> {
                        requestExactAlarmPermission(result)
                    }
                    "getLocalTimezone" -> {
                        getLocalTimezone(result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestExactAlarmPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ uses AlarmManager exact alarm allowlist
            val alarmManager = getSystemService(ALARM_SERVICE) as AlarmManager
            if (alarmManager.canScheduleExactAlarms()) {
                result.success(true)
            } else {
                val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                startActivity(intent)
                result.success(false)
            }
        } else {
            // Below Android 12, permission is automatically granted
            result.success(true)
        }
    }

    private fun getLocalTimezone(result: MethodChannel.Result) {
        try {
            val timeZoneId = java.util.TimeZone.getDefault().id
            result.success(timeZoneId)
        } catch (e: Exception) {
            result.error("timezone_error", e.message, null)
        }
    }
}
