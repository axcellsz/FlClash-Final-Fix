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
                val ip = call.argument<String>("ip")
                val pass = call.argument<String>("pass")
                val obfs = call.argument<String>("obfs")
                val portRange = call.argument<String>("port_range")
                val mtu = call.argument<String>("mtu")
                val autoBoot = call.argument<Boolean>("auto_boot") ?: false

                // Save to JSON file for multi-process consistency
                val configContent = """
                    {
                        "ip": "$ip",
                        "pass": "$pass",
                        "obfs": "$obfs",
                        "port_range": "$portRange",
                        "mtu": "$mtu",
                        "auto_boot": $autoBoot
                    }
                """.trimIndent()

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