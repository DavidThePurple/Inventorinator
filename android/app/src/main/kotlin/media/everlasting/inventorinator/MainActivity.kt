package media.everlasting.inventorinator

import android.media.MediaPlayer
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var xrealEye: XrealEyeCapture
    private fun readableDeviceName(): String {
        val configuredName = try {
            Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
        } catch (_: SecurityException) {
            null
        }
        val bluetoothName = try {
            Settings.Secure.getString(contentResolver, "bluetooth_name")
        } catch (_: SecurityException) {
            null
        }
        val avdName = try {
            Runtime.getRuntime()
                .exec(arrayOf("/system/bin/getprop", "ro.boot.qemu.avd_name"))
                .inputStream
                .bufferedReader()
                .use { it.readLine() }
                ?.trim()
        } catch (_: Exception) {
            null
        }

        fun cleaned(value: String?): String? = value
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.replace('_', ' ')

        fun isInternalName(value: String): Boolean {
            val normalized = value.lowercase().replace('_', ' ')
            return normalized == "android" ||
                normalized == "emulator" ||
                normalized.startsWith("sdk gphone") ||
                normalized.startsWith("generic ") ||
                normalized.startsWith("android sdk built for")
        }

        listOf(configuredName, bluetoothName, avdName)
            .mapNotNull(::cleaned)
            .firstOrNull { !isInternalName(it) }
            ?.let { return it }

        val model = cleaned(Build.MODEL) ?: "Android device"
        if (!isInternalName(model)) {
            val manufacturer = cleaned(Build.MANUFACTURER)
            return if (
                manufacturer == null ||
                model.lowercase().startsWith(manufacturer.lowercase())
            ) model else "$manufacturer $model"
        }
        return "Android emulator"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        xrealEye = XrealEyeCapture(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "inventorinator/xreal_eye")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> if (xrealEye.start()) result.success(null) else result.error("xreal_eye", xrealEye.status()["error"] as String?, null)
                    "stop" -> { xrealEye.stop(); result.success(null) }
                    "status" -> result.success(xrealEye.status())
                    "frame" -> result.success(xrealEye.frame())
                    else -> result.notImplemented()
                }
            }
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
            val volume = (call.argument<Number>("volume")?.toFloat()?.div(100f) ?: 0.78f)
                .coerceIn(0f, 1f)
            player.setVolume(volume, volume)
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
            result.success(readableDeviceName())
        }
    }
}
