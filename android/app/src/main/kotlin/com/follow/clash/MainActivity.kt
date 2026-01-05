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

                val prefs = getSharedPreferences("zivpn_config", MODE_PRIVATE)
                prefs.edit().apply {
                    putString("ip", ip)
                    putString("pass", pass)
                    putString("obfs", obfs)
                    putString("port_range", portRange)
                    apply()
                }
                
                // Signal service to restart/reload if needed (optional implementation)
                result.success("Config saved. Please start/restart VPN.")
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