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
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.Bundle
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import android.view.Gravity
import android.graphics.Color
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var tone: Ringtone? = null
    private var pending: MethodChannel.Result? = null
    private var pendingUid = ""
    private var launchCover: FrameLayout? = null
    private val launchHandler = Handler(Looper.getMainLooper())
    private var protectedCallLaunch = false
    private var activeCallSurface = false
    private var lastCallPayload: String? = null
    private val launchTimeout = Runnable { if (protectedCallLaunch && !activeCallSurface) closeCallSurface() }
    private val prefs get() = getSharedPreferences("school_call_audio", Context.MODE_PRIVATE)
    // flutter_local_notifications delivers its full-screen PendingIntent as
    // SELECT_NOTIFICATION. Enable the screen before Flutter initializes,
    // but never expose the school dashboard over the keyguard.
    private fun validCallPayload(source: Intent?): String? {
        if (source?.action != "SELECT_NOTIFICATION") return null
        val payload = source.getStringExtra("payload") ?: return null
        return try {
            val json = JSONObject(payload)
            val account = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.school_incoming_call_account", null)
            if (account.isNullOrEmpty() || json.optString("type") != "office_call_v2" ||
                json.optString("recipientUid") != account ||
                !Regex("^[A-Za-z0-9_-]{20}$").matches(json.optString("callId"))) return null
            val raw = json.optString("expiresAt")
            val expiry = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                java.time.Instant.parse(raw).toEpochMilli()
            } else {
                val normalized = raw.replace(Regex("\\\\.\\\\d+Z$"), "Z")
                SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("UTC")
                }.parse(normalized)?.time ?: 0L
            }
            if (expiry <= System.currentTimeMillis() || expiry > System.currentTimeMillis() + 120000L) null else payload
        } catch (_: Exception) { null }
    }
    private fun locked(): Boolean = getSystemService(KeyguardManager::class.java).isKeyguardLocked
    private fun callFlags(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(enabled); setTurnScreenOn(enabled)
        } else {
            @Suppress("DEPRECATION")
            val flags = android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (enabled) window.addFlags(flags) else window.clearFlags(flags)
        }
    }
    private fun cover() {
        if (launchCover != null) return
        val root = window.decorView as? ViewGroup ?: return
        val layer = FrameLayout(this).apply {
            setBackgroundColor(Color.rgb(16, 46, 40))
            isClickable = true
            isFocusable = true
            addView(TextView(this@MainActivity).apply {
                text = "Suffah High School\nIncoming voice call…"
                gravity = Gravity.CENTER
                setTextColor(Color.WHITE)
                textSize = 20f
            }, FrameLayout.LayoutParams(-1, -1))
        }
        root.addView(layer, ViewGroup.LayoutParams(-1, -1))
        launchCover = layer
    }
    private fun removeCover() {
        launchCover?.let { (it.parent as? ViewGroup)?.removeView(it) }
        launchCover = null
    }
    private fun openCallSurface(payload: String) {
        lastCallPayload = payload
        protectedCallLaunch = true
        if (!activeCallSurface) cover()
        callFlags(true)
        launchHandler.removeCallbacks(launchTimeout)
        launchHandler.postDelayed(launchTimeout, 35000L)
    }
    private fun closeCallSurface() {
        val wasProtected = protectedCallLaunch || activeCallSurface
        activeCallSurface = false
        protectedCallLaunch = false
        lastCallPayload = null
        launchHandler.removeCallbacks(launchTimeout)
        // Cover the Flutter view before removing the lock-screen flags.
        if (wasProtected && locked()) {
            cover()
            callFlags(false)
            moveTaskToBack(true)
        } else {
            callFlags(false)
            removeCover()
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        // Attach the cover before granting keyguard visibility.
        val payload = validCallPayload(intent)
        super.onCreate(savedInstanceState)
        if (payload != null) openCallSurface(payload)
    }
    override fun onNewIntent(intent: Intent) {
        val payload = validCallPayload(intent)
        if (payload != null) openCallSurface(payload)
        else if (protectedCallLaunch && !activeCallSurface) closeCallSurface()
        super.onNewIntent(intent)
        setIntent(intent)
    }
    override fun onResume() {
        super.onResume()
        if (!protectedCallLaunch && !activeCallSurface && !locked()) removeCover()
    }
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
                    "callLockScreen" -> {
                        val enabled = call.argument<Boolean>("enabled") == true
                        if (enabled) {
                            activeCallSurface = true
                            launchHandler.removeCallbacks(launchTimeout)
                            callFlags(true)
                            removeCover()
                        } else closeCallSurface()
                        result.success(true)
                    }
                    "pendingCallPayload" -> result.success(lastCallPayload)
                    "callNotificationStatus" -> {
                        val manager = getSystemService(NotificationManager::class.java)
                        val channel = ensureChannel(uid)
                        val full = if (Build.VERSION.SDK_INT >= 34) manager.canUseFullScreenIntent() else true
                        val notifications = if (Build.VERSION.SDK_INT >= 24) manager.areNotificationsEnabled() else true
                        val importance = if (Build.VERSION.SDK_INT >= 26) manager.getNotificationChannel(channel)?.importance ?: 0 else 4
                        result.success(mapOf("fullScreen" to full, "notifications" to notifications, "channelHigh" to (importance >= NotificationManager.IMPORTANCE_HIGH)))
                    }
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
                        val handler = Handler(Looper.getMainLooper())
                        var attempts = 0
                        val verify = object : Runnable {
                            override fun run() {
                                if (SchoolCallService.active) result.success(true)
                                else if (++attempts >= 20) result.success(false)
                                else handler.postDelayed(this, 100)
                            }
                        }
                        handler.post(verify)
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
    override fun onDestroy() { launchHandler.removeCallbacksAndMessages(null); tone?.stop(); removeCover(); super.onDestroy() }
}
class SchoolCallService : Service() {
    companion object { @Volatile var active = false }
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
            active = true
            if (wakeLock == null) wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "suffah:office-call").apply { acquire(60 * 60 * 1000L) }
        } catch (_: Exception) { stopSelf() }
        return START_NOT_STICKY
    }
    override fun onDestroy() { active = false; wakeLock?.let { if (it.isHeld) it.release() }; wakeLock = null; super.onDestroy() }
}
