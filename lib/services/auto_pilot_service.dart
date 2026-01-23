import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shizuku_api/shizuku_api.dart';

class AutoPilotService {
  static final AutoPilotService _instance = AutoPilotService._internal();
  factory AutoPilotService() => _instance;
  AutoPilotService._internal();

  // Instantiate based on GEMINI2.md Appendix
  final _shizuku = ShizukuApi();

  Timer? _timer;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  Future<void> start() async {
    if (_isRunning) return;

    try {
      // Use pingBinder first as suggested in Appendix
      final isBinderAlive = await _shizuku.pingBinder() ?? false;
      if (!isBinderAlive) {
         throw 'Shizuku service is not running.';
      }

      if (!await _shizuku.checkPermission()) {
        final granted = await _shizuku.requestPermission();
        if (!granted) {
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
      // Use runCommand as specified in Appendix
      await _shizuku.runCommand('cmd connectivity airplane-mode enable');
      await Future.delayed(const Duration(seconds: 3));
      
      await _shizuku.runCommand('cmd connectivity airplane-mode disable');
      await Future.delayed(const Duration(seconds: 10));
    } catch (e) {
      print('[AutoPilot] Reset Error: $e');
    }
  }
}