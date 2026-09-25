/// Mirrors `vokul/core/exceptions.py`.
class VaultError implements Exception {
  final String message;
  const VaultError(this.message);
  @override
  String toString() => message;
}

class VaultCryptoError extends VaultError {
  const VaultCryptoError(super.message);
}

class VaultStorageError extends VaultError {
  const VaultStorageError(super.message);
}

/// Raised while a brute-force cooldown is in effect.
class ThrottlingError extends VaultError {
  final Duration remaining;
  const ThrottlingError(super.message, this.remaining);
}
