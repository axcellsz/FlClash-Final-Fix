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
                        // Initialize GlobalState manually if needed as Application might not have done it fully for receiver context
                        // But usually Application.onCreate runs first.
                        
                        GlobalState.launch {
                            // We need to ensure State is initialized or call Service directly
                            // Calling State.handleStartServiceAction() requires Flutter Engine which might be heavy on Boot.
                            // A lighter way is starting the Service Intent directly if we trust the config.
                            
                            // However, using State ensures plugins are loaded.
                            // Let's try safe approach via State.
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