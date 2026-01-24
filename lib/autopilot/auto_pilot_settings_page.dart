import 'package:flutter/material.dart';
import 'auto_pilot_service_configurable.dart';

class AutoPilotSettingsPage extends StatefulWidget {
  const AutoPilotSettingsPage({Key? key}) : super(key: key);

  @override
  State<AutoPilotSettingsPage> createState() => _AutoPilotSettingsPageState();
}

class _AutoPilotSettingsPageState extends State<AutoPilotSettingsPage> {
  final _service = AutoPilotService();
  late AutoPilotConfig _config;

  @override
  void initState() {
    super.initState();
    _config = _service.config;
  }

  void _updateConfig(AutoPilotConfig newConfig) {
    setState(() {
      _config = newConfig;
    });
    _service.updateConfig(newConfig);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings updated successfully'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _resetToDefaults() {
    _updateConfig(const AutoPilotConfig());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AutoPilot Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            onPressed: _resetToDefaults,
            tooltip: 'Reset to defaults',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildInfoCard(),
          const SizedBox(height: 24),
          _buildTimeoutSection(),
          const SizedBox(height: 24),
          _buildRecoverySection(),
          const SizedBox(height: 24),
          _buildHealthCheckSection(), // Added
          const SizedBox(height: 24),
          _buildAdvancedSection(),
        ],
      ),
    );
  }

  Widget _buildHealthCheckSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Health Check Settings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Auto Health Check (Ping)'),
              subtitle: const Text('Automatically ping proxies while internet is OK'),
              value: _config.autoHealthCheck,
              contentPadding: EdgeInsets.zero,
              onChanged: (value) {
                _updateConfig(_config.copyWith(
                  autoHealthCheck: value,
                ));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Configure AutoPilot monitoring and recovery behavior',
                style: TextStyle(
                  color: Colors.blue.shade900,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeoutSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connection Monitoring',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _buildSliderSetting(
              title: 'Check Interval',
              description: 'How often to check internet connection',
              value: _config.checkIntervalSeconds.toDouble(),
              min: 5,
              max: 60,
              divisions: 11,
              unit: 'seconds',
              onChanged: (value) {
                _updateConfig(_config.copyWith(
                  checkIntervalSeconds: value.toInt(),
                ));
              },
            ),
            const Divider(height: 32),
            _buildSliderSetting(
              title: 'Connection Timeout',
              description: 'Maximum wait time for connection check',
              value: _config.connectionTimeoutSeconds.toDouble(),
              min: 2,
              max: 15,
              divisions: 13,
              unit: 'seconds',
              onChanged: (value) {
                _updateConfig(_config.copyWith(
                  connectionTimeoutSeconds: value.toInt(),
                ));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecoverySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recovery Settings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _buildSliderSetting(
              title: 'Max Fail Count',
              description: 'Failed attempts before triggering recovery',
              value: _config.maxFailCount.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              unit: 'attempts',
              onChanged: (value) {
                _updateConfig(_config.copyWith(
                  maxFailCount: value.toInt(),
                ));
              },
            ),
            const Divider(height: 32),
            _buildSliderSetting(
              title: 'Airplane Mode Delay',
              description: 'Time to wait in airplane mode',
              value: _config.airplaneModeDelaySeconds.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              unit: 'seconds',
              onChanged: (value) {
                _updateConfig(_config.copyWith(
                  airplaneModeDelaySeconds: value.toInt(),
                ));
              },
            ),
            const Divider(height: 32),
            _buildSliderSetting(
              title: 'Recovery Wait Time',
              description: 'Time to wait after disabling airplane mode',
              value: _config.recoveryWaitSeconds.toDouble(),
              min: 5,
              max: 30,
              divisions: 5,
              unit: 'seconds',
              onChanged: (value) {
                _updateConfig(_config.copyWith(
                  recoveryWaitSeconds: value.toInt(),
                ));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedSection() {
    final totalCycleTime = _config.checkIntervalSeconds * _config.maxFailCount;
    final recoveryTime = _config.airplaneModeDelaySeconds + _config.recoveryWaitSeconds;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Summary',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _buildSummaryItem(
              'Time until recovery trigger',
              '~${totalCycleTime} seconds',
              Icons.timer,
            ),
            const SizedBox(height: 12),
            _buildSummaryItem(
              'Recovery process duration',
              '~${recoveryTime} seconds',
              Icons.refresh,
            ),
            const SizedBox(height: 12),
            _buildSummaryItem(
              'Total worst-case duration',
              '~${totalCycleTime + recoveryTime} seconds',
              Icons.hourglass_bottom,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderSetting({
    required String title,
    required String description,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String unit,
    required ValueChanged<double> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: textTheme.bodySmall?.copyWith(
                      color: textTheme.bodySmall?.color?.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${value.toInt()} $unit',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    final textTheme = Theme.of(context).textTheme;
    
    return Row(
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
    );
  }
}
