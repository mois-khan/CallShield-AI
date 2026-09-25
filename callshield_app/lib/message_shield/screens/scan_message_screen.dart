import 'package:flutter/material.dart';

import '../database/message_shield_store.dart';
import '../models/analysis_result.dart';
import '../models/message_input.dart';
import '../models/message_origin.dart';
import '../services/message_ingest_service.dart';
import '../services/message_shield_service.dart';
import '../theme/shield_theme.dart';
import '../widgets/risk_score_gauge.dart';
import '../widgets/shield_components.dart';
import 'message_threat_result_screen.dart';

/// Manual scan flow: paste, use the clipboard, or arrive here from a share.
class ScanMessageScreen extends StatefulWidget {
  const ScanMessageScreen({
    super.key,
    this.initialText,
    this.initialSender,
    this.initialChannel = MessageChannel.manual,
    this.initialOrigin,
    this.service,
    this.store,
  });

  final String? initialText;
  final String? initialSender;
  final MessageChannel initialChannel;

  /// Source metadata Android provided (for example the sharing app package),
  /// carried through so the verdict can show where the message came from.
  final MessageOrigin? initialOrigin;
  final MessageShieldService? service;
  final MessageShieldStore? store;

  @override
  State<ScanMessageScreen> createState() => _ScanMessageScreenState();
}

class _ScanMessageScreenState extends State<ScanMessageScreen> {
  static const List<MapEntry<String, String>> _examples = <MapEntry<String, String>>[
    MapEntry<String, String>(
      'KYC scam',
      'Dear customer, your KYC is expired. Update immediately at '
          'http://sbi-kyc-update.xyz/verify or your account will be blocked within 24 hours.',
    ),
    MapEntry<String, String>(
      'OTP theft',
      'Sir I am sending an OTP on your number, please tell me the code to activate '
          'your new SIM. Do not tell anyone, this is confidential.',
    ),
    MapEntry<String, String>(
      'Real bank OTP',
      '482913 is your OTP for SBI net banking login. Do not share this code with '
          'anyone, including bank staff. Valid for 10 minutes.',
    ),
    MapEntry<String, String>(
      'Delivery fee',
      'DTDC: your parcel is held at customs, pay the clearance fee of Rs.1,250 at '
          'http://customs-clearance.help/pay to release it or it will be destroyed.',
    ),
  ];

  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText ?? '');
  late final MessageShieldService _service = widget.service ?? MessageShieldService.instance;
  late final MessageShieldStore _store = widget.store ?? MessageShieldStore();
  final MessageIngestService _ingest = MessageIngestService();

  bool _analyzing = false;
  AnalysisResult? _inlineResult;
  String? _error;

  /// Source metadata for the text currently in the box. It starts as whatever
  /// Android handed this screen (a shared/selected message) and is dropped the
  /// moment the user changes the text: an edited message belongs to the user,
  /// not to the app the original text arrived from.
  late MessageChannel _channel = widget.initialChannel;
  late MessageOrigin? _origin = widget.initialOrigin;

  void _forgetSource(MessageChannel channel) {
    _channel = channel;
    _origin = null;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final MessageInput? input = await _ingest.clipboardMessage();
    if (!mounted) return;
    if (input == null) {
      setState(() => _error = 'Clipboard is empty.');
      return;
    }
    setState(() {
      _controller.text = input.text;
      // The text is the clipboard's now, not the shared payload's.
      _forgetSource(MessageChannel.clipboard);
      _error = null;
    });
  }

  Future<void> _analyze({bool openDetail = true}) async {
    final String text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Paste or type a message first.');
      return;
    }
    // What Android gave us is only valid for the exact text it gave us.
    // Without this check the sharing app (and its subject line) would be shown
    // as the source of a message the user typed or pasted themselves.
    if ((widget.initialText ?? '').trim() != text) {
      _forgetSource(MessageChannel.manual);
    }
    final String? sender = _origin == null ? null : widget.initialSender;
    setState(() {
      _analyzing = true;
      _error = null;
    });

    final AnalysisResult result = await _service.analyzeMessage(
      MessageInput(
        text: text,
        sender: sender,
        channel: _channel,
        senderKind: MessageInput.classifySender(sender),
        origin: _origin,
      ),
      useIsolate: true,
    );

    if (!mounted) return;
    setState(() {
      _analyzing = false;
      _inlineResult = result;
    });

    if (openDetail) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MessageThreatResultScreen(result: result, store: _store),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AnalysisResult? result = _inlineResult;
    return Scaffold(
      backgroundColor: ShieldTheme.background,
      appBar: AppBar(
        backgroundColor: ShieldTheme.background,
        elevation: 0,
        title: Text('Scan a message', style: ShieldTheme.title()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: <Widget>[
          TextField(
            controller: _controller,
            // Typing over a shared message means the source is now the user.
            onChanged: (_) {
              if (_origin != null) {
                setState(() => _forgetSource(MessageChannel.manual));
              }
            },
            maxLines: 7,
            minLines: 5,
            style: ShieldTheme.body(size: 14, color: ShieldTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Paste the full message here - SMS, WhatsApp, email, anything.',
              hintStyle: ShieldTheme.body(size: 13),
              filled: true,
              fillColor: ShieldTheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: ShieldTheme.accent),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _analyzing ? null : _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste_go, size: 18),
                  label: const Text('Use clipboard'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ShieldTheme.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _analyzing ? null : _analyze,
                  icon: _analyzing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.shield_moon_rounded, size: 18),
                  label: Text(_analyzing ? 'Analysing…' : 'Analyse'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ShieldTheme.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(_error!, style: ShieldTheme.body(size: 12, color: ShieldTheme.danger)),
          ],
          const SizedBox(height: 18),
          SectionCard(
            title: 'Try an example',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _examples
                  .map(
                    (MapEntry<String, String> e) => ActionChip(
                      label: Text(e.key, style: ShieldTheme.body(size: 12)),
                      backgroundColor: ShieldTheme.surfaceAlt,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                      onPressed: () => setState(() {
                        _controller.text = e.value;
                        _forgetSource(MessageChannel.manual);
                        _error = null;
                      }),
                    ),
                  )
                  .toList(),
            ),
          ),
          if (result != null) ...<Widget>[
            const SizedBox(height: 14),
            SectionCard(
              title: 'Latest result',
              border: bandColor(result.band).withValues(alpha: 0.4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(bandIcon(result.band), color: bandColor(result.band), size: 20),
                      const SizedBox(width: 8),
                      Text(result.headline,
                          style: ShieldTheme.title(size: 14).copyWith(color: bandColor(result.band))),
                      const Spacer(),
                      Text(result.scoreLabel, style: ShieldTheme.mono(size: 14)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(result.explanation, style: ShieldTheme.body(size: 12)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MessageThreatResultScreen(result: result, store: _store),
                      ),
                    ),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open full result'),
                    style: OutlinedButton.styleFrom(foregroundColor: ShieldTheme.textPrimary),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          const PrivacyNote(),
          const SizedBox(height: 10),
          Text(
            'Got a message in WhatsApp, Telegram or a banking app? Use its '
            'Share option and pick CallShield - the text lands here ready to scan. '
            'Message Shield does not read those apps by itself.',
            style: ShieldTheme.body(size: 11),
          ),
        ],
      ),
    );
  }
}
