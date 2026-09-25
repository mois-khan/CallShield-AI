import 'package:flutter/material.dart';

import '../models/analysis_result.dart';
import '../models/scam_category.dart';
import '../models/shield_signal.dart';
import '../theme/shield_theme.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.border,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: ShieldTheme.card(border: border),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title != null) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(title!, style: ShieldTheme.title(size: 15))),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = ShieldTheme.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: ShieldTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(value, style: ShieldTheme.mono(size: 20, color: color)),
          const SizedBox(height: 2),
          Text(label, style: ShieldTheme.body(size: 12)),
        ],
      ),
    );
  }
}

class CategoryChip extends StatelessWidget {
  const CategoryChip({super.key, required this.category, this.color});

  final ScamCategory category;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color c = color ?? ShieldTheme.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: ShieldTheme.pill(c),
      child: Text(category.label, style: ShieldTheme.body(size: 12, color: c)),
    );
  }
}

class SignalTile extends StatelessWidget {
  const SignalTile({super.key, required this.signal});

  final ShieldSignal signal;

  @override
  Widget build(BuildContext context) {
    final bool mitigation = signal.isMitigation;
    final Color color = mitigation ? ShieldTheme.safe : ShieldTheme.warning;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            mitigation ? Icons.remove_circle_outline : Icons.check_circle_outline,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  signal.label,
                  style: ShieldTheme.body(size: 14, color: ShieldTheme.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  '${signal.source.label} · weight ${mitigation ? '' : '+'}${signal.weight}'
                  '${signal.matchedText == null ? '' : ' · "${signal.matchedText}"'}',
                  style: ShieldTheme.body(size: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MlScoreBar extends StatelessWidget {
  const MlScoreBar({super.key, required this.score});

  final MlClassScore score;

  @override
  Widget build(BuildContext context) {
    final bool scamLike = score.label != 'legitimate';
    final Color color = scamLike ? ShieldTheme.danger : ShieldTheme.safe;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  score.label.replaceAll('_', ' '),
                  style: ShieldTheme.body(size: 12, color: ShieldTheme.textPrimary),
                ),
              ),
              Text('${(score.probability * 100).toStringAsFixed(1)}%',
                  style: ShieldTheme.mono(size: 11, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score.probability.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class PrivacyNote extends StatelessWidget {
  const PrivacyNote({super.key, this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(Icons.lock_outline, size: 16, color: ShieldTheme.safe),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text ??
                'Analysed on this device. Message contents are never uploaded, '
                    'never sent to an AI service, and links are never opened.',
            style: ShieldTheme.body(size: 11),
          ),
        ),
      ],
    );
  }
}
