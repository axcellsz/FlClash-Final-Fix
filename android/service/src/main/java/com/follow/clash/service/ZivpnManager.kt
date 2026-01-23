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
    private var netMonitorJob: Job? = null
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
                
                // Start Network Monitor if enabled
                if (config.autoReset) {
                    startNetworkMonitor(config.resetTimeout)
                }

            } catch (e: Exception) {
                Log.e("FlClash", "Fatal engine startup error: ${e.message}")
                withContext(Dispatchers.Main) { onCoreDied() }
            }
        }
    }

    fun stop() {
        monitorJob?.cancel()
        netMonitorJob?.cancel()
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
            val maxFail = (timeoutSec / 5).coerceAtLeast(1)
            var failCount = 0
            val rishPath = File(context.filesDir, "rish").absolutePath

            writeCustomLog("[AutoPilot] STARTED (Shizuku Mode). Timeout: ${timeoutSec}s")

            while (isActive) {
                delay(5000) // Interval check
                
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
                    responseCode == 204 || responseCode == 200
                } catch (e: Exception) {
                    false
                }

                if (isConnected) {
                    if (failCount > 0) writeCustomLog("[AutoPilot] RECOVERED: Internet is back.")
                    failCount = 0
                } else {
                    failCount++
                    writeCustomLog("[AutoPilot] WARNING: Connection Lost ($failCount/$maxFail)", true)
                    
                    if (failCount >= maxFail) {
                        failCount = 0
                        writeCustomLog("[AutoPilot] ACTION: Resetting Network via Shizuku...")

                        if (!File(rishPath).exists()) {
                            writeCustomLog("[AutoPilot] ERROR: rish binary not found at $rishPath", true)
                            // Optional: Retry extraction or notify
                            continue
                        }

                        try {
                            // Helper with detailed logging
                            suspend fun runCommand(cmd: Array<String>, tag: String) {
                                val p = Runtime.getRuntime().exec(cmd)
                                
                                // Read streams in background to prevent buffer deadlock
                                val stdoutDeferred = async(Dispatchers.IO) { 
                                    p.inputStream.bufferedReader().use { it.readText().trim() } 
                                }
                                val stderrDeferred = async(Dispatchers.IO) { 
                                    p.errorStream.bufferedReader().use { it.readText().trim() } 
                                }
                                
                                val exitCode = p.waitFor()
                                val stdout = stdoutDeferred.await()
                                val stderr = stderrDeferred.await()

                                if (stdout.isNotEmpty()) writeCustomLog("[$tag] OUT: $stdout")
                                if (stderr.isNotEmpty()) writeCustomLog("[$tag] ERR: $stderr", true)
                                if (exitCode != 0) writeCustomLog("[$tag] FAILED (Exit: $exitCode)", true)
                            }

                            // 1. Enable Airplane Mode
                            runCommand(arrayOf("sh", rishPath, "-c", "cmd connectivity airplane-mode enable"), "CMD_ENABLE")
                            
                            delay(3000) // Wait 3s

                            // 2. Disable Airplane Mode
                            runCommand(arrayOf("sh", rishPath, "-c", "cmd connectivity airplane-mode disable"), "CMD_DISABLE")

                            writeCustomLog("[AutoPilot] DONE: Airplane Toggle Complete. Waiting for signal...")
                            delay(10000) // Wait 10s for signal
                            
                        } catch (e: Exception) {
                            writeCustomLog("[AutoPilot] EXCEPTION: ${e.message}", true)
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