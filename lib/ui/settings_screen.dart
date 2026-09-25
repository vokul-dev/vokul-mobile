import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../state/vault_controller.dart';
import 'theme.dart';
import 'widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricsSupported = false;
  bool _biometricsOn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final supported = await vault.biometricsAvailable();
    final on = await vault.biometricUnlockEnabled();
    if (mounted) {
      setState(() {
        _biometricsSupported = supported;
        _biometricsOn = on;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Section(
            title: 'Locking',
            children: [
              SwitchListTile(
                value: _biometricsOn,
                activeColor: VokulColors.violet,
                title: const Text('Unlock with biometrics'),
                subtitle: Text(
                  _biometricsSupported
                      ? 'Keeps your master password in this phone\'s secure '
                          'hardware so you can skip typing it'
                      : 'This device has no biometric hardware set up',
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
                onChanged: _biometricsSupported ? _toggleBiometrics : null,
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Lock after'),
                subtitle: const Text(
                  'Time in the background before the vault closes itself',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: DropdownButton<int>(
                  value: vault.autoLockAfter.inSeconds,
                  underline: const SizedBox.shrink(),
                  dropdownColor: VokulColors.surfaceHigh,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Immediately')),
                    DropdownMenuItem(value: 30, child: Text('30 seconds')),
                    DropdownMenuItem(value: 120, child: Text('2 minutes')),
                    DropdownMenuItem(value: 600, child: Text('10 minutes')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() =>
                        vault.autoLockAfter = Duration(seconds: value));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _Section(
            title: 'Vault file',
            children: [
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Export vault.vk'),
                subtitle: const Text(
                  'Sends the encrypted file as-is. Useless without your master '
                  'password, and the CLI opens it directly.',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
                onTap: () async {
                  final file = await vault.exportVaultFile();
                  await Share.shareXFiles(
                    [XFile(file.path)],
                    subject: 'Vokul vault',
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Import vault.vk'),
                subtitle: const Text(
                  'Replaces the vault on this device. The current one is backed '
                  'up first.',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
                onTap: () async {
                  try {
                    await vault.importVaultFile();
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) showToast(context, '$e');
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          _Section(
            title: 'Danger zone',
            children: [
              ListTile(
                leading:
                    const Icon(Icons.delete_forever, color: VokulColors.danger),
                title: const Text('Destroy this vault',
                    style: TextStyle(color: VokulColors.danger)),
                subtitle: const Text(
                  'Deletes the vault and every backup on this device',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () => _confirmDestruct(context),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const Text(
            'Vokul stores everything in one AES-256-GCM file on this device, '
            'with the key derived from your master password using Argon2id. '
            'Nothing is sent anywhere.',
            style: TextStyle(
                color: VokulColors.textMuted, fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleBiometrics(bool value) async {
    if (!value) {
      await vault.disableBiometricUnlock();
      setState(() => _biometricsOn = false);
      return;
    }

    final password = await _askMasterPassword();
    if (password == null) return;
    try {
      await vault.enableBiometricUnlock(password);
      setState(() => _biometricsOn = true);
    } catch (e) {
      if (mounted) showToast(context, '$e');
    }
  }

  /// Re-asks for the master password rather than caching it in memory for this
  /// one feature.
  Future<String?> _askMasterPassword() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: VokulColors.surfaceHigh,
        title: const Text('Confirm your master password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          style: monoStyle,
          decoration: const InputDecoration(labelText: 'Master password'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDestruct(BuildContext context) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: VokulColors.surfaceHigh,
        title: const Text('Destroy this vault?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Every stored password, 2FA secret and backup on this device is '
              'erased. Export the file first if you might want it back.',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Type DESTROY'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: VokulColors.danger),
            onPressed: () =>
                Navigator.pop(context, controller.text.trim() == 'DESTROY'),
            child: const Text('Destroy'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await vault.destruct();
    if (context.mounted) Navigator.pop(context);
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(title,
              style: const TextStyle(
                  color: VokulColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
        Card(child: Column(children: children)),
      ],
    );
  }
}
