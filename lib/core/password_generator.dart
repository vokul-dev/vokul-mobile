import 'dart:math';

/// Password generation, matching `vokul generate` on the CLI.
class PasswordGenerator {
  static final Random _rng = Random.secure();

  static const String _letters =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _digits = '0123456789';
  static const String _symbols = '!@#\$%^&*';

  /// The CLI ships a ten-word list; a longer list here means a memorable
  /// passphrase is actually worth using (about 43 bits over four words).
  static const List<String> words = [
    'anchor', 'basalt', 'beacon', 'bramble', 'cactus', 'canyon', 'cedar',
    'cinder', 'clover', 'cobalt', 'comet', 'copper', 'coral', 'crater',
    'dahlia', 'delta', 'dune', 'ember', 'fathom', 'fennel', 'fjord',
    'flint', 'garnet', 'granite', 'harbor', 'hollow', 'indigo', 'ivory',
    'juniper', 'kelp', 'lantern', 'lichen', 'lumen', 'magnet', 'marble',
    'meadow', 'mesa', 'monsoon', 'nebula', 'nickel', 'nomad', 'oasis',
    'onyx', 'orchid', 'otter', 'pepper', 'pewter', 'pine', 'prairie',
    'quartz', 'quiver', 'ravine', 'ripple', 'saffron', 'sage', 'sandbar',
    'sequoia', 'shale', 'sierra', 'slate', 'solstice', 'sparrow', 'spruce',
    'summit', 'tamarind', 'thicket', 'thistle', 'tidal', 'timber', 'topaz',
    'tundra', 'velvet', 'walnut', 'willow', 'zenith', 'zephyr',
  ];

  static String random({
    int length = 20,
    bool symbols = true,
    bool digits = true,
  }) {
    var pool = _letters;
    if (digits) pool += _digits;
    if (symbols) pool += _symbols;
    return List.generate(length, (_) => pool[_rng.nextInt(pool.length)]).join();
  }

  static String memorable({int wordCount = 4, String separator = '-'}) =>
      List.generate(wordCount, (_) => words[_rng.nextInt(words.length)])
          .join(separator);

  /// Rough entropy in bits, used only to label the strength meter.
  static double entropyBits(String password) {
    if (password.isEmpty) return 0;
    var pool = 0;
    if (password.contains(RegExp(r'[a-z]'))) pool += 26;
    if (password.contains(RegExp(r'[A-Z]'))) pool += 26;
    if (password.contains(RegExp(r'[0-9]'))) pool += 10;
    if (password.contains(RegExp(r'[^a-zA-Z0-9]'))) pool += 32;
    if (pool == 0) return 0;
    return password.length * (log(pool) / ln2);
  }

  static String strengthLabel(String password) {
    final bits = entropyBits(password);
    if (bits < 40) return 'Weak';
    if (bits < 60) return 'Fair';
    if (bits < 80) return 'Strong';
    return 'Very strong';
  }
}
