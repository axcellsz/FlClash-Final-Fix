import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shizuku_api/shizuku_api.dart';
import 'package:fl_clash/state.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AutoPilotConfig {
  final int checkIntervalSeconds;
  final int connectionTimeoutSeconds;
  final int maxFailCount;
  final int airplaneModeDelaySeconds;
  final int recoveryWaitSeconds;
  final bool autoHealthCheck;
  final bool enablePingStabilizer; // Added from lexpesawat
  final int stabilizerSizeMb;      // Added from lexpesawat

  const AutoPilotConfig({
    this.checkIntervalSeconds = 15,
    this.connectionTimeoutSeconds = 5,
    this.maxFailCount = 3,
    this.airplaneModeDelaySeconds = 3,
    this.recoveryWaitSeconds = 10,
    this.autoHealthCheck = true,
    this.enablePingStabilizer = false, 
    this.stabilizerSizeMb = 1,
  });

  AutoPilotConfig copyWith({
    int? checkIntervalSeconds,
    int? connectionTimeoutSeconds,
    int? maxFailCount,
    int? airplaneModeDelaySeconds,
    int? recoveryWaitSeconds,
    bool? autoHealthCheck,
    bool? enablePingStabilizer,
    int? stabilizerSizeMb,
  }) {
    return AutoPilotConfig(
      checkIntervalSeconds: checkIntervalSeconds ?? this.checkIntervalSeconds,
      connectionTimeoutSeconds: connectionTimeoutSeconds ?? this.connectionTimeoutSeconds,
      maxFailCount: maxFailCount ?? this.maxFailCount,
      airplaneModeDelaySeconds: airplaneModeDelaySeconds ?? this.airplaneModeDelaySeconds,
      recoveryWaitSeconds: recoveryWaitSeconds ?? this.recoveryWaitSeconds,
      autoHealthCheck: autoHealthCheck ?? this.autoHealthCheck,
      enablePingStabilizer: enablePingStabilizer ?? this.enablePingStabilizer,
      stabilizerSizeMb: stabilizerSizeMb ?? this.stabilizerSizeMb,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'checkIntervalSeconds': checkIntervalSeconds,
      'connectionTimeoutSeconds': connectionTimeoutSeconds,
      'maxFailCount': maxFailCount,
      'airplaneModeDelaySeconds': airplaneModeDelaySeconds,
      'recoveryWaitSeconds': recoveryWaitSeconds,
      'autoHealthCheck': autoHealthCheck,
      'enablePingStabilizer': enablePingStabilizer,
      'stabilizerSizeMb': stabilizerSizeMb,
    };
  }

  factory AutoPilotConfig.fromJson(Map<String, dynamic> json) {
    return AutoPilotConfig(
      checkIntervalSeconds: json['checkIntervalSeconds'] ?? 15,
      connectionTimeoutSeconds: json['connectionTimeoutSeconds'] ?? 5,
      maxFailCount: json['maxFailCount'] ?? 3,
      airplaneModeDelaySeconds: json['airplaneModeDelaySeconds'] ?? 3,
      recoveryWaitSeconds: json['recoveryWaitSeconds'] ?? 10,
      autoHealthCheck: json['autoHealthCheck'] ?? true,
      enablePingStabilizer: json['enablePingStabilizer'] ?? false,
      stabilizerSizeMb: json['stabilizerSizeMb'] ?? 1,
    );
  }
}

enum AutoPilotStatus {
  stopped,
  running,
  checking,
  recovering,
  error,
}

class AutoPilotState {
  final AutoPilotStatus status;
  final int failCount;
  final int consecutiveResets; // Added logic
  final String? message;
  final DateTime? lastCheck;
  final bool hasInternet;

  const AutoPilotState({
    required this.status,
    required this.failCount,
    this.consecutiveResets = 0,
    this.message,
    this.lastCheck,
    required this.hasInternet,
  });

  AutoPilotState copyWith({
    AutoPilotStatus? status,
    int? failCount,
    int? consecutiveResets,
    String? message,
    DateTime? lastCheck,
    bool? hasInternet,
  }) {
    return AutoPilotState(
      status: status ?? this.status,
      failCount: failCount ?? this.failCount,
      consecutiveResets: consecutiveResets ?? this.consecutiveResets,
      message: message ?? this.message,
      lastCheck: lastCheck ?? this.lastCheck,
      hasInternet: hasInternet ?? this.hasInternet,
    );
  }
}

class AutoPilotService {
  static final AutoPilotService _instance = AutoPilotService._internal();
  factory AutoPilotService() => _instance;
  AutoPilotService._internal();

  final _shizuku = ShizukuApi();
  
  Timer? _timer;
  AutoPilotConfig _config = const AutoPilotConfig();
  
  final _stateController = StreamController<AutoPilotState>.broadcast();
  Stream<AutoPilotState> get stateStream => _stateController.stream;
  
  bool _isChecking = false;
  String? _cachedPackageName;

  AutoPilotState _currentState = const AutoPilotState(
    status: AutoPilotStatus.stopped,
    failCount: 0,
    consecutiveResets: 0,
    hasInternet: true,
  );

