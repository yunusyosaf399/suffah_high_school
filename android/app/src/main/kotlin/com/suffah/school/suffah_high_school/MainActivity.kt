package com.suffah.school.suffah_high_school

import android.app.*
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var tone: Ringtone? = null
    private var pending: MethodChannel.Result? = null
    private var pendingUid = ""
    private val prefs get() = getSharedPreferences("school_call_audio", Context.MODE_PRIVATE)
    private fun ringtoneUri(uid: String): Uri? {
        val value = prefs.getString("tone_$uid", null)
        return if (value == "silent") null else if (value != null) Uri.parse(value)
            else RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
    }
    private fun ensureChannel(uid: String): String {
        val channel = prefs.getString("channel_$uid", "school_calls") ?: "school_calls"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
            val spec = NotificationChannel(channel, "School incoming calls", NotificationManager.IMPORTANCE_HIGH)
            spec.setSound(ringtoneUri(uid), attributes)
            spec.enableVibration(true)
            getSystemService(NotificationManager::class.java).createNotificationChannel(spec)
        }
        return channel
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "suffah/call_audio").setMethodCallHandler { call, result ->
            val uid = call.argument<String>("uid") ?: ""
            try {
                when (call.method) {
                    "channelId" -> result.success(ensureChannel(uid))
                    "chooseRingtone" -> {
                        if (pending != null) { result.error("busy", "Picker already open", null); return@setMethodCallHandler }
                        pending = result
                        pendingUid = uid
                        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER)
                            .putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_RINGTONE)
                            .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                            .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, true)
                            .putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, ringtoneUri(uid))
                        try { startActivityForResult(intent, 711) } catch (e: Exception) { pending = null; result.error("picker", e.message, null) }
                    }
                    "ring" -> {
                        tone?.stop()
                        tone = ringtoneUri(uid)?.let { RingtoneManager.getRingtone(this, it) }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) tone?.isLooping = true
                        tone?.play()
                        result.success(true)
                    }
                    "stopRing" -> { tone?.stop(); tone = null; result.success(true) }
                    "startService" -> {
                        val intent = Intent(this, SchoolCallService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                        result.success(true)
                    }
                    "stopService" -> { stopService(Intent(this, SchoolCallService::class.java)); result.success(true) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("call_audio", e.message, null) }
        }
    }
    @Deprecated("Android ringtone picker result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 711) return
        val result = pending
        pending = null
        if (resultCode != Activity.RESULT_OK) { result?.success(false); return }
        @Suppress("DEPRECATION")
        val uri = data?.getParcelableExtra<Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        val channel = "school_calls_" + System.currentTimeMillis()
        prefs.edit().putString("tone_$pendingUid", uri?.toString() ?: "silent")
            .putString("channel_$pendingUid", channel).apply()
        ensureChannel(pendingUid)
        result?.success(true)
    }
    override fun onDestroy() { tone?.stop(); super.onDestroy() }
}
class SchoolCallService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            val channel = "school_call_active"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(channel, "Active school calls", NotificationManager.IMPORTANCE_LOW).apply { setSound(null, null) })
            val open = PendingIntent.getActivity(this, 712,
                Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, channel) else Notification.Builder(this)
            val notification = builder.setContentTitle("School voice call")
                .setContentText("Call in progress — tap to return").setSmallIcon(android.R.drawable.sym_call_incoming)
                .setContentIntent(open).setOngoing(true).setCategory(Notification.CATEGORY_CALL).build()
            startForeground(712, notification)
            if (wakeLock == null) wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "suffah:office-call").apply { acquire(60 * 60 * 1000L) }
        } catch (_: Exception) { stopSelf() }
        return START_NOT_STICKY
    }
    override fun onDestroy() { wakeLock?.let { if (it.isHeld) it.release() }; wakeLock = null; super.onDestroy() }
}
