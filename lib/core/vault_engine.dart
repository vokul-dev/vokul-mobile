import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'argon2_params.dart';
import 'exceptions.dart';

/// Request passed to the key-derivation isolate. Only plain data crosses the
/// isolate boundary, never a live key object.
@immutable
class _KdfRequest {
  final String password;
  final Uint8List salt;
  final int iterations;
  final int memory;
  final int parallelism;
  final int hashLength;

  const _KdfRequest({
    required this.password,
    required this.salt,
    required this.iterations,
    required this.memory,
    required this.parallelism,
    required this.hashLength,
  });
}

/// Runs on a background isolate — Argon2id at 64 MiB blocks for a second or
/// more, which would drop frames if it ran on the UI thread.
///
/// This is the single seam to swap if you want a faster KDF: any
/// implementation that produces standard Argon2id output will interoperate
/// with the CLI. See README ("Making unlock faster").
Future<Uint8List> _deriveKeyWorker(_KdfRequest r) async {
  final kdf = Argon2id(
    memory: r.memory,
    parallelism: r.parallelism,
    iterations: r.iterations,
    hashLength: r.hashLength,
  );
  final key = await kdf.deriveKey(
    secretKey: SecretKey(utf8.encode(r.password)),
    nonce: r.salt,
  );
  return Uint8List.fromList(await key.extractBytes());
}

/// Stateful cryptographic session for a single vault.
///
/// Port of `VaultEngine` in `vokul/core/crypto.py`. Wire format is unchanged:
/// AES-256-GCM with a 12-byte nonce, and the 16-byte tag appended to the
/// ciphertext exactly the way Python's `AESGCM` does it.
class VaultEngine {
  static const int nonceLen = 12;
  static const int macLen = 16;

  final Argon2Params params;
  Uint8List? _key;

  VaultEngine({this.params = const Argon2Params()});

  bool get isUnlocked => _key != null;

  static final Random _rng = Random.secure();

  static Uint8List randomBytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _rng.nextInt(256);
    }
    return out;
  }

  Uint8List generateSalt([int? length]) =>
      randomBytes(length ?? params.saltLen);

  Future<void> unlock(String masterPassword, Uint8List salt) async {
    try {
      _key = await compute(
        _deriveKeyWorker,
        _KdfRequest(
          password: masterPassword,
          salt: salt,
          iterations: params.timeCost,
          memory: params.memoryCost,
          parallelism: params.parallelism,
          hashLength: params.keyLen,
        ),
      );
    } catch (_) {
      throw const VaultCryptoError('Key derivation failed.');
    }
  }

  /// Wipes the key material. Dart gives no hard guarantee the bytes leave RAM,
  /// but zeroing drops the obvious copy.
  void lock() {
    final key = _key;
    if (key != null) {
      key.fillRange(0, key.length, 0);
    }
    _key = null;
  }

  /// Returns `nonce` and `ciphertext||tag`.
  Future<({Uint8List nonce, Uint8List ciphertext})> encrypt(
    Uint8List plaintext,
  ) async {
    final key = _key;
    if (key == null) {
      throw const VaultCryptoError('Vault is locked. Unlock first.');
    }
    final nonce = randomBytes(nonceLen);
    try {
      final box = await AesGcm.with256bits().encrypt(
        plaintext,
        secretKey: SecretKey(key),
        nonce: nonce,
      );
      final joined = Uint8List(box.cipherText.length + macLen)
        ..setAll(0, box.cipherText)
        ..setAll(box.cipherText.length, box.mac.bytes);
      return (nonce: nonce, ciphertext: joined);
    } catch (_) {
      throw const VaultCryptoError('Encryption failed.');
    }
  }

  /// Takes `ciphertext||tag` as produced by the CLI.
  Future<Uint8List> decrypt(Uint8List nonce, Uint8List ciphertext) async {
    final key = _key;
    if (key == null) {
      throw const VaultCryptoError('Vault is locked. Unlock first.');
    }
    if (ciphertext.length < macLen) {
      throw const VaultCryptoError('Decryption failed: truncated ciphertext.');
    }
    final split = ciphertext.length - macLen;
    final box = SecretBox(
      ciphertext.sublist(0, split),
      nonce: nonce,
      mac: Mac(ciphertext.sublist(split)),
    );
    try {
      final clear = await AesGcm.with256bits().decrypt(
        box,
        secretKey: SecretKey(key),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const VaultCryptoError(
        'Wrong master password, or the vault data has been altered.',
      );
    } catch (_) {
      throw const VaultCryptoError('Decryption failed.');
    }
  }
}
