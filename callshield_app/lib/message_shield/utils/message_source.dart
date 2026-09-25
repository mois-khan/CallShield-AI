import '../models/message_input.dart';
import '../models/message_origin.dart';

/// Coarse bucket used for the source icon and wording in the UI.
enum MessageSourceKind {
  /// Picked up automatically by the Android SMS receiver.
  sms,

  /// Shared / selected text from another app, with the app reported by Android.
  sharedApp,

  /// Shared / selected text, but Android did not tell us which app sent it.
  sharedUnreported,

  /// User pasted from the clipboard.
  clipboard,

  /// User typed or pasted the text into the scan screen.
  manual,

  /// Nothing useful was provided by Android.
  unknown,
}

/// Presentation-ready description of where a message came from.
///
/// Pure Dart (no Flutter imports) so it can be used from the background entry
/// point and unit tested directly.
class MessageSourceDescriptor {
  const MessageSourceDescriptor({
    required this.kind,
    required this.label,
    this.sublabel = '',
  });

  final MessageSourceKind kind;

  /// Short label, e.g. `SMS`, `WhatsApp`, `Pasted manually`.
  final String label;

  /// Honest one-liner about how we got it (may be empty).
  final String sublabel;

  /// True when the source was decided by Android, not by the user.
  bool get isAutomatic => kind == MessageSourceKind.sms;

  /// True when Android gave us the sharing app.
  bool get hasReportedApp => kind == MessageSourceKind.sharedApp;

  static MessageSourceDescriptor describe(
    MessageChannel channel,
    MessageOrigin? origin,
  ) {
    switch (channel) {
      case MessageChannel.smsInbox:
        return const MessageSourceDescriptor(
          kind: MessageSourceKind.sms,
          label: 'SMS',
          sublabel: 'Incoming SMS, handed over by Android',
        );
      case MessageChannel.share:
        final String? app = origin?.appDisplayName;
        if (app != null && app.trim().isNotEmpty) {
          return MessageSourceDescriptor(
            kind: MessageSourceKind.sharedApp,
            label: app,
            sublabel: 'Shared from ${origin!.appPackage}',
          );
        }
        return const MessageSourceDescriptor(
          kind: MessageSourceKind.sharedUnreported,
          label: 'Shared to CallShield',
          sublabel: 'Source app not provided by Android',
        );
      case MessageChannel.clipboard:
        return const MessageSourceDescriptor(
          kind: MessageSourceKind.clipboard,
          label: 'Clipboard',
          sublabel: 'Copied by you, then analysed',
        );
      case MessageChannel.manual:
        return const MessageSourceDescriptor(
          kind: MessageSourceKind.manual,
          label: 'Pasted manually',
          sublabel: 'Typed or pasted by you',
        );
      case MessageChannel.unknown:
        return const MessageSourceDescriptor(
          kind: MessageSourceKind.unknown,
          label: 'Unknown / Not provided by Android',
        );
    }
  }
}
