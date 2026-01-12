package com.follow.clash.service.models

import org.json.JSONObject
import java.io.File

data class ZivpnConfig(
    val ip: String = "",
    val pass: String = "",
    val obfs: String = "hu``hqb`c",
    val portRange: String = "6000-19999",
    val mtu: Int = 1500,
    val autoBoot: Boolean = false
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
                    mtu = json.optInt("mtu", 1500),
                    autoBoot = json.optBoolean("auto_boot", false)
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
            }.toString(4) // Pretty print
        }
    }
}