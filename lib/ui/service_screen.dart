import 'package:flutter/material.dart';

import '../state/vault_controller.dart';
import 'service_form_screen.dart';
import 'theme.dart';
import 'widgets/common.dart';

class ServiceScreen extends StatefulWidget {
  final String service;
  const ServiceScreen({super.key, required this.service});

  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  late String _service = widget.service;
  bool _revealed = false;
  bool _historyOpen = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vault,
      builder: (context, _) {
        final record = vault.record(_service);
        if (record == null) {
          // Deleted from underneath us (e.g. an import replaced the vault).
          return const Scaffold(body: SizedBox.shrink());
        }
        final password = record.current;

        return Scaffold(
          appBar: AppBar(
            title: Text(_service),
            actions: [
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final renamed = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ServiceFormScreen(service: _service),
                    ),
                  );
                  if (renamed != null && mounted) {
                    setState(() => _service = renamed);
                  }
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Password',
                          style: TextStyle(
                              color: VokulColors.textMuted, fontSize: 13)),
                      const SizedBox(height: 10),
                      SelectableText(
                        password == null
                            ? 'Not set'
                            : (_revealed ? password : '•' * password.length),
                        style: monoStyle.copyWith(
                          fontSize: 19,
                          height: 1.3,
                          color: password == null
                              ? VokulColors.textMuted
                              : VokulColors.text,
                        ),
                      ),
                      if (password != null) ...[
                        const SizedBox(height: 14),
                        StrengthMeter(password: password),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    setState(() => _revealed = !_revealed),
                                icon: Icon(
                                    _revealed
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 18),
                                label: Text(_revealed ? 'Hide' : 'Reveal'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(44),
                                ),
                                onPressed: () async {
                                  await vault.copySecret(password);
                                  if (context.mounted) {
                                    showToast(context,
                                        'Copied. Clipboard clears in 15s.');
                                  }
                                },
                                icon: const Icon(Icons.copy_rounded, size: 18),
                                label: const Text('Copy'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (record.hasTotp) ...[
                const SizedBox(height: 12),
                TotpTile(
                  secret: record.totp!,
                  onCopy: (code) async {
                    await vault.copySecret(code);
                    if (context.mounted) {
                      showToast(context, 'Code copied. Clears in 15s.');
                    }
                  },
                ),
              ],
              if (record.history.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        title: Text(
                            '${record.history.length} previous '
                            '${record.history.length == 1 ? 'password' : 'passwords'}'),
                        subtitle: const Text(
                          'Kept in case a change did not take effect',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: Icon(_historyOpen
                            ? Icons.expand_less
                            : Icons.expand_more),
                        onTap: () =>
                            setState(() => _historyOpen = !_historyOpen),
                      ),
                      if (_historyOpen)
                        for (var i = 0; i < record.history.length; i++)
                          Column(
                            children: [
                              const Divider(height: 1),
                              ListTile(
                                dense: true,
                                title: Text(record.history[i],
                                    style: monoStyle.copyWith(fontSize: 14)),
                                subtitle: Text(
                                  i == 0
                                      ? 'Replaced most recently'
                                      : '${i + 1} changes ago',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: IconButton(
                                  icon:
                                      const Icon(Icons.copy_rounded, size: 18),
                                  onPressed: () async {
                                    await vault.copySecret(record.history[i]);
                                    if (context.mounted) {
                                      showToast(context,
                                          'Copied. Clipboard clears in 15s.');
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: VokulColors.danger,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => _confirmDelete(context),
                icon: const Icon(Icons.delete_outline, size: 20),
                label: Text('Delete $_service'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: VokulColors.surfaceHigh,
        title: Text('Delete $_service?'),
        content: const Text(
          'The password and any 2FA secret for this service are removed from '
          'the vault. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: VokulColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await vault.deleteService(_service);
    if (context.mounted) {
      Navigator.pop(context);
      showToast(context, 'Deleted $_service.');
    }
  }
}
