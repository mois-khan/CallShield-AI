/// Message ingestion for Message Shield.
///
/// Automatic path (opt-in): a native BroadcastReceiver appends incoming SMS to
/// an app-private queue file *and* hands the message to Message Shield's own
/// foreground service, which analyses it even when the UI is closed.
///
/// Manual paths (always available): paste, clipboard, and share-to-CallShield
/// via the native bridge.
///
/// No contacts, no cloud, no third-party messaging app is ever read: source
/// information is limited to what Android itself passes to the app.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/message_input.dart';
import '../models/message_origin.dart';
import '../models/protection_status.dart';

class MessageIngestService {
  MessageIngestService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.callshield.native/message_shield');

  final MethodChannel _channel;

  /// Queue file written by MessageShieldSmsReceiver.kt (app-private files dir).
  static const String queueFileName = 'message_shield_inbox.jsonl';

  Future<File> _queueFile() async {
    final Directory dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$queueFileName');
  }

  /// Reads and clears the native SMS queue. Safe to call at any time: a missing
  /// file, a malformed line or an unwritable directory never throws.
  Future<List<MessageInput>> drainNativeInbox({int maxMessages = 25}) async {
    try {
      final File file = await _queueFile();
      if (!file.existsSync()) return const <MessageInput>[];
      final List<String> lines = file.readAsLinesSync();
      // Truncate immediately so a crash cannot double-analyse the same messages.
      file.writeAsStringSync('');
      final List<MessageInput> out = <MessageInput>[];
      for (final String line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final Map<String, dynamic> row = jsonDecode(line) as Map<String, dynamic>;
          final String? body = row['body'] as String?;
          if (body == null || body.trim().isEmpty) continue;
          final String? sender = row['sender'] as String?;
          out.add(
            MessageInput(
              text: body,
              sender: sender,
              channel: MessageChannel.smsInbox,
              senderKind: MessageInput.classifySender(sender),
              receivedAt: DateTime.tryParse(row['ts'] as String? ?? ''),
              origin: _originFromQueueRow(row, sender),
              ingestId: row['id']?.toString(),
            ),
          );
        } catch (_) {
          continue; // ignore malformed lines
        }
      }
      out.sort((MessageInput a, MessageInput b) =>
          (b.receivedAt ?? DateTime(0)).compareTo(a.receivedAt ?? DateTime(0)));
      return out.take(maxMessages).toList(growable: false);
    } catch (_) {
      return const <MessageInput>[];
    }
  }

  /// Builds the origin metadata for one native queue row.
  ///
  /// Every value comes from the SMS broadcast (sender address, service-centre
  /// timestamp, subscription id, SIM slot, carrier). Missing values stay null.
  MessageOrigin? _originFromQueueRow(Map<String, dynamic> row, String? sender) {
    final MessageOrigin origin = MessageOrigin(
      originatingAddress: row['address']?.toString(),
      senderAlias: sender,
      subscriptionId: (row['subId'] as num?)?.toInt(),
      simSlot: (row['slot'] as num?)?.toInt(),
      carrier: row['carrier']?.toString(),
      deliveredAt: DateTime.tryParse(row['delivered'] as String? ?? ''),
    );
    return origin.isEmpty ? null : origin;
  }

  /// True when the SMS receiver is available on this device/platform.
  Future<bool> isAutoProtectionSupported() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('isAutoProtectionSupported');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Enables/disables the automatic (background) SMS protection.
  ///
  /// The native side persists the flag for the SMS receiver, starts or stops
  /// Message Shield's foreground service and (when possible) its boot recovery.
  Future<void> setAutoProtection(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setAutoProtection', <String, dynamic>{
        'enabled': enabled,
      });
    } catch (_) {
      // Ignore: the manual flows keep working without the native side.
    }
  }

  /// Live Android state of background protection (permissions, service,
  /// battery optimisation). Falls back to a conservative "nothing is running"
  /// snapshot when the native side is unavailable (for example on iOS).
  Future<ProtectionStatus> protectionStatus({bool autoProtectionEnabled = false}) async {
    try {
      final Map<dynamic, dynamic>? raw =
          await _channel.invokeMapMethod<dynamic, dynamic>('getProtectionStatus');
      if (raw == null) {
        return ProtectionStatus(autoProtectionEnabled: autoProtectionEnabled);
      }
      return ProtectionStatus.fromJson(raw);
    } catch (_) {
      return ProtectionStatus(autoProtectionEnabled: autoProtectionEnabled);
    }
  }

  /// Asks Android for the battery-optimisation exemption dialog for this app.
  /// The system dialog decides; nothing is changed silently.
  Future<bool> requestBatteryOptimizationExemption() async {
    try {
      final bool? result =
          await _channel.invokeMethod<bool>('requestBatteryOptimizationExemption');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system battery-optimisation list (fallback when the direct
  /// per-app request dialog is not available on the OEM build).
  Future<void> openBatteryOptimizationSettings() async {
    try {
      await _channel.invokeMethod<void>('openBatteryOptimizationSettings');
    } catch (_) {
      // Nothing to do: the settings screen just does not open.
    }
  }

  /// Picks up a message that was shared/selected into CallShield.
  Future<MessageInput?> consumeSharedPayload() async {
    try {
      final Map<dynamic, dynamic>? payload =
          await _channel.invokeMapMethod<dynamic, dynamic>('getSharedPayload');
      return _toInput(payload);
    } catch (_) {
      return null;
    }
  }

  /// Called when the app returns to the foreground: a message may have been
  /// shared into CallShield while the activity was already alive.
  Future<MessageInput?> sharedPayloadOnResume() => consumeSharedPayload();

  MessageInput? _toInput(Map<dynamic, dynamic>? payload) {
    if (payload == null) return null;
    final String? text = payload['text']?.toString();
    if (text == null || text.trim().isEmpty) return null;
    final String? sender = payload['sender']?.toString();
    final String? appPackage = payload['appPackage']?.toString();
    final String? appLabel = payload['appLabel']?.toString();
    final String? action = payload['shareAction']?.toString();
    final MessageOrigin? origin = (appPackage == null && appLabel == null && action == null)
        ? null
        : MessageOrigin(
            appPackage: appPackage,
            appLabel: appLabel,
            shareAction: action,
            deliveredAt: DateTime.now(),
          );
    return MessageInput(
      text: text,
      sender: sender,
      channel: MessageChannel.share,
      senderKind: MessageInput.classifySender(sender),
      origin: origin,
    );
  }

  /// "Analyze copied message" flow.
  Future<MessageInput?> clipboardMessage() async {
    try {
      final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      final String? text = data?.text;
      if (text == null || text.trim().isEmpty) return null;
      return MessageInput(text: text, channel: MessageChannel.clipboard);
    } catch (_) {
      return null;
    }
  }

  Future<void> copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      // Clipboard access can fail on some OEM builds; ignore.
    }
  }
}
