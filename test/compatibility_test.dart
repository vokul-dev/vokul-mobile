import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vokul_mobile/core/totp.dart';
import 'package:vokul_mobile/core/vault_engine.dart';
import 'package:vokul_mobile/core/vault_manager.dart';

/// A real `vault.vk`, produced by the Python CLI (`VaultManager.save`) with the
/// master password below. If a refactor ever breaks interoperability, this test
/// fails before anyone's vault does.
const String cliVault = '''
{
  "salt": "Cccx493QMQL7LYiIkqagOA==",
  "nonce": "301KnixBVisdEyuB",
  "ciphertext": "wPtbntDrEtqOnrxY9GQ/BJjH3AtsgWSEZGtu1fLYfBrEt3AgL42fXZW8/VIdXQjPuPikdk4HJuESxzQeOXxDaA9NzCAMDvJf1Bf8EwOnWGIJNM7nFX/qZA=="
}
''';

const String masterPassword = 'correct horse battery staple';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vokul_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  File vaultPath() =>
      File('${tempDir.path}${Platform.pathSeparator}vault.vk');

  test('opens a vault written by the CLI', () async {
    final file = vaultPath();
    await file.writeAsString(cliVault);

    final manager = VaultManager(file: file, engine: VaultEngine());
    await manager.loadAndDecrypt(masterPassword);

    expect(manager.listServices(), ['github']);
    final record = manager.getSecret('github')!;
    expect(record.current, 'hunter3');
    expect(record.history, ['hunter2']); // rotation kept the old one
    expect(record.totp, 'JBSWY3DPEHPK3PXP');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('rejects the wrong master password', () async {
    final file = vaultPath();
    await file.writeAsString(cliVault);

    final manager = VaultManager(file: file, engine: VaultEngine());
    expect(
      () => manager.loadAndDecrypt('not the password'),
      throwsA(isA<Exception>()),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('what it writes, it can read back', () async {
    final file = vaultPath();
    final manager = VaultManager(file: file, engine: VaultEngine());

    await manager.createNewVault('a-test-password');
    manager.setSecret('mybank', password: 'first', totpSecret: 'JBSWY3DPEHPK3PXP');
    manager.setSecret('mybank', password: 'second');
    await manager.save();

    final reopened = VaultManager(file: file, engine: VaultEngine());
    await reopened.loadAndDecrypt('a-test-password');

    final record = reopened.getSecret('mybank')!;
    expect(record.current, 'second');
    expect(record.history, ['first']);
    expect(record.hasTotp, isTrue);

    // The envelope must stay in the CLI's shape.
    final payload = jsonDecode(await file.readAsString()) as Map;
    expect(payload.keys.toSet(), {'salt', 'nonce', 'ciphertext'});
    expect(base64Decode(payload['nonce'] as String).length, 12);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('history never grows past three entries', () async {
    final file = vaultPath();
    final manager = VaultManager(file: file, engine: VaultEngine());
    await manager.createNewVault('a-test-password');

    for (final pw in ['one', 'two', 'three', 'four']) {
      manager.setSecret('svc', password: pw);
    }
    expect(manager.getSecret('svc')!.passwords, ['four', 'three', 'two']);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('reads the legacy bare-list record shape', () {
    final record = VaultRecord.fromJson(['current', 'older']);
    expect(record.current, 'current');
    expect(record.totp, isNull);
  });

  test('TOTP matches the reference vector', () {
    final at = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000,
        isUtc: true);
    expect(Totp.now('JBSWY3DPEHPK3PXP', at: at), '324550');
  });

  test('TOTP secrets survive spaces and lowercase', () {
    expect(Totp.decodeBase32('jbsw y3dp ehpk 3pxp'),
        Totp.decodeBase32('JBSWY3DPEHPK3PXP'));
    expect(Totp.isValidSecret('not base32 at all!'), isFalse);
  });

  test('AES-GCM output carries the tag the way Python does', () async {
    final engine = VaultEngine();
    await engine.unlock('pw', VaultEngine.randomBytes(16));
    final plaintext = Uint8List.fromList(utf8.encode('hello'));
    final sealed = await engine.encrypt(plaintext);

    expect(sealed.nonce.length, VaultEngine.nonceLen);
    expect(sealed.ciphertext.length, plaintext.length + VaultEngine.macLen);
    expect(await engine.decrypt(sealed.nonce, sealed.ciphertext), plaintext);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
