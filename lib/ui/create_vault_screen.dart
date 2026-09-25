import 'package:flutter/material.dart';

import '../core/password_generator.dart';
import '../state/vault_controller.dart';
import 'theme.dart';
import 'widgets/common.dart';

class CreateVaultScreen extends StatefulWidget {
  const CreateVaultScreen({super.key});

  @override
  State<CreateVaultScreen> createState() => _CreateVaultScreenState();
}

class _CreateVaultScreenState extends State<CreateVaultScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  /// Generated once: a suggestion that reshuffles on every keystroke is noise.
  final String _suggestion = PasswordGenerator.memorable(wordCount: 4);

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final pw = _password.text;
    if (pw.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (pw != _confirm.text) {
      setState(() => _error = 'The two entries do not match.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await vault.createVault(pw);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const VokulWordmark(),
              const SizedBox(height: 28),
              Text(
                'Choose a master password',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              const Text(
                'It encrypts everything in this vault and is never stored '
                'anywhere. If you lose it, the vault cannot be opened — not by '
                'you, not by anyone.',
                style: TextStyle(color: VokulColors.textMuted, height: 1.5),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _password,
                obscureText: _obscure,
                autofocus: true,
                style: monoStyle,
                decoration: InputDecoration(
                  labelText: 'Master password',
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              StrengthMeter(password: _password.text),
              const SizedBox(height: 18),
              TextField(
                controller: _confirm,
                obscureText: _obscure,
                style: monoStyle,
                decoration:
                    const InputDecoration(labelText: 'Type it again'),
                onSubmitted: (_) => _create(),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: const Icon(Icons.auto_awesome_outlined,
                      color: VokulColors.violet),
                  title: Text(_suggestion, style: monoStyle),
                  subtitle: const Text('A passphrase you can remember',
                      style: TextStyle(fontSize: 12)),
                  onTap: () {
                    _password.text = _suggestion;
                    _confirm.text = _suggestion;
                    setState(() {});
                  },
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 18),
                Text(_error!,
                    style: const TextStyle(color: VokulColors.danger)),
              ],
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _busy ? null : _create,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Create vault'),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          try {
                            await vault.importVaultFile();
                          } catch (e) {
                            if (context.mounted) showToast(context, '$e');
                          }
                        },
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Import a vault.vk from the desktop app'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
