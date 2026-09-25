import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// RFC 6238 TOTP with the same defaults the CLI's `pyotp.TOTP(...).now()` uses:
/// SHA-1, 30-second step, 6 digits.
class Totp {
  static const int period = 30;
  static const int digits = 6;
  static const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Accepts secrets with spaces, lowercase letters and `=` padding, which is
  /// how they normally arrive from a website or a QR scan.
  static Uint8List decodeBase32(String secret) {
    final cleaned =
        secret.replaceAll(RegExp(r'[\s=-]'), '').toUpperCase();
    if (cleaned.isEmpty) {
      throw const FormatException('Empty TOTP secret.');
    }
    var buffer = 0;
    var bits = 0;
    final out = <int>[];
    for (final char in cleaned.split('')) {
      final value = _alphabet.indexOf(char);
      if (value < 0) {
        throw FormatException('"$char" is not valid base32.');
      }
      buffer = (buffer << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xFF);
      }
    }
    if (out.isEmpty) {
      throw const FormatException('TOTP secret is too short.');
    }
    return Uint8List.fromList(out);
  }

  static bool isValidSecret(String secret) {
    try {
      decodeBase32(secret);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Current code, zero-padded to [digits].
  static String now(String secret, {DateTime? at}) {
    final time = (at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    return _code(decodeBase32(secret), time ~/ period);
  }

  /// Seconds left before the current code rolls over.
  static int secondsRemaining({DateTime? at}) {
    final time = (at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    return period - (time % period);
  }

  static String _code(Uint8List key, int counter) {
    final message = Uint8List(8);
    var value = counter;
    for (var i = 7; i >= 0; i--) {
      message[i] = value & 0xFF;
      value >>= 8;
    }

    final digest =
        Uint8List.fromList(Hmac(sha1, key).convert(message).bytes);
    final offset = digest[digest.length - 1] & 0x0F;
    final binary = ((digest[offset] & 0x7F) << 24) |
        ((digest[offset + 1] & 0xFF) << 16) |
        ((digest[offset + 2] & 0xFF) << 8) |
        (digest[offset + 3] & 0xFF);

    final modulo = binary % _pow10(digits);
    return modulo.toString().padLeft(digits, '0');
  }

  static int _pow10(int n) {
    var result = 1;
    for (var i = 0; i < n; i++) {
      result *= 10;
    }
    return result;
  }
}
