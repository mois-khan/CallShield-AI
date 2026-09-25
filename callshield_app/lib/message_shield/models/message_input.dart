import 'message_origin.dart';

/// How the message reached Message Shield.
enum MessageChannel {
  manual('Pasted manually'),
  clipboard('Copied message'),
  share('Shared to CallShield'),
  smsInbox('Incoming SMS'),
  unknown('Unknown source');

  const MessageChannel(this.label);

  final String label;
}

/// Coarse sender classification derived from the sender id itself (no contacts
/// permission is required and no contact data is read).
enum SenderKind {
  unknown('Unknown sender'),
  knownContact('Saved contact'),
  trustedId('Known service sender'),
  shortCode('Short code'),
  alphanumericId('Alphanumeric sender id'),
  localNumber('Local number'),
  international('International number'),
  emailAddress('Email sender');

  const SenderKind(this.label);

  final String label;
}

/// A single message to analyse. The text is always treated as untrusted data:
/// it is never interpreted as an instruction, never executed, and never sent
/// anywhere off the device.
class MessageInput {
  const MessageInput({
    required this.text,
    this.sender,
    this.channel = MessageChannel.manual,
    this.senderKind = SenderKind.unknown,
    this.receivedAt,
    this.isTrustedSender = false,
    this.origin,
    this.ingestId,
  });

  final String text;
  final String? sender;
  final MessageChannel channel;
  final SenderKind senderKind;
  final DateTime? receivedAt;

  /// User explicitly marked this sender as trusted (stored locally only).
  final bool isTrustedSender;

  /// Source/provider metadata Android actually handed us (SIM slot, carrier,
  /// sharing app package, SMS address). Null when nothing was provided.
  final MessageOrigin? origin;

  /// Identifier of the ingest event (native SMS queue row). Used to make sure a
  /// message captured while the app was closed is never analysed twice by the
  /// background service and the UI.
  final String? ingestId;

  String get safeText => text.length > 2000 ? text.substring(0, 2000) : text;

  MessageInput copyWith({
    String? text,
    String? sender,
    MessageChannel? channel,
    SenderKind? senderKind,
    DateTime? receivedAt,
    bool? isTrustedSender,
    MessageOrigin? origin,
    String? ingestId,
  }) =>
      MessageInput(
        text: text ?? this.text,
        sender: sender ?? this.sender,
        channel: channel ?? this.channel,
        senderKind: senderKind ?? this.senderKind,
        receivedAt: receivedAt ?? this.receivedAt,
        isTrustedSender: isTrustedSender ?? this.isTrustedSender,
        origin: origin ?? this.origin,
        ingestId: ingestId ?? this.ingestId,
      );

  /// Best-effort sender classification from the raw sender id string.
  static SenderKind classifySender(String? sender) {
    if (sender == null) return SenderKind.unknown;
    final String s = sender.trim();
    if (s.isEmpty) return SenderKind.unknown;
    if (s.contains('@') && !s.startsWith('+') && !_isUpiLike(s)) {
      return SenderKind.emailAddress;
    }
    if (RegExp(r'^[A-Za-z]{2}-?[A-Za-z0-9]{4,}$').hasMatch(s)) {
      // Indian transactional sender ids look like "VM-HDFCBK".
      return SenderKind.alphanumericId;
    }
    if (RegExp(r'^[A-Za-z]{4,}$').hasMatch(s)) {
      return SenderKind.alphanumericId;
    }
    if (RegExp(r'^\d{5,6}$').hasMatch(s)) return SenderKind.shortCode;
    if (s.startsWith('+')) {
      return s.startsWith('+91') ? SenderKind.localNumber : SenderKind.international;
    }
    if (RegExp(r'^[6-9]\d{9}$').hasMatch(s)) return SenderKind.localNumber;
    if (RegExp(r'^\d{8,15}$').hasMatch(s)) return SenderKind.international;
    return SenderKind.unknown;
  }

  static bool _isUpiLike(String s) => RegExp(
        r'^[a-z0-9.\-_]{2,}@(okaxis|oksbi|okhdfcbank|okicici|ybl|paytm|apl|upi|ibl|axl|axisb)$',
        caseSensitive: false,
      ).hasMatch(s);
}
