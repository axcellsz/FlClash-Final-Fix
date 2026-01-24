package com.follow.clash

import android.os.Bundle
import androidx.lifecycle.lifecycleScope
import com.follow.clash.common.GlobalState
import com.follow.clash.plugins.AppPlugin
import com.follow.clash.plugins.ServicePlugin
import com.follow.clash.plugins.TilePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream

import com.follow.clash.service.models.ZivpnConfig // Added Import

class MainActivity : FlutterActivity(),
    CoroutineScope by CoroutineScope(SupervisorJob() + Dispatchers.Default) {

    companion object {
        init {
            try {
                System.loadLibrary("core")
            } catch (e: UnsatisfiedLinkError) {
                // Ignore
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        lifecycleScope.launch {
            State.destroyServiceEngine()
            // extractBinaries() // Disabled: Using jniLibs packaging now
        }
    }

    private fun extractBinaries() {
        try {
            val binDir = filesDir
            
            listOf("libuz.so", "libload.so").forEach { fileName ->
                val outFile = File(binDir, fileName)
                // Always overwrite to ensure latest version from assets
                assets.open("flutter_assets/assets/bin/$fileName").use { input ->
                    FileOutputStream(outFile).use { output ->
                        input.copyTo(output)
                    }
                }
                outFile.setExecutable(true)
                // Double ensure with chmod via runtime
                try {
                    Runtime.getRuntime().exec("chmod 777 ${outFile.absolutePath}").waitFor()
                } catch (e: Exception) {}
            }
            android.util.Log.i("FlClash", "Binaries extracted successfully to ${binDir.absolutePath}")
        } catch (e: Exception) {
            android.util.Log.e("FlClash", "Failed to extract binaries: ${e.message}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(AppPlugin())
        flutterEngine.plugins.add(ServicePlugin())
        flutterEngine.plugins.add(TilePlugin())
        State.flutterEngine = flutterEngine

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.follow.clash/hysteria").setMethodCallHandler { call, result ->
            if (call.method == "start_process") {
                val ip = call.argument<String>("ip") ?: ""
                val pass = call.argument<String>("pass") ?: ""
                val obfs = call.argument<String>("obfs") ?: "hu``hqb`c"
                val portRange = call.argument<String>("port_range") ?: "6000-19999"
                val mtu = call.argument<String>("mtu")?.toIntOrNull() ?: 9000
                val autoBoot = call.argument<Boolean>("auto_boot") ?: false
                val autoReset = call.argument<Boolean>("auto_reset") ?: false
                val resetTimeout = call.argument<Int>("reset_timeout") ?: 15

                // Use ZivpnConfig Model for consistency
                val config = ZivpnConfig(ip, pass, obfs, portRange, mtu, autoBoot, autoReset, resetTimeout)
                val configContent = ZivpnConfig.toJson(config)

                try {
                    val configFile = File(filesDir, "zivpn_config.json")
                    configFile.writeText(configContent)
                    result.success("Config saved to ${configFile.absolutePath}")
                } catch (e: Exception) {
                    result.error("WRITE_ERR", "Failed to save config: ${e.message}", null)
                }
            } else if (call.method == "request_battery") {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                    val pm = getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
                    if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                        try {
                            val intent = android.content.Intent()
                            intent.action = android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                            intent.data = android.net.Uri.parse("package:$packageName")
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERR", e.message, null)
                        }
                    } else {
                        result.success(false) // Already ignored
                    }
                } else {
                    result.success(false)
                }
            } else if (call.method == "launch_app") {
                val pkgName = call.argument<String>("package_name")
                if (pkgName != null) {
                    try {
                        val launchIntent = packageManager.getLaunchIntentForPackage(pkgName)
                        if (launchIntent != null) {
                            startActivity(launchIntent)
                            result.success(true)
                        } else {
                             // Fallback to Play Store if app not found
                            try {
                                val intent = android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse("market://details?id=$pkgName"))
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("APP_NOT_FOUND", "App not installed and no Play Store found", null)
                            }
                        }
                    } catch (e: Exception) {
                        result.error("LAUNCH_ERR", e.message, null)
                    }
                } else {
                    result.error("INVALID_ARGS", "Package name is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        GlobalState.launch {
            Service.setEventListener(null)
        }
        State.flutterEngine = null
        super.onDestroy()
    }
}