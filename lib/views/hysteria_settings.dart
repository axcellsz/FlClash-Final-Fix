import 'dart:convert';
import 'dart:io';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/common/path.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fl_clash/services/auto_pilot_service.dart'; // Import Service

class HysteriaSettingsPage extends StatefulWidget {
  const HysteriaSettingsPage({super.key});

  @override
  State<HysteriaSettingsPage> createState() => _HysteriaSettingsPageState();
}

class _HysteriaSettingsPageState extends State<HysteriaSettingsPage> {
  final TextEditingController _profileNameController = TextEditingController();
  // ... (Other controllers remain same)
  bool _enableKeepAlive = true;
  bool _autoBoot = false;
  bool _autoReset = false;
  double _resetTimeout = 15.0;
  
  @override
  void initState() {
    super.initState();
    // ... (Init logic remains same)
    
    // Sync UI state with Service state
    _autoReset = AutoPilotService().isRunning; 
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkClipboardForConfig());
  }

  // ... (Methods _checkClipboardForConfig, _saveProfile, _exportToClipboard, _importFromClipboard remain same)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ... (AppBar and Body start remain same)
              const Divider(),
              SwitchListTile(
                title: const Row(
                  children: [
                    Icon(Icons.bolt, color: Colors.amber),
                    SizedBox(width: 8),
                    Text('Auto-Pilot (Shizuku)'),
                  ],
                ),
                subtitle: const Text(
                  'Auto-reset connection via Shizuku (No Root required).',
                  style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 11),
                ),
                value: _autoReset,
                onChanged: (bool value) async {
                  setState(() {
                    _autoReset = value;
                  });
                  
                  if (value) {
                    try {
                      await AutoPilotService().start();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text('Auto-Pilot Started (Shizuku Connected)')),
                        );
                      }
                    } catch (e) {
                      setState(() {
                        _autoReset = false;
                      });
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                           SnackBar(content: Text('Failed to start: $e. Is Shizuku running?')),
                        );
                      }
                    }
                  } else {
                    AutoPilotService().stop();
                  }
                },
              ),
              // ... (Rest of UI remains same)
