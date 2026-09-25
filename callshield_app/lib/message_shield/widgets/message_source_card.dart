import 'package:flutter/material.dart';

import '../models/analysis_result.dart';
import '../models/message_origin.dart';
import '../theme/shield_theme.dart';
import '../utils/message_source.dart';
import '../utils/sender_directory.dart';
import '../utils/time_format.dart';
import 'shield_components.dart';

/// "Message source" block for the verdict screen.
///
/// Shows only what Android actually reported: the channel, the SMS sender id,
/// the number (when the sender is a number), the SIM/carrier info, the message
/// timestamp and - for shares - the source app. Anything Android did not expose
/// is shown as unavailable instead of being guessed.
class MessageSourceCard extends StatelessWidget {
  const MessageSourceCard({super.key, required this.result, this.color});

  final AnalysisResult result;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final MessageSourceDescriptor source = result.source;
    final MessageOrigin? origin = result.input.origin;
    final String? sender = result.input.sender;
    final String? organisation = SenderDirectory.organisationFor(sender);
    final String? number = _number(result, origin);

    return SectionCard(
      title: 'Message source',
      border: (color ?? ShieldTheme.accent).withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _row(
            icon: _iconFor(source.kind),
            label: 'Source',
            value: source.label,
            valueColor: ShieldTheme.textPrimary,
          ),
          if (source.sublabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 27, bottom: 10),
              child: Text(source.sublabel, style: ShieldTheme.body(size: 11)),
            ),
          if (organisation != null)
            _row(
              icon: Icons.account_balance_outlined,
              label: 'Known sender',
              value: '$organisation ($sender)',
              valueColor: ShieldTheme.textPrimary,
            ),
          if (organisation == null && sender != null && sender.trim().isNotEmpty)
            _row(
              icon: Icons.person_outline,
              // For an SMS this really is the sender id; for anything shared
              // into Message Shield it is the subject line Android forwarded,
              // which is usually just the page or chat title.
              label: source.kind == MessageSourceKind.sms
                  ? 'Sender'
                  : 'Shared subject',
              value: sender,
              valueColor: ShieldTheme.textPrimary,
            ),
          if (number != null)
            _row(
              icon: Icons.phone_iphone,
              label: 'Number',
              value: number,
              valueColor: ShieldTheme.textPrimary,
            ),
          // The SIM/carrier block only makes sense for a message Android
          // delivered over SMS; for a shared text it would just be noise.
          if (source.kind == MessageSourceKind.sms ||
              origin?.carrier != null ||
              origin?.simSlot != null)
            _row(
              icon: Icons.sim_card_outlined,
              label: 'SIM / carrier',
              value: _simLine(origin),
              valueColor: origin?.carrier != null || origin?.simSlot != null
                  ? ShieldTheme.textPrimary
                  : ShieldTheme.textMuted,
            ),
          if (origin?.deliveredAt != null)
            _row(
              icon: Icons.schedule,
              // For SMS this is Android's service-centre timestamp; anything
              // else is simply when the text reached Message Shield.
              label: source.kind == MessageSourceKind.sms
                  ? 'Received'
                  : 'Entered Message Shield',
              value: formatShieldDateTime(origin!.deliveredAt),
              valueColor: ShieldTheme.textPrimary,
            ),
          if (origin?.hasAppSource ?? false)
            _row(
              icon: Icons.android,
              label: 'App package',
              value: origin!.appPackage!,
              valueColor: ShieldTheme.textMuted,
            ),
          if (origin?.shareAction != null)
            _row(
              icon: Icons.ios_share,
              label: 'Intent action',
              value: origin!.shareAction!,
              valueColor: ShieldTheme.textMuted,
            ),
          const SizedBox(height: 4),
          Text(
            _note(source, sender),
            style: ShieldTheme.body(size: 11),
          ),
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 17, color: ShieldTheme.accent),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: Text(label, style: ShieldTheme.body(size: 13)),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: ShieldTheme.body(size: 12, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(MessageSourceKind kind) {
    switch (kind) {
      case MessageSourceKind.sms:
        return Icons.sms_outlined;
      case MessageSourceKind.sharedApp:
        return Icons.chat_bubble_outline;
      case MessageSourceKind.sharedUnreported:
        return Icons.help_outline;
      case MessageSourceKind.clipboard:
        return Icons.content_paste_outlined;
      case MessageSourceKind.manual:
        return Icons.keyboard_alt_outlined;
      case MessageSourceKind.unknown:
        return Icons.help_outline;
    }
  }

  /// The phone number, when Android actually gave us one (never derived from
  /// the text or from contacts).
  String? _number(AnalysisResult result, MessageOrigin? origin) {
    final String? address = origin?.originatingAddress;
    if (address != null && address.trim().isNotEmpty) return address.trim();
    final String? sender = result.input.sender;
    if (sender != null && SenderDirectory.looksLikeNumber(sender)) return sender;
    return null;
  }

  String _simLine(MessageOrigin? origin) {
    final List<String> parts = <String>[];
    final int? slot = origin?.simSlotNumber;
    if (slot != null) parts.add('SIM slot $slot');
    final String? carrier = origin?.carrier;
    if (carrier != null && carrier.trim().isNotEmpty) parts.add(carrier.trim());
    if (origin?.subscriptionId != null) parts.add('sub id ${origin!.subscriptionId}');
    if (parts.isEmpty) return 'Not provided by Android';
    return parts.join(' · ');
  }

  String _note(MessageSourceDescriptor source, String? sender) {
    switch (source.kind) {
      case MessageSourceKind.sms:
        if (sender != null && SenderDirectory.organisationFor(sender) != null) {
          return 'Sender ids are provided by the carrier and can be spoofed. The raw '
              'sender id is shown above and the name comes from a local directory, '
              'not from the message.';
        }
        return 'Read from the Android SMS broadcast. Message Shield only sees '
            'messages Android delivers to this device.';
      case MessageSourceKind.sharedApp:
        return 'The app name was reported by Android when the text was shared. '
            'Message Shield never reads that app\'s chats.';
      case MessageSourceKind.sharedUnreported:
        return 'Android did not report which app shared this text, so Message Shield '
            'says so rather than guessing.';
      case MessageSourceKind.clipboard:
      case MessageSourceKind.manual:
        return 'You supplied this text yourself, so the source is you.';
      case MessageSourceKind.unknown:
        return 'Android provided no source information for this message.';
    }
  }
}
