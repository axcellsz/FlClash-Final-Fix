package com.follow.clash.service.models

import org.json.JSONObject
import java.io.File

data class ZivpnConfig(
    val ip: String = "",
    val pass: String = "",
    val obfs: String = "hu``hqb`c",
    val portRange: String = "6000-19999",
    val mtu: Int = 9000,
    val autoBoot: Boolean = false,
    val autoReset: Boolean = false,
    val resetTimeout: Int = 15
) {
    companion object {
        fun fromFile(file: File): ZivpnConfig {
            if (!file.exists()) return ZivpnConfig()
            return try {
                val json = JSONObject(file.readText())
                ZivpnConfig(
                    ip = json.optString("ip", ""),
                    pass = json.optString("pass", ""),
                    obfs = json.optString("obfs", "hu``hqb`c"),
                    portRange = json.optString("port_range", "6000-19999"),
                    mtu = json.optInt("mtu", 9000),
                    autoBoot = json.optBoolean("auto_boot", false),
                    autoReset = json.optBoolean("auto_reset", false),
                    resetTimeout = json.optInt("reset_timeout", 15)
                )
            } catch (e: Exception) {
                ZivpnConfig()
            }
        }

        fun toJson(config: ZivpnConfig): String {
            return JSONObject().apply {
                put("ip", config.ip)
                put("pass", config.pass)
                put("obfs", config.obfs)
                put("port_range", config.portRange)
                put("mtu", config.mtu)
                put("auto_boot", config.autoBoot)
                put("auto_reset", config.autoReset)
                put("reset_timeout", config.resetTimeout)
            }.toString(4) // Pretty print
        }
    }
}