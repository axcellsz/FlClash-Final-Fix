package com.follow.clash

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.follow.clash.common.GlobalState
import kotlinx.coroutines.launch
import java.io.File
import org.json.JSONObject

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.i("FlClash", "Boot completed detected")
            
            try {
                val configFile = File(context.filesDir, "zivpn_config.json")
                if (configFile.exists()) {
                    val content = configFile.readText()
                    val json = JSONObject(content)
                    val autoBoot = json.optBoolean("auto_boot", false)
                    
                    if (autoBoot) {
                        Log.i("FlClash", "Auto-boot enabled in config, starting VPN...")
                        
                        GlobalState.launch {
                            // Safety Delay: Give system 10s to settle before launching heavy VPN service
                            kotlinx.coroutines.delay(10000)
                            
                            State.handleStartServiceAction()
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e("FlClash", "Failed to handle auto boot: ${e.message}")
            }
        }
    }
}