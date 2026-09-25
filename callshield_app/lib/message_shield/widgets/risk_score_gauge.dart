import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/scam_category.dart';
import '../theme/shield_theme.dart';

/// Circular 0–100 risk gauge (pure CustomPainter, no images, cheap to render).
class RiskScoreGauge extends StatelessWidget {
  const RiskScoreGauge({
    super.key,
    required this.score,
    required this.band,
    this.size = 168,
    this.label,
  });

  final int score;
  final RiskBand band;
  final double size;
  final String? label;

  Color get _color => bandColor(band);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: score / 100),
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        builder: (BuildContext context, double value, Widget? _) {
          return CustomPaint(
            painter: _GaugePainter(progress: value, color: _color),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '${(value * 100).round()}',
                    style: ShieldTheme.mono(size: size * 0.24, color: _color),
                  ),
                  Text('/100 risk', style: ShieldTheme.body(size: 12)),
                  if (label != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      label!,
                      style: ShieldTheme.body(size: 12, color: _color),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = math.min(size.width, size.height) / 2 - 12;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..color = Colors.white.withValues(alpha: 0.06),
    );

    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: 3 * math.pi / 2,
          colors: <Color>[color.withValues(alpha: 0.35), color],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

Color bandColor(RiskBand band) {
  switch (band) {
    case RiskBand.safe:
      return ShieldTheme.safe;
    case RiskBand.suspicious:
      return ShieldTheme.warning;
    case RiskBand.scam:
      return ShieldTheme.danger;
  }
}

IconData bandIcon(RiskBand band) {
  switch (band) {
    case RiskBand.safe:
      return Icons.verified_user_rounded;
    case RiskBand.suspicious:
      return Icons.report_problem_rounded;
    case RiskBand.scam:
      return Icons.gpp_bad_rounded;
  }
}

/// Big headline banner: SAFE / SUSPICIOUS / SCAM + headline text.
class VerdictBanner extends StatelessWidget {
  const VerdictBanner({
    super.key,
    required this.headline,
    required this.band,
    required this.explanation,
    this.isSpam = false,
  });

  final String headline;
  final RiskBand band;
  final String explanation;
  final bool isSpam;

  @override
  Widget build(BuildContext context) {
    final Color color = bandColor(band);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: ShieldTheme.card(border: color.withValues(alpha: 0.45)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(bandIcon(band), color: color, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(headline, style: ShieldTheme.title(size: 18).copyWith(color: color)),
              ),
              if (isSpam)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: ShieldTheme.pill(ShieldTheme.warning),
                  child: Text('SPAM', style: ShieldTheme.body(size: 11, color: ShieldTheme.warning)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(explanation, style: ShieldTheme.body(size: 13, color: ShieldTheme.textPrimary)),
        ],
      ),
    );
  }
}
