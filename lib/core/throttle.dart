import 'dart:convert';
import 'dart:io';

/// Persistent brute-force protection.
///
/// Same `.vault.vk.lock` file and same maths as `enforce_persistent_throttling`
/// in the CLI: failures inside a 5-minute window are counted, and from the
/// third one on the vault stalls for 15s plus 10s per extra attempt. On a
/// phone the wait is shown as a live countdown instead of a blocked process,
/// and it survives an app restart because the timestamps live on disk.
class Throttle {
  static const int windowSeconds = 300;
  static const int freeAttempts = 3;
  static const int basePenalty = 15;
  static const int extraPenalty = 10;

  final File lockFile;

  Throttle(this.lockFile);

  static File lockFileFor(File vault) {
    final sep = Platform.pathSeparator;
    final name = vault.path.split(sep).last;
    return File('${vault.parent.path}$sep.$name.lock');
  }

  Future<List<double>> _recentFailures() async {
    if (!await lockFile.exists()) return [];
    try {
      final data = jsonDecode(await lockFile.readAsString());
      final raw = (data is Map ? data['failures'] : null);
      if (raw is! List) return [];
      final now = _now();
      return raw
          .map((e) => (e as num).toDouble())
          .where((t) => now - t < windowSeconds)
          .toList();
    } catch (_) {
      return []; // a damaged lock file must never lock someone out forever
    }
  }

  /// How long the user still has to wait, or [Duration.zero].
  Future<Duration> cooldownRemaining() async {
    final failures = await _recentFailures();
    if (failures.length < freeAttempts) return Duration.zero;

    final penalty =
        basePenalty + (failures.length - freeAttempts) * extraPenalty;
    failures.sort();
    final elapsed = _now() - failures.last;
    final left = penalty - elapsed;
    return left <= 0 ? Duration.zero : Duration(seconds: left.ceil());
  }

  Future<int> recentFailureCount() async => (await _recentFailures()).length;

  Future<void> recordFailure() async {
    final failures = await _recentFailures();
    failures.add(_now());
    try {
      await lockFile.parent.create(recursive: true);
      await lockFile.writeAsString(jsonEncode({'failures': failures}));
    } catch (_) {/* best effort */}
  }

  Future<void> clear() async {
    try {
      if (await lockFile.exists()) await lockFile.delete();
    } catch (_) {/* best effort */}
  }

  static double _now() => DateTime.now().millisecondsSinceEpoch / 1000.0;
}
