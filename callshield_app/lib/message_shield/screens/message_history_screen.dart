import 'package:flutter/material.dart';

import '../database/message_shield_store.dart';
import '../models/analysis_result.dart';
import '../models/scam_category.dart';
import '../services/message_shield_service.dart';
import '../theme/shield_theme.dart';
import '../utils/message_source.dart';
import '../utils/time_format.dart';
import '../widgets/risk_score_gauge.dart';
import 'message_threat_result_screen.dart';

/// Locally stored verdicts, newest first.
class MessageHistoryScreen extends StatefulWidget {
  const MessageHistoryScreen({
    super.key,
    this.store,
    this.embedded = false,
  });

  final MessageShieldStore? store;

  /// When true the screen is rendered inside the Message Shield tabs (no own
  /// AppBar and no back button).
  final bool embedded;

  @override
  State<MessageHistoryScreen> createState() => _MessageHistoryScreenState();
}

class _MessageHistoryScreenState extends State<MessageHistoryScreen> {
  late final MessageShieldStore _store = widget.store ?? MessageShieldStore();
  final List<RiskBand?> _filters = <RiskBand?>[null, RiskBand.scam, RiskBand.suspicious, RiskBand.safe];
  RiskBand? _filter;
  List<AnalysisResult> _items = <AnalysisResult>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    MessageShieldService.instance.revision.addListener(_onRevision);
  }

  @override
  void dispose() {
    MessageShieldService.instance.revision.removeListener(_onRevision);
    super.dispose();
  }

  void _onRevision() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final List<AnalysisResult> items = await _store.history(limit: 200, band: _filter);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _deleteAll() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: ShieldTheme.surface,
        title: Text('Delete Message Shield history?', style: ShieldTheme.title(size: 16)),
        content: Text(
          'Removes every stored verdict, statistic and sender note for Message Shield. '
          'Call Shield history and reports are not affected.',
          style: ShieldTheme.body(size: 13),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: ShieldTheme.body(size: 13)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ShieldTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.deleteAll();
    if (!mounted) return;
    setState(() => _items = <AnalysisResult>[]);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message Shield history deleted')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = _loading
        ? const Center(child: CircularProgressIndicator(color: ShieldTheme.accent))
        : Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Wrap(
                  spacing: 8,
                  children: _filters.map((RiskBand? band) {
                    final bool selected = _filter == band;
                    return ChoiceChip(
                      label: Text(_filterLabel(band), style: ShieldTheme.body(size: 12)),
                      selected: selected,
                      backgroundColor: ShieldTheme.surface,
                      selectedColor: ShieldTheme.accent.withValues(alpha: 0.25),
                      side: BorderSide(
                        color: selected
                            ? ShieldTheme.accent
                            : Colors.white.withValues(alpha: 0.08),
                      ),
                      onSelected: (_) {
                        setState(() {
                          _filter = band;
                          _loading = true;
                        });
                        _load();
                      },
                    );
                  }).toList(),
                ),
              ),
              Expanded(
                child: _items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(Icons.inbox_outlined,
                                  color: ShieldTheme.textMuted, size: 40),
                              const SizedBox(height: 12),
                              Text('No analysed messages yet.',
                                  style: ShieldTheme.body(size: 14)),
                              const SizedBox(height: 6),
                              Text(
                                'Scan a message and its verdict will be stored here, '
                                'on this device only.',
                                textAlign: TextAlign.center,
                                style: ShieldTheme.body(size: 12),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                        itemCount: _items.length,
                        itemBuilder: (BuildContext context, int index) =>
                            _buildRow(_items[index]),
                      ),
              ),
            ],
          );

    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: ShieldTheme.background,
      appBar: AppBar(
        backgroundColor: ShieldTheme.background,
        elevation: 0,
        title: Text('Message Shield history', style: ShieldTheme.title()),
        actions: <Widget>[
          IconButton(
            tooltip: 'Delete all',
            onPressed: _items.isEmpty ? null : _deleteAll,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: body,
    );
  }

  String _filterLabel(RiskBand? band) {
    switch (band) {
      case null:
        return 'All';
      case RiskBand.scam:
        return 'Scams';
      case RiskBand.suspicious:
        return 'Suspicious';
      case RiskBand.safe:
        return 'Safe';
    }
  }

  IconData _sourceIcon(AnalysisResult item) {
    switch (item.source.kind) {
      case MessageSourceKind.sms:
        return Icons.sms_outlined;
      case MessageSourceKind.sharedApp:
        return Icons.chat_bubble_outline;
      case MessageSourceKind.sharedUnreported:
      case MessageSourceKind.unknown:
        return Icons.help_outline;
      case MessageSourceKind.clipboard:
        return Icons.content_paste_outlined;
      case MessageSourceKind.manual:
        return Icons.keyboard_alt_outlined;
    }
  }

  Widget _buildRow(AnalysisResult item) {
    final Color color = bandColor(item.band);
    return Dismissible(
      key: ValueKey<String>(item.id ?? item.analyzedAt?.toIso8601String() ?? '${item.riskScore}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: ShieldTheme.danger.withValues(alpha: 0.25),
        child: const Icon(Icons.delete_outline, color: ShieldTheme.danger),
      ),
      onDismissed: (_) async {
        if (item.id != null) await _store.deleteOne(item.id!);
        if (mounted) setState(() => _items.remove(item));
      },
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MessageThreatResultScreen(result: item, store: _store),
          ),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: ShieldTheme.card(border: color.withValues(alpha: 0.35)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(bandIcon(item.band), size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.categories.isEmpty
                          ? item.band.label
                          : item.categories.first.label,
                      style: ShieldTheme.title(size: 14),
                    ),
                  ),
                  Text('${item.riskScore}/100', style: ShieldTheme.mono(size: 13, color: color)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.input.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ShieldTheme.body(size: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Icon(_sourceIcon(item), size: 13, color: ShieldTheme.accent),
                  const SizedBox(width: 5),
                  Text(item.source.label, style: ShieldTheme.body(size: 11)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                <String>[
                  formatShieldTime(item.analyzedAt),
                  if (item.input.sender != null) item.input.sender!,
                  if (item.isSpam) 'spam',
                ].join(' · '),
                style: ShieldTheme.body(size: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
