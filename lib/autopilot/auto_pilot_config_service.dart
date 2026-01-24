import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'auto_pilot_service_configurable.dart';

/// Service untuk menyimpan dan memuat konfigurasi AutoPilot
class AutoPilotConfigService {
  static const String _configKey = 'autopilot_config';
  static const String _isEnabledKey = 'autopilot_enabled';

  /// Menyimpan konfigurasi ke SharedPreferences
  static Future<void> saveConfig(AutoPilotConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(config.toJson());
    await prefs.setString(_configKey, jsonString);
  }

  /// Memuat konfigurasi dari SharedPreferences
  static Future<AutoPilotConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_configKey);
    
    if (jsonString == null) {
      return const AutoPilotConfig(); // Return default config
    }
    
    try {
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
      return AutoPilotConfig.fromJson(jsonMap);
    } catch (e) {
      // Jika terjadi error parsing, return default config
      return const AutoPilotConfig();
    }
  }

  /// Menyimpan status enabled/disabled
  static Future<void> saveEnabledStatus(bool isEnabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isEnabledKey, isEnabled);
  }

  /// Memuat status enabled/disabled
  static Future<bool> loadEnabledStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isEnabledKey) ?? false;
  }

  /// Menghapus semua konfigurasi tersimpan
  static Future<void> clearConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_configKey);
    await prefs.remove(_isEnabledKey);
  }
}

/// Extension untuk AutoPilotService dengan persistence support
extension AutoPilotServicePersistence on AutoPilotService {
  /// Memuat konfigurasi dari storage dan menerapkannya
  Future<void> loadAndApplyConfig() async {
    final config = await AutoPilotConfigService.loadConfig();
    updateConfig(config);
  }

  /// Menyimpan konfigurasi saat ini ke storage
  Future<void> saveCurrentConfig() async {
    await AutoPilotConfigService.saveConfig(config);
  }

  /// Start service dan simpan status
  Future<void> startAndSave() async {
    await start();
    await AutoPilotConfigService.saveEnabledStatus(true);
  }

  /// Stop service dan simpan status
  Future<void> stopAndSave() async {
    stop();
    await AutoPilotConfigService.saveEnabledStatus(false);
  }

  /// Restore service state dari storage
  Future<void> restoreState() async {
    await loadAndApplyConfig();
    
    final wasEnabled = await AutoPilotConfigService.loadEnabledStatus();
    if (wasEnabled) {
      try {
        await start();
      } catch (e) {
        // Jika gagal start (misal Shizuku tidak aktif), 
        // set enabled status ke false
        await AutoPilotConfigService.saveEnabledStatus(false);
      }
    }
  }
}
