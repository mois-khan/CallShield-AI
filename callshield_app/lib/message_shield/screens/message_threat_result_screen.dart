import 'package:flutter/material.dart';

import '../database/message_shield_store.dart';
import '../models/analysis_result.dart';
import '../models/scam_category.dart';
import '../models/shield_signal.dart';
import '../services/message_ingest_service.dart';
import '../theme/shield_theme.dart';
import '../utils/time_format.dart';
import '../widgets/message_source_card.dart';
import '../widgets/risk_score_gauge.dart';
import '../widgets/shield_components.dart';

/// Full verdict detail: score, category, signals, attacker objective, actions.
class MessageThreatResultScreen extends StatefulWidget {
  const MessageThreatResultScreen({
    super.key,
    required this.result,
    this.store,
  });

  final AnalysisResult result;
  final MessageShieldStore? store;

  @override
  State<MessageThreatResultScreen> createState() => _MessageThreatResultScreenState();
}

class _MessageThreatResultScreenState extends State<MessageThreatResultScreen> {
  late final MessageShieldStore _store = widget.store ?? MessageShieldStore();
  bool _trusted = false;
  bool _busy = false;

  AnalysisResult get result => widget.result;

  @override
  void initState() {
    super.initState();
    _loadTrustState();
  }

  Future<void> _loadTrustState() async {
    final String? sender = result.input.sender;
    if (sender == null || sender.trim().isEmpty) return;
    final MessageShieldSettings settings = await _store.settings();
    if (!mounted) return;
    setState(() => _trusted = settings.trustedSenders.contains(sender.trim()));
  }

  Future<void> _toggleTrusted() async {
    final String? sender = result.input.sender;
    if (sender == null || sender.trim().isEmpty) return;
    setState(() => _busy = true);
    final bool next = !_trusted;
    await _store.markSenderTrusted(sender, next);
    if (!mounted) return;
    setState(() {
      _trusted = next;
      _busy = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(next
            ? 'Sender marked as trusted - future messages lower their score'
            : 'Sender removed from the trusted list'),
        backgroundColor: next ? ShieldTheme.safe : ShieldTheme.surfaceAlt,
      ),
    );
  }

