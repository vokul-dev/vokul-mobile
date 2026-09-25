import 'package:flutter/material.dart';

import '../core/password_generator.dart';
import '../core/totp.dart';
import '../state/vault_controller.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// Add a service, or edit one when [service] is given. Pops with the (possibly
/// renamed) service name so the detail screen can follow it.
class ServiceFormScreen extends StatefulWidget {
  final String? service;
  const ServiceFormScreen({super.key, this.service});

  @override
  State<ServiceFormScreen> createState() => _ServiceFormScreenState();
}

class _ServiceFormScreenState extends State<ServiceFormScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.service ?? '');
  late final TextEditingController _password = TextEditingController(
    text: widget.service == null
        ? ''
        : (vault.record(widget.service!)?.current ?? ''),
  );
  late final TextEditingController _totp = TextEditingController(
    text: widget.service == null
        ? ''
        : (vault.record(widget.service!)?.totp ?? ''),
  );

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.service != null;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _totp.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final totp = _totp.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Give the service a name.');
      return;
    }
    if (!_isEdit && vault.record(name) != null) {
      setState(() => _error = '$name is already in the vault.');
      return;
    }
    if (totp.isNotEmpty && !Totp.isValidSecret(totp)) {
      setState(() => _error =
          'That 2FA secret is not valid base32. Letters A–Z and digits 2–7 only.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await vault.saveService(
        service: name,
        originalService: widget.service,
        password: _password.text.isEmpty ? null : _password.text,
        totpSecret: totp.isEmpty ? null : totp,
        removeTotp: _isEdit && totp.isEmpty,
      );
      if (mounted) Navigator.pop(context, name);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openGenerator() async {
    final generated = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: VokulColors.surfaceHigh,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const GeneratorSheet(),
    );
    if (generated != null) {
      setState(() => _password.text = generated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit ${widget.service}' : 'Add service')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _name,
            autofocus: !_isEdit,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(
              labelText: 'Service',
              hintText: 'github, mybank, work-vpn',
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _password,
            obscureText: _obscure,
            style: monoStyle,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  IconButton(
                    tooltip: 'Generate',
                    icon: const Icon(Icons.casino_outlined),
                    onPressed: _openGenerator,
                  ),
                ],
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          StrengthMeter(password: _password.text),
          if (_isEdit) ...[
            const SizedBox(height: 10),
            const Text(
              'Changing this keeps the old password in history, up to three '
              'back.',
              style: TextStyle(
                  color: VokulColors.textMuted, fontSize: 12, height: 1.5),
            ),
          ],
          const SizedBox(height: 22),
          TextField(
            controller: _totp,
            style: monoStyle,
            decoration: const InputDecoration(
              labelText: 'Two-factor secret (optional)',
              hintText: 'JBSWY3DPEHPK3PXP',
              helperText: 'The base32 key a site shows next to its QR code',
              helperStyle: TextStyle(color: VokulColors.textMuted),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 18),
            Text(_error!, style: const TextStyle(color: VokulColors.danger)),
          ],
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(_isEdit ? 'Save changes' : 'Add to vault'),
          ),
        ],
      ),
    );
  }
}

/// Generator as a sheet, so choosing a password never leaves the form. It also
/// serves as the body of the standalone generator screen, where the primary
/// action copies instead of returning a value.
class GeneratorSheet extends StatefulWidget {
  final bool showGrabber;
  final String primaryLabel;
  final Future<void> Function(String value)? onPrimary;

  const GeneratorSheet({
    super.key,
    this.showGrabber = true,
    this.primaryLabel = 'Use this',
    this.onPrimary,
  });

  @override
  State<GeneratorSheet> createState() => _GeneratorSheetState();
}

class _GeneratorSheetState extends State<GeneratorSheet> {
  double _length = 20;
  bool _symbols = true;
  bool _digits = true;
  bool _memorable = false;
  String _value = PasswordGenerator.random();

  void _roll() {
    setState(() {
      _value = _memorable
          ? PasswordGenerator.memorable()
          : PasswordGenerator.random(
              length: _length.round(),
              symbols: _symbols,
              digits: _digits,
            );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showGrabber) ...[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: VokulColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          SelectableText(
            _value,
            style: monoStyle.copyWith(fontSize: 20, height: 1.4),
          ),
          const SizedBox(height: 14),
          StrengthMeter(password: _value),
          const SizedBox(height: 18),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _memorable,
            activeThumbColor: VokulColors.violet,
            title: const Text('Words instead of characters'),
            subtitle: const Text('Easier to type on a phone keyboard',
                style: TextStyle(fontSize: 12)),
            onChanged: (v) {
              setState(() => _memorable = v);
              _roll();
            },
          ),
          if (!_memorable) ...[
            Row(
              children: [
                SizedBox(
                  width: 74,
                  child: Text('${_length.round()} chars',
                      style: const TextStyle(
                          color: VokulColors.textMuted, fontSize: 13)),
                ),
                Expanded(
                  child: Slider(
                    value: _length,
                    min: 8,
                    max: 64,
                    divisions: 56,
                    activeColor: VokulColors.violet,
                    onChanged: (v) => setState(() => _length = v),
                    onChangeEnd: (_) => _roll(),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 10,
              children: [
                FilterChip(
                  label: const Text('Digits'),
                  selected: _digits,
                  onSelected: (v) {
                    setState(() => _digits = v);
                    _roll();
                  },
                ),
                FilterChip(
                  label: const Text('Symbols'),
                  selected: _symbols,
                  onSelected: (v) {
                    setState(() => _symbols = v);
                    _roll();
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _roll,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Again'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44)),
                  onPressed: () async {
                    final handler = widget.onPrimary;
                    if (handler != null) {
                      await handler(_value);
                    } else {
                      Navigator.pop(context, _value);
                    }
                  },
                  child: Text(widget.primaryLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
