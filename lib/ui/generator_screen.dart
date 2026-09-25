import 'package:flutter/material.dart';

import '../state/vault_controller.dart';
import 'service_form_screen.dart';
import 'widgets/common.dart';

/// The same generator used inside the add/edit form, reachable on its own for
/// when someone just needs a password to paste somewhere else.
class GeneratorScreen extends StatelessWidget {
  const GeneratorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generate a password')),
      body: GeneratorSheet(
        showGrabber: false,
        primaryLabel: 'Copy',
        onPrimary: (value) async {
          await vault.copySecret(value);
          if (context.mounted) {
            showToast(context, 'Copied. Clipboard clears in 15s.');
          }
        },
      ),
    );
  }
}
