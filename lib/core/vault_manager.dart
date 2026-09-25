import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'exceptions.dart';
import 'vault_engine.dart';

/// One stored service. `passwords[0]` is current; the rest are history.
class VaultRecord {
  final List<String> passwords;
  final String? totp;

  const VaultRecord({this.passwords = const [], this.totp});

  String? get current => passwords.isEmpty ? null : passwords.first;
  List<String> get history =>
      passwords.length > 1 ? passwords.sublist(1) : const [];
  bool get hasTotp => (totp ?? '').trim().isNotEmpty;

  /// Accepts both the current `{"pass": [...], "totp": ...}` shape and the
  /// older bare-list shape, same as the CLI loader.
  factory VaultRecord.fromJson(Object? raw) {
    if (raw is List) {
      return VaultRecord(passwords: raw.map((e) => '$e').toList());
    }
    if (raw is Map) {
      final pass = raw['pass'];
      return VaultRecord(
        passwords: pass is List ? pass.map((e) => '$e').toList() : const [],
        totp: raw['totp'] as String?,
      );
    }
    return const VaultRecord();
  }

  Map<String, dynamic> toJson() => {'pass': passwords, 'totp': totp};
}

/// Reads and writes `vault.vk`, keeps timestamped backups, and self-heals from
/// the newest readable backup when the main file is missing or damaged.
///
/// Port of `VaultManager` in `vokul/core/vault.py`.
class VaultManager {
  static const int historyDepth = 3;
  static const int maxBackups = 10;

  final File file;
  final VaultEngine engine;
  Map<String, VaultRecord> _records = {};

  /// Set when the last load had to fall back to a backup, so the UI can say so.
  String? lastRecoveryNotice;

  VaultManager({required this.file, required this.engine});

  Directory get _backupDir =>
      Directory('${file.parent.path}${Platform.pathSeparator}backups');

  Map<String, VaultRecord> get records => Map.unmodifiable(_records);

  Future<bool> exists() async {
    if (await file.exists()) return true;
    if (await _backupDir.exists()) {
      final backups = await _listBackups();
      return backups.isNotEmpty;
    }
    return false;
  }

  Future<void> createNewVault(String masterPassword) async {
    final salt = engine.generateSalt();
    await engine.unlock(masterPassword, salt);
    _records = {};
    await save(salt: salt);
  }

  Future<void> loadAndDecrypt(String masterPassword) async {
    lastRecoveryNotice = null;
    try {
      final payload =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final salt = base64Decode(payload['salt'] as String);
      final nonce = base64Decode(payload['nonce'] as String);
      final ciphertext = base64Decode(payload['ciphertext'] as String);

      await engine.unlock(masterPassword, salt);
      final clear = await engine.decrypt(nonce, ciphertext);
      _records = _decodeRecords(clear);
      return;
    } catch (e) {
      final recovered = await _attemptBackupRecovery(masterPassword);
      if (recovered != null) {
        _records = recovered;
        lastRecoveryNotice = e is FileSystemException
            ? 'Main vault file was missing. Restored from the latest backup.'
            : 'Main vault file was unreadable. Restored from the latest backup.';
        await save(); // rewrite a healthy main file
        return;
      }
      if (e is FileSystemException) {
        throw const VaultStorageError(
          'Vault file is missing and no readable backup was found.',
        );
      }
      if (e is VaultCryptoError) {
        throw VaultStorageError(e.message);
      }
      throw const VaultStorageError(
        'Vault file is damaged and backup recovery failed.',
      );
    }
  }

  Map<String, VaultRecord> _decodeRecords(Uint8List plaintext) {
    final raw = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
    return {
      for (final entry in raw.entries)
        entry.key: VaultRecord.fromJson(entry.value),
    };
  }

