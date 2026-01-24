import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shizuku_api/shizuku_api.dart';
import 'package:fl_clash/state.dart';

class AutoPilotConfig {
  final int checkIntervalSeconds;
  final int connectionTimeoutSeconds;
  final int maxFailCount;
  final int airplaneModeDelaySeconds;
  final int recoveryWaitSeconds;
  final bool autoHealthCheck; // Added

  const AutoPilotConfig({
    this.checkIntervalSeconds = 15,
    this.connectionTimeoutSeconds = 5,
    this.maxFailCount = 3,
    this.airplaneModeDelaySeconds = 3,
    this.recoveryWaitSeconds = 10,
    this.autoHealthCheck = true, // Added Default True
  });

  AutoPilotConfig copyWith({
    int? checkIntervalSeconds,
    int? connectionTimeoutSeconds,
    int? maxFailCount,
    int? airplaneModeDelaySeconds,
    int? recoveryWaitSeconds,
    bool? autoHealthCheck,
  }) {
    return AutoPilotConfig(
      checkIntervalSeconds: checkIntervalSeconds ?? this.checkIntervalSeconds,
      connectionTimeoutSeconds: connectionTimeoutSeconds ?? this.connectionTimeoutSeconds,
      maxFailCount: maxFailCount ?? this.maxFailCount,
      airplaneModeDelaySeconds: airplaneModeDelaySeconds ?? this.airplaneModeDelaySeconds,
      recoveryWaitSeconds: recoveryWaitSeconds ?? this.recoveryWaitSeconds,
      autoHealthCheck: autoHealthCheck ?? this.autoHealthCheck,
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
  final String? message;
  final DateTime? lastCheck;
  final bool hasInternet;

  const AutoPilotState({
    required this.status,
    required this.failCount,
    this.message,
    this.lastCheck,
    required this.hasInternet,
  });

  AutoPilotState copyWith({
    AutoPilotStatus? status,
    int? failCount,
    String? message,
    DateTime? lastCheck,
    bool? hasInternet,
  }) {
    return AutoPilotState(
      status: status ?? this.status,
      failCount: failCount ?? this.failCount,
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
  
  AutoPilotState _currentState = const AutoPilotState(
    status: AutoPilotStatus.stopped,
    failCount: 0,
    hasInternet: true,
  );

  AutoPilotState get currentState => _currentState;
  AutoPilotConfig get config => _config;
  bool get isRunning => _currentState.status != AutoPilotStatus.stopped;

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
      const pkg = 'com.follow.clash'; 
      
      // 1. Whitelist dari Doze Mode & Idle (Level Sistem & User)
      await _shizuku.runCommand('dumpsys deviceidle whitelist +$pkg');
      await _shizuku.runCommand('dumpsys deviceidle except-idle-whitelist +$pkg');
      
      // 2. Paksa Permission RUN_IN_BACKGROUND & RUN_ANY_IN_BACKGROUND
      await _shizuku.runCommand('cmd appops set $pkg RUN_IN_BACKGROUND allow');
      await _shizuku.runCommand('cmd appops set $pkg RUN_ANY_IN_BACKGROUND allow');
      await _shizuku.runCommand('cmd appops set $pkg START_FOREGROUND allow');

      // 3. Paksa status "Active" & Bucket "Exempted" (Bucket 5)
      await _shizuku.runCommand('cmd activity set-inactive $pkg false');
      await _shizuku.runCommand('dumpsys usagestats setappstandby $pkg active');
      
      // 4. Disable Phantom Process Killer (Android 12+) - Mencegah libuz di-kill
      await _shizuku.runCommand('device_config put activity_manager max_phantom_processes 2147483647');

      // 5. Network Policy (Data Saver Whitelist) - Membutuhkan UID
      try {
        final uidResult = await _shizuku.runCommand('id -u $pkg');
        if (uidResult != null && uidResult.trim().isNotEmpty) {
           final uid = uidResult.trim();
           await _shizuku.runCommand('cmd netpolicy add restrict-background-whitelist $uid');
        }
      } catch(_) {}
      
      // 6. Bypass DuraSpeed & Auto-Start Whitelist (Khusus MediaTek/Infinix)
      await _shizuku.runCommand('settings put global duraspeed_allow 1');
      await _shizuku.runCommand('settings put global duraspeed_package_list $pkg');
      await _shizuku.runCommand('settings put long standalone_app_auto_start_whitelist $pkg');
      
      // 7. Tandai sebagai aplikasi Aktif di mata BatteryStats
      await _shizuku.runCommand('cmd batterystats --active $pkg');
      
      print('[_strengthenBackground] All-In-One Background Enforcement Applied');
    } catch (e) {
      print('[_strengthenBackground] Warning: $e');
    }
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
    if (!isRunning) return;

    try {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.checking,
        lastCheck: DateTime.now(),
      ));

      // Re-apply Shizuku Priority (VIP Status) every check cycle
      // This ensures the OS doesn't demote the app to a lower bucket
      await _strengthenBackground();

      final hasInternet = await checkInternet();

      if (hasInternet) {
        // Auto Health Check (Press Ping Button)
        if (_config.autoHealthCheck && globalState.isStart) {
           globalState.appController.autoHealthCheck();
        }

        if (_currentState.failCount > 0) {
          _updateState(_currentState.copyWith(
            status: AutoPilotStatus.running,
            failCount: 0,
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
          await _performReset();
        }
      }
    } catch (e) {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.error,
        message: 'Check failed: $e',
      ));
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

  Future<void> _performReset() async {
    try {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.recovering,
        failCount: 0,
        message: 'Initiating connection recovery...',
      ));

      await _shizuku.runCommand('cmd connectivity airplane-mode enable');
      await Future.delayed(Duration(seconds: _config.airplaneModeDelaySeconds));

      _updateState(_currentState.copyWith(
        message: 'Restoring connection...',
      ));

      await _shizuku.runCommand('cmd connectivity airplane-mode disable');
      await Future.delayed(Duration(seconds: _config.recoveryWaitSeconds));

      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.running,
        message: 'Recovery process completed',
      ));
    } catch (e) {
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