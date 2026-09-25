import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'state/vault_controller.dart';
import 'ui/create_vault_screen.dart';
import 'ui/theme.dart';
import 'ui/unlock_screen.dart';
import 'ui/vault_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const VokulApp());
}

class VokulApp extends StatefulWidget {
  const VokulApp({super.key});

  @override
  State<VokulApp> createState() => _VokulAppState();
}

class _VokulAppState extends State<VokulApp> with WidgetsBindingObserver {
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    vault.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Locks the vault once the app has been away longer than the chosen window.
  /// A password manager left open in the app switcher is the everyday risk,
  /// far more than an attacker with the phone in hand.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundedAt;
      _backgroundedAt = null;
      if (since != null &&
          vault.status == VaultStatus.unlocked &&
          DateTime.now().difference(since) >= vault.autoLockAfter) {
        vault.lock();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vokul',
      debugShowCheckedModeBanner: false,
      theme: buildVokulTheme(),
      home: ListenableBuilder(
        listenable: vault,
        builder: (context, _) {
          // Keyed so unlocking tears down the locked screen's state entirely
          // rather than leaving a stale password field behind it.
          return switch (vault.status) {
            VaultStatus.loading => const _Splash(),
            VaultStatus.empty =>
              const CreateVaultScreen(key: ValueKey('create')),
            VaultStatus.locked => const UnlockScreen(key: ValueKey('locked')),
            VaultStatus.unlocked =>
              const VaultScreen(key: ValueKey('unlocked')),
          };
        },
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: VokulColors.violet),
        ),
      ),
    );
  }
}
