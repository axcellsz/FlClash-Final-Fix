import 'dart:convert';
import 'dart:io';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/common/path.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_clash/autopilot/auto_pilot_dashboard.dart';

class HysteriaSettingsPage extends StatefulWidget {
  const HysteriaSettingsPage({super.key});

  @override
  State<HysteriaSettingsPage> createState() => _HysteriaSettingsPageState();
}

class _HysteriaSettingsPageState extends State<HysteriaSettingsPage> {
  final TextEditingController _profileNameController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _obfsController = TextEditingController();
  final TextEditingController _portRangeController = TextEditingController();
  final TextEditingController _mtuController = TextEditingController();
  bool _enableKeepAlive = true;
  bool _autoBoot = false;
  bool _enableTurbo = false; // Added Turbo Switch
  double _recvWindowMultiplier = 1.0;
  
  @override
  void initState() {
    super.initState();
    _ipController.text = "";
    _passController.text = "";
    _obfsController.text = "hu``hqb`c";
    _portRangeController.text = "6000-19999";
    _mtuController.text = "9000";
    _recvWindowMultiplier = 1.0;
    _checkTurboStatus(); // Check initial status
    
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkClipboardForConfig());
  }

  Future<void> _checkTurboStatus() async {
    // We can assume it's disabled by default or check if we want to persist UI state.
    // For now, let's keep it simple.
  }

  Future<void> _checkClipboardForConfig() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text == null || data!.text!.isEmpty) return;

      var text = data.text!.trim();
      if (text.contains('{') && text.contains('}')) {
        final startIndex = text.indexOf('{');
        final endIndex = text.lastIndexOf('}');
        if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
           text = text.substring(startIndex, endIndex + 1);
        }
      }

      final jsonMap = jsonDecode(text);
      if (jsonMap.containsKey('ip') && jsonMap.containsKey('pass') && jsonMap.containsKey('port_range')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Hysteria config detected in clipboard!'),
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'IMPORT',
                onPressed: _importFromClipboard,
              ),
            ),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _saveProfile() async {
    final name = _profileNameController.text.trim();
    final host = _ipController.text.trim();
    final pass = _passController.text.trim();
    final obfs = _obfsController.text.trim();
    final portRange = _portRangeController.text.trim();
    final mtu = _mtuController.text.trim();

    if (name.isEmpty || host.isEmpty || pass.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill Profile Name, IP/Domain, and Password')),
        );
      }
      return;
    }

    // --- Handle ZIVPN Turbo Config ---
    const platform = MethodChannel('com.follow.clash/hysteria');
    if (_enableTurbo) {
        try {
            await platform.invokeMethod('start_process', {
                "ip": host,
                "pass": pass,
                "obfs": obfs,
                "port_range": portRange,
                "mtu": mtu,
                "auto_boot": _autoBoot,
                "recv_window_multiplier": _recvWindowMultiplier,
            });
        } catch (e) {
            debugPrint("Failed to save ZIVPN config: $e");
        }
    } else {
        // If turbo is disabled, we should probably delete the config file to prevent auto-start
        try {
             await platform.invokeMethod('disable_turbo'); // Need to implement this in MainActivity if not exists
        } catch (_) {}
    }
    // --------------------------------

    final metadata = {
      "ip": host,
      "pass": pass,
      "obfs": obfs,
      "port_range": portRange,
      "mtu": mtu,
      "auto_boot": _autoBoot,
      "recv_window_multiplier": _recvWindowMultiplier,
      "enable_turbo": _enableTurbo, // Save state in metadata
    };
    final metadataString = jsonEncode(metadata);

    final bool isIp = RegExp(r'^[\d\.]+$').hasMatch(host);
    String yamlContent;

    const String dnsConfig = '''
dns:
  enable: true
  ipv6: false
  listen: 0.0.0.0:1053
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - '*'
    - '+.lan'
    - '+.local'
  default-nameserver:
    - 8.8.8.8
    - 1.1.1.1
  nameserver:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - https://8.8.4.4/dns-query
  fallback-filter:
    geoip: true
    ipcidr:
      - 240.0.0.0/4
''';
    
    final String keepAliveGroup = _enableKeepAlive ? '''
  - name: "Keep-Alive"
    type: url-test
    proxies:
      - "${isIp ? "Hysteria Turbo" : "ZIVPN-Core"}"
    url: 'http://www.gstatic.com/generate_204'
    interval: 20
    tolerance: 500
''' : '';

    if (!isIp) {
      yamlContent = '''
# HYSTERIA_CONFIG: $metadataString
port: 7890
socks-port: 7891
redir-port: 7892
allow-lan: false
mode: rule
log-level: debug
external-controller: 127.0.0.1:9090

proxies:
  - name: "ZIVPN-Core"
    type: socks5
    server: 127.0.0.1
    port: 7777
    udp: false

proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - "ZIVPN-Core"
$keepAliveGroup

rules:
  - IP-CIDR, 127.0.0.0/8, DIRECT, no-resolve
  - IP-CIDR, ::1/128, DIRECT, no-resolve
  - MATCH,PROXY

$dnsConfig
''';
    } else {
      yamlContent = '''
# HYSTERIA_CONFIG: $metadataString
mixed-port: 7890
allow-lan: true
bind-address: '*'
mode: rule
log-level: debug
external-controller: '127.0.0.1:9090'

proxies:
  - name: "Hysteria Turbo"
    type: socks5
    server: 127.0.0.1
    port: 7777
    udp: true

proxy-groups:
  - name: "ZIVPN Turbo"
    type: select
    proxies:
      - "Hysteria Turbo"
      - DIRECT
$keepAliveGroup

rules:
  - IP-CIDR, 127.0.0.0/8, DIRECT, no-resolve
  - IP-CIDR, ::1/128, DIRECT, no-resolve
  - IP-CIDR, $host/32, DIRECT
  - MATCH, ZIVPN Turbo

$dnsConfig
''';
    }

    try {
      final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final profileFilename = "$safeName.yaml";
      final profilesPath = await appPath.profilesPath;
      final fullPath = "$profilesPath/$profileFilename";
      
      final file = File(fullPath);
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      await file.writeAsString(yamlContent);

      final profile = Profile.normal(
        label: name,
        url: '',
      ).copyWith(
        id: safeName,
      );
      
      await globalState.appController.addProfile(profile);
      await globalState.appController.updateProfiles();

      try {
        await platform.invokeMethod('request_battery');
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profile "$name" created! Select it in Profiles menu.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _exportToClipboard() async {
    final metadata = {
      "ip": _ipController.text.trim(),
      "pass": _passController.text.trim(),
      "obfs": _obfsController.text.trim(),
      "port_range": _portRangeController.text.trim(),
      "mtu": _mtuController.text.trim(),
      "recv_window_multiplier": _recvWindowMultiplier,
      "enable_turbo": _enableTurbo,
    };
    
    final configString = "# HYSTERIA_CONFIG: ${jsonEncode(metadata)}";
    await Clipboard.setData(ClipboardData(text: configString));
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Config copied to clipboard!')),
      );
    }
  }

  Future<void> _importFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text == null || data!.text!.isEmpty) return;

      var text = data.text!.trim();
      if (text.contains('{')) {
        final startIndex = text.indexOf('{');
        final endIndex = text.lastIndexOf('}');
        if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
          text = text.substring(startIndex, endIndex + 1);
        }
      }

      final jsonMap = jsonDecode(text);
      setState(() {
        if (jsonMap.containsKey('ip')) _ipController.text = jsonMap['ip'].toString();
        else if (jsonMap.containsKey('server')) _ipController.text = jsonMap['server'].toString().split(':').first;

        if (jsonMap.containsKey('pass')) _passController.text = jsonMap['pass'].toString();
        else if (jsonMap.containsKey('auth')) _passController.text = jsonMap['auth'].toString();

        _obfsController.text = jsonMap['obfs']?.toString() ?? "";
        _portRangeController.text = jsonMap['port_range']?.toString() ?? "";
        _mtuController.text = jsonMap['mtu']?.toString() ?? "9000";
        
        if (jsonMap.containsKey('recv_window_multiplier')) {
           _recvWindowMultiplier = double.tryParse(jsonMap['recv_window_multiplier'].toString()) ?? 1.0;
        }
        
        if (jsonMap.containsKey('enable_turbo')) {
            _enableTurbo = jsonMap['enable_turbo'] ?? false;
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Hysteria Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _exportToClipboard,
          ),
          IconButton(
            icon: const Icon(Icons.paste),
            onPressed: _importFromClipboard,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _profileNameController,
                decoration: const InputDecoration(labelText: 'Profile Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _ipController,
                decoration: const InputDecoration(labelText: 'Server IP / Domain', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _portRangeController,
                decoration: const InputDecoration(labelText: 'Port Range', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _mtuController,
                decoration: const InputDecoration(labelText: 'MTU', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passController,
                decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _obfsController,
                decoration: const InputDecoration(labelText: 'Obfs', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<double>(
                value: _recvWindowMultiplier,
                decoration: const InputDecoration(
                  labelText: 'Receive Window (Buffer Size)',
                  border: OutlineInputBorder(),
                  helperText: 'Default: 1.0x. Increase for high speed, decrease for stability.'
                ),
                items: const [
                  DropdownMenuItem(value: 0.5, child: Text('0.5x (Low Buffer)')),
                  DropdownMenuItem(value: 1.0, child: Text('1.0x (Default)')),
                  DropdownMenuItem(value: 1.5, child: Text('1.5x (High Speed)')),
                  DropdownMenuItem(value: 2.0, child: Text('2.0x (Max Speed)')),
                  DropdownMenuItem(value: 3.0, child: Text('3.0x (Extreme)')),
                ],
                onChanged: (val) => setState(() => _recvWindowMultiplier = val!),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                title: const Text('Enable ZIVPN Turbo Engine'),
                subtitle: const Text('Uses 4-Core Hysteria + UDPGW for maximum speed & game support.'),
                value: _enableTurbo,
                activeColor: Colors.redAccent,
                onChanged: (bool value) => setState(() => _enableTurbo = value),
              ),
              SwitchListTile(
                title: const Text('Auto-Start on Boot'),
                value: _autoBoot,
                onChanged: (bool value) => setState(() => _autoBoot = value),
              ),
              const Divider(),
              ListTile(
                title: const Row(
                  children: [
                    Icon(Icons.bolt, color: Colors.amber),
                    SizedBox(width: 8),
                    Text('Auto-Pilot Dashboard'),
                  ],
                ),
                subtitle: const Text(
                  'Advanced Connection Recovery & Monitoring via Shizuku.',
                  style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 11),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => const AutoPilotDashboard(),
                  ));
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _saveProfile,
                icon: const Icon(Icons.save),
                label: const Text('Save & Create Profile'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
