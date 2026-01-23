package com.follow.clash.service

import android.content.Context
import android.os.Build
import android.util.Log
import com.follow.clash.service.models.ZivpnConfig
import kotlinx.coroutines.*
import java.io.File
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL

class ZivpnManager(
    private val context: Context,
    private val onCoreDied: () -> Unit
) {

    private val coreProcesses = mutableListOf<Process>()
    private var monitorJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO)

    fun start() {
        scope.launch {
            try {
                // 1. Aggressive Clean Up
                stop()
                
                // Kill any lingering native processes by name pattern
                val cmdKill = arrayOf("sh", "-c", "pkill -9 libuz && pkill -9 libload")
                try { Runtime.getRuntime().exec(cmdKill).waitFor() } catch (e: Exception) {}
                
                delay(1200) // Longer delay to ensure OS releases sockets

                val nativeDir = context.applicationInfo.nativeLibraryDir
                val libUz = File(nativeDir, "libuz.so").absolutePath
                val libLoad = File(nativeDir, "libload.so").absolutePath

                if (!File(libUz).exists()) {
                    Log.e("FlClash", "Native Binary libuz.so not found at $libUz")
                    return@launch
                }

                val configFile = File(context.filesDir, "zivpn_config.json")
                if (!configFile.exists()) {
                    Log.e("FlClash", "Config file missing, skipping engine start")
                    return@launch
                }
                
                val config = ZivpnConfig.fromFile(configFile)
                Log.i("FlClash", "Initializing ZIVPN Turbo Cores...")

                val tunnels = mutableListOf<String>()
                val ports = listOf(20080, 20081, 20082, 20083)
                val ranges = config.portRange.split(",").map { it.trim() }.filter { it.isNotEmpty() }

                for ((index, port) in ports.withIndex()) {
                    val currentRange = if (ranges.isNotEmpty()) ranges[index % ranges.size] else "6000-19999"
                    val configContent = """{"server":"${config.ip}:$currentRange","obfs":"${config.obfs}","auth":"${config.pass}","socks5":{"listen":"127.0.0.1:$port"},"insecure":true,"recvwindowconn":131072,"recvwindow":327680}"""
                    
                    // Use ProcessBuilder with custom environment to prevent inheritance issues
                    val pb = ProcessBuilder(libUz, "-s", config.obfs, "--config", configContent)
                    pb.directory(context.filesDir)
                    pb.environment()["LD_LIBRARY_PATH"] = nativeDir
                    
                    try {
                        val process = pb.start()
                        coreProcesses.add(process)
                        startProcessLogger(process, "Core-$port")
                        tunnels.add("127.0.0.1:$port")
                    } catch (e: Exception) {
                        Log.e("FlClash", "Failed to launch Core-$port: ${e.message}")
                    }
                    delay(200) // Staggered start to prevent CPU spike
                }

                delay(1200)

                if (tunnels.isNotEmpty()) {
                    val lbArgs = mutableListOf(libLoad, "-lport", "7777", "-tunnel")
                    lbArgs.addAll(tunnels)
                    val lbPb = ProcessBuilder(lbArgs)
                    lbPb.environment()["LD_LIBRARY_PATH"] = nativeDir
                    
                    try {
                        val lbProcess = lbPb.start()
                        coreProcesses.add(lbProcess)
                        startProcessLogger(lbProcess, "LoadBalancer")
                        Log.i("FlClash", "ZIVPN Turbo Engine Ready on Port 7777")
                    } catch (e: Exception) {
                        Log.e("FlClash", "LoadBalancer failed: ${e.message}")
                    }
                }

                startMonitor(config)

            } catch (e: Exception) {
                Log.e("FlClash", "Fatal engine startup error: ${e.message}")
                withContext(Dispatchers.Main) { onCoreDied() }
            }
        }
    }

    fun stop() {
        monitorJob?.cancel()
        coreProcesses.forEach { 
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    it.destroyForcibly()
                } else {
                    it.destroy()
                }
            } catch(e: Exception) {}
        }
        coreProcesses.clear()
        try {
            Runtime.getRuntime().exec("killall -9 libuz.so libload.so")
            Runtime.getRuntime().exec("pkill -9 -f libuz.so")
            Runtime.getRuntime().exec("pkill -9 -f libload.so")
        } catch (e: Exception) {}
        Log.i("FlClash", "ZIVPN Cores stopped")
    }

    private fun startMonitor(config: ZivpnConfig) {
        monitorJob?.cancel()
        monitorJob = scope.launch {
            val startTime = System.currentTimeMillis()
            while (isActive) {
                delay(3000) // Check every 3 seconds
                if (coreProcesses.isNotEmpty()) {
                    var aliveCount = 0
                    for (proc in coreProcesses) {
                        val isAlive = try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                proc.isAlive
                            } else {
                                proc.exitValue()
                                false
                            }
                        } catch (e: IllegalThreadStateException) {
                            true
                        }
                        if (isAlive) aliveCount++
                    }

                    // Only trigger failure if most cores died
                    if (aliveCount < (coreProcesses.size / 2)) {
                        val uptime = System.currentTimeMillis() - startTime
                        Log.e("FlClash", "CRITICAL: ZIVPN Engine crashed. Uptime: ${uptime}ms")
                        
                        // Prevent infinite restart loop: if died within 10s, don't auto-stop everything immediately
                        if (uptime > 10000) {
                            withContext(Dispatchers.Main) {
                                onCoreDied()
                            }
                        }
                        stop()
                        break
                    }
                }
            }
        }
    }

    private fun startNetworkMonitor(timeoutSec: Int) {
        netMonitorJob?.cancel()
        netMonitorJob = scope.launch {
            var failCount = 0
            val maxFail = (timeoutSec / 5).coerceAtLeast(1)
            
            // 1. Initial Setup: Mimic modpes radios config
            try {
                Runtime.getRuntime().exec(arrayOf("su", "-c", "settings put global airplane_mode_radios cell,bluetooth,nfc,wifi,wimax")).waitFor()
            } catch (e: Exception) {}

            writeCustomLog("[NetworkMonitor] STARTED (Timeout: ${timeoutSec}s, MaxFail: $maxFail)")

            while (isActive) {
                delay(5000)
                
                val isConnected = try {
                    val url = URL("https://www.gstatic.com/generate_204")
                    val conn = url.openConnection() as HttpURLConnection
                    conn.instanceFollowRedirects = false
                    conn.connectTimeout = 3000
                    conn.readTimeout = 3000
                    conn.useCaches = false
                    conn.connect()
                    val responseCode = conn.responseCode
                    conn.disconnect()
                    responseCode == 204
                } catch (e: Exception) {
                    false
                }

                if (isConnected) {
                    if (failCount > 0) writeCustomLog("[NetworkMonitor] CHECK: Internet Recovered")
                    failCount = 0
                } else {
                    failCount++
                    writeCustomLog("[NetworkMonitor] WARNING: Connection Check Failed ($failCount/$maxFail)", true)
                    
                    if (failCount >= maxFail) {
                        failCount = 0 
                        
                        // 2. Strict Call Check: mCallState=2 (Mimic modpes)
                        var isCalling = false
                        try {
                            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", "dumpsys telephony.registry | grep mCallState"))
                            process.inputStream.bufferedReader().use { reader ->
                                if (reader.readText().contains("mCallState=2")) {
                                    isCalling = true
                                }
                            }
                        } catch (e: Exception) {}

                        if (isCalling) {
                            writeCustomLog("[NetworkMonitor] SKIP: User is in a call, reset aborted", true)
                            continue
                        }

                        writeCustomLog("[NetworkMonitor] ACTION: Connection Dead. Toggling Airplane Mode...")
                        
                        try {
                            // 3. Reset Action
                            val result = Runtime.getRuntime().exec(arrayOf("su", "-c", "cmd connectivity airplane-mode enable")).waitFor()
                            if (result == 0) {
                                delay(2000)
                                Runtime.getRuntime().exec(arrayOf("su", "-c", "cmd connectivity airplane-mode disable")).waitFor()
                            } else {
                                Runtime.getRuntime().exec(arrayOf("su", "-c", "settings put global airplane_mode_on 1")).waitFor()
                                Runtime.getRuntime().exec(arrayOf("su", "-c", "am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true")).waitFor()
                                delay(2500)
                                Runtime.getRuntime().exec(arrayOf("su", "-c", "settings put global airplane_mode_on 0")).waitFor()
                                Runtime.getRuntime().exec(arrayOf("su", "-c", "am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false")).waitFor()
                            }
                            
                            // 4. Wait for Data: Polling mDataConnectionState=2 (Mimic modpes until loop)
                            writeCustomLog("[NetworkMonitor] WAITING: Waiting for data signal...")
                            var signalRecovered = false
                            for (i in 1..30) { // Timeout 30s for signal recovery
                                delay(1000)
                                try {
                                    val proc = Runtime.getRuntime().exec(arrayOf("su", "-c", "dumpsys telephony.registry"))
                                    val out = proc.inputStream.bufferedReader().use { it.readText() }
                                    if (out.contains("mDataConnectionState=2")) {
                                        signalRecovered = true
                                        break
                                    }
                                } catch (e: Exception) {}
                            }
                            
                            writeCustomLog(if (signalRecovered) "[NetworkMonitor] SUCCESS: Signal Recovered" else "[NetworkMonitor] TIMEOUT: Signal recovery took too long")
                            delay(2000) 
                            
                        } catch (e: Exception) {
                            writeCustomLog("[NetworkMonitor] ERROR: Root execution failed: ${e.message}", true)
                        }
                    }
                }
            }
        }
    }

    private fun writeCustomLog(msg: String, isError: Boolean = false) {
        try {
            val logDir = File(context.filesDir, "zivpn_logs")
            if (!logDir.exists()) logDir.mkdirs()
            val logFile = File(logDir, "zivpn_core.log")
            val dateFormat = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
            val timestamp = dateFormat.format(java.util.Date())
            val type = if (isError) "ERR" else "OUT"
            val logLine = "[$timestamp] [SYSTEM] [$type] $msg\n"
            
            java.io.FileWriter(logFile, true).use { it.write(logLine) }
            if (isError) Log.e("FlClash", msg) else Log.i("FlClash", msg)
        } catch (e: Exception) {}
    }

    private fun startProcessLogger(process: Process, tag: String) {
        val logDir = File(context.filesDir, "zivpn_logs")
        if (!logDir.exists()) logDir.mkdirs()
        val logFile = File(logDir, "zivpn_core.log")
        
        val writer = java.io.FileWriter(logFile, true)
        val dateFormat = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())

        fun writeLog(msg: String, isError: Boolean) {
            val timestamp = dateFormat.format(java.util.Date())
            val type = if (isError) "ERR" else "OUT"
            val logLine = "[$timestamp] [$tag] [$type] $msg\n"
            if (isError) Log.e("FlClash", "[$tag] $msg") else Log.i("FlClash", "[$tag] $msg")
            try {
                writer.write(logLine)
                writer.flush()
            } catch (e: Exception) {}
        }

        Thread {
            try {
                process.inputStream.bufferedReader().use { reader ->
                    reader.forEachLine { writeLog(it, false) }
                }
            } catch (e: Exception) {}
        }.start()
        
        Thread {
            try {
                process.errorStream.bufferedReader().use { reader ->
                    reader.forEachLine { writeLog(it, true) }
                }
            } catch (e: Exception) {}
        }.start()
    }
}