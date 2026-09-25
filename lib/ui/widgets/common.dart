import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/password_generator.dart';
import '../../core/totp.dart';
import '../theme.dart';

/// The lock glyph doubles as the letter O in VOKUL, the way the CLI banner
/// carries its identity in the wordmark rather than in a separate logo.
class VokulWordmark extends StatelessWidget {
  final double size;
  const VokulWordmark({super.key, this.size = 34});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('V',
            style: TextStyle(
              fontSize: size,
              height: 1,
              fontWeight: FontWeight.w700,
              color: VokulColors.text,
              letterSpacing: size * 0.06,
            )),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: size * 0.04),
          child: Icon(Icons.lock_rounded,
              size: size * 0.78, color: VokulColors.violet),
        ),
        Text('KUL',
            style: TextStyle(
              fontSize: size,
              height: 1,
              fontWeight: FontWeight.w700,
              color: VokulColors.text,
              letterSpacing: size * 0.06,
            )),
      ],
    );
  }
}

/// Four segments that fill as entropy rises — a count of how much room is left,
/// not a mood ring.
class StrengthMeter extends StatelessWidget {
  final String password;
  const StrengthMeter({super.key, required this.password});

  @override
  Widget build(BuildContext context) {
    final bits = PasswordGenerator.entropyBits(password);
    final filled = bits < 40
        ? 1
        : bits < 60
            ? 2
            : bits < 80
                ? 3
                : 4;
    final color = filled == 1
        ? VokulColors.danger
        : filled == 2
            ? VokulColors.amber
            : VokulColors.violet;

    return Row(
      children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i == 3 ? 0 : 6),
              decoration: BoxDecoration(
                color: password.isEmpty
                    ? VokulColors.line
                    : (i < filled ? color : VokulColors.line),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        const SizedBox(width: 12),
        SizedBox(
          width: 88,
          child: Text(
            password.isEmpty
                ? ''
                : '${PasswordGenerator.strengthLabel(password)} · ${bits.round()} bits',
            style: const TextStyle(
                fontSize: 11, color: VokulColors.textMuted, height: 1),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Live 2FA code with a ring that drains over the 30-second window.
class TotpTile extends StatefulWidget {
  final String secret;
  final ValueChanged<String> onCopy;

  const TotpTile({super.key, required this.secret, required this.onCopy});

  @override
  State<TotpTile> createState() => _TotpTileState();
}

class _TotpTileState extends State<TotpTile> {
  Timer? _timer;
  String _code = '------';
  int _left = Totp.period;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    setState(() {
      try {
        _code = Totp.now(widget.secret);
        _left = Totp.secondsRemaining();
        _error = null;
      } catch (e) {
        _error = 'This 2FA secret is not valid base32.';
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!,
              style: const TextStyle(color: VokulColors.danger)),
        ),
      );
    }

    final expiring = _left <= 5;
    final formatted = '${_code.substring(0, 3)} ${_code.substring(3)}';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => widget.onCopy(_code),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Two-factor code',
                        style: TextStyle(
                            color: VokulColors.textMuted, fontSize: 13)),
                    const SizedBox(height: 6),
                    Text(
                      formatted,
                      style: monoStyle.copyWith(
                        fontSize: 30,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        color: expiring
                            ? VokulColors.amber
                            : VokulColors.text,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 44,
                height: 44,
                child: CustomPaint(
                  painter: _CountdownRing(
                    progress: _left / Totp.period,
                    color: expiring ? VokulColors.amber : VokulColors.violet,
                  ),
                  child: Center(
                    child: Text('$_left',
                        style: monoStyle.copyWith(
                          fontSize: 13,
                          color: expiring
                              ? VokulColors.amber
                              : VokulColors.textMuted,
                        )),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountdownRing extends CustomPainter {
  final double progress;
  final Color color;
  _CountdownRing({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = VokulColors.line;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = color;

    canvas.drawArc(rect.deflate(2), 0, math.pi * 2, false, track);
    canvas.drawArc(
      rect.deflate(2),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_CountdownRing old) =>
      old.progress != progress || old.color != color;
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
