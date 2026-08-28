package media.everlasting.inventorinator

import android.media.MediaPlayer
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "inventorinator/audio",
        ).setMethodCallHandler { call, result ->
            val sound = when (call.method) {
                "playSyncChime" -> R.raw.transhuman_sync
                "playDryingCompleteChime" -> R.raw.drying_complete
                "playMoistureAlertChime" -> R.raw.moisture_alert
                else -> {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
            }
            val player = MediaPlayer.create(this, sound)
            player.setVolume(0.78f, 0.78f)
            player.setOnCompletionListener { completed -> completed.release() }
            player.start()
            result.success(null)
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "inventorinator/device",
        ).setMethodCallHandler { call, result ->
            if (call.method != "getDeviceName") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val configuredName = Settings.Global.getString(contentResolver, "device_name")
            result.success(configuredName?.trim()?.takeIf { it.isNotEmpty() } ?: Build.MODEL)
        }
    }
}
