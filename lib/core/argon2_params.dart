/// Argon2id cost parameters.
///
/// These MUST stay identical to `vokul/core/params.py` in the CLI, otherwise a
/// vault written on the desktop will not open on the phone.
class Argon2Params {
  final int timeCost; // iterations
  final int memoryCost; // KiB
  final int parallelism; // lanes
  final int saltLen; // bytes
  final int keyLen; // bytes -> AES-256

  const Argon2Params({
    this.timeCost = 3,
    this.memoryCost = 65536, // 64 MiB
    this.parallelism = 4,
    this.saltLen = 16,
    this.keyLen = 32,
  });

  /// Lower-memory profile for very old handsets. Vaults created with this are
  /// *not* readable by the stock CLI, so it is opt-in and stored nowhere.
  static const Argon2Params lowMemory = Argon2Params(memoryCost: 19456);
}