  Future<List<File>> _listBackups() async {
    if (!await _backupDir.exists()) return [];
    final prefix = '${_pathBasename(file.path)}.bak_';
    final files = await _backupDir
        .list()
        .where((e) => e is File && _pathBasename(e.path).startsWith(prefix))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path)); // newest first
    return files;
  }

  Future<Map<String, VaultRecord>?> _attemptBackupRecovery(
    String masterPassword,
  ) async {
    for (final backup in await _listBackups()) {
      try {
        final payload =
            jsonDecode(await backup.readAsString()) as Map<String, dynamic>;
        await engine.unlock(
          masterPassword,
          base64Decode(payload['salt'] as String),
        );
        final clear = await engine.decrypt(
          base64Decode(payload['nonce'] as String),
          base64Decode(payload['ciphertext'] as String),
        );
        return _decodeRecords(clear);
      } catch (_) {
        continue; // wrong password for this one, or it is damaged too
      }
    }
    return null;
  }

  Future<void> backupVault() async {
    if (!await file.exists()) return;
    await _backupDir.create(recursive: true);
    final now = DateTime.now();
    final stamp = '${now.year}'
        '${_two(now.month)}${_two(now.day)}_'
        '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
    final target =
        '${_backupDir.path}${Platform.pathSeparator}${_pathBasename(file.path)}.bak_$stamp';
    await file.copy(target);
    await _pruneBackups();
  }

  Future<void> _pruneBackups() async {
    final backups = await _listBackups();
    for (final stale in backups.skip(maxBackups)) {
      try {
        await stale.delete();
      } catch (_) {/* a failed prune must never block a save */}
    }
  }

  Future<void> save({Uint8List? salt}) async {
    if (!engine.isUnlocked) {
      throw const VaultStorageError('Cannot save while the vault is locked.');
    }

    // Reuse the existing salt so the derived key stays valid.
    if (salt == null && await file.exists()) {
      try {
        final payload =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        salt = base64Decode(payload['salt'] as String);
      } catch (_) {/* fall through to a fresh salt */}
    }
    salt ??= engine.generateSalt();

    await backupVault();

    final plaintext = Uint8List.fromList(
      utf8.encode(jsonEncode(_records.map((k, v) => MapEntry(k, v.toJson())))),
    );
    final sealed = await engine.encrypt(plaintext);

    final payload = {
      'salt': base64Encode(salt),
      'nonce': base64Encode(sealed.nonce),
      'ciphertext': base64Encode(sealed.ciphertext),
    };

    await file.parent.create(recursive: true);
    // Write to a temp file first so a crash mid-write cannot shred the vault.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  void setSecret(String service, {String? password, String? totpSecret}) {
    final existing = _records[service] ?? const VaultRecord();
    var passwords = List<String>.from(existing.passwords);

    if (password != null && password.isNotEmpty) {
      if (passwords.isEmpty || passwords.first != password) {
        passwords.insert(0, password);
        if (passwords.length > historyDepth) {
          passwords = passwords.sublist(0, historyDepth);
        }
      }
    }

    _records[service] = VaultRecord(
      passwords: passwords,
      totp: (totpSecret != null && totpSecret.isNotEmpty)
          ? totpSecret
          : existing.totp,
    );
  }

  void clearTotp(String service) {
    final existing = _records[service];
    if (existing == null) return;
    _records[service] = VaultRecord(passwords: existing.passwords, totp: null);
  }

  void renameService(String from, String to) {
    final record = _records.remove(from);
    if (record != null) _records[to] = record;
  }

  bool deleteSecret(String service) => _records.remove(service) != null;

  VaultRecord? getSecret(String service) => _records[service];

  List<String> listServices() => _records.keys.toList()..sort();

  List<String> searchServices(String query) {
    final q = query.toLowerCase();
    return listServices()
        .where((s) => s.toLowerCase().contains(q))
        .toList();
  }

  Map<String, dynamic> exportVaultData() =>
      _records.map((k, v) => MapEntry(k, v.toJson()));

  /// Irreversible: removes the vault and every backup.
  Future<void> destruct() async {
    if (await file.exists()) await file.delete();
    if (await _backupDir.exists()) {
      await _backupDir.delete(recursive: true);
    }
    _records = {};
    engine.lock();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _pathBasename(String path) =>
      path.split(Platform.pathSeparator).last;
}
