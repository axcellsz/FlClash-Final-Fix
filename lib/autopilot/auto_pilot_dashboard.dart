import 'package:flutter/material.dart';
import 'auto_pilot_service_configurable.dart';
import 'auto_pilot_settings_page.dart';
import 'auto_pilot_config_service.dart';

class AutoPilotDashboard extends StatefulWidget {
  const AutoPilotDashboard({Key? key}) : super(key: key);

  @override
  State<AutoPilotDashboard> createState() => _AutoPilotDashboardState();
}

class _AutoPilotDashboardState extends State<AutoPilotDashboard> {
  final _service = AutoPilotService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AutoPilot Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AutoPilotSettingsPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<AutoPilotState>(
        stream: _service.stateStream,
        initialData: _service.currentState,
        builder: (context, snapshot) {
          final state = snapshot.data ?? _service.currentState;
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatusCard(state),
                const SizedBox(height: 16),
                _buildControlCard(state),
                const SizedBox(height: 16),
                _buildConfigurationCard(),
                const SizedBox(height: 16),
                _buildConnectionStatusCard(state),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(AutoPilotState state) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (state.status) {
      case AutoPilotStatus.stopped:
        statusColor = Colors.grey;
        statusIcon = Icons.stop_circle_outlined;
        statusText = 'Stopped';
        break;
      case AutoPilotStatus.running:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_outline;
        statusText = 'Running';
        break;
      case AutoPilotStatus.checking:
        statusColor = Colors.blue;
        statusIcon = Icons.sync;
        statusText = 'Checking...';
        break;
      case AutoPilotStatus.recovering:
        statusColor = Colors.orange;
        statusIcon = Icons.healing;
        statusText = 'Recovering';
        break;
      case AutoPilotStatus.error:
        statusColor = Colors.red;
        statusIcon = Icons.error_outline;
        statusText = 'Error';
        break;
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              statusIcon,
              size: 64,
              color: statusColor,
            ),
            const SizedBox(height: 12),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
            if (state.message != null) ...[
              const SizedBox(height: 8),
              Text(
                state.message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.8),
                ),
              ),
            ],
            if (state.lastCheck != null) ...[
              const SizedBox(height: 12),
              Text(
                'Last check: ${_formatTime(state.lastCheck!)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).textTheme.labelSmall?.color?.withOpacity(0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildControlCard(AutoPilotState state) {
    final isRunning = state.status != AutoPilotStatus.stopped;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isRunning ? _stopService : _startService,
                icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
                label: Text(isRunning ? 'Stop AutoPilot' : 'Start AutoPilot'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isRunning ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _testConnection,
                icon: const Icon(Icons.network_check),
                label: const Text('Test Connection Now'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigurationCard() {
    final config = _service.config;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Current Configuration',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AutoPilotSettingsPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Edit'),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            _buildConfigItem(
              'Check Interval',
              '${config.checkIntervalSeconds}s',
              Icons.timer,
            ),
            _buildConfigItem(
              'Connection Timeout',
              '${config.connectionTimeoutSeconds}s',
              Icons.hourglass_empty,
            ),
            _buildConfigItem(
              'Max Fail Count',
              '${config.maxFailCount} attempts',
              Icons.replay,
            ),
            _buildConfigItem(
              'Airplane Delay',
              '${config.airplaneModeDelaySeconds}s',
              Icons.airplanemode_active,
            ),
            _buildConfigItem(
              'Recovery Wait',
              '${config.recoveryWaitSeconds}s',
              Icons.restore,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatusCard(AutoPilotState state) {
    return Card(
      color: state.hasInternet ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              state.hasInternet ? Icons.wifi : Icons.wifi_off,
              color: state.hasInternet ? Colors.green : Colors.red,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.hasInternet ? 'Connected' : 'No Connection',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: state.hasInternet
                          ? Colors.green.shade900
                          : Colors.red.shade900,
                    ),
                  ),
                  if (state.failCount > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Failed attempts: ${state.failCount}/${_service.config.maxFailCount}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigItem(String label, String value, IconData icon) {
    final textTheme = Theme.of(context).textTheme;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: textTheme.bodyMedium?.color?.withOpacity(0.7)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: textTheme.bodyMedium?.color?.withOpacity(0.9),
              ),
            ),
          ),
          Text(
            value,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _startService() async {
    try {
      await _service.startAndSave();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _stopService() {
    _service.stopAndSave();
  }

  Future<void> _testConnection() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    final hasInternet = await _service.checkInternet();

    if (!mounted) return;
    Navigator.pop(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              hasInternet ? Icons.check_circle : Icons.error,
              color: hasInternet ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 12),
            Text(hasInternet ? 'Connected' : 'No Connection'),
          ],
        ),
        content: Text(
          hasInternet
              ? 'Internet connection is working properly.'
              : 'Unable to reach the internet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
