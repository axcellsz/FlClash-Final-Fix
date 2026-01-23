import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shizuku_api/shizuku_api.dart' as sz;

class AutoPilotService {
  static final AutoPilotService _instance = AutoPilotService._internal();
  factory AutoPilotService() => _instance;
  AutoPilotService._internal();

  Timer? _timer;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  Future<void> start() async {
    if (_isRunning) return;

    try {
      // Use alias to avoid scope confusion
      final hasPermission = await sz.Shizuku.checkSelfPermission();
      if (hasPermission != true) {
        final granted = await sz.Shizuku.requestPermission();
        if (granted != true) {
          throw 'Shizuku Permission Denied';
        }
      }
    } catch (e) {
      rethrow;
    }

    _isRunning = true;
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
      await _runShizukuCommand('cmd connectivity airplane-mode enable');
      await Future.delayed(const Duration(seconds: 3));
      await _runShizukuCommand('cmd connectivity airplane-mode disable');
      await Future.delayed(const Duration(seconds: 10));
    } catch (e) {
      print('[AutoPilot] Reset Error: $e');
    }
  }

  Future<void> _runShizukuCommand(String cmd) async {
    // Explicitly use the static class from the library
    final process = await sz.Shizuku.newProcess(
      ['sh', '-c', cmd], 
      environment: {}
    );
    await process.exitCode;
  }
}