import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shizuku_api/shizuku_api.dart';

class AutoPilotService {
  static final AutoPilotService _instance = AutoPilotService._internal();
  factory AutoPilotService() => _instance;
  AutoPilotService._internal();

  Timer? _timer;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  Future<void> start() async {
    if (_isRunning) return;

    // Check Shizuku Permission
    try {
      final hasPermission = await Shizuku.checkSelfPermission();
      if (hasPermission != true) {
        final granted = await Shizuku.requestPermission();
        if (granted != true) {
          throw 'Shizuku Permission Denied';
        }
      }
    } catch (e) {
      // Handle "Shizuku not running" or other errors
      rethrow;
    }

    _isRunning = true;
    // Initial check immediately
    _checkAndRecover();
    // Loop every 15s
    _timer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      await _checkAndRecover();
    });
  }

  void stop() {
    _timer?.cancel();
    _isRunning = false;
  }

  Future<void> _checkAndRecover() async {
    if (!_isRunning) return;
    
    final hasInternet = await checkInternet();
    if (!hasInternet) {
      // Double check before acting
      await Future.delayed(const Duration(seconds: 1));
      if (!await checkInternet()) {
         await _performReset();
      }
    }
  }

  Future<bool> checkInternet() async {
    try {
      final response = await http.head(
        Uri.parse('http://connectivitycheck.gstatic.com/generate_204')
      ).timeout(const Duration(seconds: 5));
      
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _performReset() async {
    try {
      // Enable Airplane Mode
      await _runShizukuCommand('cmd connectivity airplane-mode enable');
      
      await Future.delayed(const Duration(seconds: 3));
      
      // Disable Airplane Mode
      await _runShizukuCommand('cmd connectivity airplane-mode disable');
      
      // Cooldown to prevent spam
      await Future.delayed(const Duration(seconds: 10));
    } catch (e) {
      // Log error internally or to debug console
      print('[AutoPilot] Reset Error: $e');
    }
  }

  Future<void> _runShizukuCommand(String cmd) async {
    // Execute command via sh -c
    // Using newProcess from shizuku_api
    final process = await Shizuku.newProcess(
      ['sh', '-c', cmd], 
      environment: {}
    );
    
    // Wait for exit
    await process.exitCode;
  }
}
