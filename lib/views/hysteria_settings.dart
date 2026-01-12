import 'dart:convert';
import 'dart:io';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/common/path.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  bool _autoReset = false;
  double _resetTimeout = 15.0;
  
  @override
  void initState() {
    super.initState();
    _ipController.text = "";
    _passController.text = "";
    _obfsController.text = "hu``hqb`c";
    _portRangeController.text = "6000-19999";
    _mtuController.text = "9000";

    WidgetsBinding.instance.addPostFrameCallback((_) => _checkClipboardForConfig());
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
      // Simple check for key indicators of a hysteria config
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
    } catch (_) {
      // Ignore invalid JSON or clipboard errors quietly
    }
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

    // 1. Prepare Metadata JSON
    final metadata = {
      "ip": host,
      "pass": pass,
      "obfs": obfs,
      "port_range": portRange,
      "mtu": mtu,
      "auto_boot": _autoBoot,
      "auto_reset": _autoReset,
      "reset_timeout": _resetTimeout.toInt()
    };
    final metadataString = jsonEncode(metadata);

    // 2. Generate YAML Config (Smart Mode)
    final bool isIp = RegExp(r'^[\d\.]+$').hasMatch(host);
    String yamlContent;

    // 3. DNS Configuration (Universal Full DoH Anti-Leak)
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
    
    // Keep-Alive Group Block
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
      // TCP Optimized for Domain (Zero Quota)
      yamlContent = '''
# HYSTERIA_CONFIG: $metadataString
# Clash Config (TCP Optimized for $name)
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
      // Standard UDP for IP (With Full DoH)
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
      // 3. Save File to Profiles Directory
      final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final profileFilename = "$safeName.yaml";
      final profilesPath = await appPath.profilesPath;
      final fullPath = "$profilesPath/$profileFilename";
      
      final file = File(fullPath);
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      await file.writeAsString(yamlContent);

      // 4. Register Profile in App Logic
      final profile = Profile.normal(
        label: name,
        url: '', // Empty URL indicates a local file profile
      ).copyWith(
        id: safeName,
      );
      
      await globalState.appController.addProfile(profile);
      await globalState.appController.updateProfiles();

      // Auto-Request Battery Optimization Ignore
      try {
        const platform = MethodChannel('com.follow.clash/hysteria');
        await platform.invokeMethod('request_battery');
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profile "$name" created! Select it in Profiles menu.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Save profile error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _exportToClipboard() async {
    final metadata = {
      "ip": _ipController.text.trim(),
      "pass": _passController.text.trim(),
      "obfs": _obfsController.text.trim(),
      "port_range": _portRangeController.text.trim(),
      "mtu": _mtuController.text.trim()
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
      if (data?.text == null || data!.text!.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clipboard is empty')));
        return;
      }

      var text = data.text!.trim();
      
      // Handle potential prefixes like "# HYSTERIA_CONFIG: "
      if (text.contains('{')) {
        final startIndex = text.indexOf('{');
        final endIndex = text.lastIndexOf('}');
        if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
          text = text.substring(startIndex, endIndex + 1);
        }
      }

      Map<String, dynamic> jsonMap;
      
      try {
        jsonMap = jsonDecode(text);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid JSON format')));
        return;
      }

      // Strict Validation
      bool hasIp = jsonMap.containsKey('ip') || jsonMap.containsKey('server');
      bool hasPass = jsonMap.containsKey('pass') || jsonMap.containsKey('auth') || jsonMap.containsKey('password');
      bool hasObfs = jsonMap.containsKey('obfs');
      bool hasRange = jsonMap.containsKey('port_range');
      bool hasMtu = jsonMap.containsKey('mtu');

      List<String> missing = [];
      if (!hasIp) missing.add('IP/Server');
      if (!hasPass) missing.add('Password');
      if (!hasObfs) missing.add('Obfs');
      if (!hasRange) missing.add('Port Range');
      if (!hasMtu) missing.add('MTU');

      if (missing.isNotEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Missing fields: ${missing.join(", ")}')));
        return;
      }

      setState(() {
        // IP / Server
        if (jsonMap.containsKey('ip')) _ipController.text = jsonMap['ip'].toString();
        else if (jsonMap.containsKey('server')) _ipController.text = jsonMap['server'].toString().split(':').first;

        // Password / Auth
        if (jsonMap.containsKey('pass')) _passController.text = jsonMap['pass'].toString();
        else if (jsonMap.containsKey('auth')) _passController.text = jsonMap['auth'].toString();
        else if (jsonMap.containsKey('password')) _passController.text = jsonMap['password'].toString();

        // Obfs
        _obfsController.text = jsonMap['obfs'].toString();

        // Port Range
        _portRangeController.text = jsonMap['port_range'].toString();

        // MTU
        _mtuController.text = jsonMap['mtu'].toString();
        
        // Auto Reset
        if (jsonMap.containsKey('auto_reset')) {
             _autoReset = jsonMap['auto_reset'] == true;
        }
        if (jsonMap.containsKey('reset_timeout')) {
             _resetTimeout = double.tryParse(jsonMap['reset_timeout'].toString()) ?? 15.0;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Config imported successfully!')));
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Hysteria Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy Config to Clipboard',
            onPressed: _exportToClipboard,
          ),
          IconButton(
            icon: const Icon(Icons.paste),
            tooltip: 'Import from Clipboard (JSON)',
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
                decoration: const InputDecoration(
                    labelText: 'Profile Name (e.g. Indo-Game)', 
                    border: OutlineInputBorder(),
                    helperText: "This name will appear in Profiles list"
                ),
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
              SwitchListTile(
                title: const Text('Auto-Start on Boot'),
                subtitle: const Text('Automatically start VPN when device restarts.'),
                value: _autoBoot,
                onChanged: (bool value) {
                  setState(() {
                    _autoBoot = value;
                  });
                },
              ),
              const Divider(),
              SwitchListTile(
                title: const Row(
                  children: [
                    Icon(Icons.bolt, color: Colors.amber),
                    SizedBox(width: 8),
                    Text('Auto-Reset Network'),
                  ],
                ),
                subtitle: const Text(
                  'REQUIRES ROOT. Automatically toggles Airplane Mode if internet dies (Fixes UDP Jammed).',
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11),
                ),
                value: _autoReset,
                onChanged: (bool value) {
                  setState(() {
                    _autoReset = value;
                  });
                },
              ),
              if (_autoReset) ...[
                 Padding(
                   padding: const EdgeInsets.symmetric(horizontal: 16),
                   child: Row(
                     children: [
                       const Text("Timeout:"),
                       Expanded(
                         child: Slider(
                           value: _resetTimeout,
                           min: 5,
                           max: 60,
                           divisions: 11,
                           label: "${_resetTimeout.toInt()}s",
                           onChanged: (double value) {
                             setState(() {
                               _resetTimeout = value;
                             });
                           },
                         ),
                       ),
                       Text("${_resetTimeout.toInt()}s"),
                     ],
                   ),
                 ),
                 const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                        "If connection is dead for this long, airplane mode will be toggled automatically.",
                        style: TextStyle(fontSize: 12, color: Colors.grey)
                    ),
                 ),
              ],
              const Divider(),
              SwitchListTile(
                title: const Text('Enable Keep-Alive Mode'),
                subtitle: const Text('Prevents NAT timeout (NAT Hole). Disable if unstable.'),
                value: _enableKeepAlive,
                onChanged: (bool value) {
                  setState(() {
                    _enableKeepAlive = value;
                  });
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _saveProfile,
                icon: const Icon(Icons.save),
                label: const Text('Save & Create Profile', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
