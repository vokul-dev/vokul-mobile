import 'package:flutter/material.dart';

import '../state/vault_controller.dart';
import 'generator_screen.dart';
import 'service_form_screen.dart';
import 'service_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'widgets/common.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vault,
      builder: (context, _) {
        final services = vault.services;
        final total = vault.manager.listServices().length;

        return Scaffold(
          appBar: AppBar(
            title: const VokulWordmark(size: 22),
            actions: [
              IconButton(
                tooltip: 'Password generator',
                icon: const Icon(Icons.casino_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const GeneratorScreen()),
                ),
              ),
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
              IconButton(
                tooltip: 'Lock now',
                icon: const Icon(Icons.lock_outline),
                onPressed: vault.lock,
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ServiceFormScreen()),
            ),
            backgroundColor: VokulColors.violet,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('Add service'),
          ),
          body: Column(
            children: [
              if (vault.notice != null)
                _Notice(
                    message: vault.notice!, onDismiss: vault.dismissNotice),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TextField(
                  controller: _search,
                  onChanged: vault.search,
                  decoration: InputDecoration(
                    hintText: total == 0
                        ? 'Search'
                        : 'Search $total ${total == 1 ? 'service' : 'services'}',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: vault.query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _search.clear();
                              vault.search('');
                            },
                          ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              Expanded(
                child: services.isEmpty
                    ? _EmptyState(searching: vault.query.isNotEmpty)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        itemCount: services.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, i) =>
                            _ServiceTile(service: services[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final String service;
  const _ServiceTile({required this.service});

  @override
  Widget build(BuildContext context) {
    final record = vault.record(service);
    final initial =
        service.trim().isEmpty ? '?' : service.trim()[0].toUpperCase();

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: VokulColors.violetDim.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(11),
          ),
          alignment: Alignment.center,
          child: Text(initial,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: VokulColors.text)),
        ),
        title: Text(service,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(
          [
            if (record?.hasTotp ?? false) '2FA',
            if ((record?.history.length ?? 0) > 0)
              '${record!.history.length} past ${record.history.length == 1 ? 'password' : 'passwords'}',
          ].join(' · '),
          style: const TextStyle(fontSize: 12, color: VokulColors.textMuted),
        ),
        trailing: IconButton(
          tooltip: 'Copy password',
          icon: const Icon(Icons.copy_rounded, size: 20),
          onPressed: () async {
            final password = record?.current;
            if (password == null) {
              showToast(context, 'No password stored for $service yet.');
              return;
            }
            await vault.copySecret(password);
            if (context.mounted) {
              showToast(context, 'Copied. Clipboard clears in 15s.');
            }
          },
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ServiceScreen(service: service)),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool searching;
  const _EmptyState({required this.searching});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? Icons.search_off : Icons.inventory_2_outlined,
              size: 44,
              color: VokulColors.line,
            ),
            const SizedBox(height: 16),
            Text(
              searching
                  ? 'Nothing matches that search.'
                  : 'Your vault is empty. Add the first service and it will be '
                      'encrypted on this device straight away.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: VokulColors.textMuted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _Notice({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: VokulColors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VokulColors.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.healing_outlined,
              size: 20, color: VokulColors.amber),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message,
                style: const TextStyle(height: 1.4, fontSize: 13)),
          ),
          IconButton(
              icon: const Icon(Icons.close, size: 18), onPressed: onDismiss),
        ],
      ),
    );
  }
}