  AutoPilotState get currentState => _currentState;
  AutoPilotConfig get config => _config;
  bool get isRunning => _currentState.status != AutoPilotStatus.stopped;

  Future<String> get _packageName async {
    if (_cachedPackageName != null) return _cachedPackageName!;
    final info = await PackageInfo.fromPlatform();
    _cachedPackageName = info.packageName;
    return _cachedPackageName!;
  }

  void updateConfig(AutoPilotConfig newConfig) {
    final wasRunning = isRunning;
    if (wasRunning) {
      stop();
    }
    _config = newConfig;
    if (wasRunning) {
      start();
    }
  }

  Future<void> start() async {
    if (isRunning) return;

    try {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.running,
        message: 'Initializing Shizuku service...',
      ));

      final isBinderAlive = await _shizuku.pingBinder() ?? false;
      if (!isBinderAlive) {
        throw 'Shizuku service is not running.';
      }

      if (!(await _shizuku.checkPermission() ?? false)) {
        final granted = await _shizuku.requestPermission() ?? false;
        if (!granted) {
          throw 'Shizuku Permission Denied';
        }
      }

      // --- TRICK: Strengthen Background Resilience ---
      await _strengthenBackground();

      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.running,
        failCount: 0,
        consecutiveResets: 0,
        message: 'AutoPilot service started (High Priority)',
      ));

      _timer = Timer.periodic(
        Duration(seconds: _config.checkIntervalSeconds),
        (timer) async {
          await _checkAndRecover();
        },
      );
    } catch (e) {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.error,
        message: 'Failed to start: $e',
      ));
      rethrow;
    }
  }

  /// Trik Shizuku: Memaksa Android untuk tidak mematikan aplikasi ini (Anti-DeepSleep)
  Future<void> _strengthenBackground() async {
    try {
      final pkg = await _packageName; 
      
      // 1. Whitelist Doze & Idle (Ini yang memberikan Bucket 5 secara otomatis)
      await _shizuku.runCommand('dumpsys deviceidle whitelist +$pkg && dumpsys deviceidle except-idle-whitelist +$pkg && dumpsys deviceidle tempwhitelist +$pkg');
      
      // 2. Gabungkan Izin Penting via AppOps
      final ops = [
        'RUN_IN_BACKGROUND', 'RUN_ANY_IN_BACKGROUND', 'START_FOREGROUND',
        'WAKE_LOCK', 'SYSTEM_ALERT_WINDOW', 'SCHEDULE_EXACT_ALARM',
        'GET_USAGE_STATS', 'AUTO_START', 'ACTIVATE_VPN', 'ESTABLISH_VPN_SERVICE'
      ];
      final chainedOps = ops.map((op) => 'cmd appops set $pkg $op allow').join(' && ');
      await _shizuku.runCommand('sh -c "$chainedOps"');

      // 3. Status Aktivitas & Standby (Gunakan 'active' agar tidak error, whitelist di atas sudah memberi Bucket 5)
      await _shizuku.runCommand('cmd activity set-inactive $pkg false && cmd activity set-standby-bucket $pkg active');
      
      // 4. Pengaturan Global & Anti-Killer
      await _shizuku.runCommand('device_config put activity_manager max_phantom_processes 2147483647');
      await _shizuku.runCommand('settings put global adaptive_battery_management_enabled 0');
      await _shizuku.runCommand('settings put global activity_manager_constants max_cached_processes=128');
      await _shizuku.runCommand('cmd power set-battery-saver-mode-enabled false');
      
      // 5. Whitelist Network Policy (UID Detection)
      try {
        final packageInfo = await _shizuku.runCommand('dumpsys package $pkg');
        if (packageInfo != null) {
           final match = RegExp(r'userId=(\d+)').firstMatch(packageInfo);
           if (match != null) {
              await _sh_shizukuRun('cmd netpolicy add restrict-background-whitelist ${match.group(1)}');
           }
        }
      } catch(_) {}
      
      // 6. Vendor-Specific Tweaks (MIUI, ColorOS, Infinix)
      await _shizuku.runCommand('settings put global duraspeed_allow 1 && settings put global duraspeed_package_list $pkg && settings put long standalone_app_auto_start_whitelist $pkg');
      await _shizuku.runCommand('setprop persist.sys.miui.autostart $pkg'); // Xiaomi
      await _shizuku.runCommand('settings put global background_freeze_timeout -1'); // Oppo/Realme
      
      // 7. Battery Stats Active
      await _shizuku.runCommand('cmd batterystats --active $pkg');
      
      print('[_strengthenBackground] Ultimate Multi-Vendor Enforcement Applied for $pkg');
    } catch (e) {
      print('[_strengthenBackground] Warning: $e');
    }
  }

  // Helper untuk menjalankan perintah shell via Shizuku
  Future<String?> _sh_shizukuRun(String cmd) async {
     return await _shizuku.runCommand(cmd);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    
    _updateState(_currentState.copyWith(
      status: AutoPilotStatus.stopped,
      failCount: 0,
      message: 'AutoPilot service stopped',
    ));
  }

  Future<void> _checkAndRecover() async {
    if (!isRunning || _isChecking) return;
    _isChecking = true;

    try {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.checking,
        lastCheck: DateTime.now(),
      ));

      // Re-apply Shizuku Priority (VIP Status) every check cycle
      await _strengthenBackground();

      final hasInternet = await checkInternet();

      if (hasInternet) {
        // Auto Health Check (Press Ping Button)
        if (_config.autoHealthCheck && globalState.isStart) {
           globalState.appController.autoHealthCheck();
        }

        if (_currentState.failCount > 0 || _currentState.consecutiveResets > 0) {
          _updateState(_currentState.copyWith(
            status: AutoPilotStatus.running,
            failCount: 0,
            consecutiveResets: 0,
            hasInternet: true,
            message: 'Internet connection recovered',
          ));
        } else {
          _updateState(_currentState.copyWith(
            status: AutoPilotStatus.running,
            hasInternet: true,
            message: 'Connection stable',
          ));
        }
      } else {
        final newFailCount = _currentState.failCount + 1;
        
        _updateState(_currentState.copyWith(
          status: AutoPilotStatus.running,
          failCount: newFailCount,
          hasInternet: false,
          message: 'Connection lost ($newFailCount/${_config.maxFailCount})',
        ));

        if (newFailCount >= _config.maxFailCount) {
          if (_currentState.consecutiveResets >= 5) {
             _updateState(_currentState.copyWith(
               status: AutoPilotStatus.stopped,
               message: 'Gave up: Internet unstable after 5 resets.',
             ));
             stop(); 
          } else {
             await _performReset();
          }
        }
      }
    } catch (e) {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.error,
        message: 'Check failed: $e',
      ));
    } finally {
      _isChecking = false;
    }
  }

  Future<bool> checkInternet() async {
    try {
      final response = await http
          .head(Uri.parse('http://connectivitycheck.gstatic.com/generate_204'))
          .timeout(Duration(seconds: _config.connectionTimeoutSeconds));

      return response.statusCode == 204 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _runPingStabilizer() async {
    if (!_config.enablePingStabilizer) return;

    final client = http.Client();

    try {
      _updateState(_currentState.copyWith(
        message: 'Stabilizing: Warming up connection...',
      ));
      
      // Allow modem/DNS to settle after airplane mode toggle
      await Future.delayed(const Duration(seconds: 2));

      for (int i = 1; i <= _config.stabilizerSizeMb; i++) {
        if (!isRunning) break; 
        
        try {
          _updateState(_currentState.copyWith(
            message: 'Stabilizing: Downloading chunk $i/${_config.stabilizerSizeMb} MB...',
          ));

          final request = http.Request('GET', Uri.parse('http://speedtest.tele2.net/1MB.zip'));
          // Disable keep-alive to force fresh connection per chunk
          request.headers['Connection'] = 'close'; 
          
          final response = await client.send(request).timeout(const Duration(seconds: 15));

          if (response.statusCode == 200) {
            await for (var _ in response.stream) {
              if (!isRunning) break;
              // Discard bytes
            }
          } else {
             await Future.delayed(const Duration(seconds: 1));
          }
        } catch (e) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    } catch (e) {
      // Ignore errors during stabilization
    } finally {
      client.close();
    }
  }

  Future<void> _performReset({int retryCount = 0}) async {
    try {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.recovering,
        failCount: 0,
        consecutiveResets: _currentState.consecutiveResets + 1,
        message: retryCount > 0 ? 'Retrying reset (${retryCount + 1})...' : 'Resetting network (Attempt #${_currentState.consecutiveResets + 1})...',
      ));

      await _shizuku.runCommand('cmd connectivity airplane-mode enable');
      await Future.delayed(Duration(seconds: _config.airplaneModeDelaySeconds));

      _updateState(_currentState.copyWith(
        message: 'Restoring connection...',
      ));

      await _shizuku.runCommand('cmd connectivity airplane-mode disable');
      await Future.delayed(Duration(seconds: _config.recoveryWaitSeconds));

      // Verify connection before stabilizing
      final isConnected = await checkInternet();
      if (isConnected) {
         await _runPingStabilizer();
      }

      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.running,
        message: 'Recovery process completed',
      ));
    } catch (e) {
      // Safety: Attempt to disable airplane mode in case we got stuck
      try {
        await _shizuku.runCommand('cmd connectivity airplane-mode disable');
      } catch (_) {}

      if (retryCount < 2) {
         await Future.delayed(const Duration(seconds: 2));
         return _performReset(retryCount: retryCount + 1);
      }
      
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.error,
        message: 'Reset error: $e',
      ));
    }
  }

  void _updateState(AutoPilotState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  void dispose() {
    _timer?.cancel();
    _stateController.close();
  }

  /// Call this when app comes to foreground
  void onAppResume() {
    if (isRunning && (_timer == null || !_timer!.isActive)) {
        // Restart timer if it was killed by OS but service should be running
        _timer?.cancel();
        _timer = Timer.periodic(
          Duration(seconds: _config.checkIntervalSeconds),
          (timer) async {
            await _checkAndRecover();
          },
        );
        // Do an immediate check
        _checkAndRecover();
    }
  }
}
