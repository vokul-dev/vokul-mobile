import 'dart:async';

import 'package:flutter/material.dart';

import '../core/exceptions.dart';
import '../state/vault_controller.dart';
import 'theme.dart';
import 'widgets/common.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  Duration _cooldown = Duration.zero;
  Timer? _cooldownTimer;
  bool _biometricsReady = false;

  @override
  void initState() {
    super.initState();
    _refreshCooldown();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final ready = await vault.biometricsAvailable() &&
        await vault.biometricUnlockEnabled();
    if (mounted) setState(() => _biometricsReady = ready);
  }

  Future<void> _refreshCooldown() async {
    final left = await vault.throttle.cooldownRemaining();
    if (!mounted) return;
    setState(() => _cooldown = left);
    _cooldownTimer?.cancel();
    if (left > Duration.zero) {
      _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() {
          _cooldown = _cooldown - const Duration(seconds: 1);
          if (_cooldown <= Duration.zero) {
            _cooldown = Duration.zero;
            t.cancel();
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty || _cooldown > Duration.zero) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await vault.unlock(_password.text);
      _password.clear();
    } on ThrottlingError catch (e) {
      setState(() => _error = e.message);
      await _refreshCooldown();
    } on VaultError catch (e) {
      setState(() => _error = e.message);
      await _refreshCooldown();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _biometricUnlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await vault.unlockWithBiometrics();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _cooldown > Duration.zero;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const VokulWordmark(size: 40),
                const SizedBox(height: 12),
                const Text(
                  'Everything stays on this device.',
                  style: TextStyle(color: VokulColors.textMuted),
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  autofocus: !_biometricsReady,
                  enabled: !locked && !_busy,
                  style: monoStyle,
                  decoration: InputDecoration(
                    labelText: 'Master password',
                    prefixIcon: const Icon(Icons.key_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!,
                      style: const TextStyle(color: VokulColors.danger)),
                ],
                if (locked) ...[
                  const SizedBox(height: 16),
                  _CooldownBanner(remaining: _cooldown),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: (_busy || locked) ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(locked
                          ? 'Locked for ${_cooldown.inSeconds}s'
                          : 'Unlock'),
                ),
                if (_biometricsReady && !locked) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton.icon(
                      onPressed: _busy ? null : _biometricUnlock,
                      icon: const Icon(Icons.fingerprint, size: 20),
                      label: const Text('Unlock with biometrics'),
                    ),
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Deriving your key with Argon2id. This takes a moment by '
                    'design — it is what makes guessing expensive.',
                    style: TextStyle(
                        color: VokulColors.textMuted,
                        fontSize: 12,
                        height: 1.5),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CooldownBanner extends StatelessWidget {
  final Duration remaining;
  const _CooldownBanner({required this.remaining});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VokulColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VokulColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined,
              color: VokulColors.danger, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Too many failed attempts. Entry reopens in '
              '${remaining.inSeconds}s, and the wait grows with each further '
              'miss.',
              style: const TextStyle(color: VokulColors.text, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
