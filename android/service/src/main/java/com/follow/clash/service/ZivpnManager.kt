package com.follow.clash.service

import android.content.Context
import android.os.Build
import android.util.Log
import com.follow.clash.service.models.ZivpnConfig
import kotlinx.coroutines.*
import java.io.File

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
                stop() // Clean up first
                
                // Kill zombies aggressive
                try {
                    Runtime.getRuntime().exec("killall -9 libuz.so").waitFor()
                    Runtime.getRuntime().exec("killall -9 libload.so").waitFor()
                    Runtime.getRuntime().exec("pkill -9 -f libuz.so").waitFor()
                    Runtime.getRuntime().exec("pkill -9 -f libload.so").waitFor()
                } catch (e: Exception) {}
                
                delay(800) // Give OS time to release ports

                val nativeDir = context.applicationInfo.nativeLibraryDir
                val libUz = File(nativeDir, "libuz.so").absolutePath
                val libLoad = File(nativeDir, "libload.so").absolutePath

                if (!File(libUz).exists()) {
                    Log.e("FlClash", "Native Binary libuz.so not found")
                    return@launch
                }

                // Load Config using Model
                val configFile = File(context.filesDir, "zivpn_config.json")
                val config = ZivpnConfig.fromFile(configFile)

                Log.i("FlClash", "Starting ZIVPN Cores with IP: ${config.ip}, Range: ${config.portRange}")

                val tunnels = mutableListOf<String>()
                // Use Safe Ports (Avoid 1080 conflict)
                val ports = listOf(20080, 20081, 20082, 20083)
                val ranges = config.portRange.split(",").map { it.trim() }.filter { it.isNotEmpty() }

                for ((index, port) in ports.withIndex()) {
                    val currentRange = if (ranges.isNotEmpty()) ranges[index % ranges.size] else "6000-19999"
                    val configContent = """{"server":"${config.ip}:$currentRange","obfs":"${config.obfs}","auth":"${config.pass}","socks5":{"listen":"127.0.0.1:$port"},"insecure":true,"recvwindowconn":131072,"recvwindow":327680}"""
                    
                    val pb = ProcessBuilder(libUz, "-s", config.obfs, "--config", configContent)
                    pb.environment()["LD_LIBRARY_PATH"] = nativeDir
                    
                    val process = pb.start()
                    coreProcesses.add(process)
                    startProcessLogger(process, "Core-$port")
                    tunnels.add("127.0.0.1:$port")
                    delay(150)
                }

                delay(1000)

                val lbArgs = mutableListOf(libLoad, "-lport", "7777", "-tunnel")
                lbArgs.addAll(tunnels)
                val lbPb = ProcessBuilder(lbArgs)
                lbPb.environment()["LD_LIBRARY_PATH"] = nativeDir
                
                val lbProcess = lbPb.start()
                coreProcesses.add(lbProcess)
                startProcessLogger(lbProcess, "LoadBalancer")

                Log.i("FlClash", "ZIVPN Turbo Engine started successfully on port 7777")
                
                startMonitor(config) // Start monitoring

            } catch (e: Exception) {
                Log.e("FlClash", "Failed to start ZIVPN Cores: ${e.message}", e)
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
            while (isActive) {
                delay(2000)
                if (coreProcesses.isNotEmpty()) {
                    var allAlive = true
                    for (proc in coreProcesses) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            if (!proc.isAlive) {
                                allAlive = false
                                break
                            }
                        } else {
                            try {
                                proc.exitValue()
                                allAlive = false 
                                break
                            } catch (e: IllegalThreadStateException) {}
                        }
                    }

                    if (!allAlive) {
                        Log.e("FlClash", "CRITICAL: One or more ZIVPN Cores died unexpectedly!")
                        withContext(Dispatchers.Main) {
                            onCoreDied()
                        }
                        stop()
                        break
                    }
                }
            }
        }
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
