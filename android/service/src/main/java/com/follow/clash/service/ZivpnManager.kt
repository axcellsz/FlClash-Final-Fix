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

                // Dynamic RecvWindow Calculation
                val baseConn = 131072
                val baseWin = 327680
                val multiplier = config.recvWindowMultiplier
                
                val dynamicConn = (baseConn * multiplier).toInt()
                val dynamicWin = (baseWin * multiplier).toInt()
                
                Log.i("FlClash", "Hysteria Config - Window: $dynamicWin, Conn: $dynamicConn (x$multiplier)")

                for ((index, port) in ports.withIndex()) {
                    val currentRange = if (ranges.isNotEmpty()) ranges[index % ranges.size] else "6000-19999"
                    val configContent = """{"server":"${config.ip}:$currentRange","obfs":"${config.obfs}","auth":"${config.pass}","socks5":{"listen":"127.0.0.1:$port"},"insecure":true,"recvwindowconn":$dynamicConn,"recvwindow":$dynamicWin}"""
                    
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

                // --- UDPGW Implementation ---
                delay(800)
                val libUdpgw = File(nativeDir, "libudpgw.so").absolutePath
                if (File(libUdpgw).exists()) {
                    val udpgwArgs = listOf(
                        libUdpgw,
                        "--listen-addr", "127.0.0.1:7300",
                        "--max-clients", "500",
                        "--max-connections-for-client", "20",
                        "--loglevel", "none"
                    )
                    val udpgwPb = ProcessBuilder(udpgwArgs)
                    udpgwPb.environment()["LD_LIBRARY_PATH"] = nativeDir
                    try {
                        val udpgwProcess = udpgwPb.start()
                        coreProcesses.add(udpgwProcess)
                        startProcessLogger(udpgwProcess, "UDPGW")
                        Log.i("FlClash", "UDPGW started on port 7300")
                    } catch (e: Exception) {
                        Log.e("FlClash", "Failed to start UDPGW: ${e.message}")
                    }
                }

                // --- PDNSD Implementation (DNSGW) ---
                delay(200)
                val libPdnsd = File(nativeDir, "libpdnsd.so").absolutePath
                val pdnsdConf = File(context.filesDir, "pdnsd.conf")
                
                if (!pdnsdConf.exists()) {
                    // Create default config matching ZIVPN
                    val confContent = """
                        global {
                            perm_cache=1024;
                            cache_dir="${context.cacheDir.absolutePath}";
                            server_ip = 169.254.1.1;
                            server_port = 8091;
                            query_method = tcp_only;
                            min_ttl=15m;
                            max_ttl=1w;
                            timeout=10;
                            daemon=off;
                        }
                        server {
                            label= "GoogleDNS";
                            ip = 8.8.8.8;
                            uptest = none;
                            proxy_only = on;
                        }
                    """.trimIndent()
                    pdnsdConf.writeText(confContent)
                }

                if (File(libPdnsd).exists()) {
                    val pdnsdArgs = listOf(libPdnsd, "-c", pdnsdConf.absolutePath, "-v2")
                    val pdnsdPb = ProcessBuilder(pdnsdArgs)
                    pdnsdPb.environment()["LD_LIBRARY_PATH"] = nativeDir
                    try {
                        val pdnsdProcess = pdnsdPb.start()
                        coreProcesses.add(pdnsdProcess)
                        startProcessLogger(pdnsdProcess, "PDNSD")
                        Log.i("FlClash", "PDNSD started on port 8091")
                    } catch (e: Exception) {
                        Log.e("FlClash", "Failed to start PDNSD: ${e.message}")
                    }
                }
                // ----------------------------------

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