  Future<void> _copyReport() async {
    final StringBuffer buffer = StringBuffer()
      ..writeln('CallShield Message Shield report')
      ..writeln('Verdict: ${result.headline} (${result.riskScore}/100)')
      ..writeln('Source: ${result.source.label} (${result.input.channel.label})')
      ..writeln('Sender: ${result.input.sender ?? 'not provided by Android'}')
      ..writeln('Categories: ${result.categories.map((ScamCategory c) => c.label).join(', ')}')
      ..writeln('Detected signals:');
    for (final ShieldSignal signal in result.activeSignals) {
      buffer.writeln(' - ${signal.label} (weight ${signal.weight})');
    }
    if (result.objectives.isNotEmpty) {
      buffer.writeln('Likely objective: ${result.objectives.first}');
    }
    buffer.writeln('Analyzed fully on-device by CallShield Message Shield.');
    await MessageIngestService().copy(buffer.toString());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color color = bandColor(result.band);
    return Scaffold(
      backgroundColor: ShieldTheme.background,
      appBar: AppBar(
        backgroundColor: ShieldTheme.background,
        elevation: 0,
        title: Text('Message Shield result', style: ShieldTheme.title()),
        actions: <Widget>[
          IconButton(
            tooltip: 'Copy report',
            onPressed: _copyReport,
            icon: const Icon(Icons.copy_all_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: <Widget>[
          Center(
            child: RiskScoreGauge(
              score: result.riskScore,
              band: result.band,
              label: result.band.label,
            ),
          ),
          const SizedBox(height: 8),
          VerdictBanner(
            headline: result.headline,
            band: result.band,
            explanation: result.explanation,
            isSpam: result.isSpam,
          ),
          const SizedBox(height: 14),
          MessageSourceCard(result: result, color: color),
          const SizedBox(height: 14),
          if (result.categories.isNotEmpty)
            SectionCard(
              title: 'Detected category',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: result.categories
                    .map((ScamCategory c) => CategoryChip(category: c, color: color))
                    .toList(),
              ),
            ),
          if (result.activeSignals.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            SectionCard(
              title: 'Detected signals',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: result.activeSignals
                    .take(10)
                    .map((ShieldSignal s) => SignalTile(signal: s))
                    .toList(),
              ),
            ),
          ],
          if (result.objectives.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            SectionCard(
              title: 'Likely objective',
              border: color.withValues(alpha: 0.4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: result.objectives
                    .map((String o) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('• $o',
                              style: ShieldTheme.body(size: 13, color: ShieldTheme.textPrimary)),
                        ))
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SectionCard(
            title: 'Recommended action',
            border: ShieldTheme.safe.withValues(alpha: 0.4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: result.recommendedActions
                  .map((String a) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Icon(Icons.arrow_right_alt, size: 16, color: ShieldTheme.safe),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(a,
                                  style: ShieldTheme.body(size: 13, color: ShieldTheme.textPrimary)),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
          if (result.urlFindings.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            SectionCard(
              title: 'Links found in the message',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ...result.urlFindings.map(
                    (UrlFinding f) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(
                                f.isSuspicious
                                    ? Icons.link_off_rounded
                                    : Icons.link_rounded,
                                size: 16,
                                color: f.isSuspicious ? ShieldTheme.danger : ShieldTheme.textMuted,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(f.host,
                                    style: ShieldTheme.body(
                                        size: 13, color: ShieldTheme.textPrimary)),
                              ),
                              Text('${f.suspicion}/100', style: ShieldTheme.mono(size: 11)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(f.reasons.join(' · '), style: ShieldTheme.body(size: 11)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Links are only read as text. Message Shield never opens, '
                    'loads or sandboxes them.',
                    style: ShieldTheme.body(size: 11),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          SectionCard(
            title: 'On-device ML view',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ...result.mlScores.map((MlClassScore s) => MlScoreBar(score: s)),
                const SizedBox(height: 6),
                Text(
                  'Model ${result.modelVersion} · one weighted signal of many, '
                  'never the verdict on its own.',
                  style: ShieldTheme.body(size: 11),
                ),
              ],
            ),
          ),
          if (result.mitigations.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            SectionCard(
              title: 'What lowered the score',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: result.mitigations
                    .take(6)
                    .map((ShieldSignal s) => SignalTile(signal: s))
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SectionCard(
            title: 'Message inspected',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  result.input.text.isEmpty ? '(text not stored)' : result.input.text,
                  style: ShieldTheme.body(size: 13, color: ShieldTheme.textPrimary),
                ),
                const SizedBox(height: 10),
                Text(
                  <String>[
                    'Source: ${result.source.label}',
                    'Channel: ${result.input.channel.label}',
                    if (result.input.sender != null) 'Sender: ${result.input.sender}',
                    if (result.analyzedAt != null) 'Analyzed ${formatShieldTime(result.analyzedAt)}',
                    'Processing time: ${(result.processingMicros / 1000).toStringAsFixed(1)} ms',
                  ].join(' · '),
                  style: ShieldTheme.body(size: 11),
                ),
                if (result.input.sender != null && result.input.sender!.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _toggleTrusted,
                    icon: Icon(_trusted ? Icons.undo : Icons.verified_user_outlined, size: 18),
                    label: Text(_trusted
                        ? 'Remove sender from trusted list'
                        : 'Mark this sender as trusted'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _trusted ? ShieldTheme.warning : ShieldTheme.safe,
                      side: BorderSide(
                        color: (_trusted ? ShieldTheme.warning : ShieldTheme.safe)
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          const PrivacyNote(),
        ],
      ),
    );
  }
}
