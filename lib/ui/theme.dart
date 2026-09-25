import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The CLI greets you with purple ASCII art on a black terminal. The app keeps
/// that inheritance: near-black ground, one violet for anything actionable, and
/// amber reserved exclusively for the TOTP countdown so a code about to expire
/// is the only warm thing on screen.
class VokulColors {
  static const ink = Color(0xFF0F0D16);
  static const surface = Color(0xFF191524);
  static const surfaceHigh = Color(0xFF221D33);
  static const line = Color(0xFF302945);
  static const violet = Color(0xFF9B6BFF);
  static const violetDim = Color(0xFF5C3FA8);
  static const amber = Color(0xFFE8A33D);
  static const danger = Color(0xFFE5576B);
  static const text = Color(0xFFEDE9F7);
  static const textMuted = Color(0xFF9A93B0);
}

/// Secrets are data, not prose: fixed width so digits and lookalike glyphs are
/// readable when checking a password by eye.
const List<String> monoFallback = [
  'JetBrains Mono',
  'SF Mono',
  'Menlo',
  'Roboto Mono',
  'monospace',
];

const TextStyle monoStyle = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: monoFallback,
  letterSpacing: 0.4,
);

ThemeData buildVokulTheme() {
  const scheme = ColorScheme.dark(
    primary: VokulColors.violet,
    onPrimary: Colors.white,
    secondary: VokulColors.amber,
    surface: VokulColors.surface,
    onSurface: VokulColors.text,
    error: VokulColors.danger,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: VokulColors.ink,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: VokulColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: TextStyle(
        color: VokulColors.text,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: VokulColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: VokulColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VokulColors.surface,
      hintStyle: const TextStyle(color: VokulColors.textMuted),
      labelStyle: const TextStyle(color: VokulColors.textMuted),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: VokulColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: VokulColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: VokulColors.violet, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: VokulColors.violet),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: VokulColors.textMuted,
      textColor: VokulColors.text,
    ),
    dividerTheme: const DividerThemeData(color: VokulColors.line, space: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: VokulColors.surfaceHigh,
      contentTextStyle: const TextStyle(color: VokulColors.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
